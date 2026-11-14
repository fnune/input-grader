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
cp "${repo}/LICENSE" "${stage}/LICENSE.txt"
cat > "${stage}/README.txt" <<TXT
Input grader ${version}, for Street Fighter III: 3rd Strike on Fightcade.

To install, drag the fbneo-training-mode folder from this zip onto Fightcade's
emulator\\fbneo folder, and say yes when asked to merge the folders. Then start
3rd Strike with Fightcade's training mode. Press M in a match for the menu.

On Linux with Fightcade's Flatpak, extract the zip into
~/.var/app/com.fightcade.Fightcade/data instead.

To update, do the same with a newer zip.

More, and the source code: https://github.com/fnune/input-grader
TXT
(cd "${stage}" && zip -qr "${zip_path}" .)
echo "${zip_path}"
