-- Equivalence check of the Lua checker against the game, one frame transition at a time.
-- Each frame: load the game's command state from RAM into the checker, step the checker with
-- the input word the game read, and compare every field of all 56 slots with RAM.
--
-- mame sfiii3n -rompath roms -video none -sound none -nothrottle -autoboot_script harness/mame/validate.lua
-- Environment: VALIDATE_SEED (default 1), VALIDATE_REPS (default 400), VALIDATE_OUT (report path).

package.path = "harness/mame/?.lua;lua/?.lua;" .. package.path

local S = require("session")
local Checker = require("input_grader.games.sfiii3.checker")
local inputs = require("input_grader.games.sfiii3.inputs")
local C = require("input_grader.games.sfiii3.constants")
local ram = require("input_grader.games.sfiii3.ram")
local commands = dofile("lua/input_grader/games/sfiii3/commands.lua")

local ROW = tonumber(os.getenv("VALIDATE_CHAR") or "2")
local seed = tonumber(os.getenv("VALIDATE_SEED") or "1")
local reps = tonumber(os.getenv("VALIDATE_REPS") or "400")
local out_path = os.getenv("VALIDATE_OUT") or "build/validate-report.txt"

local function rng()
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed
end
local function rand(lo, hi)
  return lo + rng() % (hi - lo + 1)
end

