-- The 3rd Strike game module: turns check frames from a source (RAM or the Lua checker) into
-- graded attempts in the game-agnostic format described in docs/porting.md.

local bits = require("input_grader.core.bits")
local History = require("input_grader.core.history")
local C = require("input_grader.games.sfiii3.constants")
local inputs = require("input_grader.games.sfiii3.inputs")
local Tracker = require("input_grader.games.sfiii3.tracker")

local band, has = bits.band, bits.has
local CK = C.CK

local Game = {}
Game.__index = Game

local DEFAULTS = { lookback = 60, settle = 12 }

-- Steps whose `time` is the number of frames allowed since the previous step matched.
local TIMED = {
  [CK.LEVER] = true,
  [CK.LEVER_PRESS] = true,
  [CK.LEVER_HELD] = true,
  [CK.LEVER_NEW] = true,
  [CK.LEVER_CHANGE] = true,
  [CK.PRESS] = true,
  [CK.LEVER_SET] = true,
}

local LEVER_STEPS = {
  [CK.LEVER] = true,
  [CK.LEVER_PRESS] = true,
  [CK.LEVER_HELD] = true,
  [CK.LEVER_NEW] = true,
  [CK.LEVER_CHANGE] = true,
  [CK.LEVER_OFF] = true,
  [CK.LEVER_SET] = true,
  [CK.LEVER_REPEAT] = true,
  [CK.LEVER_COUNT] = true,
}

local DIAGONALS = { [1] = true, [3] = true, [7] = true, [9] = true }

local function step_label(step)
  local ck, sw = step[1], bits.u16(step[4])
  if LEVER_STEPS[ck] then
    local digit = inputs.lever_to_numpad(band(sw, C.LV_MASK))
    if has(sw, C.LV_EXACT) or sw == 0 then
      return tostring(digit)
    end
    return "~" .. digit
  elseif ck == CK.CHARGE then
    return "[" .. inputs.lever_to_numpad(band(sw, C.LV_MASK)) .. "]"
  elseif ck == CK.ROTATE then
    return "360"
  elseif ck == CK.TURN then
    return "turn"
  elseif ck == CK.RENDA or ck == CK.RENDA3 then
    return "mash"
  end
  return inputs.buttons_text(sw)
end

local function lever_matches(step, lever)
  local sw = bits.u16(step[4])
  if has(sw, C.LV_EXACT) then
    return lever == band(sw, C.LV_MASK)
  end
  if sw == 0 then
    return lever == 0
  end
  return has(lever, band(sw, C.LV_MASK))
end

--- @param source table with :poll() (see sources.lua)
--- @param commands table games/sfiii3/commands.lua
--- @param options table|nil { target = move id, lookback, settle }
function Game.new(source, commands, options)
  local self = setmetatable({}, Game)
  self.source, self.commands = source, commands
  self.options = {}
  for k, v in pairs(DEFAULTS) do
    self.options[k] = v
  end
  for k, v in pairs(options or {}) do
    self.options[k] = v
  end
  self.frame, self.history, self.prev_buttons = 0, History.new(240), 0
  return self
end

function Game:set_target(id)
  self.options.target = id
end

--- Moves the current character can be graded on, for choosing a bench target.
function Game:moves()
  local list = {}
  if not self.fighter then
    return list
  end
  for slot, record in pairs(self.fighter.slots) do
    if slot >= C.SA_GROUND and record.steps[1][1] ~= CK.NONE and band(record.btix, C.BT_INDEX) ~= C.BT_NONE then
      table.insert(
        list,
        { id = self.fighter.name .. ":" .. slot, name = record.name, notation = record.notation, slot = slot }
      )
    end
  end
  table.sort(list, function(a, b)
    return a.slot < b.slot
  end)
  return list
end

local function selected_art_slots(fighter, art)
  local a = fighter.super_arts[(art or 0) + 1] or {}
  return { [a.ground or -1] = true, [a.air or -1] = true }
end

local function candidate(self, slot, record, flags)
  if slot < C.SA_GROUND or flags[slot] == -1 then
    return false
  end
  if record.steps[1][1] == CK.NONE or band(record.btix, C.BT_INDEX) == C.BT_NONE then
    return false
  end
  if (slot < C.SP_GROUND or (slot >= C.SA_AIR and slot < C.SP_AIR)) and not self.art_slots[slot] then
    return false
  end
  return true
end

local function button_fits(record, pressed)
  for j = 3, 0, -1 do
    if not (j == 3 and not has(record.btix, C.BT_STRENGTH4)) then
      local ex = record.exdt[j + 1]
      if band(pressed, C.SHOT_CONV[ex + 1]) == C.SHOT_CONV[band(ex, C.EX_BUTTON) + 1] then
        return true
      end
    end
  end
  return false
end

