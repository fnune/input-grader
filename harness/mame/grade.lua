-- End-to-end check in the real game: the live grader (RAM source, platform/mame) grades
-- scripted attempts, and each must get the expected verdict. Optionally saves snapshots.
--
-- mame sfiii3n -rompath roms -video none -sound none -nothrottle -autoboot_script harness/mame/grade.lua
-- Environment: GRADE_SNAPSHOTS=1 to save screenshots (needs a video backend), GRADE_OUT (report path).

package.path = "harness/mame/?.lua;lua/?.lua;lua/?/init.lua;" .. package.path

local S = require("session")
local inputs = require("input_grader.games.sfiii3.inputs")
local platform = require("input_grader.platform.mame").new(manager, emu)
local sfiii3 = require("input_grader.games.sfiii3")
local run = require("input_grader.core.run")

local snapshots = os.getenv("GRADE_SNAPSHOTS") == "1"
local out_path = os.getenv("GRADE_OUT") or "build/grade-report.txt"

local app = sfiii3.build(platform, {})
local graded = {}
local original_frame = app.frame
function app:frame()
  local before = self.last
  original_frame(self)
  if self.last ~= before then table.insert(graded, self.last) end
end
run.attach(platform, app)

-- name, script, expected move, expected ok, expected error code
local CASES = {
  { "clean Hadoken", { { 5, 20 }, { 2, 2 }, { 3, 2 }, { 6, 1, "LP" }, { 5, 70 } }, "Hadoken", true },
  { "skipped diagonal", { { 5, 20 }, { 2, 3 }, { 6, 1, "LP" }, { 5, 70 } }, "Hadoken", false, "skipped_step" },
  { "slow diagonal", { { 5, 20 }, { 2, 1 }, { 1, 12 }, { 3, 1 }, { 6, 1, "LP" }, { 5, 70 } }, "Hadoken", false, "too_slow" },
  { "late button", { { 5, 20 }, { 2, 1 }, { 3, 1 }, { 6, 14 }, { 6, 1, "LP" }, { 5, 70 } }, "Hadoken", false, "late_button" },
  { "early held button", { { 5, 20 }, { 2, 1 }, { 3, 1, "LP" }, { 6, 16, "LP" }, { 5, 70 } }, "Hadoken", false, "early_button" },
  -- Pressing LP on 2 starts a crouching jab, so the release that completes the motion comes
  -- while Ryu is busy and no Hadoken starts: early button is the right verdict here.
  { "press on 2, release on 6", { { 5, 20 }, { 2, 1, "LP" }, { 3, 1, "LP" }, { 6, 1 }, { 5, 70 } }, "Hadoken", false, "early_button" },
  { "up cancels", { { 5, 20 }, { 2, 2 }, { 3, 1 }, { 8, 1 }, { 6, 1, "LP" }, { 5, 90 } }, "Hadoken", false, "cancelled" },
  { "Shoryuken", { { 5, 20 }, { 6, 2 }, { 2, 1 }, { 3, 1, "HP" }, { 5, 90 } }, "Shoryuken", true },
  { "Tatsumaki", { { 5, 20 }, { 2, 2 }, { 1, 2 }, { 4, 1, "LK" }, { 5, 110 } }, "Tatsumaki Senpukyaku", true },
}

S.spawn(function()
  S.boot_to_match(0)
  app:toggle_bench()
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
      if not good then failures = failures + 1 end
      line = string.format("%s %s: %s ok=%s %s | %s | %s", good and "PASS" or "FAIL", case[1], a.move, tostring(a.ok),
        code or "", require("input_grader.core.overlay").steps_line(a), a.error and a.error.text or "")
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
  app:toggle_bench()
  app.last = nil
  S.wait(4)
  if snapshots then manager.machine.video:snapshot() end
  local summary = app.bench:summary()
  for _, m in ipairs(summary.moves) do
    table.insert(report, string.format("bench %s: %d/%d", m.name, m.ok, m.n))
  end
  table.insert(report, failures == 0 and "all cases pass" or (failures .. " case(s) failed"))
  local f = io.open(out_path, "w")
  f:write(table.concat(report, "\n") .. "\n")
  f:close()
  print(report[#report])
  S.exit()
end)
