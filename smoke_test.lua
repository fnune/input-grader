-- Smoke test for running inside Fightcade's FBNeo. Load it with Game > Lua Scripting > New Lua
-- Script Window > Browse > smoke_test.lua > Run, during a 3rd Strike match. It checks the risky
-- parts of the overlay one by one, shows a checklist on screen, and writes logs/smoke-test.txt.
--
-- Standalone on purpose (no requires): a failure in one check cannot hide the others.
-- Steps for the person running it are on screen; see also docs/smoke-test.md.

local results, order = {}, {}
local write_log
local lines_out = {}

local function log(s)
  table.insert(lines_out, s)
  print("smoke: " .. s)
end

local function check(name, fn)
  local ok, detail = pcall(fn)
  if results[name] == nil then
    table.insert(order, name)
  end
  results[name] = { ok = ok and detail ~= false, detail = ok and tostring(detail) or ("error: " .. tostring(detail)) }
  log(string.format("%-14s %s  %s", name, results[name].ok and "OK  " or "FAIL", results[name].detail))
  if write_log then
    write_log()
  end
end

write_log = function()
  local f = io.open("logs/smoke-test.txt", "w")
  if not f then
    print("smoke: could not write logs/smoke-test.txt (is logs/ writable for Fightcade?)")
    return
  end
  f:write(table.concat(lines_out, "\n") .. "\n")
  f:close()
end

-- 1. Environment --------------------------------------------------------------------------------

-- Fightcade's FBNeo ships gd as a module (gd.dll next to the emulator), not as a global.
local gd_ok, gd = pcall(require, "gd")
if not gd_ok then
  gd = nil
end

check("lua", function()
  return _VERSION .. ", bit " .. tostring(type(bit) == "table") .. ", gd " .. tostring(gd ~= nil)
end)
check("rom", function()
  local name = emu.romname()
  return name .. (name == "sfiii3nr1" and "" or " (expected sfiii3nr1)")
end)
check("write logs/", function()
  local f = io.open("logs/smoke-write.tmp", "w")
  if not f then
    return false
  end
  f:write("ok")
  f:close()
  os.remove("logs/smoke-write.tmp")
  return "logs/ is writable"
end)

-- 2. Memory reads (3rd Strike Japan 990512) -------------------------------------------------------

local P1 = 0x02068C6C
check("memory", function()
  local row = memory.readword(P1 + 0x3C0)
  local state = memory.readbyte(0x020154A7)
  return string.format("P1 character row %d (Ryu is 2), match state %d (2 = fighting)", row, state)
end)

local reported_match = false

-- 3. Fightcade's icon sheet through gd ------------------------------------------------------------

-- Where Fightcade's training mode may be, as seen from its FBNeo under Wine (Z: is /).
local SHEET = "inputs\\scrolling-input\\icons-capcom-32.png"
local EMULATOR = "Z:\\app\\fightcade\\Fightcade\\emulator\\fbneo\\"
local SHEET_PATHS = {
  EMULATOR .. "fbneo-training-mode\\" .. SHEET,
  EMULATOR .. "fbneo-training-mode-original\\" .. SHEET,
  "Z:\\var\\data\\fbneo-training-mode\\" .. SHEET,
  "../fbneo-training-mode/inputs/scrolling-input/icons-capcom-32.png",
  "fbneo-training-mode/inputs/scrolling-input/icons-capcom-32.png",
}
-- A blank 32x32 transparent PNG to resample icons into (generated for this project).
local BLANK_HEX = "89504E470D0A1A0A0000000D494844520000002000000020010300000049B4E8B700000003504C5445000000A77A3DDA00"
  .. "00000174524E530040E6D8660000000C4944415478DA636018DC000000A000018EFBB1B40000000049454E44AE426082"
local function hex_to_string(hex)
  return (hex:gsub("..", function(h)
    return string.char(tonumber(h, 16))
  end))
end

