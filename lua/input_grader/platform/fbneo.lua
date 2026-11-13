local M = {}

local PAD = {
  up = "P1 Up",
  down = "P1 Down",
  left = "P1 Left",
  right = "P1 Right",
  LP = "P1 Weak Punch",
  MP = "P1 Medium Punch",
  HP = "P1 Strong Punch",
  LK = "P1 Weak Kick",
  MK = "P1 Medium Kick",
  HK = "P1 Strong Kick",
}

local SHEET_ROWS =
  { l = 0, r = 1, u = 2, d = 3, ul = 4, ur = 5, dl = 6, dr = 7, LP = 8, MP = 9, HP = 10, LK = 11, MK = 12, HK = 13 }
local SHEET_FILE = "inputs\\scrolling-input\\icons-capcom-32.png"

function M.sheet_dirs(env)
  local dirs = {}
  for entry in ((env.package and env.package.cpath) or ""):gmatch("[^;]+") do
    local dir = entry:match("^(.*[\\/])%?%.dll$")
    if dir and (dir:match("^%a:[\\/]") or dir:match("^[\\/]")) then
      table.insert(dirs, dir .. "fbneo-training-mode\\")
    end
  end
  for _, dir in ipairs({
    "Z:\\app\\fightcade\\Fightcade\\emulator\\fbneo\\fbneo-training-mode\\",
    "Z:\\var\\data\\fbneo-training-mode\\",
  }) do
    table.insert(dirs, dir)
  end
  return dirs
end

local BLANK_HEX = "89504E470D0A1A0A0000000D494844520000002000000020010300000049B4E8B700000003504C5445000000A77A3DDA00"
  .. "00000174524E530040E6D8660000000C4944415478DA636018DC000000A000018EFBB1B40000000049454E44AE426082"

local function hex_to_string(hex)
  return (hex:gsub("..", function(h)
    return string.char(tonumber(h, 16))
  end))
end

local function icon_loader(env)
  local ok, gd = pcall(env.require or require, "gd")
  if not ok or type(gd) ~= "table" then
    return nil
  end
  local sheet
  for _, dir in ipairs(M.sheet_dirs(env)) do
    local f = env.io.open(dir .. SHEET_FILE, "rb")
    if f then
      f:close()
      sheet = gd.createFromPng(dir .. SHEET_FILE)
      break
    end
  end
  if not sheet then
    return nil
  end
  local cell = sheet:sizeX() / 2
  local blank = hex_to_string(BLANK_HEX)
  local cache = {}
  return function(key, size)
    local id = key .. ":" .. size
    if cache[id] == nil then
      local row = SHEET_ROWS[key]
      if not row then
        cache[id] = false
      else
        local img = gd.createFromPngStr(blank)
        gd.copyResampled(img, sheet, 0, 0, 0, row * cell, size, size, cell, cell)
        cache[id] = img:gdStr()
      end
    end
    return cache[id] or nil
  end
end

function M.new(env)
  env = env or _G
  local memory, gui, emu, input, joypad = env.memory, env.gui, env.emu, env.input, env.joypad
  local p = {}

  p.name = "fbneo"
  p.romname = emu.romname and emu.romname() or "?"
  p.mem = {
    u8 = memory.readbyte,
    u16 = memory.readword,
    s16 = memory.readwordsigned,
    u32 = memory.readdword,
  }

  local icon = icon_loader(env)
  p.has_icons = icon ~= nil
  p.canvas = {
    pixel = function(_, x, y, c)
      gui.pixel(x, y, c)
    end,
    line = function(_, x1, y1, x2, y2, c)
      gui.line(x1, y1, x2, y2, c)
    end,
    box = function(_, x1, y1, x2, y2, fill, outline)
      gui.box(x1, y1, x2, y2, fill, outline or fill)
    end,
    text = function(_, x, y, s, c)
      gui.text(x, y, s, c, 0x000000FF)
    end,
    icon = function(_, key, x, y, size)
      local str = icon and key and icon(key, size)
      if not str then
        return false
      end
      gui.image(x, y, str)
      return true
    end,
  }

  local live = {}
  function p.pad()
    live = joypad.get()
    local out = {}
    for name, fbneo in pairs(PAD) do
      out[name] = live[fbneo] or nil
    end
    return out
  end
  function p.keys()
    return input.get()
  end
  function p.block()
    local blocked = {}
    for name in pairs(live) do
      if name:sub(1, 3) == "P1 " then
        blocked[name] = false
      end
    end
    joypad.set(blocked)
  end

  function p.on_before(fn)
    emu.registerbefore(fn)
  end
  function p.on_frame(fn)
    emu.registerafter(fn)
  end
  function p.on_draw(fn)
    gui.register(fn)
  end
  function p.hotkey(n, fn)
    input.registerhotkey(n, fn)
  end
  function p.clock()
    return emu.framecount() / 60
  end
  function p.timestamp()
    return env.os.date("!%Y-%m-%dT%H:%M:%SZ")
  end
  function p.print(s)
    env.print(s)
  end

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