function Game:rebuild(obs)
  self.fighter = self.commands.fighters[obs.fighter_row]
  self.fighter_row = obs.fighter_row
  self.art = obs.super_art
  self.art_slots = selected_art_slots(self.fighter, obs.super_art)
  local tracked = {}
  for slot, record in pairs(self.fighter.slots) do
    if slot >= C.SA_GROUND then
      tracked[slot] = record
    end
  end
  self.tracker = Tracker.new(tracked)
  self.pending = nil
end

--- Advance one emulator frame. Returns the attempts graded this frame (usually none).
function Game:update()
  local obs = self.source:poll()
  if not obs then
    return {}
  end
  if obs.fighter_row ~= self.fighter_row or obs.super_art ~= self.art then
    self:rebuild(obs)
  end
  if not self.fighter then
    return {}
  end
  self.frame = self.frame + 1
  local frame = self.frame

  local lever = inputs.raw_to_lever(obs.raw, obs.facing_right)
  local buttons = band(obs.raw, C.SW_SHOT)
  local pressed = band(buttons, bits.bnot16(self.prev_buttons))
  local released = band(self.prev_buttons, bits.bnot16(buttons))
  self.prev_buttons = buttons
  self.history:push(frame, { lever = lever, pressed = pressed, released = released, held = buttons })

  local dead = {}
  for slot, record in pairs(self.fighter.slots) do
    if (record.dead ~= 0 and obs.sw_new == record.dead) or (record.dead2 ~= 0 and obs.sw_new == record.dead2) then
      dead[slot] = true
    end
  end
  self.flags = obs.state.flag
  self.tracker:update(obs.state, dead, obs.started and obs.started.slot)

  local graded = {}
  local function finish()
    local attempt = self:grade(self.pending)
    self.pending = nil
    if attempt then
      table.insert(graded, attempt)
    end
  end

  if pressed ~= 0 then
    if self.pending then
      finish()
    end
    self.pending = { frame = frame, pressed = pressed, facing_right = obs.facing_right }
  end
  if obs.started then
    if self.pending and frame - self.pending.frame <= self.options.settle then
      self.pending.started = obs.started
      self.pending.started_frame = frame
    else
      if self.pending then
        finish()
      end
      self.pending = {
        frame = frame,
        pressed = released,
        started = obs.started,
        started_frame = frame,
        facing_right = obs.facing_right,
      }
    end
    finish()
  elseif self.pending and frame - self.pending.frame >= self.options.settle then
    finish()
  end
  return graded
end

local function count(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

-- One matched step is an attempt only when a later step's direction followed it (2 then 6
-- for a Hadoken), so a crouching normal does not count as a failed Hadoken.
local function later_step_seen(self, record, run, last)
  if not run.steps[1] then
    return false
  end
  for k = 2, #record.steps do
    local step = record.steps[k]
    if LEVER_STEPS[step[1]] then
      for _, h in ipairs(self.history:range(run.steps[1] + 1, last)) do
        if lever_matches(step, h.lever) then
          return true
        end
      end
    end
  end
  return false
end

