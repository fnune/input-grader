#!/usr/bin/env bash
set -euo pipefail

training_dir=${1:?usage: $0 <3rd_training_lua dir> [--windows-path]}
style=${2:-}
repo=$(cd "$(dirname "$0")/.." && pwd)

if [[ ! -f "${training_dir}/3rd_training.lua" ]]; then
  echo "no 3rd_training.lua in ${training_dir}" >&2
  exit 1
fi

grader="${repo}/"
if [[ "${style}" == "--windows-path" ]]; then
  grader="Z:${repo//\//\\}\\"
fi

sed "s|@GRADER@|${grader//\\/\\\\}|" "${repo}/tools/training_launcher.lua.in" > "${training_dir}/3rd_training_with_grader.lua"
echo "wrote ${training_dir}/3rd_training_with_grader.lua"
echo "In Fightcade: Game > Lua Scripting > New Lua Script Window > Browse > 3rd_training_with_grader.lua"
if command -v flatpak >/dev/null && flatpak info com.fightcade.Fightcade >/dev/null 2>&1; then
  echo "Fightcade is a Flatpak; let it read this repo and the training folder:"
  echo "  flatpak override --user --filesystem=${repo}:ro --filesystem=${repo}/logs --filesystem=$(cd "${training_dir}" && pwd) com.fightcade.Fightcade"
fi
