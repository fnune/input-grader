-- Turns the game's per-frame command state into motion "runs": for each slot, when each step
-- matched, when the motion completed, and when and why it was abandoned. The state can come
-- from RAM (live) or from the Lua checker (tests), since both expose waza_flag and WAZA_WORK.
--
-- Frames are counted in check frames: frames where the game ran the command check. That is the
-- clock the game's windows use, so frozen frames (super freeze) do not count against the player.

local Tracker = {}
Tracker.__index = Tracker

local KEEP_RUNS = 6

--- @param records table slot -> record (only slots to track)
function Tracker.new(records)
  local self = setmetatable({ records = records, frame = 0, prev = nil, runs = {} }, Tracker)
  for slot in pairs(records) do
    self.runs[slot] = {}
  end
  return self
end

local function progress(w)
  if w.w_type == 0 then
    return 0
  end
  return math.max(w.ptr - 2, 0)
end

local function current_run(self, slot)
  local runs = self.runs[slot]
  return runs[#runs]
end

local function start_run(self, slot)
  local runs = self.runs[slot]
  local run = { slot = slot, steps = {}, start = self.frame }
  table.insert(runs, run)
  if #runs > KEEP_RUNS then
    table.remove(runs, 1)
  end
  return run
end

local function mark_steps(run, from, to, frame)
  for k = from, to do
    if not run.steps[k] then
      run.steps[k] = frame
    end
  end
end

--- Feed one check frame.
--- @param state table { flag = {[slot]=n}, work = {[slot]={w_type, ptr, ...}} }
--- @param dead table|nil slot -> true when a dead input abandoned the slot this frame
--- @param started number|nil slot of a move the game started this frame
function Tracker:update(state, dead, started)
  self.frame = self.frame + 1
  local prev = self.prev
  for slot, record in pairs(self.records) do
    local w, flag = state.work[slot], state.flag[slot]
    local p = progress(w)
    local before = prev and prev.work[slot]
    local before_flag = prev and prev.flag[slot] or 0
    local before_p = before and progress(before) or 0
    local run = current_run(self, slot)
    local open = run and not run.done

    -- command_ok sets the flag to `reset` and command_ok_move decrements it in the same frame,
    -- so a completion shows as a rising flag.
    -- A move that starts in the frame its motion completes is cleared (waza_compel_init) before
    -- RAM can show the flag, so the start itself marks the completion.
    local completed = flag > before_flag or (started == slot and before_flag <= 0)
    if completed then
      if not open or before_p == 0 then
        run = start_run(self, slot)
      end
      mark_steps(run, before_p + 1, #record.steps, self.frame)
      run.complete, run.done = self.frame, true
    elseif p > before_p then
      if not open or before_p == 0 then
        run = start_run(self, slot)
      end
      mark_steps(run, before_p + 1, p, self.frame)
    elseif open and before_p > 0 and p < before_p then
      run.reset = { frame = self.frame, step = before_p + 1, why = (dead and dead[slot]) and "dead" or "timeout" }
      run.done = true
      if p > 0 then
        run = start_run(self, slot)
        mark_steps(run, 1, p, self.frame)
      end
    end
  end
  self.prev = state
end

--- The most advanced run of a slot that started at or after `since` (check frame).
function Tracker:best_run(slot, since)
  local best
  for _, run in ipairs(self.runs[slot] or {}) do
    if run.start >= since then
      local n = 0
      for _ in pairs(run.steps) do
        n = n + 1
      end
      run.matched = n
      if not best or n >= best.matched then
        best = run
      end
    end
  end
  return best
end

return Tracker
