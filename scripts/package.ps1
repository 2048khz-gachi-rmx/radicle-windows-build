# Package a static-CRT build: a zip of the three binaries and the WiX MSI.
#
# Inputs (env):
#   SRC_DIR   source checkout (default: src)
#   VERSION   artifact version, e.g. 1.10.3 or 1.10.3-50-g2a758c94
#   ARCH      x64 or arm64 (default: x64)
#
# Produces dist/radicle-$VERSION-<target>.zip and .msi

$ErrorActionPreference = 'Stop'

$src = if ($env:SRC_DIR) { $env:SRC_DIR } else { 'src' }
$version = $env:VERSION
$arch = if ($env:ARCH) { $env:ARCH } else { 'x64' }
if (-not $version) { throw 'VERSION is required' }

$target = @{ x64 = 'x86_64-pc-windows-msvc'; arm64 = 'aarch64-pc-windows-msvc' }[$arch]
if (-not $target) { throw "unsupported ARCH: $arch" }

$bin = Join-Path $src 'target-static\release'
$dist = Join-Path $src 'dist'
$name = "radicle-$version-$target"
New-Item -ItemType Directory -Force $dist | Out-Null

# radicle-schemars is an internal schema-dump utility, so it is not shipped.
$files = @('rad.exe', 'radicle-node.exe', 'git-remote-rad.exe')
foreach ($file in $files) {
    if (-not (Test-Path (Join-Path $bin $file))) { throw "missing $bin\$file" }
}

# A static-CRT binary must not import the redistributable runtime. This guards
# against a stale RUSTFLAGS silently producing a redist-dependent build.
# dumpbin ships with the VS Build Tools that MSVC linking needs anyway.
$dumpbin = Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\bin\Host*\*\dumpbin.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\bin\Host*\*\dumpbin.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
if (-not $dumpbin) { throw 'dumpbin.exe not found; cannot verify the static CRT' }

$redist = @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')
foreach ($file in $files) {
    $deps = & $dumpbin.FullName /nologo /dependents (Join-Path $bin $file) |
        Select-String -Pattern '^\s+(\S+\.dll)\s*$' |
        ForEach-Object { $_.Matches[0].Groups[1].Value.ToLowerInvariant() }
    if ($LASTEXITCODE -ne 0) { throw "dumpbin failed on $file" }
    foreach ($dll in $redist) {
        if ($deps -contains $dll) { throw "$file imports $dll (not a static CRT build)" }
    }
    Write-Host "${file}: $($deps -join ', ')"
}

$stage = Join-Path $dist $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
foreach ($file in $files) { Copy-Item (Join-Path $bin $file) $stage }
Copy-Item (Join-Path $src 'LICENSE-MIT') $stage
Copy-Item (Join-Path $src 'LICENSE-APACHE') $stage

$zip = Join-Path $dist "$name.zip"
Compress-Archive -Force -Path (Join-Path $stage '*') -DestinationPath $zip
Write-Host "zip: $zip"

# MSI. windows/version.ps1 derives a 4-field numeric version from the nearest
# `releases/X.Y.Z` tag, which Package.wxs requires. Packaging is wired for one
# architecture upstream, so only the x64 leg produces an installer.
if ($arch -ne 'x64') {
    Write-Host "skipping MSI on $arch (installer is x64 only)"
    return
}

Push-Location (Join-Path $src 'windows')
try {
    $env:CARGO_PROFILE = 'release'
    $env:CARGO_TARGET_DIR = 'target-static'
    $Env:RADICLE_VERSION = (& .\version.ps1)
    if ($LASTEXITCODE -ne 0 -or -not $Env:RADICLE_VERSION) {
        throw 'version.ps1 failed (no releases/* tag reachable?)'
    }
    Write-Host "msi version: $Env:RADICLE_VERSION"
    dotnet build -c Release
    if ($LASTEXITCODE -ne 0) { throw 'dotnet build failed' }
    Copy-Item 'bin\Release\Radicle.msi' (Join-Path $dist "$name.msi") -Force
    Write-Host "msi: $(Join-Path $dist "$name.msi")"
} finally {
    Pop-Location
}