local icons = {}
local ROWS = { r = 1, d = 3, dr = 7, LP = 8 }
check("icon sheet", function()
  for _, path in ipairs(SHEET_PATHS) do
    local f = io.open(path, "rb")
    if f then
      f:close()
      local sheet = gd.createFromPng(path)
      local cell = sheet:sizeX() / 2
      for name, row in pairs(ROWS) do
        local img = gd.createFromPngStr(hex_to_string(BLANK_HEX))
        gd.copyResampled(img, sheet, 0, 0, 0, row * cell, 13, 13, cell, cell)
        icons[name] = img:gdStr()
      end
      return "loaded from " .. path
    end
  end
  return false
end)

-- 4. Drawing speed ---------------------------------------------------------------------------------

local GREEN, RED, GOLD, PANEL = 0x4CD964FF, 0xFF5A5AFF, 0xFFD23CFF, 0x101018C8

local function bevel_box(x1, y1, x2, y2, fill, outline)
  for y = y1 + 1, y2 - 1 do
    local inset = math.max(0, 3 - math.min(y - y1, y2 - y))
    gui.line(x1 + inset + 1, y, x2 - inset - 1, y, fill)
  end
  gui.line(x1 + 3, y1, x2 - 3, y1, outline)
  gui.line(x1 + 3, y2, x2 - 3, y2, outline)
  gui.line(x1, y1 + 3, x1, y2 - 3, outline)
  gui.line(x2, y1 + 3, x2, y2 - 3, outline)
  gui.line(x1, y1 + 3, x1 + 3, y1, outline)
  gui.line(x2 - 3, y1, x2, y1 + 3, outline)
  gui.line(x1, y2 - 3, x1 + 3, y2, outline)
  gui.line(x2 - 3, y2, x2, y2 - 3, outline)
end

local NEUTRAL = { "..#####..", ".#WWWWW#.", "#WWWWWWW#", "#WWWWWWS#", "#WWWWWWS#", "#WWWWWSS#", "#WWWWSSS#",
  ".#SSSSS#.", "..#####.." }
local function neutral(x, y)
  local colour = { ["#"] = 0x000000FF, W = 0xFFFFFFFF, S = 0xA8A8B0FF }
  for j, row in ipairs(NEUTRAL) do
    for i = 1, #row do
      local c = colour[row:sub(i, i)]
      if c then
        gui.pixel(x + i - 1, y + j - 1, c)
      end
    end
  end
end

-- A sample card like the mock's: four slots, played inputs, meters.
local function sample_card()
  local x0, y0 = 48, 148
  gui.text(x0 + 1, y0 - 9, "HADOKEN  SMOKE TEST", 0xFFFFFFFF)
  bevel_box(x0, y0, x0 + 150, y0 + 44, (GREEN - 0xFF) + 0x30, GREEN)
  local slots = { "d", "dr", "r", "LP" }
  for i, name in ipairs(slots) do
    local cx = x0 + 6 + (i - 1) * 36
    bevel_box(cx, y0 + 4, cx + 14, y0 + 18, (GREEN - 0xFF) + 0x40, GREEN)
    if icons[name] then
      gui.image(cx + 1, y0 + 5, icons[name])
    else
      gui.text(cx + 4, y0 + 8, name, 0xFFFFFFFF)
    end
    gui.text(cx, y0 + 24, i == 1 and "" or "2/10", GREEN)
    gui.box(cx - 2, y0 + 33, cx + 18, y0 + 35, 0x2A2A36FF, 0x5A5A6AFF)
  end
  neutral(x0 + 152 - 14, y0 + 30)
end

local draw_ms
check("draw speed", function()
  local t0 = os.clock()
  for _ = 1, 10 do
    sample_card()
  end
  draw_ms = (os.clock() - t0) * 1000 / 10
  return string.format("%.2f ms per card (a frame is 16.7 ms)", draw_ms)
end)

-- 5. Inputs, hotkeys and a menu that blocks the character -----------------------------------------