local function motion_script(record)
  local script = { { 5, rand(1, 6) } }
  for _, step in ipairs(record.steps) do
    table.insert(script, { inputs.lever_to_numpad(step[4] % 65536), rand(1, 12) })
  end
  local buttons = { "LP", "MP", "HP", "LK", "MK", "HK", "LPMP", "LKMK" }
  script[rand(1, #script)][3] = buttons[rand(1, #buttons)]
  local hold = rand(0, 12)
  if hold > 0 then
    table.insert(script, { script[#script][1], hold })
  end
  table.insert(script, { 5, rand(1, 20) })
  return script
end

local function noise_script()
  local script = {}
  for _ = 1, rand(5, 30) do
    local buttons = ({ nil, nil, nil, "LP", "MK", "HP", "LPMP", "HK", "LKMK", "LPLK" })[rand(1, 10)]
    table.insert(script, { rand(1, 9), rand(1, 6), buttons })
  end
  table.insert(script, { 5, 30 })
  return script
end

local FIELDS = { "w_type", "w_int", "free1", "free2", "free3", "w_lvr", "flag", "shot_flag", "shot_flag2", "shot_ok" }

local function deep_copy(t)
  if type(t) ~= "table" then
    return t
  end
  local c = {}
  for k, v in pairs(t) do
    c[k] = deep_copy(v)
  end
  return c
end

S.spawn(function()
  S.boot_to_match(0, ROW)
  local fighter = commands.fighters[ROW]
  if S.u16(S.ADDR.p1_base + 0x3C0) ~= ROW then
    error("P1 is not character row " .. ROW)
  end
  local mem = { u8 = S.u8, u16 = S.u16, s16 = S.s16, u32 = S.u32 }
  local game = ram.new(mem, 1)
  local checker = Checker.new(fighter)
  local report = {}
  local stats = { frames = 0, skipped = 0, consumed = 0, mismatched_frames = 0 }
  local examples, history = {}, {}

  local function load_game_state(state)
    for slot = 0, C.SLOTS - 1 do
      if checker.flag[slot] ~= -1 then
        checker.flag[slot] = state.flag[slot]
        local w, g = checker.work[slot], state.work[slot]
        for _, f in ipairs(FIELDS) do
          w[f] = g[f]
        end
        w.ptr, w.idx = g.ptr, g.ptr - 1
      end
    end
  end

  local function same_state(a, b)
    for slot = 0, C.SLOTS - 1 do
      if checker.flag[slot] ~= -1 then
        if a.flag[slot] ~= b.flag[slot] then
          return false
        end
        for _, f in ipairs(FIELDS) do
          if a.work[slot][f] ~= b.work[slot][f] then
            return false
          end
        end
      end
    end
    return true
  end

  -- Game code outside the command check clears slots: waza_compel_init reloads the first step
  -- (a move starts, a jump starts or lands), waza_compel_all_init2 sets w_type to 0.
  local function external_reset(slot, was, g, flag)
    local first = checker.records[slot].steps[1]
    local reloaded = g.w_type == first[1]
      and g.w_int == first[2]
      and g.free1 == first[3]
      and g.ptr == 2
      and g.shot_ok == 0
      and g.free3 == 0
      and flag == 0
    local cleared = g.w_type == 0 and g.w_int == was.w_int and g.ptr == was.ptr
    return reloaded or cleared
  end

  local before = game:read_commands(checker.records)
  local function step_frame()
    local raw, ctx = game:read_input()
    local after = game:read_commands(checker.records)
    table.insert(
      history,
      inputs.lever_to_numpad(inputs.raw_to_lever(raw, ctx.facing_right)) .. inputs.buttons_text(raw)
    )
    if #history > 16 then
      table.remove(history, 1)
    end
    stats.frames = stats.frames + 1

    local lvr_snapshot = deep_copy(checker.lvr)
    local cp_snapshot = deep_copy(checker.cp)
    load_game_state(before)
    checker:frame(raw, ctx)

    -- Hypothesis: game code reloaded these slots before the check ran this frame.
    local function check_after_reload(slots)
      local saved =
        { lvr = checker.lvr, cp = checker.cp, flag = deep_copy(checker.flag), work = deep_copy(checker.work) }
      checker.lvr, checker.cp = deep_copy(lvr_snapshot), deep_copy(cp_snapshot)
      load_game_state(before)
      for _, slot in ipairs(slots) do
        checker.flag[slot] = 0
        checker:consume({ slot = slot })
        checker.work[slot].w_type = 0
      end
      checker:frame(raw, ctx)
      local result = { flag = deep_copy(checker.flag), work = deep_copy(checker.work) }
      checker.lvr, checker.cp, checker.flag, checker.work = saved.lvr, saved.cp, saved.flag, saved.work
      return result
    end

    local diffs = {}
    for slot = 0, C.SLOTS - 1 do
      if checker.flag[slot] ~= -1 then
        local g, w = after.work[slot], checker.work[slot]
        local bad = {}
        if after.flag[slot] ~= checker.flag[slot] then
          table.insert(bad, "flag " .. after.flag[slot] .. "/" .. checker.flag[slot])
        end
        for _, f in ipairs(FIELDS) do
          if g[f] ~= w[f] then
            table.insert(bad, f .. " " .. g[f] .. "/" .. w[f])
          end
        end
        if g.ptr ~= w.ptr and g.w_type ~= 0 then
          table.insert(bad, "ptr " .. g.ptr .. "/" .. w.ptr)
        end
        if #bad > 0 then
          table.insert(diffs, {
            slot = slot,
            text = table.concat(bad, ", "),
            reinit = external_reset(slot, before.work[slot], g, after.flag[slot]),
          })
        end
      end
    end

    if #diffs > 0 and same_state(before, after) then
      stats.skipped = stats.skipped + 1
      checker.lvr, checker.cp = lvr_snapshot, cp_snapshot
    elseif #diffs > 0 then
      local real, pending = {}, {}
      for _, d in ipairs(diffs) do
        local w, g = checker.work[d.slot], after.work[d.slot]
        local consumed_on_fire = after.flag[d.slot] == 0 and checker.flag[d.slot] > 0
        local cleared_after = g.w_type == 0
        for _, f in ipairs(FIELDS) do
          if f ~= "w_type" and g[f] ~= w[f] then
            cleared_after = false
          end
        end
        if d.reinit or consumed_on_fire or cleared_after then
          stats.consumed = stats.consumed + 1
        else
          table.insert(pending, d)
        end
      end
      if #pending > 0 then
        local slots = {}
        for _, d in ipairs(pending) do
          table.insert(slots, d.slot)
        end
        local alt = check_after_reload(slots)
        for _, d in ipairs(pending) do
          local g, w = after.work[d.slot], alt.work[d.slot]
          local same = alt.flag[d.slot] == after.flag[d.slot]
          for _, f in ipairs(FIELDS) do
            if g[f] ~= w[f] then
              same = false
            end
          end
          if same then
            stats.consumed = stats.consumed + 1
          else
            table.insert(real, d)
          end
        end
      end
      if #real > 0 then
        stats.mismatched_frames = stats.mismatched_frames + 1
        if #examples < 25 then
          for _, d in ipairs(real) do
            table.insert(
              examples,
              string.format(
                "frame %d slot %d %s (game/sim): %s | inputs %s",
                stats.frames,
                d.slot,
                checker.records[d.slot].name,
                d.text,
                table.concat(history, " ")
              )
            )
          end
        end
      end
    end
    before = after
  end

  local function play(script)
    for _, raw in ipairs(inputs.timeline(script, game:facing_right())) do
      S.hold_raw(raw)
      coroutine.yield()
      step_frame()
    end
  end

  for i = 1, reps do
    if i % 4 == 0 then
      play(noise_script())
    else
      local motions = {}
      for slot, record in pairs(fighter.slots) do
        if slot >= C.SA_GROUND and record.steps[1][1] ~= C.CK.NONE then
          table.insert(motions, record)
        end
      end
      table.sort(motions, function(a, b)
        return a.record < b.record
      end)
      play(motion_script(motions[rand(1, #motions)]))
    end
  end

  table.insert(
    report,
    string.format(
      "frames %d, skipped by the game %d, slots reset by game code outside the check %d, frames with mismatches %d",
      stats.frames,
      stats.skipped,
      stats.consumed,
      stats.mismatched_frames
    )
  )
  for _, e in ipairs(examples) do
    table.insert(report, e)
  end
  local f = io.open(out_path, "w")
  f:write(table.concat(report, "\n") .. "\n")
  f:close()
  print(table.concat(report, "\n"))
  S.exit()
end)
