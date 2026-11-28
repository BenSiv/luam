#!/usr/bin/env bash
set -euo pipefail

# Build and verify Luam itself plus every core Luam stack checkout.
#
# Usage:
#   ./bld/test_stack.sh [--skip-luam-build] [repo1 repo2 ...]
#
# Environment:
#   PROJECTS_DIR  Directory holding sibling repo checkouts (default: parent of luam)

LUAM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECTS_DIR="${PROJECTS_DIR:-$(cd "$LUAM_ROOT/.." && pwd)}"

SKIP_BUILD=0
REPOS=()
for arg in "$@"; do
    case "$arg" in
        --skip-luam-build)
            SKIP_BUILD=1
            ;;
        *)
            REPOS+=("$arg")
            ;;
    esac
done

if [ "${#REPOS[@]}" -eq 0 ]; then
    REPOS=(daat brain-ex teken seder warden camopass luametry automations)
fi

cd "$LUAM_ROOT"
if [ "$SKIP_BUILD" -eq 0 ]; then
    echo "=== [luam] Building language & C extension modules ==="
    bash bld/build_lang.sh
    bash bld/build_libs.sh
fi

echo "=== [luam] Running core & stdlib test suite ==="
make test

PASS_LIST=("luam")
FAIL_LIST=()
SKIP_LIST=()

for repo in "${REPOS[@]}"; do
    repo_dir="$PROJECTS_DIR/$repo"
    if [ ! -d "$repo_dir" ] && [ -d "/opt/teken-build/$repo" ]; then
        repo_dir="/opt/teken-build/$repo"
    fi

    if [ ! -d "$repo_dir" ]; then
        echo "=== [$repo] SKIP (checkout not found at $PROJECTS_DIR/$repo) ==="
        SKIP_LIST+=("$repo (missing)")
        continue
    fi

    if [ ! -f "$repo_dir/bld/test.sh" ]; then
        echo "=== [$repo] SKIP (no bld/test.sh yet) ==="
        SKIP_LIST+=("$repo (no bld/test.sh)")
        continue
    fi

    echo "=== [$repo] Running bld/test.sh against LUAM_DIR=$LUAM_ROOT ==="
    if (cd "$repo_dir" && LUAM_DIR="$LUAM_ROOT" bash bld/test.sh); then
        PASS_LIST+=("$repo")
    else
        FAIL_LIST+=("$repo")
    fi
done

echo
echo "=== Luam Stack Verification Summary ==="
echo "  Passed (${#PASS_LIST[@]}): ${PASS_LIST[*]}"
if [ "${#SKIP_LIST[@]}" -gt 0 ]; then
    echo "  Skipped (${#SKIP_LIST[@]}): ${SKIP_LIST[*]}"
fi
if [ "${#FAIL_LIST[@]}" -gt 0 ]; then
    echo "  FAILED (${#FAIL_LIST[@]}): ${FAIL_LIST[*]}" >&2
    exit 1
fi