local seen_joypad, seen_keys = {}, {}
local menu_open, menu_sel, menu_frozen_frames = false, 1, 0
local prev, prev_m = {}, false
local MENU = { "HADOKEN", "SHORYUKEN", "TATSUMAKI", "FORWARD DASH" }

-- FBNeo's Lua hotkeys are game inputs the player must map (Input > Map game inputs > Lua Hotkey
-- 6); nothing is mapped by default. The M key, read directly, works without any mapping.
local function toggle_menu(source)
  menu_open = not menu_open
  check("menu toggle", function()
    return "menu " .. (menu_open and "opened" or "closed") .. " with " .. source
  end)
end
input.registerhotkey(6, function()
  toggle_menu("Lua Hotkey 6")
end)

emu.registerbefore(function()
  if menu_open then
    -- Block P1's controls so the character stands still while the stick moves the menu.
    local blocked = {}
    for name in pairs(joypad.get()) do
      if name:sub(1, 3) == "P1 " then
        blocked[name] = false
      end
    end
    joypad.set(blocked)
  end
end)

emu.registerafter(function()
  local pad = joypad.get()
  for name, down in pairs(pad) do
    if down and name:sub(1, 3) == "P1 " and not seen_joypad[name] then
      seen_joypad[name] = true
      check("joypad", function()
        local names = {}
        for n in pairs(seen_joypad) do
          table.insert(names, n)
        end
        table.sort(names)
        return "seen: " .. table.concat(names, ", ")
      end)
    end
  end
  local keys = input.get()
  if keys.M and not prev_m then
    toggle_menu("the M key")
  end
  prev_m = keys.M
  for name, down in pairs(keys) do
    if down and not seen_keys[name] then
      seen_keys[name] = true
      check("keyboard", function()
        local names = {}
        for n in pairs(seen_keys) do
          table.insert(names, n)
        end
        table.sort(names)
        return "input.get() saw: " .. table.concat(names, ", ")
      end)
    end
  end
  if not reported_match and memory.readbyte(0x020154A7) == 2 then
    reported_match = true
    check("match", function()
      return string.format("in a match: P1 character row %d (Ryu is 2)", memory.readword(P1 + 0x3C0))
    end)
  end
  if menu_open then
    local function pressed(n)
      return pad[n] and not prev[n]
    end
    if pressed("P1 Down") then
      menu_sel = menu_sel % #MENU + 1
    end
    if pressed("P1 Up") then
      menu_sel = (menu_sel - 2) % #MENU + 1
    end
    if pressed("P1 Weak Punch") then
      check("menu select", function()
        return "picked " .. MENU[menu_sel] .. " with LP"
      end)
      write_log()
    end
    menu_frozen_frames = menu_frozen_frames + 1
    if menu_frozen_frames == 120 then
      check("menu block", function()
        local x = memory.readwordsigned(P1 + 0x64)
        return string.format("P1 x position %d (should not change while the menu is open)", x)
      end)
    end
  else
    menu_frozen_frames = 0
  end
  prev = pad
end)

-- 6. On-screen checklist ---------------------------------------------------------------------------

gui.register(function()
  sample_card()
  local y = 44
  gui.box(48, y - 2, 300, y + 10 + #order * 8, 0x000000B0, 0x5A5A6AFF)
  gui.text(52, y, "SMOKE TEST  M: menu, stick to move, LP pick", GOLD)
  for i, name in ipairs(order) do
    local r = results[name]
    local text = (r.ok and "OK   " or "FAIL ") .. name .. ": " .. r.detail:sub(1, 48)
    gui.text(52, y + i * 8, text, r.ok and GREEN or RED)
  end
  if menu_open then
    bevel_box(200, 100, 300, 104 + #MENU * 10, PANEL, 0xFFFFFFFF)
    for i, item in ipairs(MENU) do
      gui.text(206, 102 + (i - 1) * 10 + 2, item, i == menu_sel and 0xFFFFFFFF or 0x8A8A9AFF)
    end
  end
end)

write_log()
log("loaded: in a match, press M, move the stick up and down, press LP, wait 2 s, press M again")
