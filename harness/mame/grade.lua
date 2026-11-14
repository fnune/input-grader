package.path = "harness/mame/?.lua;lua/?.lua;lua/?/init.lua;" .. package.path

local S = require("session")
local inputs = require("input_grader.games.sfiii3.inputs")
local platform = require("input_grader.platform.mame").new(manager, emu)
local sfiii3 = require("input_grader.games.sfiii3")
local run = require("input_grader.core.run")
local App_HISTORY = require("input_grader.core.app").HISTORY

local snapshots = os.getenv("GRADE_SNAPSHOTS") == "1"
local out_path = os.getenv("GRADE_OUT") or "build/grade-report.txt"

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

local function steps_line(a)
  local parts = {}
  for _, st in ipairs(a.steps or {}) do
    table.insert(parts, st.used and st.window and (st.label .. " " .. st.used .. "/" .. st.window) or st.label)
  end
  local b = a.button
  if b and b.label then
    table.insert(parts, b.after and b.window and (b.label .. " " .. b.after .. "/" .. b.window) or b.label)
  end
  return table.concat(parts, "  ")
end

local CASES = {
  { "clean Hadoken", { { 5, 20 }, { 2, 2 }, { 3, 2 }, { 6, 1, "LP" }, { 5, 70 } }, "Hadoken", true },
  { "skipped diagonal", { { 5, 20 }, { 2, 3 }, { 6, 1, "LP" }, { 5, 70 } }, "Hadoken", false, "skipped_step" },
  {
    "slow diagonal",
    { { 5, 20 }, { 2, 1 }, { 1, 12 }, { 3, 1 }, { 6, 1, "LP" }, { 5, 70 } },
    "Hadoken",
    false,
    "too_slow",
  },
  {
    "late button",
    { { 5, 20 }, { 2, 1 }, { 3, 1 }, { 6, 14 }, { 6, 1, "LP" }, { 5, 70 } },
    "Hadoken",
    false,
    "late_button",
  },
  {
    "early held button",
    { { 5, 20 }, { 2, 1 }, { 3, 1, "LP" }, { 6, 16, "LP" }, { 5, 70 } },
    "Hadoken",
    false,
    "early_button",
  },
  {
    "press on 2 starts a cr.LP, so the release on 6 is an early button",
    { { 5, 20 }, { 2, 1, "LP" }, { 3, 1, "LP" }, { 6, 1 }, { 5, 70 } },
    "Hadoken",
    false,
    "early_button",
  },
  {
    "up cancels",
    { { 5, 20 }, { 2, 2 }, { 3, 1 }, { 8, 1 }, { 6, 1, "LP" }, { 5, 90 } },
    "Hadoken",
    false,
    "cancelled",
  },
  { "Shoryuken", { { 5, 20 }, { 6, 2 }, { 2, 1 }, { 3, 1, "HP" }, { 5, 90 } }, "Shoryuken", true },
  { "Tatsumaki", { { 5, 20 }, { 2, 2 }, { 1, 2 }, { 4, 1, "LK" }, { 5, 110 } }, "Tatsumaki Senpukyaku", true },
}

-- P2 attacks on frame 15 (standing MP connects on 21, crouching MK on 23); P1 taps on `tap`.
local PARRY_CASES = {
  { "parry in the window", 0x20, 16, 8, true },
  { "parry too early", 0x20, 5, 8, false, "parry_early" },
  { "parry too late", 0x20, 23, 8, false, "parry_late" },
  { "forward against a low", 0x202, 18, 8, false, "parry_direction" },
  { "low parry", 0x202, 18, 2, true },
}

local LP_LK = 0x110
-- Forward dash from a step back, then a press `at` frames after the dash's last input (a throw is
-- first possible 12 frames after it, measured in throw.lua).
local FOLLOWUP_CASES = {
  { "dash, throw on the first frame", "mid", 12, LP_LK, true, nil, 0 },
  { "dash, throw 1 frame early", "mid", 11, LP_LK, false, "followup_early", -1 },
  { "dash, throw 3 frames late", "mid", 15, LP_LK, true, nil, 3 },
  { "dash, LP then LK 2 frames later", "mid", 12, 0x10, false, "throw_split", 0 },
  { "dash, throw out of range", "far", 12, LP_LK, false, "throw_whiff", 0 },
}

local function followup_cases(report)
  local failures = 0
  app:choose({ id = "ryu:after:forward_dash:throw", name = "dash > throw" })
  S.load("parry")
  S.hold_raw(4)
  S.wait(16)
  S.hold({})
  S.wait(20)
  S.save("mid")
  S.load("parry")
  S.hold_raw(4)
  S.wait(60)
  S.hold({})
  S.wait(20)
  S.save("far")
  for _, case in ipairs(FOLLOWUP_CASES) do
    S.load(case[2])
    local before = #graded
    local words = inputs.timeline({ { 6, 1 }, { 5, 2 }, { 6, 1 } }, true)
    local dash_len = #words
    for f = 1, 50 do
      words[dash_len + f] = (f == case[3]) and case[4] or ((case[4] == 0x10 and f == case[3] + 2) and 0x100 or 0)
    end
    for _, raw in ipairs(words) do
      S.hold_raw(raw)
      coroutine.yield()
    end
    S.hold({})
    local a = graded[before + 1]
    local code = a and a.error and a.error.code or nil
    local gap = a and a.followup and a.followup.gap
    local good = a ~= nil and a.ok == case[5] and code == case[6] and gap == case[7]
    failures = failures + (good and 0 or 1)
    local line = a
        and string.format(
          "%s %s: %s ok=%s %s gap=%s | %s",
          good and "PASS" or "FAIL",
          case[1],
          a.move,
          tostring(a.ok),
          code or "",
          tostring(gap),
          a.error and a.error.text or ""
        )
      or string.format("FAIL %s: no attempt graded", case[1])
    table.insert(report, line)
    print(line)
    if snapshots and a then
      manager.machine.video:snapshot()
    end
  end
  return failures
