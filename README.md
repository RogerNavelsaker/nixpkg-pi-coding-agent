# pi-coding-agent

Nix packaging for `@mariozechner/pi-coding-agent` using Bun and `bun2nix`.

## Package

- Upstream package: `@mariozechner/pi-coding-agent`
- Pinned version: `0.61.0`
- Description: coding agent CLI with read, bash, edit, write tools and session management
- Installed binary: `pi-coding-agent`
- Upstream executable invoked by Bun: `pi`

## What This Repo Does

- Uses `bun.lock` and generated `bun.nix` as the dependency lock surface for Nix
- Builds the upstream package as an internal Bun application with `bun2nix`
- Exposes the canonical `pi-coding-agent` binary
- Injects the pinned `RogerNavelsaker/os-eco-pi-extension` package via Pi's explicit `-e` path hook
- Preserves useful alias metadata in the manifest for external wrappers
- Provides a manifest sync script for updating the pinned npm metadata

## Files

- `flake.nix`: flake entrypoint
- `nix/package.nix`: Nix derivation
- `nix/package-manifest.json`: pinned package metadata and exposed binary name
- `scripts/sync-from-npm.ts`: updates pinned npm metadata without changing the canonical output binary

## Notes

- The default `out` output installs the longform binary name `pi-coding-agent`.
- Wrapper commands such as `pi`, `gmi`, `cc`, and `cod` are available as separate Nix outputs, not in the default `out` output.
- Set `PI_OS_ECO_EXTENSION_DISABLE=1` to run the packaged Pi CLI without the injected extension.
- Set `PI_OS_ECO_EXTENSION_PATH=/abs/path` to override the injected extension source.
