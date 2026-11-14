#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "usage: nix run .#release (no arguments): tags and publishes the version in lua/input_grader/version.lua" >&2
  exit 2
fi

FORGEJO=https://git.fnune.com
FORGEJO_REPO=fnune/input-grader
GITHUB_REPO=fnune/input-grader

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

if [[ -z "${FORGEJO_TOKEN:-}" ]]; then
  echo "FORGEJO_TOKEN is not set, so the release is on GitHub only"
  exit 0
fi

echo "waiting for the GitHub release, to copy it to Forgejo"
for _ in $(seq 1 60); do
  gh release view "${tag}" --repo "${GITHUB_REPO}" >/dev/null 2>&1 && break
  sleep 20
done
gh release view "${tag}" --repo "${GITHUB_REPO}" >/dev/null || fail "no GitHub release for ${tag} after 20 minutes; check the Release workflow"

download="build/release-${version}"
rm -rf "${download}"
gh release download "${tag}" --repo "${GITHUB_REPO}" --pattern "*.zip" --dir "${download}"
zip_path="${download}/input-grader-${version}.zip"

body=$(tools/release-notes.sh "${version}" | python3 -I -c 'import json, sys; print(json.dumps({"tag_name": sys.argv[1], "name": sys.argv[2], "body": sys.stdin.read()}))' "${tag}" "Input grader ${version}")
id=$(curl -sSf -X POST -H "Authorization: token ${FORGEJO_TOKEN}" -H "Content-Type: application/json" \
  "${FORGEJO}/api/v1/repos/${FORGEJO_REPO}/releases" -d "${body}" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["id"])')
curl -sSf -X POST -H "Authorization: token ${FORGEJO_TOKEN}" -F "attachment=@${zip_path}" \
  "${FORGEJO}/api/v1/repos/${FORGEJO_REPO}/releases/${id}/assets?name=input-grader-${version}.zip" >/dev/null
echo "copied ${tag} and its zip to ${FORGEJO}/${FORGEJO_REPO}/releases"
