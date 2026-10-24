# Prepare a Radicle source checkout for a Windows build.
#
# The repository stores 7 paths as symlinks. They are checked out as regular
# files that contain the link target, because the clone runs with
# core.symlinks=false (no SeCreateSymbolicLinkPrivilege needed, and the same
# code path works on x64 and arm64). This script replaces each of them with a
# copy of its target, verifies the result, and derives the build metadata that
# the workspace build.rs bakes into the binaries.
#
# Link targets are read from the git object database, not the working tree, so
# the script is idempotent: after a first run the paths hold real content, and
# re-reading them from disk would mistake that content for a link target.
#
# Inputs (env):
#   SRC_DIR     source checkout (default: src)
#   BUILD_REF   ref that was checked out; "releases/*" means a tag build
#
# Outputs:
#   GITHUB_ENV     RADICLE_VERSION, GIT_HEAD, SOURCE_DATE_EPOCH
#   GITHUB_OUTPUT  version

$ErrorActionPreference = 'Stop'

$src = if ($env:SRC_DIR) { $env:SRC_DIR } else { 'src' }
$src = (Resolve-Path $src).Path

function Invoke-Git([string[]]$GitArgs) {
    $out = & git -C $src @GitArgs
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed in $src" }
    $out
}

# Normalize a repository-relative path that may contain `..` segments.
function Resolve-RepoPath([string]$Base, [string]$Target) {
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($segment in ("$Base/$Target" -split '/')) {
        switch ($segment) {
            '' { }
            '.' { }
            '..' {
                if ($parts.Count -eq 0) { throw "path escapes the repository: $Base/$Target" }
                $parts.RemoveAt($parts.Count - 1)
            }
            default { $parts.Add($segment) }
        }
    }
    $parts -join '/'
}

# "120000 <sha> 0<TAB><path>"
$links = @(Invoke-Git @('ls-files', '-s') | ForEach-Object {
        $parts = $_ -split "`t", 2
        if ($parts.Count -eq 2 -and $parts[0] -like '120000 *') {
            [pscustomobject]@{
                Sha  = ($parts[0] -split ' ')[1]
                Path = $parts[1]
            }
        }
    })

if ($links.Count -eq 0) {
    throw "no symlink entries found in $src (is this a Radicle checkout?)"
}

foreach ($link in $links) {
    # Blob content of a symlink entry is the link target, as stored by git.
    $target = ((Invoke-Git @('cat-file', 'blob', $link.Sha)) -join "`n").Trim()
    $targetPath = Resolve-RepoPath ((Split-Path -Parent $link.Path) -replace '\\', '/') $target

    $targetBlob = (Invoke-Git @('rev-parse', "HEAD:$targetPath")).Trim()
    $content = Invoke-Git @('cat-file', 'blob', $targetBlob)
    $bytes = [Text.Encoding]::UTF8.GetBytes(($content -join "`n") + "`n")

    $path = Join-Path $src ($link.Path -replace '/', '\')
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    [IO.File]::WriteAllBytes($path, $bytes)

    # Guard: regular file, no reparse point, content equals the target.
    $item = Get-Item -LiteralPath $path -Force
    if ($item.LinkType) { throw "$($link.Path) is still a reparse point ($($item.LinkType))" }
    $actual = (Invoke-Git @('hash-object', '--', $link.Path)).Trim()
    if ($actual -ne $targetBlob) {
        throw "$($link.Path) content $actual does not match target $targetPath ($targetBlob)"
    }
    Write-Host "materialized $($link.Path) <- $target"
}
Write-Host "verified $($links.Count) symlinks"

# Version string baked into the binaries. Passed explicitly so that build.rs
# never calls `git describe --dirty`, which would append `-dirty` because the
# materialized symlinks differ from the index.
$ref = $env:BUILD_REF
if ($ref -like 'releases/*') {
    $version = $ref.Substring('releases/'.Length)
} else {
    $described = (Invoke-Git @('describe', '--tags', '--always', '--match', 'releases/*')).Trim()
    $version = $described -replace '^releases/', ''
}

$head = (Invoke-Git @('rev-parse', '--short', 'HEAD')).Trim()
$epoch = (Invoke-Git @('log', '-1', '--pretty=%ct')).Trim()

Write-Host "version: $version  commit: $head  epoch: $epoch"

foreach ($line in @(
        "RADICLE_VERSION=$version",
        "GIT_HEAD=$head",
        "SOURCE_DATE_EPOCH=$epoch")) {
    $line >> $env:GITHUB_ENV
}
"version=$version" >> $env:GITHUB_OUTPUT
