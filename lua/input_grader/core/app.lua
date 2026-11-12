-- Composes a game module, the bench, the CSV log and the overlay. Game-agnostic: the game
-- module only has to provide :update() -> attempts, :moves() and :set_target(id).

local csv = require("input_grader.core.csv")
local Overlay = require("input_grader.core.overlay")

local App = {}
App.__index = App

App.HELP = "Alt+7 bench start/stop  Alt+8 target move  Alt+9 hide"

--- @param deps table { game, bench, clock = fn() -> seconds, timestamp = fn() -> string,
---   log = fn(line)|nil, overlay = Overlay|nil }
function App.new(deps)
  local self = setmetatable({}, App)
  self.game, self.bench, self.clock, self.log = deps.game, deps.bench, deps.clock, deps.log
  self.timestamp = deps.timestamp or function()
    return ""
  end
  self.overlay = deps.overlay or Overlay.new()
  self.visible, self.show_bench = true, false
  self.started_at = self.clock()
  self.target_index = 0
  return self
end

function App:frame()
  for _, attempt in ipairs(self.game:update()) do
    self.last, self.last_at = attempt, self.clock()
    self.bench:record(attempt)
    if self.log then
      self.log(csv.row(self.timestamp(), attempt))
    end
  end
end

function App:toggle_bench()
  if self.bench.running then
    self.bench:stop()
  else
    self.bench:start(self.target and self.target.id or nil)
  end
  self.show_bench = true
end

--- Cycle through: all moves, then each move the current character can be graded on.
function App:cycle_target()
  local moves = self.game:moves()
  self.target_index = (self.target_index + 1) % (#moves + 1)
  self.target = moves[self.target_index]
  self.game:set_target(self.target and self.target.id or nil)
end

function App:toggle_visible()
  self.visible = not self.visible
end

function App:draw(canvas)
  if not self.visible then
    return
  end
  local now = self.clock()
  self.overlay:draw(canvas, {
    attempt = self.last,
    attempt_age = self.last_at and (now - self.last_at) or nil,
    bench = self.show_bench and self.bench:summary() or nil,
    target_name = self.target and (self.target.name .. " " .. self.target.notation) or nil,
    help = (now - self.started_at < 10) and App.HELP or nil,
  })
end

return App
