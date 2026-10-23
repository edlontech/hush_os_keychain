# Releasing

Only final versions (`X.Y.Z`, no `-rc`/`-dev` suffix) are published.
`rustler_precompiled` forces a source build for pre-release versions, so a
pre-release would require every user to have Rust installed.

1. Bump `version` in `mix.exs` to `X.Y.Z` and commit.
2. Tag the commit `vX.Y.Z` and push the tag:

   ```sh
   jj tag set vX.Y.Z -r <change>
   jj git push -b main
   git push origin vX.Y.Z
   ```

3. Wait for the `Release` workflow to finish. It builds the NIF for every
   target and attaches the tarballs to the `vX.Y.Z` GitHub Release. The
   workflow fails if the tag does not match the version in `mix.exs`.
4. Generate the checksum file from the published artifacts:

   ```sh
   mix rustler_precompiled.download HushOsKeychain.Native --all --print
   ```

5. Commit `checksum-Elixir.HushOsKeychain.Native.exs`.
6. Publish to Hex:

   ```sh
   mix hex.publish
   ```
