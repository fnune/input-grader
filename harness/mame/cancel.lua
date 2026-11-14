package.path = "harness/mame/?.lua;lua/?.lua;lua/?/init.lua;" .. package.path

local S = require("session")
local ram = require("input_grader.games.sfiii3.ram")
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
local SA_SLOT, SA_RNO = 20, 19
local out_path = os.getenv("CANCEL_OUT") or "build/cancel.txt"
local DOWN, DOWN_RIGHT, RIGHT, MK, HP, BACK_P2 = 0x2, 0xA, 0x8, 0x200, 0x40, 0x8

local function fill_meter()
  S.w8(GAUGE, 0)
  S.w8(METER, S.u8(METER_MAX))
  S.w8(METER_UPDATE, 1)
end

local function state()
  return {
    r1 = S.s16(P1 + ram.ROUTINE_NO + 2),
    r2 = S.s16(P1 + ram.ROUTINE_NO + 4),
    cancel = S.u8(P1 + ram.CG_CANCEL),
    hit = S.u8(P1 + ram.MEOSHI_HIT_FLAG),
    flag = S.s16(ram.WORK_CP[1] + ram.WAZA_FLAG + 2 * SA_SLOT),
  }
end

local function mk_then_super_with_hp_on(press)
  local w = { DOWN + MK }
  local motion = { DOWN, DOWN_RIGHT, RIGHT, DOWN, DOWN_RIGHT }
  for f = 2, press + 30 do
    local k = f - (press - #motion)
    w[f] = motion[k] or (f < press - #motion + 1 and DOWN or 0)
  end
  w[press] = w[press] + HP
  return w
end

local function play(w, p2)
  local log, super = {}, nil
  for f = 1, #w do
    S.hold_raw(w[f], p2)
    coroutine.yield()
    local s = state()
    log[f] = s
    if not super and s.r1 == 4 and s.r2 == SA_RNO then
      super = f
    end
  end
  S.hold({})
  return log, super
end

local function line(f, s)
  return string.format("%3d  rno %d.%2d  cg_cancel 0x%02X  hit %d  sa_flag %3d", f, s.r1, s.r2, s.cancel, s.hit, s.flag)
end

S.spawn(function()
  S.boot_to_match(0)
  local report = {}
  S.hold_raw(8)
  S.wait(40)
  S.hold({})
  S.wait(30)
  S.save("close")
  S.hold_raw(4)
  S.wait(60)
  S.hold({})
  S.wait(20)
  S.save("far")

  for _, case in ipairs({ { "hit", "close", 0 }, { "block", "close", BACK_P2 }, { "whiff", "far", 0 } }) do
    local results = {}
    for press = 6, 36 do
      S.load(case[2])
      fill_meter()
      S.wait(2)
      local before = #graded
      local log, super = play(mk_then_super_with_hp_on(press), case[3])
      local verdicts = {}
      for i = before + 1, #graded do
        local a = graded[i]
        table.insert(verdicts, a.move .. " " .. (a.ok and "out" or (a.error.code .. ": " .. a.error.text)))
      end
      table.insert(
        results,
        string.format(
          "%s: HP %2d frames after MK -> %-5s | %s",
          case[1],
          press - 1,
          super and "SUPER" or "no",
          table.concat(verdicts, "; ")
        )
      )
      if press == 14 then
        table.insert(report, "== " .. case[1] .. ": frame log, HP 13 after MK")
        for f = 1, #log do
          table.insert(report, line(f, log[f]))
        end
      end
    end
    for _, r in ipairs(results) do
      table.insert(report, r)
    end
  end
  local f = io.open(out_path, "w")
  f:write(table.concat(report, "\n") .. "\n")
  f:close()
  print("wrote " .. out_path)
  S.exit()
end)
