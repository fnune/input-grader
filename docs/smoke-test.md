# Smoke test in Fightcade

A 10-minute check that the riskiest parts of the overlay work inside Fightcade's FBNeo, before the full UI is built on them. `smoke_test.lua` checks each part on its own, shows a checklist on screen, and writes the results to `logs/smoke-test.txt`.

## What it checks

| Check | What it proves |
| --- | --- |
| lua | The Lua version, and that the `bit` and `gd` libraries exist |
| rom | The loaded set is `sfiii3nr1` |
| write logs/ | The script can write its attempt log |
| memory | 3rd Strike's RAM reads work (P1's character and the match state) |
| icon sheet | Fightcade training mode's icon sheet can be found and resampled with `gd` |
| draw speed | How long a sample card takes to draw, against the 16.7 ms of a frame |
| hotkey Alt+6 | Lua hotkeys work |
| joypad, keyboard | The stick, buttons and keyboard can be read |
| menu select, menu block | A menu can be driven with the stick while P1's character stands still |

## Steps

1. Let Fightcade's Flatpak read this repository and write its `logs/` folder (once):

    ```sh
    flatpak override --user \
      --filesystem=/home/fausto/Development/input-grader:ro \
      --filesystem=/home/fausto/Development/input-grader/logs \
      com.fightcade.Fightcade
    ```

2. Start Fightcade and open 3rd Strike in Test Game (offline). Get into a match with Ryu against anyone.
3. **Game > Lua Scripting > New Lua Script Window > Browse**, pick `smoke_test.lua` in this repository, then **Run**. A checklist appears at the top of the screen and a sample card at the bottom.
4. Press **Alt+6**: a small menu opens on the right. Move the stick up and down, press **LP**, then wait 2 seconds without touching anything.
5. Press **Alt+6** again to close it, walk around a bit, and press any key on the keyboard.
6. Take a screenshot if something looks wrong, close the Lua window, and say it's done: the results are in `logs/smoke-test.txt`.

Loading this script stops any other Lua script, including Fightcade's training mode. That is expected; running next to the training mode is the next step after this one.
