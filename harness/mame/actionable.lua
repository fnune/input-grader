-- Measures when a player can act again after an action, by experiment: from the same save
-- state, do the action, then press a button k frames later for k = 1..N, and record whether the
-- press started a move. Also logs the timing fields the game tags each animation frame with
-- (cg_type, cg_ctr, permited_koa), to find which RAM signal marks the first actionable frame.
--
-- mame sfiii3n -rompath roms -video none -sound none -nothrottle -state_directory build/mame/sta \
--   -autoboot_script harness/mame/actionable.lua
-- Environment: ACTION (dash | backdash | jump, default dash), PRESS (LP | LPLK, default LP),
-- ACT_OUT (report path, default build/actionable-<action>-<press>.txt).

package.path = "harness/mame/?.lua;lua/?.lua;lua/?/init.lua;" .. package.path

local S = require("session")
local inputs = require("input_grader.games.sfiii3.inputs")

local P1 = S.ADDR.p1_base
local ROUTINE, CG_CTR, CG_TYPE, PERMITED = 36, 532, 533, 1132
local action = os.getenv("ACTION") or "dash"
local press = os.getenv("PRESS") or "LP"
local out_path = os.getenv("ACT_OUT") or ("build/actionable-" .. action .. "-" .. press .. ".txt")

local ACTIONS = {
  dash = { { 6, 1 }, { 5, 2 }, { 6, 1 } },
  backdash = { { 4, 1 }, { 5, 2 }, { 4, 1 } },
  jump = { { 8, 1 } },
}

local function state()
  return {
    r = { S.s16(P1 + ROUTINE), S.s16(P1 + ROUTINE + 2), S.s16(P1 + ROUTINE + 4), S.s16(P1 + ROUTINE + 6) },
    cg_type = S.u8(P1 + CG_TYPE),
    cg_ctr = S.u8(P1 + CG_CTR),
    permited = S.u16(P1 + PERMITED),
    -- The input word the game read this frame (WORK_CP.sw_new), to line presses up with tags.
    sw_new = S.u16(0x02026318 + 2),
  }
end

local function key(st)
  return table.concat(st.r, ".")
end

-- Plays the action, then neutral; with `at`, presses the button for 1 frame `at` frames after
-- the action's last input. Returns the per-frame log from the action's last input on.
local function play(at, frames)
  local log = {}
  local script = {}
  for _, e in ipairs(ACTIONS[action]) do
    table.insert(script, e)
  end
  for _, raw in ipairs(inputs.timeline(script, true)) do
    S.hold_raw(raw)
    coroutine.yield()
  end
  for f = 1, frames do
    if at and f == at then
      S.hold_raw(inputs.buttons_word(press))
    else
      S.hold({})
    end
    coroutine.yield()
    log[f] = state()
  end
  S.hold({})
  return log
end

S.spawn(function()
  S.boot_to_match(0)
  S.hold({})
  S.wait(30)
  manager.machine:save("before")
  S.wait(2)

  local report =
    { string.format("action %s, press %s (frame 1 = the frame after the action's last input)", action, press) }
  local base = play(nil, 60)
  table.insert(report, "frame  routine_no  cg_type cg_ctr permited_koa   (no press)")
  for f, st in ipairs(base) do
    table.insert(
      report,
      string.format("%5d  %-10s  %7d %6d       0x%04X", f, key(st), st.cg_type, st.cg_ctr, st.permited)
    )
  end

  table.insert(report, "")
  table.insert(report, "press at  result")
  local function trace(at)
    manager.machine:load("before")
    S.wait(2)
    local log = play(at, at + 4)
    table.insert(report, string.format("press at %d, frame by frame:", at))
    for f = math.max(1, at - 2), at + 3 do
      local st = log[f]
      table.insert(
        report,
        string.format(
          "  %3d  sw_new 0x%03X  %-10s cg_type %3d cg_ctr %3d",
          f,
          st.sw_new,
          key(st),
          st.cg_type,
          st.cg_ctr
        )
      )
    end
  end
  trace(12)
  trace(13)
  table.insert(report, "")
  for at = 1, 50 do
    manager.machine:load("before")
    S.wait(2)
    local log = play(at, at + 6)
    local after = log[at + 3] or log[#log]
    local reference = base[at + 3] or base[#base]
    local started = key(after) ~= key(reference)
    table.insert(
      report,
      string.format(
        "%8d  %s  (%s vs %s without the press)",
        at,
        started and "ACCEPTED" or "dropped",
        key(after),
        key(reference)
      )
    )
  end

  local f = io.open(out_path, "w")
  f:write(table.concat(report, "\n") .. "\n")
  f:close()
  print(out_path)
  S.exit()
end)
