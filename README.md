# HushOsKeychain

`hush_os_keychain` reads configuration secrets from macOS Keychain, Linux Secret
Service, or Windows Credential Manager through [Hush](https://hexdocs.pm/hush).
It also provides an Elixir API to store, fetch, and delete generic passwords.
It is intended for local development with an unlocked desktop session, not
production or headless servers.

## Installation

Requires Elixir `~> 1.19` and Hush `~> 1.3`. Add this dependency to `mix.exs`:

```elixir
def deps do
  [
    {:hush_os_keychain, "~> 0.1.0"} # x-release-please-version
  ]
end
```

Run `mix deps.get`. Final releases ship a Rustler NIF through
`rustler_precompiled` for the targets below, using NIF version `2.17`.
Precompiled builds do not need Rust. Development and test environments build
from source and need the toolchain described under [Contributing](#contributing).
Only final versions are published because pre-release versions force a source build.

## Hush configuration

Use the service name as the Hush key in your application's configuration:

```elixir
config :app, MyApp.Repo,
  password: {:hush, Hush.Provider.OsKeychain, "myapp.db_password"}
```

Optionally select an account globally:

```elixir
config :hush, Hush.Provider.OsKeychain, account: "ygor"
```

Hush handles tuple options such as `default:` and `optional:` itself:

```elixir
config :app, MyApp.Repo,
  password: {:hush, Hush.Provider.OsKeychain, "myapp.db_password", default: "local-only"}
```

The account is global provider configuration, not a per-tuple option. Set up Hush
resolution as described in the [Hush documentation](https://hexdocs.pm/hush).
Use app-prefixed keys such as `myapp.db_password` to avoid collisions with other
applications, especially on Windows where target names share one namespace.

## Storing secrets

### Elixir API

Given a variable `secret` containing the value obtained through secure input:

```elixir
HushOsKeychain.put("myapp.db_password", secret, account: "ygor")
#=> :ok

HushOsKeychain.fetch("myapp.db_password", account: "ygor")
#=> {:ok, secret}

HushOsKeychain.delete("myapp.db_password", account: "ygor")
#=> :ok
```

The `account:` option is optional on all three functions. Without an option or
global account, `put/3` writes under `"hush"`; `fetch/2` and `delete/2` search by
service alone. A write replaces the existing item for the selected account,
except on Windows where each service has only one credential.

Services, explicit accounts, and values must be non-empty valid UTF-8 strings.
The API returns `{:error, reason}` on failure. `fetch/2` returns `{:ok, value}` on
success; `put/3` and `delete/2` return `:ok`. Use
`HushOsKeychain.format_error(reason, "myapp.db_password")` to format an error with
the OS store and service name. It adds an account-selection hint for ambiguous
matches.

Do not print fetched values or type real secrets into commands or sessions that
save history. The API returns secrets to its caller; the caller must keep them
out of logs and inspection output.

### OS tools

These commands prompt for the secret instead of putting it in process arguments.
Their account is your OS username, not the API's default `"hush"` account. Set the
global account to match if you use account-specific lookup.

macOS:

```sh
security add-generic-password -s myapp.db_password -a "$USER" -w
```

You can also create a generic password in **Keychain Access**, with the service
`myapp.db_password` and your chosen account.

Linux:

```sh
secret-tool store --label=myapp.db_password service myapp.db_password username "$USER"
```

You can also use **Seahorse** to manage Secret Service items. The item must have
attributes `service=myapp.db_password` and `username` set to the chosen account;
a display label alone is not the lookup key.

Windows Command Prompt:

```bat
cmdkey /generic:myapp.db_password /user:%USERNAME% /pass
```

You can also add a **Generic Credential** in **Credential Manager**, using
`myapp.db_password` as the target name and your chosen username.

## Lookup rules

- The key is the generic password's service. On Windows it is the credential's
  target name, exactly as passed to `cmdkey /generic:`.
- The API's `account:` option takes precedence over
  `config :hush, Hush.Provider.OsKeychain, account: "..."`.
- On macOS and Linux, a configured account selects that account's item. Without
  an account, exactly one item must match the service. Multiple matches return
  `{:error, {:ambiguous, count}}`, not the first match. Set an account to choose one.
- Windows has only one credential per service. An account checks its username,
  rather than selecting another credential. A different username returns
  `{:error, :not_found}`. Writing with another account replaces the service's
  credential.
- `delete/2` uses the same lookup rules as `fetch/2`, including ambiguity checks.
- The default write account is `"hush"`. Reads without an account can find it.

## Missing items and errors

The provider's `fetch/1` returns `{:ok, value}`, `{:error, :not_found}`, or
`{:error, message}`. The public Elixir API preserves structured error reasons;
only the provider maps unavailable stores to `:not_found`.

| Situation | Public API result | Hush behavior |
| --- | --- | --- |
| Missing item or Windows username mismatch | `{:error, :not_found}` | Applies `default:` or `optional:`; otherwise reports a required value missing |
| Unsupported platform or no usable store, including Linux without a D-Bus session or Secret Service | `{:error, {:unavailable, message}}` | Logs the reason at debug level and treats it as not found |
| Access denied, locked store, or dismissed unlock prompt | `{:error, {:access_denied, message}}` | Error, no default substitution |
| Several matching items without an account | `{:error, {:ambiguous, count}}` | Error with a hint to set `account` |
| Invalid input or stored text that is not UTF-8 | `{:error, {:invalid, message}}` | Error, no default substitution |
| Native library fails to load on a supported target | `{:error, {:native_not_loaded, message}}` | Error, no default substitution |
| Other store failure | `{:error, {:platform, message}}` | Error, no default substitution |

Failed store initialization is not cached; the next call retries. Updating a
secret after Hush has resolved application configuration does not update values
already written to the application environment.

## macOS prompts and timeouts

Keychain may show **Allow** dialogs when the BEAM first reads an item. Choose
**Always Allow** only if you trust the requesting executable. Items created by
`security` initially trust that tool, so the first BEAM read can prompt. Items
written with `put/3` trust the current `beam.smp`; prompts can return after an
Erlang upgrade changes its path.

Hush's default timeout is 5000 ms. Allow more time for dialogs in your config:

```elixir
config :hush, timeout: 60_000
```

Hush fetches concurrently, so several prompts may appear at once. Calls run on
dirty I/O schedulers, but an unanswered dialog still occupies a scheduler thread
until it closes. A timeout does not dismiss the OS dialog.

## Supported platforms

Precompiled targets:

- `aarch64-apple-darwin`
- `x86_64-apple-darwin`
- `aarch64-unknown-linux-gnu`
- `x86_64-unknown-linux-gnu`
- `x86_64-pc-windows-msvc`

macOS uses Keychain. Linux requires a logged-in D-Bus session and a Secret Service
implementation such as GNOME Keyring or KWallet. Windows uses Credential Manager.

On other targets, including musl Linux, FreeBSD, and Windows GNU, the provider
returns `{:error, :not_found}` and logs the unavailable reason at debug level, so
Hush defaults apply. This fallback applies when not forcing a source build.
A native library load failure on a supported target is an error, not a fallback.

## Security and limitations

OS stores protect secrets at rest and from other users. They do not protect
against other processes running as the same user. On Linux and Windows, other
processes in the session can read unlocked items. On macOS, another Elixir project
using the same Erlang installation can read items that trust its `beam.smp`
without another prompt.

This library does not log, inspect, include in errors, or write plaintext secret
values to disk. It writes secrets to the OS credential store. Secrets returned to
Elixir live in ordinary binaries, which cannot be reliably zeroed from memory.
Avoid logging or inspecting them in application code.

Only generic passwords in the default OS store are supported. There is no support
for custom keychain files, access groups, iCloud sync configuration, certificates,
internet passwords, Linux kernel keyutils, or `pass`. There is no extra secret
cache beyond Hush's own resolution behavior.

## Contributing

Building from source requires Rust **1.91+** because Rustler 0.38 requires it.
Rust is needed only for source builds. In `:dev` and `:test`, the NIF is always
built from source. Set `HUSH_OS_KEYCHAIN_BUILD=1` to force a source build in other
environments.

```sh
mix deps.get
mix compile --warnings-as-errors
mix test
mix format --check-formatted
mix docs
```

`mix test` runs unit tests only and does not access the real OS store. Run the
integration suite separately in an unlocked desktop session:

```sh
mix test --only integration
```

Integration tests write temporary `hush_os_keychain_test.*` items to the real OS
store and delete them during cleanup. They may trigger access dialogs. Do not run
them against a store you cannot unlock.

## License

Apache-2.0. See the `LICENSE` file in the repository.
