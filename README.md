# Input grader

Frame-accurate feedback on special move inputs for Street Fighter III: 3rd Strike, as an overlay for [Fightcade](https://www.fightcade.com/)'s FBNeo. After every attempt it shows what the move needed next to what you did, how many frames each part took against the window the game allows, and what went wrong when the move did not come out.

![The overlay in Fightcade after a clean 2MK xx Shinkuu Hadoken: the card's name line reads CLEAN 16F (MIN 4F), each input of 236236+P has a green meter of frames used over frames allowed, a gold sparkle marks the clean attempt, and recent attempts sit underneath as pearls](docs/images/clean-super.jpg)

The windows are the game's own: read from the command tables in the arcade ROM, and checked against the running game frame by frame (over 165,000 frames across every character and both Japanese ROM revisions, without a mismatch).

## Features

- **A card per attempt** for every special move and super art, for all 20 characters. One column per input of the motion plus the button: what the move needs on top, what you did in that input's time below it, and a meter with frames used over frames allowed.
- **Specific feedback** when it fails, in a few words and icons: a skipped diagonal (`NO ↘`), a direction too late and by how much (`↘ +3F LATE`), a button too early or too late, a motion cancelled by up, a cancel from a normal past its window (`HP +3F LATE CANCEL`) or from a normal that whiffed. The input that broke the attempt is boxed in red.
- **Clean and frame-perfect**: an attempt where every input used at most half its window earns a gold sparkle and CLEAN; the fastest possible input turns the card gold.
- **Recent attempts** as pearls under the card (red missed, green out, grey refused by the game, a gold plus for clean, all gold for frame-perfect). Page Up and Page Down step back through them.
- **Target any move** you can practise alone: specials, super arts, dashes and the high jump. Dashes and the high jump are only graded while targeted.
- **Timing after a dash**: target DASH > THROW, DASH > BUTTON or BACK DASH > BUTTON. The card times your first press against the first frame the dash lets you act: FRAME-PERFECT, how many frames late, or how many early (the game drops an early press). For throws it also says when LP and LK were split or the throw was out of range.
- **Mash moves**: Chun-Li's Hyakuretsukyaku, the one move started by mashing, gets a card with a slot per press: five of one kick strength, or why not (too few, or strengths mixed, which the game does not add up).
- **Parry practice**: target PARRY and let the opponent attack (another player, or the training mode's recorded dummy). Each hit gets a card: the direction the attack needed, your tap, and where the hit landed in your 10-frame window, or how many frames early or late you were. With a target, moving around between reps never counts as an attempt, and a running count shows your success rate since you picked it.
- **Attempt log**: every graded attempt appended to `logs/attempts.csv` for comparing sessions.
- **Runs inside Fightcade's training mode** as an add-on, next to its hitboxes and input display, with Fightcade's own icons.
- **Reference tables**: [every character's motions and windows](docs/windows.md), generated from the ROM.

## Requirements

- Fightcade 2 with 3rd Strike (the `sfiii3nr1` set, which Fightcade uses).
- This repository on the same machine.

## Install

### Linux (Fightcade Flatpak)

Start Fightcade once, then run:

```sh
tools/install-fightcade-addon.sh
```

It adds the grader to Fightcade's training mode and lets the Flatpak read this repository and write its `logs/` folder. Start 3rd Strike with Fightcade's training mode, as usual: the grader loads with it.

### Windows

Run Git Bash in this repository and pass your training mode folder:

```sh
tools/install-fightcade-addon.sh "/c/path/to/Fightcade/emulator/fbneo/fbneo-training-mode"
```

Without Git Bash, create the folder `fbneo-training-mode\games\sfiii3\addon\` next to Fightcade's emulator, and put two files in it: `addons.lua` containing `addons_run = { "input_grader.lua" }`, and a copy of `tools\fightcade_addon.lua.in` named `input_grader.lua`, with `@GRADER@` replaced by the path of this repository ending in a backslash.

### Without the training mode

In a 3rd Strike match, open **Game > Lua Scripting > New Lua Script Window**, **Browse** to `input_grader.lua` in this repository, and **Run**. Loading a script this way stops any other script, including the training mode.

## Controls

Plain keys, no setup in the emulator. Only `M MENU` is shown on screen; the menu lists the rest.

| Key | Action |
| --- | --- |
| M | Open or close the menu to pick a target move (and show the overlay if hidden). While it is open your character stands still: the stick moves through the list, LP picks, LK closes |
| H | Hide or show the overlay |
| Page Up, Page Down | Step back and forward through recent attempts; a new attempt returns to the latest |

If you map FBNeo's Lua Hotkeys 8 and 9 (Input > Map game inputs), they do the same as M and H.

## Reading the card

| Part | Meaning |
| --- | --- |
| Name line | The move, then CLEAN or FRAME-PERFECT, or what went wrong. TARGET in front marks your target move |
| Top row | What the move needs: each direction, then the button. A dashed box is an optional direction (the last 6 of a super). A small ball on a slot means "then let go" (the Shoryuken's first 6) |
| Middle row | What you did in that input's time. The first column also shows how long you held the first direction |
| Meters | Frames since the previous input over frames allowed: `2/10`. The bar is green up to half the window, orange past half, red past the end, with a notch where the window ended |
| Box colour | Green: the move came out. Red: it did not. Grey: your input was right but the game refused the move (busy, or a fireball still on screen). Gold: frame-perfect |
| Pearls | Recent attempts; the one shown is bigger and lifted |
| Dimmed card | It no longer answers what you did: a button since then got no card, or it is for another move than your target |
| Line above the card | With a target: successes over attempts and the rate since you picked it. A refused input counts as a success |

The verdicts are explained in [how it works](docs/how-it-works.md#verdicts).

## Attempt log

Every graded attempt is appended to `logs/attempts.csv`: time, character, move, facing, result, mistake, per-step timings and margins.

## Running with 3rd_training_lua

To use the grader with [3rd_training_lua](https://github.com/Grouflon/3rd_training_lua) instead of Fightcade's training mode, write a launcher that runs both in one script:

```sh
tools/install-training-launcher.sh /path/to/3rd_training_lua
```

This writes `3rd_training_with_grader.lua` into the training folder. Load that file instead of `3rd_training.lua`. If Fightcade runs under Wine and the training folder is on another Wine drive, add `--windows-path`.

## What the game does that you might not expect

From the game's own code, each pinned by a test:

- Each direction must come within a window counted from the previous one: 10 frames for most steps, 14 for the second 2 of a super motion, 5 for the 2 of a Shoryuken.
- The button may come on the frame the motion completes or up to 10 frames later.
- Most specials also come out on the release of a button (negative edge).
- The Shoryuken's 6 can be held as long as you like; the 5-frame window starts when you let go of it.
- Holding down before a Hadoken re-arms the motion every 11 frames, so the 10 frames for the next direction count from the last re-arm, not from letting go of down. A slow roll through down-back after a long crouch can fail by luck of timing.
- Super motions do not check the last 6: 23623+P is enough.
- Only an exact up cancels a motion. Up-forward does not.
- A super from a normal needs the normal to hit or be blocked, and only works for a few frames after: from Ryu's 2MK, HP 7 to 19 frames after MK. Later, the game refuses the super until the kick has recovered.

Details in [how it works](docs/how-it-works.md); every move's windows in [windows.md](docs/windows.md).

## Limitations

- P1 only.
- Validated in the real game on both the Japan 990608 set and Fightcade's 990512 set.
- Charge, 360 and mash moves are graded, with less specific feedback than motions.
- The end-to-end verdict checks use Ryu; other characters' command checks are validated frame by frame, but their verdicts have only been spot-checked.
- The overlay's drawing, icons, keys and menu were checked inside Fightcade 2.4.2 (Flatpak, Linux) with a smoke test (`smoke_test.lua`, [steps](docs/smoke-test.md)); a full session as a training-mode add-on is next.

## Development

Everything runs through the Nix flake, which pins the toolchain, MAME and the decomp:

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

ROMs go in `roms/` (ignored by git) and are checked against `roms.sha1`. The real-game checks need `sfiii3.zip` and `sfiii3n.zip` (MAME set names); set `ROMSET=sfiii3nr1` to run them on Fightcade's revision. Engineering conventions are in [ENGINEERING.md](ENGINEERING.md); adding another game or emulator is described in [porting.md](docs/porting.md).

### Layout

| Path | Contents |
| --- | --- |
| `input_grader.lua` | The script to load in FBNeo |
| `lua/input_grader/core/` | Game-agnostic: app, card, pearls, menu, drawing, CSV log, hook multiplexer |
| `lua/input_grader/platform/` | FBNeo and MAME adapters |
| `lua/input_grader/games/sfiii3/` | 3rd Strike: generated tables, RAM map, checker port, tracker, grader |
| `harness/mame/` | Real-game validation and end-to-end checks |
| `tools/` | ROM decryption, table generation, ROM check, struct offsets, add-on and launcher installers |
| `tests/` | Unit tests (`lua tests/run.lua`) |
| `docs/` | How it works, porting, windows reference |

## Roadmap

- P2 support, so you can grade from either side of a netplay or training session.
- A training journal: progress per move over days and weeks, built from the attempt log.
- Red parry detail: the card says when a parry needed the shorter red window, but not yet whether the attack counted as a normal (3 frames) or a special (2 frames).
- More actions before a press: landing from a jump, the end of blockstun (reversals) and waking up. Each needs its own routine and first actionable frame measured; the follow-up tracker and card already take any action.
- A move cheatsheet on a hotkey: the current character's specials and selected super art, drawn with the same icons as the grid, with each step's window and the optional last directions. The command tables already hold everything it needs.
- A pinned FBNeo build under Wine in the flake, to try the script without Fightcade. FBNeo's Lua only exists in its Windows build, and its command line takes a game or a script but not both, so this would be a manual check rather than an automated one.
- Other games, using the porting interfaces.

## Credits

- [sfIII3-cps3-decomp](https://github.com/gibletto/sfIII3-cps3-decomp): the annotated arcade decompilation this project's understanding of the command check comes from. The checker port follows its `CMD_MAIN_2.C`, and the tables are labelled with its names.
- [3s-decomp](https://github.com/crowded-street/3s-decomp): the PS2 decompilation, used to get started.
- [3rd_training_lua](https://github.com/Grouflon/3rd_training_lua): player object and match state addresses, and an independent check of the RAM layout.
- [MAME](https://www.mamedev.org/): the headless test bench. [FBNeo](https://github.com/finalburnneo/FBNeo): the emulator Fightcade runs.

## Licence

Not chosen yet. The generated tables and the checker port derive from the arcade decomp, which is AGPL-3.0, so a public release would most simply be AGPL-3.0 too. ROMs are not included and never will be.
