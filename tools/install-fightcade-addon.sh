#!/usr/bin/env bash
# Install the input grader as an add-on of Fightcade's training mode, so both run together.
# Usage: tools/install-fightcade-addon.sh [fbneo-training-mode folder]
# Without an argument, uses the Linux Flatpak's copy. On Windows, see the README: copy the two
# files into <Fightcade>\emulator\fbneo\fbneo-training-mode\games\sfiii3\addon\.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
training=${1:-$HOME/.var/app/com.fightcade.Fightcade/data/fbneo-training-mode}

if [[ ! -f "${training}/fbneo-training-mode.lua" ]]; then
  echo "no fbneo-training-mode.lua in ${training}; start Fightcade once, or pass the folder" >&2
  exit 1
fi

# The game-specific add-on folder is not part of Fightcade's own files, so the Flatpak launcher,
# which copies those over the training mode on every start, leaves it alone.
addon="${training}/games/sfiii3/addon"
mkdir -p "${addon}"
# The training mode loads every file listed in addons_run from this folder.
printf 'addons_run = { "input_grader.lua" }\n' > "${addon}/addons.lua"
# Fightcade's FBNeo runs under Wine on Linux, where the repository is under drive Z:.
grader="Z:${repo//\//\\}\\"
sed "s|@GRADER@|${grader//\\/\\\\}|" "${repo}/tools/fightcade_addon.lua.in" > "${addon}/input_grader.lua"
echo "installed into ${addon}"

if command -v flatpak >/dev/null && flatpak info com.fightcade.Fightcade >/dev/null 2>&1; then
  flatpak override --user --filesystem="${repo}:ro" --filesystem="${repo}/logs" com.fightcade.Fightcade
  echo "Fightcade's Flatpak may now read ${repo} and write ${repo}/logs"
fi
echo "Start 3rd Strike in Fightcade with its training mode; the grader loads with it."
