package.path = "harness/mame/?.lua;lua/?.lua;lua/?/init.lua;" .. package.path

local S = require("session")
local inputs = require("input_grader.games.sfiii3.inputs")
local platform = require("input_grader.platform.mame").new(manager, emu)
local app = require("input_grader.games.sfiii3").build(platform, {})
require("input_grader.core.run").attach(platform, app)

local snapshots = os.getenv("GRADE_SNAPSHOTS") == "1"
local CHUN = 16

local function mash(buttons, gap)
  local script = { { 5, 20 } }
  for _, b in ipairs(buttons) do
    table.insert(script, { 5, 2, b })
    table.insert(script, { 5, gap })
  end
  table.insert(script, { 5, 90 })
  return script
end

-- name, script, expected ok, expected error code
local CASES = {
  { "five LK", mash({ "LK", "LK", "LK", "LK", "LK" }, 2), true },
  { "mixed strengths", mash({ "LK", "LK", "LK", "MK", "MK" }, 2), false, "mash_mixed" },
  { "four LK", mash({ "LK", "LK", "LK", "LK" }, 2), false, "mash_short" },
}

S.spawn(function()
  S.boot_to_match(0, CHUN)
  local report, failures = {}, 0
  for _, case in ipairs(CASES) do
    local before = #app.attempts
    for _, raw in ipairs(inputs.timeline(case[2], true)) do
      S.hold_raw(raw)
      coroutine.yield()
    end
    local a = app.attempts[before + 1]
    local code = a and a.error and a.error.code or nil
    local good = a ~= nil and a.ok == case[3] and code == case[4] and #app.attempts == before + 1
    failures = failures + (good and 0 or 1)
    local line = string.format(
      "%s %s: %s",
      good and "PASS" or "FAIL",
      case[1],
      a and (a.move .. " ok=" .. tostring(a.ok) .. " " .. (code or "") .. " attempts=" .. (#app.attempts - before))
        or "no attempt"
    )
    table.insert(report, line)
    print(line)
    if snapshots then
      manager.machine.video:snapshot()
    end
  end
  table.insert(report, failures == 0 and "all cases pass" or (failures .. " case(s) failed"))
  print(report[#report])
  S.exit()
end)
