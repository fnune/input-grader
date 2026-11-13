local card = require("input_grader.core.card")
local draw = require("input_grader.core.draw")

local COL = draw.COL
local M = {}

M.VISIBLE, M.STEP = 12, 9

local KIND_COL = { missed = COL.bad, refused = COL.dim, perfect = COL.gold }

local function draw_kind(canvas, kind, x, y, n)
  draw.pearl(canvas, x, y, KIND_COL[kind] or COL.good, n)
  if kind == "perfect" or kind == "clean" then
    draw.gold_plus(canvas, x + n - 1, y)
  end
end

--- Draws `attempts` (oldest first) under `box`, with `shown` (an index into attempts) lifted.
function M.draw(canvas, box, attempts, shown)
  local first = math.max(1, math.min(shown - 6, #attempts - M.VISIBLE + 1))
  local y = box.y1 + 4
  local x = box.x0 + 3
  for i = first, math.min(#attempts, first + M.VISIBLE - 1) do
    local kind = card.kind(attempts[i])
    if i == shown then
      draw.lift_shadow(canvas, x, y + 5)
      draw_kind(canvas, kind, x - 1, y - 1, 7)
    else
      local c = KIND_COL[kind] or COL.good
      draw.pearl(canvas, x, y, draw.alpha(c, 0x70), 5)
    end
    x = x + M.STEP
  end
end

return M
