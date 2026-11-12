-- One CSV row per attempt, for comparing sessions in a spreadsheet.

local M = {}

M.HEADER = "time,game,character,move,notation,side,result,error,steps,button_after,button_window,total,minimum,margin"

local function field(v)
  if v == nil then
    return ""
  end
  local s = tostring(v)
  if s:find('[,"\n]') then
    s = '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

function M.row(time, attempt)
  local steps = {}
  for _, s in ipairs(attempt.steps or {}) do
    local used = s.used and (s.used .. "/" .. (s.window or "-")) or "-"
    table.insert(steps, s.label .. ":" .. used)
  end
  local b = attempt.button or {}
  return table.concat({
    field(time),
    field(attempt.game),
    field(attempt.character),
    field(attempt.move),
    field(attempt.notation),
    field(attempt.side),
    field(attempt.ok and "out" or "failed"),
    field(attempt.error and attempt.error.code),
    field(table.concat(steps, " ")),
    field(b.after),
    field(b.window),
    field(attempt.total),
    field(attempt.minimum),
    field(attempt.margin),
  }, ",")
end

return M
