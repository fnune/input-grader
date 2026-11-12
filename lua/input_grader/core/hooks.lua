-- Lets several scripts share an emulator whose Lua API keeps one callback per hook (FBNeo and
-- FBA-RR: a second emu.registerafter replaces the first). install() wraps the registration
-- functions so every callback registered afterwards runs, in registration order.

local M = {}

local MULTI = {
  { "emu", "registerbefore" }, { "emu", "registerafter" }, { "emu", "registerstart" },
  { "emu", "registerexit" }, { "gui", "register" },
  { "savestate", "registerload" }, { "savestate", "registersave" },
}

--- @param env table the global environment holding emu, gui, savestate, input (_G by default)
function M.install(env)
  env = env or _G
  if env.__input_grader_hooks then return env.__input_grader_hooks end
  local installed = { lists = {}, hotkeys = {} }
  for _, pair in ipairs(MULTI) do
    local lib, name = env[pair[1]], pair[2]
    if lib and lib[name] then
      local original = lib[name]
      local list = {}
      installed.lists[pair[1] .. "." .. name] = list
      original(function(...)
        for _, fn in ipairs(list) do fn(...) end
      end)
      lib[name] = function(fn)
        if fn then table.insert(list, fn) end
      end
    end
  end
  if env.input and env.input.registerhotkey then
    local original = env.input.registerhotkey
    env.input.registerhotkey = function(n, fn)
      if installed.hotkeys[n] and env.print then
        env.print("input_grader: hotkey Alt+" .. n .. " registered twice, the later script wins")
      end
      installed.hotkeys[n] = true
      original(n, fn)
    end
  end
  env.__input_grader_hooks = installed
  return installed
end

return M
