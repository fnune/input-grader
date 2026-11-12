-- FBNeo (and Fightcade's fcadefbneo) adapter: the emulator's Lua 5.1 API behind the small
-- interface the app needs. `env` is injectable so the adapter can be tested with fakes.

local M = {}

local COLORS = {
  text = 0xFFFFFFFF,
  dim = 0xB0B0B0FF,
  good = 0x50E070FF,
  bad = 0xFF6060FF,
  warn = 0xFFD050FF,
  panel = 0x000000B0,
  edge = 0x606060FF,
}

function M.new(env)
  env = env or _G
  local memory, gui, emu, input = env.memory, env.gui, env.emu, env.input
  local p = {}

  p.name = "fbneo"
  p.romname = emu.romname and emu.romname() or "?"
  p.mem = {
    u8 = memory.readbyte,
    u16 = memory.readword,
    s16 = memory.readwordsigned,
    u32 = memory.readdword,
  }
  p.canvas = {
    text = function(_, x, y, s, color)
      gui.text(x, y, s, COLORS[color] or COLORS.text, 0x000000FF)
    end,
    box = function(_, x1, y1, x2, y2, fill, edge)
      gui.box(x1, y1, x2, y2, COLORS[fill] or fill, COLORS[edge] or edge)
    end,
  }

  function p.on_frame(fn)
    emu.registerafter(fn)
  end
  function p.on_draw(fn)
    gui.register(fn)
  end
  function p.hotkey(n, fn)
    input.registerhotkey(n, fn)
  end
  -- Emulated time: frames at 60 per second, so pauses and fast-forward behave.
  function p.clock()
    return emu.framecount() / 60
  end
  function p.timestamp()
    return env.os.date("!%Y-%m-%dT%H:%M:%SZ")
  end
  function p.print(s)
    env.print(s)
  end

  --- A function that appends a line to `path`, writing `header` first when the file is new.
  function p.appender(path, header)
    local existing = env.io.open(path, "r")
    if existing then
      existing:close()
    else
      local f = env.io.open(path, "w")
      if f then
        f:write(header .. "\n")
        f:close()
      end
    end
    return function(line)
      local f = env.io.open(path, "a")
      if not f then
        return
      end
      f:write(line .. "\n")
      f:close()
    end
  end

  return p
end

return M