local function choose(self, p)
  local best, best_score
  local since = p.frame - self.options.lookback
  for slot, record in pairs(self.fighter.slots) do
    if candidate(self, slot, record, self.flags) then
      local id = self.fighter.name .. ":" .. slot
      local wanted = not self.options.target or self.options.target == id
      local fits = button_fits(record, p.pressed) or (p.started and p.started.slot == slot)
      local run = wanted and fits and self.tracker:best_run(slot, since)
      if run then
        local n, total = count(run.steps), #record.steps
        if n >= math.min(2, total) or later_step_seen(self, record, run, p.frame) then
          local score = n / total
          local better = not best
            or score > best_score
            or (score == best_score and p.started and p.started.slot == slot)
            or (score == best_score and not (p.started and p.started.slot == best.slot) and total > #best.record.steps)
          if better then
            best, best_score = { slot = slot, record = record, run = run, id = id }, score
          end
        end
      end
    end
  end
  return best
end

local function plural(n, word)
  return n .. " " .. word .. (n == 1 and "" or "s")
end

function Game:diagnose(p, pick)
  local record, run = pick.record, pick.run
  local steps = record.steps
  local c = run.complete
  if p.started then
    local other = self.fighter.slots[p.started.slot]
    return { code = "other_move", text = (other and other.name or "another move") .. " came out instead" }
  end
  if c and c > p.frame then
    return { code = "early_button", text = "button " .. plural(c - p.frame, "frame") .. " before the motion finished" }
  end
  if c then
    local window = record.reset - 2
    local after = p.frame - c
    if after > window then
      return {
        code = "late_button",
        text = "button " .. plural(after - window, "frame") .. " too late (allowed " .. window .. " after the motion)",
      }
    end
    return {
      code = "not_allowed",
      text = "motion and button were in time; the game refused the move (busy, meter or a fireball on screen)",
    }
  end
  local k = 1
  while run.steps[k] do
    k = k + 1
  end
  local step = steps[k]
  local want = step_label(step)
  if run.reset and run.reset.why == "dead" then
    return { code = "cancelled", text = "a jump input cancelled the motion before " .. want }
  end
  local prev_frame = run.steps[k - 1] or run.start
  local arrival
  if LEVER_STEPS[step[1]] then
    for _, h in ipairs(self.history:range(prev_frame + 1, p.frame + self.options.settle)) do
      if lever_matches(step, h.lever) then
        arrival = h.frame
        break
      end
    end
  end
  local window = TIMED[step[1]] and step[2] > 0 and step[2] or nil
  if arrival and window and arrival - prev_frame > window then
    return {
      code = "too_slow",
      text = want
        .. " came "
        .. plural(arrival - prev_frame - window, "frame")
        .. " too late (window "
        .. window
        .. ")",
    }
  end
  if not arrival then
    local digit = tonumber(want)
    local next_step = steps[k + 1]
    if digit and DIAGONALS[digit] and next_step then
      for _, h in ipairs(self.history:range(prev_frame + 1, p.frame)) do
        if lever_matches(next_step, h.lever) then
          return {
            code = "skipped_step",
            text = "went from "
              .. step_label(steps[k - 1] or step)
              .. " to "
              .. step_label(next_step)
              .. " without "
              .. want,
          }
        end
      end
    end
    return { code = "missing_step", text = "the motion never reached " .. want }
  end
  if arrival > p.frame then
    return { code = "early_button", text = "button pressed while the motion still needed " .. want }
  end
  return { code = "missing_step", text = "the game did not accept " .. want }
end

function Game:grade(p)
  if not p then
    return nil
  end
  local pick = choose(self, p)
  if not pick then
    return nil
  end
  local record, run = pick.record, pick.run
  local attempt = {
    game = "sfiii3",
    character = self.fighter.name,
    id = pick.id,
    move = record.name,
    notation = record.notation,
    frame = p.frame,
    side = p.facing_right and "right" or "left",
    ok = p.started ~= nil and p.started.slot == pick.slot,
    steps = {},
    minimum = #record.steps - 1,
  }
  local margin
  for k, step in ipairs(record.steps) do
    local s = { label = step_label(step) }
    if k > 1 and run.steps[k] and run.steps[k - 1] then
      s.used = run.steps[k] - run.steps[k - 1]
      if TIMED[step[1]] and step[2] > 0 then
        s.window = step[2]
        margin = math.min(margin or s.window, s.window - s.used)
      end
    end
    table.insert(attempt.steps, s)
  end
  local c = run.complete
  if c and c <= p.frame then
    attempt.button = { label = inputs.buttons_text(p.pressed), after = p.frame - c, window = record.reset - 2 }
    margin = math.min(margin or attempt.button.window, attempt.button.window - attempt.button.after)
  else
    attempt.button = { label = inputs.buttons_text(p.pressed) }
  end
  if run.steps[1] then
    attempt.total = p.frame - run.steps[1]
  end
  attempt.margin = margin
  if not attempt.ok then
    attempt.error = self:diagnose(p, pick)
  end
  attempt.trace = self:trace(p, pick)
  return attempt
end

--- Per-frame inputs around the attempt, for drawing it on a time axis. Frame numbers are
--- relative to the first frame of `frames` (1-based), so the record stays game-agnostic.
function Game:trace(p, pick)
  local record, run = pick.record, pick.run
  -- Reach back over the whole hold of step 1's direction: a held 2 is re-accepted every 11
  -- frames, so the accepted frame is often late in the hold.
  local first = run.steps[1] or run.start
  local held = self.history:at(first)
  while held and first > 1 and first > p.frame - 90 do
    local before = self.history:at(first - 1)
    if not before or before.lever ~= held.lever then
      break
    end
    first = first - 1
  end
  first = math.max(first - 2, 1)
  local last = math.max(p.frame, run.complete or 0) + 4
  local trace = { frames = {}, steps = {} }
  for _, h in ipairs(self.history:range(first, last)) do
    table.insert(trace.frames, { dir = inputs.lever_to_numpad(h.lever), press = inputs.buttons_text(h.pressed) })
  end
  local origin = first - 1
  for k, step in ipairs(record.steps) do
    local s = { label = step_label(step) }
    if run.steps[k] then
      s.at = run.steps[k] - origin
    end
    if k > 1 and TIMED[step[1]] and step[2] > 0 then
      s.window = step[2]
    end
    table.insert(trace.steps, s)
  end
  trace.button_at = p.frame - origin
  trace.button_window = record.reset - 2
  trace.complete_at = run.complete and (run.complete - origin) or nil
  return trace
end

Game.step_label = step_label
Game.TIMED = TIMED

return Game
