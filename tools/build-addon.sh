#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" == -h || "$1" == --help ]]; then
  echo "usage: $0 DEST" >&2
  echo "writes the add-on as DEST/fbneo-training-mode/games/sfiii3/addon/, mirroring Fightcade's folders" >&2
  exit 2
fi

repo=$(cd "$(dirname "$0")/.." && pwd)
addon="$1/fbneo-training-mode/games/sfiii3/addon"
mkdir -p "${addon}/input_grader"
printf 'addons_run = { "input_grader.lua" }\n' > "${addon}/addons.lua"
cp "${repo}/tools/fightcade_addon.lua" "${addon}/input_grader.lua"
rm -rf "${addon}/input_grader/lua"
cp -r "${repo}/lua" "${addon}/input_grader/lua"
cp "${repo}/LICENSE" "${addon}/input_grader/LICENSE"
