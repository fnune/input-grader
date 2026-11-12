-- FBNeo scripts run on Lua 5.1 (LuaJIT for tests); the emulator provides these globals.
std = "lua51+lua54"
max_line_length = 120
globals = { "emu", "gui", "memory", "input", "joypad", "savestate", "bit", "manager", "__input_grader_hooks" }
exclude_files = { "lua/input_grader/games/sfiii3/commands.lua" }
files["harness"] = { globals = { "manager", "emu" } }
