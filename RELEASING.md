# Releasing

Releases are automated with [release-please](https://github.com/googleapis/release-please)
in `.github/workflows/release.yml`. Commits on `main` must follow
[Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`,
`feat!:` ...), because they decide the next version and the changelog.

## Flow

1. Every push to `main` runs release-please. It opens or updates a release PR
   that bumps `version` in `mix.exs`, the install snippet in `README.md`,
   `.release-please-manifest.json` and `CHANGELOG.md`.
2. Merging the release PR makes release-please tag `vX.Y.Z` and create the
   GitHub Release. The same workflow then:
   - builds the NIF for every precompiled target and uploads the tarballs to
     that release;
   - runs `mix rustler_precompiled.download HushOsKeychain.Native --all --print`
     to write `checksum-Elixir.HushOsKeychain.Native.exs` from those tarballs;
   - runs `mix hex.publish --yes`.

The checksum file is generated in CI for each release and is not committed.

The first release is `0.1.0` (`initial-version` in `release-please-config.json`).
Before `1.0.0`, breaking changes bump the minor version.

Only final versions (`X.Y.Z`, no `-rc`/`-dev` suffix) are published.
`rustler_precompiled` forces a source build for pre-release versions, so a
pre-release would require every user to have Rust installed.

## Repository setup

- `vars.APP_ID` and `secrets.APP_KEY`: a GitHub App with contents, issues and
  pull-requests write access. Its token lets the release PR trigger CI.
- `secrets.HEX_API_KEY`: a Hex API key with publish rights for
  `hush_os_keychain`.

## Recovering a failed release

If the build or publish jobs fail after the GitHub Release exists, re-run the
failed jobs from the Actions UI. Uploads use `--clobber`, so re-running a build
job replaces its tarball.
