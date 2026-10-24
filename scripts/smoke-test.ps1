# Smoke test the built binaries. No network access beyond localhost.
#
# Inputs (env):
#   SRC_DIR   source checkout (default: src)
#   ARCH      target arch, x64 or arm64 (default: x64)

$ErrorActionPreference = 'Stop'

$src = if ($env:SRC_DIR) { $env:SRC_DIR } else { 'src' }
$arch = if ($env:ARCH) { $env:ARCH } else { 'x64' }
$bin = Join-Path $src 'target-static\release'

# Binaries are native for the runner they are built on (windows-latest is x64,
# windows-11-arm is arm64), so the check is on the host architecture. A
# cross-arch build would need emulation and is not attempted.
$hostArch = if ([Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
} else { 'x86' }
if ($arch -ne $hostArch) {
    Write-Host "skipping execution: building ${arch} on a ${hostArch} host"
    foreach ($file in 'rad.exe', 'radicle-node.exe', 'git-remote-rad.exe') {
        if (-not (Test-Path (Join-Path $bin $file))) { throw "missing $file" }
    }
    exit 0
}

$work = Join-Path $env:RUNNER_TEMP 'smoke'
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $work | Out-Null

$env:RAD_HOME = Join-Path $work 'radhome'
$env:RAD_PASSPHRASE = 'smoketest-passphrase'

$rad = Join-Path $bin 'rad.exe'
$version = & $rad --version
Write-Host $version
if ($version -notmatch '^rad \d+\.\d+\.\d+') { throw "unexpected --version output: $version" }

& $rad auth --alias smoketest
if ($LASTEXITCODE -ne 0) { throw 'rad auth failed' }

$self = & $rad self --did 2>&1
Write-Host "did: $self"
if ("$self" -notmatch 'did:key:') { throw 'rad self --did did not print a DID' }

# End-to-end: local repository, one commit, rad init, then push. rad clone is
# avoided on purpose, it needs outbound port 8776 to a seed node.
$repo = Join-Path $work 'repo'
New-Item -ItemType Directory -Force $repo | Out-Null
Push-Location $repo
try {
    git init -q
    git config user.email 'smoke@radicle.local'
    git config user.name 'smoke'
    'smoke' | Out-File -Encoding utf8 file.txt
    git add file.txt
    git commit -qm 'smoke'
    & $rad init --no-confirm --no-seed --name smoketest --description smoke --public
    if ($LASTEXITCODE -ne 0) { throw 'rad init failed' }
    $remotes = git remote -v
    Write-Host $remotes
    if ($remotes -notmatch 'rad\s+rad://') { throw 'no rad:// remote after rad init' }
    git push --quiet rad HEAD:refs/heads/main
    if ($LASTEXITCODE -ne 0) { throw 'git push to rad remote failed' }
} finally {
    Pop-Location
}

Write-Host 'smoke test passed'
