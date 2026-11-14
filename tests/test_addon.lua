local T = require("helpers")

local DRIVER = [[
local function noop() end
local function slot() return noop end
emu = { registerbefore = slot(), registerafter = slot(), registerstart = slot(), registerexit = slot(),
  romname = function() return "sfiii3nr1" end, framecount = function() return 0 end }
gui = { register = slot(), text = noop, box = noop }
savestate = { registerload = slot(), registersave = slot() }
input = { registerhotkey = noop }
local function zero() return 0 end
memory = { readbyte = zero, readword = zero, readwordsigned = zero, readdword = zero }
registers = { registerbefore = {}, registerafter = {}, guiregister = {} }
dofile("addon/addons.lua")
dofile("games/sfiii3/addon/addons.lua")
for _, name in ipairs(addons_run) do
  dofile("games/sfiii3/addon/" .. name)
end
for _, list in pairs(registers) do
  for _, fn in ipairs(list) do fn() end
end
io.write("hooks ", #registers.registerbefore, " ", #registers.registerafter, " ", #registers.guiregister, "\n")
]]

local EFFIE_DRIVER = [[
local function noop() end
local hooks = {}
local function slot(name) return function(fn) hooks[name] = fn end end
local function start_now(fn) hooks.start = fn; fn() end
emu = { registerbefore = slot("before"), registerafter = slot("after"), registerstart = start_now,
  registerexit = slot("exit"), romname = function() return "sfiii3nr1" end, framecount = function() return 0 end }
gui = { register = slot("gui"), text = noop, box = noop }
savestate = { registerload = slot("load"), registersave = slot("save") }
input = { registerhotkey = noop }
local function zero() return 0 end
memory = { readbyte = zero, readword = zero, readwordsigned = zero, readdword = zero }
dofile("fbneo-training-mode.lua")
for _, name in ipairs({ "before", "after", "gui" }) do
  if hooks[name] then hooks[name]() end
end
local lists = __input_grader_hooks.lists
io.write("effie ", tostring(effie_ran), " before ", #lists["emu.registerbefore"],
  " after ", #lists["emu.registerafter"], " gui ", #lists["gui.register"], "\n")
]]

local FAKE_EFFIE = [[
emu.registerstart(function() effie_started = true end)
emu.registerbefore(function() effie_ran = effie_started end)
gui.register(function() end)
]]

local function interpreter()
  local i = -1
  while arg and arg[i - 1] do
    i = i - 1
  end
  return arg and arg[i] or "lua"
end

local function run(command)
  local p = assert(io.popen(command .. " 2>&1"))
  local out = p:read("*a")
  p:close()
  return out
end

local function exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
  end
  return f ~= nil
end

local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

return {
  {
    "with effie3rd's training mode, the add-on runs first and multiplexes the hooks, so both scripts' callbacks run",
    function()
      local dest = os.tmpname()
      os.remove(dest)
      run(
        "tools/build-addon.sh "
          .. dest
          .. " && cp tools/effie3rd_entry.lua "
          .. dest
          .. "/fbneo-training-mode/fbneo-training-mode.lua"
      )
      local training = dest .. "/fbneo-training-mode"
      run("mkdir -p " .. training .. "/src/data")
      write(training .. "/src/data/game_data.lua", "return {}\n")
      write(training .. "/3rd_training.lua", FAKE_EFFIE)
      write(training .. "/driver.lua", EFFIE_DRIVER)
      local out = run("cd " .. training .. " && " .. interpreter() .. " driver.lua")
      run("rm -rf " .. dest)
      T.contains(out, "loaded")
      T.contains(out, "effie true before 2 after 1 gui 2")
    end,
  },
  {
    "the add-on runs from the training mode's folder with relative paths, hooks in, and logs next to itself",
    function()
      local dest = os.tmpname()
      os.remove(dest)
      run("mkdir -p " .. dest .. "/fbneo-training-mode/addon && tools/build-addon.sh " .. dest)
      local training = dest .. "/fbneo-training-mode"
      local f = assert(io.open(training .. "/addon/addons.lua", "w"))
      f:write("addons_run = {}\n")
      f:close()
      f = assert(io.open(training .. "/driver.lua", "w"))
      f:write(DRIVER)
      f:close()
      local out = run("cd " .. training .. " && " .. interpreter() .. " driver.lua")
      local logged = exists(training .. "/games/sfiii3/addon/input_grader/attempts.csv")
      run("rm -rf " .. dest)
      T.contains(out, "loaded")
      T.contains(out, "hooks 1 1 1")
      T.truthy(logged, "attempts.csv next to the add-on")
    end,
  },
}
