package.path = "harness/mame/?.lua;lua/?.lua;lua/?/init.lua;" .. package.path

local S = require("session")
local ram = require("input_grader.games.sfiii3.ram")
local inputs = require("input_grader.games.sfiii3.inputs")
local platform = require("input_grader.platform.mame").new(manager, emu)
local sfiii3 = require("input_grader.games.sfiii3")
local run = require("input_grader.core.run")
local App_HISTORY = require("input_grader.core.app").HISTORY

local app = sfiii3.build(platform, {})
local graded = {}
local original_frame = app.frame
function app:frame()
  local before = #self.attempts
  original_frame(self)
  if
    #self.attempts ~= before or (#self.attempts == App_HISTORY and self.attempts[#self.attempts] ~= graded[#graded])
  then
    table.insert(graded, self.attempts[#self.attempts])
  end
end
run.attach(platform, app)

local P1 = S.ADDR.p1_base
local GAUGE, METER, METER_MAX, METER_UPDATE = 0x020695B5, 0x020695BF, 0x020695BD, 0x020157C8
local FRW, OBJECT_BYTES = 0x02028990, 0x800
local SHELL_IX, ORIGINAL_VITALITY, REFRECTED = 0x34C, 0x362, 0x3C5
local SA_POINTER, SA_MP, SA_OK, SA_EX, SA_STORE = 0x3F0, 9, 10, 12, 34
local out_path = os.getenv("REFUSALS_OUT") or "build/refusals.txt"

local function set_meter(full)
  S.w8(GAUGE, 0)
  S.w8(METER, full and S.u8(METER_MAX) or 0)
  S.w8(METER_UPDATE, 1)
end

local function s8(v)
  return v >= 128 and v - 256 or v
end

local function state()
  local sa = S.u32(P1 + SA_POINTER)
  local shells = {}
  for i = 0, 7 do
    local ix = S.s16(P1 + SHELL_IX + 2 * i)
    if ix == -1 then
      break
    end
    local obj = FRW + ix * OBJECT_BYTES
    table.insert(
      shells,
      string.format("%d:%d%s", ix, S.s16(obj + ORIGINAL_VITALITY), S.u8(obj + REFRECTED) ~= 0 and "r" or "")
    )
  end
  return string.format(
    "rno %d.%2d  sa ok %2d mp %2d ex %2d store %d  shells [%s]",
    S.s16(P1 + ram.ROUTINE_NO + 2),
    S.s16(P1 + ram.ROUTINE_NO + 4),
    s8(S.u8(sa + SA_OK)),
    s8(S.u8(sa + SA_MP)),
    s8(S.u8(sa + SA_EX)),
    S.s16(sa + SA_STORE),
    table.concat(shells, " ")
  )
end

local function play(report, title, script, frames)
  table.insert(report, "== " .. title)
  local before = #graded
  local words = inputs.timeline(script, true)
  for f = 1, frames do
    S.hold_raw(words[f] or 0)
    coroutine.yield()
    if f % 3 == 0 or f < 4 then
      table.insert(report, string.format("%3d  %s", f, state()))
    end
  end
  S.hold({})
  for i = before + 1, #graded do
    local a = graded[i]
    table.insert(report, "  graded: " .. a.move .. " " .. (a.ok and "out" or (a.error.code .. ": " .. a.error.text)))
  end
end

local SUPER = { { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1 }, { 2, 1 }, { 3, 1, "HP" }, { 5, 1 } }
local HADOKEN = { { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" }, { 5, 1 } }
local TWO_HADOKENS =
  { { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" }, { 5, 50 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" }, { 5, 1 } }
local EX_HADOKEN = { { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP+MP" }, { 5, 1 } }

S.spawn(function()
  S.boot_to_match(0)
  local report = {}
  S.hold_raw(4)
  S.wait(60)
  S.hold({})
  S.wait(20)
  S.save("far")
  local cases = {
    { "super, empty meter", SUPER, false, 40 },
    { "super, full meter", SUPER, true, 40 },
    { "Hadoken", HADOKEN, true, 40 },
    { "two Hadokens 50 frames apart", TWO_HADOKENS, true, 90 },
    { "EX Hadoken, empty meter", EX_HADOKEN, false, 40 },
    { "EX Hadoken, full meter", EX_HADOKEN, true, 40 },
  }
  for _, case in ipairs(cases) do
    S.load("far")
    set_meter(case[3])
    S.wait(4)
    play(report, case[1], case[2], case[4])
  end
  local f = io.open(out_path, "w")
  f:write(table.concat(report, "\n") .. "\n")
  f:close()
  print("wrote " .. out_path)
  S.exit()
end)