end

local GAUGE, METER, METER_MAX, METER_UPDATE = 0x020695B5, 0x020695BF, 0x020695BD, 0x020157C8

local CANCEL_CASES = {
  { "2MK xx super in the cancel window", "close", 0, 13, true },
  { "2MK xx super 3 frames late", "close", 0, 22, false, "cancel_late", "3 frames after" },
  { "2MK xx super before a blocked MK connects", "close", 8, 5, false, "cancel_early", "3 frames before" },
  { "2MK xx super after a whiffed MK", "far", 0, 10, false, "cancel_whiff" },
}

local function mk_then_super_with_hp_after(after)
  local press = after + 1
  local w = { 0x202 }
  local motion = { 0x2, 0xA, 0x8, 0x2, 0xA }
  for f = 2, press + 40 do
    local k = f - (press - #motion)
    w[f] = motion[k] or (k < 1 and 0x2 or 0)
  end
  w[press] = w[press] + 0x40
  return w
end

local function cancel_cases(report)
  local failures = 0
  app:choose(nil)
  S.load("parry")
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
  for _, case in ipairs(CANCEL_CASES) do
    S.load(case[2])
    S.w8(GAUGE, 0)
    S.w8(METER, S.u8(METER_MAX))
    S.w8(METER_UPDATE, 1)
    S.wait(2)
    local before = #graded
    for _, raw in ipairs(mk_then_super_with_hp_after(case[4])) do
      S.hold_raw(raw, case[3])
      coroutine.yield()
    end
    S.hold({})
    local a
    for i = before + 1, #graded do
      a = a or (graded[i].move == "SA I Shinkuu Hadoken" and graded[i] or nil)
    end
    local code = a and a.error and a.error.code or nil
    local good = a ~= nil
      and a.ok == case[5]
      and code == case[6]
      and (not case[7] or a.error.text:find(case[7], 1, true) ~= nil)
    failures = failures + (good and 0 or 1)
    local line = a
        and string.format(
          "%s %s: %s ok=%s %s | %s",
          good and "PASS" or "FAIL",
          case[1],
          a.move,
          tostring(a.ok),
          code or "",
          a.error and a.error.text or ""
        )
      or string.format("FAIL %s: no attempt graded", case[1])
    table.insert(report, line)
    print(line)
    if snapshots and a then
      manager.machine.video:snapshot()
    end
  end
  return failures
end

local function parry_cases(report)
  local failures = 0
  app:choose({ id = "ryu:parry", name = "parry" })
  S.hold_raw(8)
  S.wait(70)
  S.hold({})
  S.wait(30)
  S.save("parry")
  for _, case in ipairs(PARRY_CASES) do
    S.load("parry")
    local before = #graded
    for f = 1, 45 do
      S.hold_raw(f == case[3] and case[4] or 0, (f == 15 or f == 16) and case[2] or 0)
      coroutine.yield()
    end
    S.hold({})
    local a = graded[before + 1]
    local code = a and a.error and a.error.code or nil
    local good = a ~= nil and a.ok == case[5] and code == case[6]
    if not good then
      failures = failures + 1
    end
    local line = a
        and string.format(
          "%s %s: %s ok=%s %s | %s",
          good and "PASS" or "FAIL",
          case[1],
          a.move,
          tostring(a.ok),
          code or "",
          a.error and a.error.text or ""
        )
      or string.format("FAIL %s: no attempt graded", case[1])
    table.insert(report, line)
    print(line)
    if snapshots and a then
      manager.machine.video:snapshot()
    end
  end
  return failures
end

S.spawn(function()
  S.boot_to_match(0)
  local report, failures = {}, 0
  for i, case in ipairs(CASES) do
    local before = #graded
    for _, raw in ipairs(inputs.timeline(case[2], app.game.source.ram:facing_right())) do
      S.hold_raw(raw)
      coroutine.yield()
    end
    local a = graded[before + 1]
    local line
    if not a then
      line = string.format("FAIL %s: no attempt graded", case[1])
      failures = failures + 1
    else
      local code = a.error and a.error.code or nil
      local good = a.move == case[3] and a.ok == case[4] and code == case[5]
      if not good then
        failures = failures + 1
      end
      line = string.format(
        "%s %s: %s ok=%s %s | %s | %s",
        good and "PASS" or "FAIL",
        case[1],
        a.move,
        tostring(a.ok),
        code or "",
        steps_line(a),
        a.error and a.error.text or ""
      )
    end
    table.insert(report, line)
    print(line)
    if snapshots and a then
      S.wait(2)
      manager.machine.video:snapshot()
    end
    if #graded > before + 1 then
      table.insert(report, "  extra attempts: " .. (#graded - before - 1))
    end
    local _ = i
  end
  if snapshots then
    app:toggle_menu()
    S.wait(2)
    manager.machine.video:snapshot()
    app:toggle_menu()
  end
  failures = failures + parry_cases(report)
  failures = failures + followup_cases(report)
  failures = failures + cancel_cases(report)
  table.insert(report, failures == 0 and "all cases pass" or (failures .. " case(s) failed"))
  local f = io.open(out_path, "w")
  f:write(table.concat(report, "\n") .. "\n")
  f:close()
  print(report[#report])
  S.exit()
end)
