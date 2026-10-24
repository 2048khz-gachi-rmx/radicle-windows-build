<img width="1301" height="390" alt="image" src="https://github.com/user-attachments/assets/35b3d751-b0cb-46a1-9065-1a7eb26d4ac7" />

# Radicle for Windows

[![build](https://github.com/2048khz-gachi-rmx/radicle-windows-build/actions/workflows/build.yml/badge.svg)](https://github.com/2048khz-gachi-rmx/radicle-windows-build/actions/workflows/build.yml)

Windows builds of [Radicle](https://radicle.dev), rebuilt from upstream source
every day. Upstream builds macOS and Linux binaries but lists no Windows
download (technically, Radicle's Windows support is still beta), so
this repository fills that gap.

## Downloads

Every build is attached to [releases](https://github.com/2048khz-gachi-rmx/radicle-windows-build/releases).

For unreleased builds the version reads like `1.10.3-50-g2a758c94`:
 50 commits after the `releases/1.10.3` tag, at commit `2a758c94`.

Each release carries:

- `radicle-<version>-x86_64-pc-windows-msvc.zip` — `rad.exe`, `radicle-node.exe`,
  `git-remote-rad.exe`, licenses
- `radicle-<version>-aarch64-pc-windows-msvc.zip` — same, for Windows on ARM
- `radicle-<version>-<target>.msi` — per-user installer that puts the binaries in
  `%LOCALAPPDATA%\Radicle\bin` and adds that directory to `PATH`
- `SHA256SUMS.txt` - for the security nerds

Note: binaries are **unsigned**. SmartScreen warns on first run.

## Use

```powershell
rad auth --alias <you>
rad self
```

`git-remote-rad.exe` is found through `PATH`, so keep all three binaries together.
