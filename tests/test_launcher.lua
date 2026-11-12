local hooks = require("input_grader.core.hooks")
local T = require("helpers")

-- A fake of FBNeo's Lua API: one callback per hook, like the real emulator.
local function fake_fbneo(memory_reader)
  local env = { registered = {}, hotkeys = {}, printed = {}, drawn = {} }
  local function slot(name)
    return function(fn)
      env.registered[name] = fn
    end
  end
  env.emu = {
    registerbefore = slot("before"),
    registerafter = slot("after"),
    registerstart = slot("start"),
    registerexit = slot("exit"),
    romname = function()
      return "sfiii3nr1"
    end,
    framecount = function()
      return 0
    end,
  }
  env.gui = {
    register = slot("gui"),
    text = function(_, _, s)
      table.insert(env.drawn, s)
    end,
    box = function() end,
  }
  env.savestate = { registerload = slot("load"), registersave = slot("save") }
  env.input = {
    registerhotkey = function(n, fn)
      env.hotkeys[n] = fn
    end,
  }
  local read = memory_reader or function()
    return 0
  end
  env.memory = { readbyte = read, readword = read, readwordsigned = read, readdword = read }
  env.os, env.io = os, io
  env.print = function(s)
    table.insert(env.printed, s)
  end
  return env
end

return {
  {
    "two scripts' after-frame callbacks both run once hooks are installed",
    function()
      local env = fake_fbneo()
      hooks.install(env)
      local calls = {}
      env.emu.registerafter(function()
        table.insert(calls, "training")
      end)
      env.emu.registerafter(function()
        table.insert(calls, "grader")
      end)
      env.registered.after()
      T.eq(table.concat(calls, ","), "training,grader")
    end,
  },
  {
    "the FBNeo entry script runs a frame and draws against the fake API",
    function()
      local env = fake_fbneo()
      local saved = {}
      for _, k in ipairs({ "emu", "gui", "savestate", "input", "memory", "print" }) do
        saved[k] = _G[k]
        _G[k] = env[k]
      end
      local ok, err = pcall(function()
        package.loaded["input_grader.platform.fbneo"] = nil
        local platform = require("input_grader.platform.fbneo").new(env)
        local app = require("input_grader.games.sfiii3").build(platform, {})
        require("input_grader.core.run").attach(platform, app)
        env.registered.after()
        env.registered.gui()
        env.hotkeys[7]()
        env.registered.gui()
      end)
      for k, v in pairs(saved) do
        _G[k] = v
      end
      T.truthy(ok, tostring(err))
      T.truthy(#env.drawn > 0, "drew something")
    end,
  },
}
