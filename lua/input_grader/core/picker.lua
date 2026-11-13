-- The target picker, ported from design/overlay-mock.html (drawPicker): every move of the
-- character, specials and super arts first, then moves without a button (dashes, parries) that
-- are graded only while targeted. It fills the play area and scrolls to keep the selection seen.

local draw = require("input_grader.core.draw")

local COL = draw.COL
local M = {}

-- The play area: clear of the input display on the left, the portraits and top HUD, and the
-- bottom HUD.
M.X0, M.Y0, M.WIDTH, M.VISIBLE, M.ROW_H = 44, 36, 296, 14, 11

local function is_notation(s)
  return s:match("^[%d%[%]]+$") or s:match("^[%d%[%]]+%+[PK][PK]?$")
end

--- Rows for `moves` (from the game module's :moves()): ALL MOVES, the main moves, a divider,
--- the other moves. Duplicates are merged; only real notation is kept, to be drawn as icons.
function M.rows(moves)
  local seen, main, other = {}, {}, {}
  for _, m in ipairs(moves) do
    local key = m.name .. "|" .. (m.notation or "")
    if not seen[key] then
      seen[key] = true
      local row = { id = m.id, name = m.name, notation = is_notation(m.notation or "") and m.notation or "" }
      table.insert((m.buttonless or m.other) and other or main, row)
    end
  end
  local rows = { { name = "ALL MOVES", notation = "" } }
  for _, r in ipairs(main) do
    table.insert(rows, r)
  end
  if #other > 0 then
    table.insert(rows, { divider = true })
    for _, r in ipairs(other) do
      table.insert(rows, r)
    end
  end
  return rows
end

--- The selectable rows (no divider), in order.
function M.selectable(rows)
  local out = {}
  for _, r in ipairs(rows) do
    if not r.divider then
      table.insert(out, r)
    end
  end
  return out
end

--- Draws the picker with selectable row `selected` (1-based) highlighted.
function M.draw(canvas, rows, selected, hint)
  local selectable = M.selectable(rows)
  local target = selectable[math.max(1, math.min(selected, #selectable))]
  local sel_row = 1
  for i, r in ipairs(rows) do
    if r == target then
      sel_row = i
    end
  end
  local first = math.max(1, math.min(sel_row - 6, #rows - M.VISIBLE + 1))
  local last = math.min(#rows, first + M.VISIBLE - 1)
  local x0, y0, width = M.X0, M.Y0, M.WIDTH
  local height = 16 + (last - first + 1) * M.ROW_H
  draw.rbox(canvas, x0, y0, x0 + width, y0 + height, COL.panel, COL.edge)
  canvas:text(x0 + 5, y0 + 4, "TARGET", COL.text)
  hint = hint or "STICK MOVE  LP PICK  LK CLOSE"
  canvas:text(x0 + width - 4 - draw.CHAR_W * #hint, y0 + 4, hint, COL.dim)
  for i = first, last do
    local m = rows[i]
    local y = y0 + 16 + (i - first) * M.ROW_H
    if m.divider then
      canvas:line(x0 + 6, y + 3, x0 + width - 6, y + 3, COL.edge)
      canvas:text(x0 + 8, y, "OTHER MOVES", COL.dim)
    else
      local is_sel = i == sel_row
      if is_sel then
        draw.rbox(canvas, x0 + 2, y - 2, x0 + width - 2, y + M.ROW_H - 3, 0xFFFFFF20, COL.text)
      end
      if m.notation ~= "" then
        draw.inline(canvas, x0 + 6, y, draw.notation_parts(m.notation), COL.text)
      end
      canvas:text(x0 + 104, y, m.name:upper(), is_sel and COL.text or COL.dim)
    end
  end
  if last < #rows then
    canvas:text(x0 + width / 2 - 4, y0 + height - 4, "...", COL.dim)
  end
end

return M
