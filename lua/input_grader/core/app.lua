local card = require("input_grader.core.card")
local csv = require("input_grader.core.csv")
local draw = require("input_grader.core.draw")
local layout = require("input_grader.core.layout")
local menu = require("input_grader.core.menu")
local pearls = require("input_grader.core.pearls")

local COL = draw.COL
local App = {}
App.__index = App

App.HISTORY = 20
App.HELP = "M MENU"
App.LEGEND_X, App.LEGEND_Y = 4, 49
App.CARD_Y = 145
App.STALE_AFTER = 30
App.STALE_FADE = 0.4

local BUTTONS = { "LP", "MP", "HP", "LK", "MK", "HK" }

--- @param deps table { game, timestamp = fn() -> string, log = fn(line)|nil,
---   avoid = rectangles to keep clear (the input display), y = card top, active = fn() -> bool }
function App.new(deps)
  local self = setmetatable({}, App)
  self.game, self.log = deps.game, deps.log
  self.timestamp = deps.timestamp or function()
    return ""
  end
  self.avoid = deps.avoid or {}
  self.active = deps.active or function()
    return true
  end
  self.card_y = deps.y or App.CARD_Y
  self.attempts, self.shown = {}, nil
  self.visible = true
  self.menu_open, self.pick = false, 1
  self.target, self.tally = nil, { ok = 0, n = 0 }
  self.prev_keys, self.prev_pad = {}, {}
  self.tick, self.unanswered_press_at = 0, nil
  return self
end

-- An input the game refused (busy, a fireball on screen) was still the right input.
local function good_input(attempt)
  return attempt.ok or (attempt.error ~= nil and attempt.error.code == "not_allowed")
end

function App:frame()
  self.tick = self.tick + 1
  for _, attempt in ipairs(self.game:update()) do
    self.unanswered_press_at = nil
    table.insert(self.attempts, attempt)
    if #self.attempts > App.HISTORY then
      table.remove(self.attempts, 1)
    end
    self.shown = nil
    if self.target and attempt.id == self.target.id then
      self.tally.n = self.tally.n + 1
      if good_input(attempt) then
        self.tally.ok = self.tally.ok + 1
      end
    end
    if self.log then
      self.log(csv.row(self.timestamp(), attempt))
    end
  end
end

--- Whether the player's controls should be kept from the game this frame (the menu is open).
function App:blocks_input()
  return self.menu_open
end

local function pressed(now, before, name)
  return now[name] and not before[name]
end

--- Handles this frame's keyboard keys and pad (the player's real controls, read before any
--- blocking): tables of name -> true. Pad names: up, down, left, right, LP .. HK.
function App:controls(keys, pad)
  local k, p = keys or {}, pad or {}
  if not self.active() then
    self.menu_open = false
    self.prev_keys, self.prev_pad = k, p
    return
  end
  if pressed(k, self.prev_keys, "M") then
    self:toggle_menu()
  elseif self.menu_open then
    local rows = menu.selectable(menu.rows(self.game:moves()))
    if pressed(p, self.prev_pad, "down") then
      self.pick = self.pick % #rows + 1
    elseif pressed(p, self.prev_pad, "up") then
      self.pick = (self.pick - 2) % #rows + 1
    elseif pressed(p, self.prev_pad, "LP") then
      self:choose(rows[self.pick])
    elseif pressed(p, self.prev_pad, "LK") then
      self.menu_open = false
    end
  end
  if not self.menu_open and not self.unanswered_press_at then
    for _, b in ipairs(BUTTONS) do
      if pressed(p, self.prev_pad, b) then
        self.unanswered_press_at = self.tick
      end
    end
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

function App:toggle_menu()
  self.menu_open = not self.menu_open
  if self.menu_open then
    local rows = menu.selectable(menu.rows(self.game:moves()))
    self.pick = 1
    for i, r in ipairs(rows) do
      local is_target = self.target and r.id == self.target.id
      local is_all = not self.target and not r.action and not r.id
      if is_target or (is_all and self.pick == 1) then
        self.pick = i
      end
    end
  end
end

function App:choose(row)
  self.menu_open = false
  if row and row.action == "hide" then
    self.visible = false
    return
  end
  self.target = row and row.id and row or nil
  self.tally = { ok = 0, n = 0 }
  self.game:set_target(self.target and self.target.id or nil)
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

--- Whether the latest card no longer answers what the player did: a button since then got no card.
function App:stale()
  if self.shown or not self.unanswered_press_at then
    return false
  end
  return self.tick - self.unanswered_press_at >= App.STALE_AFTER
end

--- The target's success count and rate since it was picked: "14/20  70%".
function App:tally_text()
  local t = self.tally
  if t.n == 0 then
    return "0/0"
  end
  return t.ok .. "/" .. t.n .. "  " .. math.floor(100 * t.ok / t.n + 0.5) .. "%"
end

function App:draw(canvas)
  if not self.visible or not self.active() then
    return
  end
  if self.menu_open then
    menu.draw(canvas, menu.rows(self.game:moves()), self.pick)
    return
  end
  canvas:text(App.LEGEND_X, App.LEGEND_Y, App.HELP, COL.dim)
  local fit = layout.panel(self.card_y - 22, self.card_y + card.HEIGHT, self.avoid)
  if self.target then
    local y = self.card_y - card.NAME_H - 9
    local x = draw.inline(canvas, fit.x1 + 1, y, { self.target.name:upper() .. "  " }, COL.dim)
    canvas:text(x, y, self:tally_text(), COL.gold)
  end
  local shown = self.shown or #self.attempts
  local attempt = self.attempts[shown]
  if not attempt then
    return
  end
  local card_canvas = self:stale() and draw.faded(canvas, App.STALE_FADE) or canvas
  local box = card.draw(card_canvas, attempt, {
    x0 = fit.x1,
    y0 = self.card_y,
    max_x1 = fit.x2,
    target = self.target ~= nil and attempt.id == self.target.id,
  })
  pearls.draw(canvas, box, self.attempts, shown)
end

return App
