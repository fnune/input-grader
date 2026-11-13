local bench_panel = require("input_grader.core.bench_panel")
local card = require("input_grader.core.card")
local csv = require("input_grader.core.csv")
local draw = require("input_grader.core.draw")
local layout = require("input_grader.core.layout")
local pearls = require("input_grader.core.pearls")
local picker = require("input_grader.core.picker")

local COL = draw.COL
local App = {}
App.__index = App

App.HISTORY = 20
App.HELP = "M TARGET   B BENCH   H HIDE   PGUP/PGDN HISTORY"
App.CARD_Y = 145

--- @param deps table { game, bench, clock = fn() -> seconds, timestamp = fn() -> string,
---   log = fn(line)|nil, avoid = rectangles to keep clear (the input display), y = card top }
function App.new(deps)
  local self = setmetatable({}, App)
  self.game, self.bench, self.clock, self.log = deps.game, deps.bench, deps.clock, deps.log
  self.timestamp = deps.timestamp or function()
    return ""
  end
  self.avoid = deps.avoid or {}
  self.card_y = deps.y or App.CARD_Y
  self.attempts, self.shown = {}, nil
  self.visible = true
  self.picker_open, self.pick = false, 1
  self.target = nil
  self.prev_keys, self.prev_pad = {}, {}
  return self
end

function App:frame()
  for _, attempt in ipairs(self.game:update()) do
    table.insert(self.attempts, attempt)
    if #self.attempts > App.HISTORY then
      table.remove(self.attempts, 1)
    end
    self.shown = nil
    self.bench_result = nil
    self.bench:record(attempt)
    if self.log then
      self.log(csv.row(self.timestamp(), attempt))
    end
  end
end

--- Whether the player's controls should be kept from the game this frame (the picker is open).
function App:blocks_input()
  return self.picker_open
end

local function pressed(now, before, name)
  return now[name] and not before[name]
end

--- Handles this frame's keyboard keys and pad (the player's real controls, read before any
--- blocking): tables of name -> true. Pad names: up, down, left, right, LP .. HK.
function App:controls(keys, pad)
  local k, p = keys or {}, pad or {}
  if pressed(k, self.prev_keys, "M") then
    self:toggle_picker()
  elseif self.picker_open then
    local rows = picker.selectable(picker.rows(self.game:moves()))
    if pressed(p, self.prev_pad, "down") then
      self.pick = self.pick % #rows + 1
    elseif pressed(p, self.prev_pad, "up") then
      self.pick = (self.pick - 2) % #rows + 1
    elseif pressed(p, self.prev_pad, "LP") then
      self:choose(rows[self.pick])
    elseif pressed(p, self.prev_pad, "LK") then
      self.picker_open = false
    end
  end
  if pressed(k, self.prev_keys, "B") then
    self:toggle_bench()
  end
  if pressed(k, self.prev_keys, "H") then
    self:toggle_visible()
  end
  if pressed(k, self.prev_keys, "pageup") then
    self:browse(-1)
  elseif pressed(k, self.prev_keys, "pagedown") then
    self:browse(1)
  end
  self.prev_keys, self.prev_pad = k, p
end

function App:toggle_picker()
  self.picker_open = not self.picker_open
  if self.picker_open then
    self.pick = 1
    local rows = picker.selectable(picker.rows(self.game:moves()))
    for i, r in ipairs(rows) do
      if self.target and r.id == self.target.id then
        self.pick = i
      end
    end
  end
end

function App:choose(row)
  self.target = row and row.id and row or nil
  self.game:set_target(self.target and self.target.id or nil)
  self.picker_open = false
end

function App:toggle_bench()
  if self.bench.running then
    self.bench_result = self.bench:stop()
  else
    self.bench_result = nil
    self.bench:start(self.target and self.target.id or nil)
  end
end

function App:toggle_visible()
  self.visible = not self.visible
end

function App:browse(step)
  if #self.attempts == 0 then
    return
  end
  local at = (self.shown or #self.attempts) + step
  at = math.max(1, math.min(#self.attempts, at))
  self.shown = at < #self.attempts and at or nil
end

function App:draw(canvas)
  if not self.visible then
    return
  end
  if self.picker_open then
    picker.draw(canvas, picker.rows(self.game:moves()), self.pick)
    return
  end
  if self.bench_result then
    bench_panel.draw(canvas, self.bench_result)
    return
  end
  local fit = layout.panel(self.card_y - 22, self.card_y + card.HEIGHT, self.avoid)
  local shown = self.shown or #self.attempts
  local attempt = self.attempts[shown]
  if not attempt then
    canvas:text(fit.x1 + 1, self.card_y + 30, App.HELP, COL.dim)
    return
  end
  local box = card.draw(canvas, attempt, {
    x0 = fit.x1,
    y0 = self.card_y,
    max_x1 = fit.x2,
    target = self.target ~= nil and attempt.id == self.target.id,
  })
  pearls.draw(canvas, box, self.attempts, shown)
  if self.bench.running then
    canvas:text(fit.x1 + 1, self.card_y - card.NAME_H - 9, bench_panel.counter(self.bench:summary()), COL.gold)
  end
end

return App
