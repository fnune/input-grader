local M = {}

M.ACTIONS = {
  forward_dash = { routine = { 0, 5 }, name = "dash" },
  back_dash = { routine = { 0, 6 }, name = "back dash" },
}
-- In RAM, a press seen on a frame whose animation frame type is one of these starts a move (live
-- cases in harness/mame/grade.lua; throw.lua measured it).
M.ACTIONABLE_CG = { [2] = true, [3] = true, [64] = true }
M.THROW_START = { 4, 14 }
M.THROWING, M.ATTACKING = 2, 4
M.SETTLE = 6
M.GIVE_UP = 40

local Followup = {}
Followup.__index = Followup

function M.new()
  return setmetatable({ frame = 0 }, Followup)
end

local function action_of(routine)
  for key, a in pairs(M.ACTIONS) do
    if routine[1] == a.routine[1] and routine[2] == a.routine[2] then
      return key
    end
  end
  return nil
end

local function outcome(routine)
  if routine[1] == M.THROWING then
    return "threw"
  end
  if routine[1] == M.ATTACKING and routine[2] == M.THROW_START[2] then
    return "throw_whiffed"
  end
  if routine[1] == M.ATTACKING then
    return "attacked"
  end
  return nil
end

--- Feed one frame: P1's `routine` {r1, r2}, the animation frame type `cg_type` and the buttons
--- newly `pressed` (a list of names). Returns a finished follow-up once it can be judged:
--- { action, start, actionable, press = { frame, buttons }, result }.
function Followup:update(obs)
  self.frame = self.frame + 1
  local f = self.frame
  local key = action_of(obs.routine)
  if key and key ~= self.last_action then
    self.current = { action = key, start = f }
  end
  self.last_action = key
  local cur = self.current
  if not cur then
    return nil
  end
  if not cur.actionable and M.ACTIONABLE_CG[obs.cg_type] then
    cur.actionable = f
  end
  if not cur.press and #obs.pressed > 0 then
    cur.press = { frame = f, buttons = obs.pressed }
  end
  if cur.press then
    local now = outcome(obs.routine)
    if now == "threw" or (now and not cur.result) then
      cur.result = now
    end
  end
  local settled = cur.press and cur.actionable and f - math.max(cur.press.frame, cur.actionable) >= M.SETTLE
  if settled or f - cur.start >= M.GIVE_UP then
    self.current = nil
    cur.result = cur.result or (cur.press and "nothing" or "no_press")
    return cur
  end
  return nil
end

return M
