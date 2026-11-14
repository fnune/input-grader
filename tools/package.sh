#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 's/^return "\(.*\)"$/\1/p' "${repo}/lua/input_grader/version.lua")
name="input-grader-${version}"
stage="${repo}/build/${name}"
zip_path="${repo}/build/${name}.zip"

rm -rf "${stage}" "${zip_path}"
mkdir -p "${stage}"
"${repo}/tools/build-addon.sh" "${stage}"
"${repo}/tools/build-addon.sh" "${stage}/effie3rd-compatible"
cp "${repo}/tools/effie3rd_entry.lua" "${stage}/effie3rd-compatible/fbneo-training-mode/fbneo-training-mode.lua"
cp "${repo}/LICENSE" "${stage}/LICENSE.txt"
cat > "${stage}/README.txt" <<TXT
Input grader ${version}, for Street Fighter III: 3rd Strike in Fightcade 2's training mode.

To install, copy the fbneo-training-mode folder from this zip into this folder,
and if asked, choose to replace the files:

  On Windows: Documents\\Fightcade\\emulator\\fbneo
  On Linux with the Flatpak: ~/.var/app/com.fightcade.Fightcade/data

If you use effie3rd's training mode, copy effie3rd-compatible/fbneo-training-mode
instead.

Then start 3rd Strike with Fightcade's training mode, and press M in a match.

To update, do the same with a newer zip. The grader lives in
fbneo-training-mode\\games\\sfiii3\\addon: if you already have that folder, back it up
first; to uninstall, delete it or put your backup back.

More, and the source code: https://github.com/fnune/input-grader
TXT
(cd "${stage}" && zip -qr "${zip_path}" .)
echo "${zip_path}"
