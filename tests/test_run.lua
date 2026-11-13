local run = require("input_grader.core.run")
local fbneo = require("input_grader.platform.fbneo")
local ram = require("input_grader.games.sfiii3.ram")
local T = require("helpers")

local function fake_platform()
  local p = { printed = {}, stick = {} }
  function p.on_before(fn)
    p.before = fn
  end
  function p.on_frame(fn)
    p.frame = fn
  end
  function p.on_draw(fn)
    p.draw = fn
  end
  function p.print(s)
    table.insert(p.printed, s)
  end
  function p.keys()
    return {}
  end
  function p.pad()
    return p.stick
  end
  function p.block()
    p.stick = {}
  end
  return p
end

local function fake_ram(row, w_ptrs)
  local work = ram.WAZA_WORK[1]
  return {
    u8 = function()
      return 0
    end,
    u16 = function(a)
      if a == ram.PLAYER[1] + ram.PLAYER_NUMBER then
        return row
      end
      return 0
    end,
    s16 = function()
      return 0
    end,
    u32 = function(a)
      return w_ptrs[(a - work - 8) / ram.WORK_SIZE] or 0
    end,
  }
end

return {
  {
    "a failing callback is reported once and runs again next frame, so the emulator keeps the script",
    function()
      local p = fake_platform()
      local calls = 0
      run.attach(p, {
        frame = function()
          calls = calls + 1
          error("boom")
        end,
      })
      p.frame()
      p.frame()
      T.eq(calls, 2)
      T.eq(#p.printed, 1)
      T.contains(p.printed[1], "boom")
    end,
  },
  {
    "the real stick is read before it is blocked, since a blocked pad reads as released",
    function()
      local p = fake_platform()
      local seen
      run.attach(p, {
        controls = function(_, _, pad)
          seen = pad.down
        end,
        blocks_input = function()
          return true
        end,
      })
      p.stick = { down = true }
      p.before()
      T.eq(seen, true)
    end,
  },
  {
    "a slot's lowest w_ptr is its idle state, so steps are counted without the ROM's addresses",
    function()
      local base = 0x06123456
      local w_ptrs = { [0] = base + 8 }
      local r = ram.new(fake_ram(2, w_ptrs), 1)
      local active = { [0] = true }
      T.eq(r:read_commands(active).work[0].ptr, 2)
      w_ptrs[0] = base
      T.eq(r:read_commands(active).work[0].ptr, 2)
      w_ptrs[0] = base + 16
      T.eq(r:read_commands(active).work[0].ptr, 4)
    end,
  },
  {
    "Windows: the icon sheet is looked for next to the emulator, which Lua's cpath names",
    function()
      local dirs = fbneo.sheet_dirs({
        package = { cpath = ".\\?.dll;D:\\Games\\Fightcade\\emulator\\fbneo\\?.dll;D:\\Games\\loadall.dll" },
      })
      T.eq(dirs[1], "D:\\Games\\Fightcade\\emulator\\fbneo\\fbneo-training-mode\\")
    end,
  },
}
