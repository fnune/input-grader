local M = {}

M.SCREEN_W = 384
M.MARGIN = 8
M.GAP = 4
M.COMPACT_BELOW = 300

local function overlaps(y1, y2, r)
  return r.y1 <= y2 and r.y2 >= y1
end

--- @param y1 number top of the panel
--- @param y2 number bottom of the panel
--- @param avoid table list of { x1, y1, x2, y2 } to keep clear
--- @return table { x1, x2, compact }
function M.panel(y1, y2, avoid)
  local x1, x2 = M.MARGIN, M.SCREEN_W - M.MARGIN
  local middle = M.SCREEN_W / 2
  for _, r in ipairs(avoid or {}) do
    if overlaps(y1, y2, r) then
      if (r.x1 + r.x2) / 2 < middle then
        x1 = math.max(x1, r.x2 + M.GAP)
      else
        x2 = math.min(x2, r.x1 - M.GAP)
      end
    end
  end
  return { x1 = x1, x2 = x2, compact = (x2 - x1) < M.COMPACT_BELOW }
end

return M
