# Radicle for Windows

[![build](https://github.com/2048khz-gachi-rmx/radicle-windows-build/actions/workflows/build.yml/badge.svg)](https://github.com/2048khz-gachi-rmx/radicle-windows-build/actions/workflows/build.yml)

Windows builds of [Radicle](https://radicle.dev), rebuilt from upstream source
every day. Upstream builds macOS and Linux binaries and lists no Windows
download, so this repository fills that gap. Windows support in Radicle is
still beta.

## Downloads

Every build is attached to [releases](https://github.com/2048khz-gachi-rmx/radicle-windows-build/releases).

| Release | Contents |
|---|---|
| `continuous` (prerelease) | latest upstream `main`, rebuilt when `main` moves |
| `1.10.3`, `1.10.2`, … | built from the matching upstream `releases/X.Y.Z` tag |

Each release carries:

- `radicle-<version>-x86_64-pc-windows-msvc.zip` — `rad.exe`, `radicle-node.exe`,
  `git-remote-rad.exe`, licenses
- `radicle-<version>-aarch64-pc-windows-msvc.zip` — same, for Windows on ARM
- `radicle-<version>-<target>.msi` — per-user installer that puts the binaries in
  `%LOCALAPPDATA%\Radicle\bin` and adds that directory to `PATH`
- `SHA256SUMS.txt`

The MSI is x64 only: WiX packaging is wired for one architecture upstream.

## Install

Unzip into a directory on your `PATH`, or run the MSI. Binaries are built with
the static C runtime, so no Visual C++ Redistributable is needed.

```powershell
rad auth --alias <you>
rad self
```

`git-remote-rad.exe` is found through `PATH`, so keep all three binaries
together.

### Notes

- Binaries are **unsigned**. SmartScreen warns on first run. Build
  provenance is attested on the release workflow; each release body records the
  upstream commit it was built from.
- `rad.exe --version` prints the upstream version plus the commit, e.g.
  `rad 1.10.3 (7e1cb406)`.
- For unreleased builds the version reads like `1.10.3-50-g2a758c94`: 50 commits
  after the `releases/1.10.3` tag, at commit `2a758c94`.

## How it works

One workflow, three jobs:

1. **check** (`ubuntu-latest`) runs `git ls-remote` against the upstream seed,
   takes the newest `releases/X.Y.Z[-suffix]` tag and the `main` head, and
   compares both with what is already published here. Nothing is built if
   neither moved. A release candidate counts as the newest tag only while its
   final release does not exist.
2. **build** (`windows-latest` for x64, `windows-11-arm` for arm64) clones
   upstream, materializes the 7 symlinked paths, builds the three binaries with
   `RUSTFLAGS=-C target-feature=+crt-static` in `target-static`, smoke tests them
   against a local repository, then produces the zip and the MSI.
3. **publish** attests the assets and creates or updates the GitHub release.

A tag build wins over the rolling prerelease, so a day with a new tag does not
also rebuild `main`.

Manual runs (`workflow_dispatch`) accept an upstream `ref` to build a specific
tag or commit, `no_release` to build without publishing, and `run_tests` to run
the upstream test suite on x64 first.

### Source

Upstream lives on its own seed node, not on GitHub:

    https://seed.radicle.xyz/z3gqcJUoA1n9HaHKufZs5FCSGazv5.git

A full clone is ~16 MB, so the workflow clones normally instead of using
shallow or filtered checkouts. `RADICLE_SOURCE` overrides the URL; the GitHub
mirror `radicle-dev/heartwood` works as a fallback.

### Caching

| Path | Key | Note |
|---|---|---|
| `src/target-static` | rustc version, `Cargo.lock`, `RUSTFLAGS` | ~500 dependencies, including vendored libgit2 and bundled SQLite |
| `~/.cargo` | same | registry and git dependencies |
| `~/.nuget/packages` | `Radicle.wixproj`, `Package.wxs` | WiX SDK restore |

`actions-rust-lang/setup-rust-toolchain` reads `rust-toolchain.toml` from the
upstream checkout and passes the cache settings to `Swatinem/rust-cache`, which
prunes build artifacts down to dependencies and keeps a restore-key fallback so
a `Cargo.lock` change does not start from zero. `RUSTFLAGS` is part of the cache
key, and a separate target directory is used because cargo does not fingerprint
`RUSTFLAGS` itself.

## Repository layout

```
.github/workflows/build.yml   check -> build (x64, arm64) -> publish
scripts/check.sh              decide what to build, resolve the commit
scripts/prepare-source.ps1    materialize + verify symlinks, derive version metadata
scripts/smoke-test.ps1        run the binaries against a local repository
scripts/package.ps1           zip + MSI, static-CRT assertion
```

## License

Radicle is dual licensed under Apache-2.0 and MIT. The scripts here are
MIT-licensed; see the licenses shipped in each release for the binaries.
