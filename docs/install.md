# Other setups

The [README](../README.md#install) covers the usual install: the add-on script, on Linux with Fightcade's Flatpak or on Windows with Git Bash. On Linux the script also lets the Flatpak read this repository and write its `logs/` folder.

## Windows without Git Bash

Create the folder `fbneo-training-mode\games\sfiii3\addon\` next to Fightcade's emulator, and put two files in it:

- `addons.lua`, containing `addons_run = { "input_grader.lua" }`
- a copy of `tools\fightcade_addon.lua.in` named `input_grader.lua`, with `@GRADER@` replaced by the path of this repository, ending in a backslash

## Without the training mode

In a 3rd Strike match, open **Game > Lua Scripting > New Lua Script Window**, browse to `input_grader.lua` in this repository, and run it. Loading a script this way stops any other script, including the training mode.

## With 3rd_training_lua

To use the grader with [3rd_training_lua](https://github.com/Grouflon/3rd_training_lua) instead of Fightcade's training mode, write a launcher that runs both in one script:

```sh
tools/install-training-launcher.sh /path/to/3rd_training_lua
```

This writes `3rd_training_with_grader.lua` into the training folder. Load that file instead of `3rd_training.lua`. If Fightcade runs under Wine and the training folder is on another Wine drive, add `--windows-path`.
