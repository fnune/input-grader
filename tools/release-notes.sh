#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 VERSION" >&2
  exit 2
fi

repo=$(cd "$(dirname "$0")/.." && pwd)
notes=$(awk -v v="## $1" '$0 == v { on = 1; next } on && /^## / { exit } on' "${repo}/CHANGELOG.md")
if [[ -z "${notes//[[:space:]]/}" ]]; then
  echo "CHANGELOG.md has no section for $1" >&2
  exit 1
fi
printf '%s\n' "${notes}" | sed -e '/./,$!d'
