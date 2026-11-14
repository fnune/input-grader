# Development

Everything runs through the Nix flake, which pins the toolchain, MAME and the arcade decomp:

```sh
nix develop                 # shell with LuaJIT, Lua 5.4, MAME, stylua, luacheck, Python
nix run .#check             # format check, lint, tests on LuaJIT and Lua 5.4
nix run .#test              # tests only
nix run .#check-roms        # which 3rd Strike sets are in roms/, by file hash
nix run .#gen               # regenerate the command tables from the ROM
nix run .#validate          # Lua checker against the running game, frame by frame
nix run .#grade             # live grader against scripted attempts in the running game
GRADE_SNAPSHOTS=1 nix run .#grade   # the same, saving screenshots to build/snaps
```

Conventions are in [ENGINEERING.md](../ENGINEERING.md), and agent instructions in [AGENTS.md](../AGENTS.md). Adding another game or emulator is described in [porting.md](porting.md), and how the grader reads the game in [the internals](how-it-works.md).

## Other setups

All three run the grader from a clone of this repository.

- `tools/install-fightcade-addon.sh [fbneo-folder]` copies the add-on into Fightcade's training mode, the same files the release zip holds. It defaults to the Linux Flatpak's data folder; on Windows, run it in Git Bash with your `Fightcade/emulator/fbneo` folder.
- Without the training mode, load `input_grader.lua` from **Game > Lua Scripting > New Lua Script Window** in a 3rd Strike match. This stops any other script, the training mode included, and logs to `logs/attempts.csv`.
- With [3rd_training_lua](https://github.com/Grouflon/3rd_training_lua), `tools/install-training-launcher.sh /path/to/3rd_training_lua` writes `3rd_training_with_grader.lua`, which runs both scripts; load it instead of `3rd_training.lua`. FBNeo keeps one callback per hook, so the launcher installs the grader's hook multiplexer first. Add `--windows-path` when Fightcade runs under Wine and the folder is on another Wine drive.

## ROMs

ROMs go in `roms/`, which git ignores, and are checked against `roms.sha1`. The real-game checks need `sfiii3.zip` and `sfiii3n.zip` (MAME set names). Set `ROMSET=sfiii3nr1` to run them on Fightcade's revision instead. ROMs are not included and never will be.

## Verification

The Lua checker has been compared with the running game frame by frame: over 165,000 frames across every character and both Japanese ROM revisions, without a mismatch. The end-to-end verdict checks in `harness/mame/grade.lua` use Ryu. Other characters' verdicts have only been spot-checked.

The overlay's drawing, icons, keys and menu were checked inside Fightcade 2.4.2 (Flatpak, Linux) with a [smoke test](smoke-test.md). A full session as a training-mode add-on is still to do.

## Layout

| Path | Contents |
| --- | --- |
| `input_grader.lua` | The script to load in FBNeo |
| `lua/input_grader/core/` | Game-agnostic: app, card, pearls, menu, drawing, CSV log, hook multiplexer |
| `lua/input_grader/platform/` | FBNeo and MAME adapters |
| `lua/input_grader/games/sfiii3/` | 3rd Strike: generated tables, RAM map, checker port, tracker, grader |
| `harness/mame/` | Real-game validation, end-to-end checks and measurement scripts |
| `tools/` | ROM decryption, table generation, ROM check, struct offsets, add-on and launcher installers |
| `tests/` | Unit tests (`lua tests/run.lua`) |
| `docs/` | Internals, porting, windows reference, this page |

## Attempt log

`attempts.csv` gets one row per graded attempt: time, character, move, facing, result, mistake, per-step timings and margins. The add-on writes it next to itself in the training mode; the other setups write `logs/attempts.csv` in this repository.

## Releases

Versions follow [semantic versioning](https://semver.org/), and the version lives in `lua/input_grader/version.lua`. The menu shows it, and a test checks it matches the newest section of `CHANGELOG.md`.

To release:

1. In one commit, set the new version in `lua/input_grader/version.lua` and add its section at the top of `CHANGELOG.md`, in plain words for players.
2. Push that commit to `main` on Forgejo.
3. Run `nix run .#release`. It checks that the tree is clean, the changelog has the section, the tag is new, `main` on Forgejo is this commit and `nix run .#check` passes. Then it tags `vX.Y.Z` and pushes the tag.

Forgejo's push mirror carries the tag to [GitHub](https://github.com/fnune/input-grader), where the Release workflow checks again, builds `input-grader-X.Y.Z.zip` with `nix run .#package`, and publishes it as a GitHub release with that changelog section as its notes. `nix run .#package` also builds the zip locally, in `build/`.

With `FORGEJO_TOKEN` set, the script then waits for the GitHub release, downloads its zip, and creates the same release on Forgejo with the same notes and zip. GitHub Actions cannot reach Forgejo, which only answers on the VPN. To use the token from the keyring:

```sh
FORGEJO_TOKEN=$(secret-tool lookup service doriath username home-nix/forgejo-fnune) nix run .#release
```

## CI

The Forgejo repository is the primary one; GitHub is a push mirror with issues enabled. GitHub Actions runs `nix run .#check` on every push the mirror makes. The real-game checks need ROMs, so they only run locally.

The mirror pushes over a deploy key, and GitHub rejects changes to `.github/workflows/` pushed that way. After committing such a change, push it to GitHub once yourself (`git push git@github.com:fnune/input-grader.git <commit>:refs/heads/main`); the mirror carries on from there.

## README images

The README's images come from Fightcade screenshots (3840x2160, game in the middle) and are rebuilt with:

```sh
nix run .#readme-images -- ~/Pictures/Screenshots
```

`design/readme_images.py` crops the hero shot. `design/card_explained.py` draws the explained cards: it dims the screenshot outside the card, lights the parts it explains, and labels them in FBNeo's pixel font from `lua/input_grader/core/font.lua`, with pixel arrows. Each figure is a `Spec` there: its screenshot, the parts to light and their labels. Part positions are measured on the screenshot it names, so a new screenshot needs its parts measured again.
