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

local function parry_cases(report)
  local failures = 0
  app:choose({ id = "ryu:parry", name = "parry" })
  S.hold_raw(8)
  S.wait(70)
  S.hold({})
  S.wait(30)
  manager.machine:save("parry")
  S.wait(2)
  for _, case in ipairs(PARRY_CASES) do
    manager.machine:load("parry")
    S.wait(2)
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
  table.insert(report, failures == 0 and "all cases pass" or (failures .. " case(s) failed"))
  local f = io.open(out_path, "w")
  f:write(table.concat(report, "\n") .. "\n")
  f:close()
  print(report[#report])
  S.exit()
end)
