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

## Supported platforms

Precompiled targets:

- `aarch64-apple-darwin`
- `x86_64-apple-darwin`
- `aarch64-unknown-linux-gnu`
- `x86_64-unknown-linux-gnu`
- `x86_64-pc-windows-msvc`

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
