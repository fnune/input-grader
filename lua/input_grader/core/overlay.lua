-- Draws the last graded attempt and the bench summary through a canvas port:
--   canvas:text(x, y, string, color)   canvas:box(x1, y1, x2, y2, fill, outline)
-- Colors are names ("text", "dim", "good", "bad", "warn", "panel", "edge") that each platform
-- maps to its own format. Game-agnostic: it only reads attempt and bench-summary records.

local layout = require("input_grader.core.layout")

local Overlay = {}
Overlay.__index = Overlay

local DEFAULTS = { x = 8, y = 150, width = 368, char_w = 4, line_h = 9 }

function Overlay.new(config)
  local self = setmetatable({ config = {} }, Overlay)
  for k, v in pairs(DEFAULTS) do
    self.config[k] = v
  end
  for k, v in pairs(config or {}) do
    self.config[k] = v
  end
  return self
end

local ERROR_TITLES = {
  skipped_step = "skipped a direction",
  too_slow = "too slow",
  early_button = "button too early",
  late_button = "button too late",
  cancelled = "cancelled",
  missing_step = "incomplete motion",
  other_move = "different move",
  not_allowed = "refused by the game",
}

function Overlay.error_title(code)
  return ERROR_TITLES[code] or code
end

--- "2  3 2/10  6 1/10  LP 0/10": each step with frames used and the frames allowed.
function Overlay.steps_line(attempt)
  local parts = {}
  for _, s in ipairs(attempt.steps or {}) do
    if s.used and s.window then
      table.insert(parts, s.label .. " " .. s.used .. "/" .. s.window)
    elseif s.used then
      table.insert(parts, s.label .. " " .. s.used)
    else
      table.insert(parts, s.label)
    end
  end
  local b = attempt.button
  if b and b.label and b.label ~= "" then
    if b.after and b.window then
      table.insert(parts, b.label .. " " .. b.after .. "/" .. b.window)
    else
      table.insert(parts, b.label)
    end
  end
  return table.concat(parts, "  ")
end

function Overlay.timing_line(attempt)
  local bits = {}
  if attempt.total then
    table.insert(bits, attempt.total .. "f total (fastest possible " .. attempt.minimum .. "f)")
  end
  if attempt.margin then
    table.insert(bits, "tightest margin " .. attempt.margin .. "f")
  end
  return table.concat(bits, ", ")
end

function Overlay.bench_lines(summary)
  local lines = {}
  local head = summary.running and "BENCH running" or "BENCH result"
  if summary.target then
    head = head .. " (one move)"
  end
  table.insert(lines, { head, "warn" })
  if #summary.moves == 0 then
    table.insert(lines, { "no attempts yet", "dim" })
  end
  for i, m in ipairs(summary.moves) do
    if i > 3 then
      break
    end
    local sides = {}
    for _, side in ipairs({ "left", "right" }) do
      local s = m.sides[side]
      if s then
        table.insert(sides, "facing " .. side .. " " .. s.rate .. "%")
      end
    end
    table.insert(lines, {
      string.format("%s %s  %d/%d  %d%%  %s", m.name, m.notation, m.ok, m.n, m.rate or 0, table.concat(sides, "  ")),
      "text",
    })
    local detail = {}
    if m.top_error then
      table.insert(detail, "most common: " .. Overlay.error_title(m.top_error.code) .. " (" .. m.top_error.count .. ")")
    end
    if m.n > 10 then
      table.insert(detail, "first 10 " .. m.first_rate .. "% > last 10 " .. m.last_rate .. "%")
    end
    if m.median_margin then
      table.insert(detail, "median margin " .. m.median_margin .. "f")
    end
    if #detail > 0 then
      table.insert(lines, { table.concat(detail, "  "), "dim" })
    end
  end
  return lines
end

--- @param view table { attempt, bench (summary or nil), help (string or nil),
---   target_name }
function Overlay:draw(canvas, view)
  local c = self.config
  local lines = {}
  -- The card stays until the next attempt replaces it, or the overlay is hidden.
  if view.attempt then
    local a = view.attempt
    local verdict = a.ok and "OUT" or ("MISSED: " .. Overlay.error_title(a.error and a.error.code or "?"))
    table.insert(lines, { a.move .. " " .. a.notation .. "   " .. verdict, a.ok and "good" or "bad" })
    table.insert(lines, { Overlay.steps_line(a), "text" })
    if not a.ok and a.error then
      table.insert(lines, { a.error.text, "warn" })
    end
    local timing = Overlay.timing_line(a)
    if timing ~= "" then
      table.insert(lines, { timing, "dim" })
    end
  end
  if view.bench then
    for _, l in ipairs(Overlay.bench_lines(view.bench)) do
      table.insert(lines, l)
    end
  end
  if view.target_name then
    table.insert(lines, { "target: " .. view.target_name, "dim" })
  end
  if view.help then
    table.insert(lines, { view.help, "dim" })
  end
  if #lines == 0 then
    return
  end
  local height = #lines * c.line_h + 6
  local y0 = c.y
  local fit = layout.panel(y0, y0 + height, c.avoid)
  local x1, x2 = math.max(c.x, fit.x1), math.min(c.x + c.width, fit.x2)
  local max_chars = math.floor((x2 - x1 - 8) / c.char_w)
  canvas:box(x1, y0, x2, y0 + height, "panel", "edge")
  for i, l in ipairs(lines) do
    local text = l[1]
    if #text > max_chars then
      text = text:sub(1, math.max(max_chars - 1, 0)) .. "~"
    end
    canvas:text(x1 + 4, y0 + 4 + (i - 1) * c.line_h, text, l[2])
  end
end

return Overlay
