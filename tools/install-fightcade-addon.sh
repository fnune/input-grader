#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  echo "usage: $0 [fbneo-training-mode folder, default: the Linux Flatpak's]"
  exit 0
fi

repo=$(cd "$(dirname "$0")/.." && pwd)
training=${1:-$HOME/.var/app/com.fightcade.Fightcade/data/fbneo-training-mode}

if [[ ! -f "${training}/fbneo-training-mode.lua" ]]; then
  echo "no fbneo-training-mode.lua in ${training}; start Fightcade once, or pass the folder" >&2
  exit 1
fi

addon="${training}/games/sfiii3/addon"
mkdir -p "${addon}"
printf 'addons_run = { "input_grader.lua" }\n' > "${addon}/addons.lua"
repo_under_wine="Z:${repo//\//\\}\\"
sed "s|@GRADER@|${repo_under_wine//\\/\\\\}|" "${repo}/tools/fightcade_addon.lua.in" > "${addon}/input_grader.lua"
echo "installed into ${addon}"

if command -v flatpak >/dev/null && flatpak info com.fightcade.Fightcade >/dev/null 2>&1; then
  flatpak override --user --filesystem="${repo}:ro" --filesystem="${repo}/logs" com.fightcade.Fightcade
  echo "Fightcade's Flatpak may now read ${repo} and write ${repo}/logs"
fi
echo "Start 3rd Strike in Fightcade with its training mode; the grader loads with it."
