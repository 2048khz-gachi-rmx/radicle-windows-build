#!/usr/bin/env bash
# Decide whether a build is needed.
#
# Outputs (GITHUB_OUTPUT):
#   kind     release | prerelease | none
#   ref      git ref to build (tag name or commit sha)
#   version  version string for a tag build, empty for a prerelease build
#   sha      upstream commit
set -euo pipefail

SRC="${RADICLE_SOURCE:-https://seed.radicle.xyz/z3gqcJUoA1n9HaHKufZs5FCSGazv5.git}"
REPO="${GITHUB_REPOSITORY:?}"

refs=$(git ls-remote --heads --tags "$SRC")

main_sha=$(awk '$2 == "refs/heads/main" { print $1 }' <<<"$refs")
if [[ -z "$main_sha" ]]; then
    echo "upstream has no main branch at $SRC" >&2
    exit 1
fi

tags=$(awk '{ print $2 }' <<<"$refs" | sed -n 's|^refs/tags/releases/||p' | grep -v '\^{}' | sort -V)

# Highest tag. A suffix (rc/alpha) only wins while its final release is
# missing, because `sort -V` ranks 1.10.0-rc.2 above 1.10.0.
latest_final=$(grep -v -- '-' <<<"$tags" | tail -n1 || true)
latest_pre=$(grep -- '-' <<<"$tags" | tail -n1 || true)
latest_tag="$latest_final"
if [[ -n "$latest_pre" ]]; then
    pre_core="${latest_pre%%-*}"
    if [[ -z "$latest_final" || "$latest_final" != "$pre_core" && \
        "$(printf '%s\n%s\n' "$pre_core" "$latest_final" | sort -V | tail -n1)" == "$pre_core" ]]; then
        latest_tag="$latest_pre"
    fi
fi

echo "upstream main:       $main_sha"
echo "upstream latest tag: ${latest_tag:-<none>}"

published_sha=""
if body=$(gh release view continuous --repo "$REPO" --json body -q .body 2>/dev/null); then
    published_sha=$(sed -n 's/^Upstream-Commit: \(.*\)$/\1/p' <<<"$body" | head -n1)
fi
echo "published continuous: ${published_sha:-<none>}"

if [[ -n "${INPUT_REF:-}" ]]; then
    # Manual override: build this ref even if it is already published.
    ref="$INPUT_REF"
    if [[ "$ref" == releases/* ]]; then kind=release; else kind=prerelease; fi
    echo "override: building $ref ($kind)" >&2
elif [[ -n "$latest_tag" ]] && ! gh release view "$latest_tag" --repo "$REPO" >/dev/null 2>&1; then
    kind=release
    ref="releases/$latest_tag"
elif [[ "$main_sha" != "$published_sha" ]]; then
    kind=prerelease
    ref="$main_sha"
else
    kind=none
    ref=""
fi

version=""
if [[ "$kind" == release ]]; then
    version="${ref#releases/}"
fi

# Resolve the ref to a commit. Annotated tags list both the tag object and the
# peeled commit, so the `^{}` entry wins.
sha=""
if [[ "$kind" != none ]]; then
    sha=$(awk -v name="refs/tags/$ref" -v head="refs/heads/$ref" '
        $2 == head       { direct = $1 }
        $2 == name "^{}" { peeled = $1 }
        $2 == name       { tagged = $1 }
        END {
            if (peeled)      print peeled
            else if (direct) print direct
            else if (tagged) print tagged
        }' <<<"$refs")
    if [[ -z "$sha" ]]; then
        # A commit sha may be given directly, but a typo must not pass.
        if [[ "$ref" =~ ^[0-9a-f]{7,40}$ ]]; then
            sha="$ref"
        else
            echo "$ref is neither a tag, a branch, nor a commit sha" >&2
            exit 1
        fi
    fi
fi

{
    echo "kind=$kind"
    echo "ref=$ref"
    echo "version=$version"
    echo "sha=$sha"
} >>"$GITHUB_OUTPUT"

if [[ "$kind" == none ]]; then
    echo "nothing to build: latest tag published, main unchanged" >&2
else
    echo "build $kind from $ref ($sha)" >&2
fi
