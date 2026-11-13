-- The bench result: per move, successes out of attempts, the rate per facing, the most common
-- mistake and the median margin, in a panel over the play area. While the bench runs, a one-line
-- counter sits above the card instead.

local draw = require("input_grader.core.draw")

local COL = draw.COL
local M = {}

local ERRORS = {
  skipped_step = "skipped a direction",
  too_slow = "too slow",
  early_button = "button too early",
  late_button = "button too late",
  cancelled = "cancelled",
  missing_step = "incomplete motion",
  other_move = "different move",
  not_allowed = "refused by the game",
}

--- One line while running: "BENCH 7/10".
function M.counter(summary)
  local ok, n = 0, 0
  for _, m in ipairs(summary.moves) do
    ok, n = ok + m.ok, n + m.n
  end
  return "BENCH " .. ok .. "/" .. n
end

function M.draw(canvas, summary)
  local x0, y0, width = 44, 36, 296
  local lines = { { "BENCH RESULT  B: NEW SESSION", COL.gold } }
  if #summary.moves == 0 then
    table.insert(lines, { "no attempts", COL.dim })
  end
  for i, m in ipairs(summary.moves) do
    if i > 6 then
      break
    end
    local sides = {}
    for _, side in ipairs({ "left", "right" }) do
      if m.sides[side] then
        table.insert(sides, side:upper() .. " " .. m.sides[side].rate .. "%")
      end
    end
    table.insert(lines, {
      string.format("%s  %d/%d  %d%%  %s", m.name:upper(), m.ok, m.n, m.rate or 0, table.concat(sides, "  ")),
      COL.text,
    })
    local detail = {}
    if m.top_error then
      table.insert(detail, "most often: " .. (ERRORS[m.top_error.code] or m.top_error.code))
    end
    if m.median_margin then
      table.insert(detail, "median margin " .. m.median_margin .. "F")
    end
    if #detail > 0 then
      table.insert(lines, { table.concat(detail, ", "), COL.dim })
    end
  end
  local height = 8 + #lines * 10
  draw.rbox(canvas, x0, y0, x0 + width, y0 + height, COL.panel, COL.edge)
  for i, l in ipairs(lines) do
    canvas:text(x0 + 6, y0 + 5 + (i - 1) * 10, l[1], l[2])
  end
end

return M
