# Other setups

The [README](../README.md#install) covers the usual install: the release zip, merged into Fightcade's training mode. The zip holds the training mode's add-on folder `games/sfiii3/addon/`: its `addons.lua`, the add-on `input_grader.lua`, and the grader's code and attempt log in `input_grader/`. The zip's `addons.lua` replaces any other 3rd Strike add-on list you had there.

## From this repository

To install the add-on from a clone instead of a release, run:

```sh
tools/install-fightcade-addon.sh [fbneo-folder]
```

It copies the same files the zip holds. Without an argument it installs into the Linux Flatpak's `~/.var/app/com.fightcade.Fightcade/data`; on Windows, run it in Git Bash with your `Fightcade/emulator/fbneo` folder.

## Without the training mode

In a 3rd Strike match, open **Game > Lua Scripting > New Lua Script Window**, browse to `input_grader.lua` in this repository, and run it. Loading a script this way stops any other script, including the training mode. The attempt log goes to the repository's `logs/` folder.

## With 3rd_training_lua

To use the grader with [3rd_training_lua](https://github.com/Grouflon/3rd_training_lua) instead of Fightcade's training mode, write a launcher that runs both in one script:

```sh
tools/install-training-launcher.sh /path/to/3rd_training_lua
```

This writes `3rd_training_with_grader.lua` into the training folder. Load that file instead of `3rd_training.lua`. If Fightcade runs under Wine and the training folder is on another Wine drive, add `--windows-path`.
