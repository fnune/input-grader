#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "${repo}"
version=$(sed -n 's/^return "\(.*\)"$/\1/p' lua/input_grader/version.lua)
tag="v${version}"

fail() {
  echo "release: $*" >&2
  exit 1
}

[[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes; commit them first"
tools/release-notes.sh "${version}" >/dev/null || fail "add a ## ${version} section to CHANGELOG.md"
git rev-parse -q --verify "refs/tags/${tag}" >/dev/null && fail "${tag} already exists; bump lua/input_grader/version.lua"
head=$(git rev-parse HEAD)
remote_main=$(git ls-remote origin refs/heads/main | cut -f1)
[[ "${head}" == "${remote_main}" ]] || fail "HEAD is not origin's main; push the release commit first"
nix run .#check

git tag -a "${tag}" -m "Input grader ${version}" "${head}"
git push origin "${tag}"
echo "pushed ${tag}; the mirror carries it to GitHub, where the Release workflow builds input-grader-${version}.zip and publishes it"
