#!/usr/bin/env python3
import hashlib
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def known():
    sets = defaultdict(dict)
    for line in (ROOT / "roms.sha1").read_text().splitlines():
        if line and not line.startswith("#"):
            sha1, path = line.split()
            machine, name = path.split("/", 1)
            sets[machine][name] = sha1
    return sets


def present(roms_dir):
    hashes = set()
    for archive in sorted(Path(roms_dir).glob("*.zip")):
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist():
                hashes.add(hashlib.sha1(z.read(info.filename)).hexdigest())
    return hashes


def main(roms_dir, required=None):
    have = present(roms_dir)
    complete = []
    for machine, files in known().items():
        missing = [n for n, h in files.items() if h not in have]
        state = "complete" if not missing else f"missing {len(missing)} of {len(files)}"
        print(f"{machine:10} {state}")
        if not missing:
            complete.append(machine)
    if required and required not in complete:
        sys.exit(f"{required} is not complete in {roms_dir}")


if __name__ == "__main__":
    main(*sys.argv[1:])
