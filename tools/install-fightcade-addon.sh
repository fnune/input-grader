#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  echo "usage: $0 [Fightcade's fbneo folder, default: the Linux Flatpak's data folder]"
  echo "copies the add-on from this repository into the training mode, as the release zip would"
  exit 0
fi

repo=$(cd "$(dirname "$0")/.." && pwd)
fbneo=${1:-$HOME/.var/app/com.fightcade.Fightcade/data}

if [[ ! -f "${fbneo}/fbneo-training-mode/fbneo-training-mode.lua" ]]; then
  echo "no fbneo-training-mode/fbneo-training-mode.lua in ${fbneo}; start Fightcade once, or pass the folder" >&2
  exit 1
fi

"${repo}/tools/build-addon.sh" "${fbneo}"
echo "installed into ${fbneo}/fbneo-training-mode/games/sfiii3/addon"
echo "Start 3rd Strike in Fightcade with its training mode; the grader loads with it."
