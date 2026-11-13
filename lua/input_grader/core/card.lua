local draw = require("input_grader.core.draw")

local COL = draw.COL
local M = {}

M.HEIGHT, M.NAME_H, M.PAD, M.GAP = 52, 11, 4, 8

local SHORT = {
  skipped_step = "SKIPPED",
  too_slow = "TOO SLOW",
  early_button = "EARLY",
  late_button = "LATE",
  cancelled = "CANCELLED",
  missing_step = "INCOMPLETE",
  other_move = "OTHER MOVE",
  not_allowed = "REFUSED",
}

local function label_dir(label)
  local d = tonumber((label or ""):match("^~?(%d)$"))
  return d
end

local function first_missing(steps)
  for k, s in ipairs(steps) do
    if s.at == nil then
      return k
    end
  end
  return nil
end

local function button_icon(attempt)
  return attempt.button and attempt.button.label and attempt.button.label:match("[LMH][PK]") or nil
end

--- The step the miss is about and a few words with icons: "NO <3>", "<P> +4F LATE".
function M.reason(attempt)
  if attempt.ok then
    return { parts = { attempt.total .. "F  (MIN " .. attempt.minimum .. "F)" } }
  end
  local t, code = attempt.trace, attempt.error.code
  local k = first_missing(t.steps)
  local step = k and t.steps[k]
  local icon = step and (label_dir(step.label) and { dir = label_dir(step.label) } or step.label) or ""
  local btn = { btn = button_icon(attempt) or "LP" }
  local n = attempt.error.text:match("(%d+) frames?") or "?"
  if code == "skipped_step" then
    return { parts = { "NO ", icon }, step = k }
  elseif code == "too_slow" then
    return { parts = { icon, " +" .. n .. "F LATE" }, step = k }
  elseif code == "late_button" then
    return { parts = { btn, " +" .. n .. "F LATE" }, button = true }
  elseif code == "early_button" then
    if step then
      return { parts = { btn, " BEFORE ", icon }, step = k, button = true }
    end
    return { parts = { btn, " " .. n .. "F EARLY" }, button = true }
  elseif code == "cancelled" then
    return { parts = { { dir = 8 }, " CANCELLED" }, step = k }
  end
  return { parts = { SHORT[code] or code }, step = k }
end

local function safe(attempt)
  if not attempt.ok then
    return false
  end
  local t = attempt.trace
  for k, s in ipairs(t.steps) do
    local prev = t.steps[k - 1]
    if k > 1 and s.window and s.at and prev and prev.at and not draw.safe_use(s.at - prev.at, s.window) then
      return false
    end
  end
  if t.complete_at and t.button_at and not draw.safe_use(t.button_at - t.complete_at, t.button_window) then
    return false
  end
  return true
end

--- "missed", "out", "clean" (every input used at most half its window) or "perfect" (the
--- fastest possible).
function M.kind(attempt)
  if not attempt or not attempt.ok then
    return "missed"
  end
  if attempt.total == attempt.minimum then
    return "perfect"
  end
  return safe(attempt) and "clean" or "out"
end

local function first_frame_with(frames, from, to, dir)
  for i = from, to do
    if frames[i] and frames[i].dir == dir then
      return i
    end
  end
  return nil
end

--- Splits the played frames into one group per column: each frame goes to the first step at or
--- after it that the player reached (accepted, or seen late); the counted press goes to the button
--- column. Steps never reached get no frames, which is what shows a skip.
function M.columns(attempt)
  local t = attempt.trace
  local frames, n = t.frames, #t.frames
  local reach = {}
  for k, s in ipairs(t.steps) do
    reach[k] = s.at
  end
  local last = reach[1] or 0
  for k, s in ipairs(t.steps) do
    if reach[k] == nil and k > 1 then
      local limit = math.max(t.button_at or n, t.complete_at or 0)
      reach[k] = first_frame_with(frames, last + 1, limit, label_dir(s.label))
    end
    if reach[k] then
      last = reach[k]
    end
  end
  local cols, button_col = {}, {}
  for k = 1, #t.steps do
    cols[k] = {}
  end
  local first = reach[1] or 1
  local start = first
  while start > 1 and frames[start - 1].dir == frames[first].dir do
    start = start - 1
  end
  if t.steps[1] and t.steps[1].release then
    local d = label_dir(t.steps[1].label)
    while start > 1 and frames[start - 1].dir == d do
      start = start - 1
    end
  end
  local early = t.complete_at ~= nil and t.button_at ~= nil and t.button_at < t.complete_at
  local stop = (t.button_at == nil and n) or (early and t.complete_at) or t.button_at
  local function step_at_or_after(f)
    local found
    for k = 1, #t.steps do
      if reach[k] == f then
        found = k
      elseif not found and reach[k] and reach[k] > f then
        return k
      end
    end
    return found
  end
  for f = start, math.min(n, stop) do
    local k = step_at_or_after(f)
    local frame = frames[f]
    if early and k then
      table.insert(cols[k], frame)
    elseif f == t.button_at then
      local step_here = k ~= nil and reach[k] == f
      table.insert(button_col, { dir = step_here and 0 or frame.dir, press = frame.press })
      if step_here then
        table.insert(cols[k], { dir = frame.dir, press = "" })
      end
    elseif k then
      table.insert(cols[k], frame)
    else
      table.insert(button_col, frame)
    end
  end
  local function leftover(list, dir)
    local i = 1
    while list[i] and list[i].dir == dir and list[i].press == "" do
      i = i + 1
    end
    local out = {}
    for j = i, #list do
      table.insert(out, list[j])
    end
    return out
  end
  local last_at
  for k = 1, #t.steps do
    if k > 1 and reach[k - 1] and reach[k - 1] ~= reach[k] then
      cols[k] = leftover(cols[k], frames[reach[k - 1]].dir)
    end
    if reach[k] then
      last_at = reach[k]
    end
  end
  if last_at then
    button_col = leftover(button_col, frames[last_at].dir)
  end
  return reach, cols, button_col
end

--- Consecutive equal frames as runs { dir, press, n }; a press made while holding a direction
--- joins that run.
function M.runs(frames)
  local runs = {}
  for _, f in ipairs(frames) do
    local last = runs[#runs]
    if last and last.dir == f.dir and last.press == "" then
      last.n = last.n + 1
      if f.press ~= "" then
        last.press = f.press
      end
    else
      table.insert(runs, { dir = f.dir, press = f.press, n = 1 })
    end
  end
  return runs
end

local function buttons_of(press)
  local out = {}
  for b in (press or ""):gmatch("[LMH][PK]") do
    table.insert(out, b)
  end
  return out
end

local function count_w(r)
  return (r.counted and r.dir ~= 0 and r.n > 1) and draw.CHAR_W * #tostring(r.n) + 1 or 0
end

local function run_w(r)
  return math.max((r.dir ~= 0 and 10 or 0) + count_w(r) + #buttons_of(r.press) * 10, 9)
end

local function runs_w(runs)
  local w = 0
  for _, r in ipairs(runs) do
    w = w + run_w(r)
  end
  return w + 3 * math.max(#runs - 1, 0)
end

local function draw_runs(canvas, cx, y, runs, culprit)
  local x = cx - math.floor(runs_w(runs) / 2)
  for _, r in ipairs(runs) do
    local ix = x
    if culprit and culprit(r) then
      draw.rbox(canvas, x - 2, y - 2, x + run_w(r) + 1, y + 10, draw.alpha(COL.bad, 0x60), COL.bad)
    end
    if r.dir == 5 then
      draw.neutral(canvas, ix + 1, y + 1, 7)
    elseif r.dir ~= 0 then
      draw.icon(canvas, r.dir, ix, y, 9)
    end
    if r.dir ~= 0 then
      ix = ix + 10
    end
    if count_w(r) > 0 then
      canvas:text(ix, y + 2, tostring(r.n), COL.dim)
      ix = ix + count_w(r)
    end
    for _, b in ipairs(buttons_of(r.press)) do
      draw.icon(canvas, b, ix, y, 9)
      ix = ix + 10
    end
    x = x + run_w(r) + 3
  end
end

--- Draws the card for `attempt` with its box's top-left at (opts.x0, opts.y0). opts.target marks
--- a targeted move; opts.max_x1 caps the right edge. Returns the box { x0, x1, y0, y1 }.
function M.draw(canvas, attempt, opts)
  local t = attempt.trace
  local x0, y0, height = opts.x0, opts.y0, M.HEIGHT
  local ok = attempt.ok
  local r = M.reason(attempt)
  local kind = M.kind(attempt)
  local perfect, starred = kind == "perfect", kind == "perfect" or kind == "clean"
  local verdict = perfect and COL.gold or (ok and COL.good or COL.bad)
  local reach, cols, button_col = M.columns(attempt)
  local has_button = attempt.button ~= nil
  local last_col = has_button and #t.steps + 1 or #t.steps

  local function col_runs(k)
    local runs = M.runs(k > #t.steps and button_col or cols[k])
    if k == 1 then
      for _, run in ipairs(runs) do
        run.counted = true
      end
    end
    return runs
  end

  local function col_w(k)
    local is_button = k > #t.steps
    local win = is_button and t.button_window or t.steps[k].window
    local slot = 15 + (is_button and #(t.optional or {}) * 16 or 0)
    local meter = win and draw.CHAR_W * 5 or 0
    local cancelled = not ok and attempt.error.code == "cancelled" and r.step == k
    local label = (k == 1 or is_button) and draw.CHAR_W * 5 or (cancelled and draw.CHAR_W * 9 or 0)
    return math.max(slot, runs_w(col_runs(k)), meter, label)
  end

  local grid_w = 0
  for k = 1, last_col do
    grid_w = grid_w + col_w(k) + (k > 1 and M.GAP or 0)
  end
  local x1 = math.min(opts.max_x1 or 376, x0 + M.PAD + grid_w + M.PAD)

  local name = attempt.move:upper()
  local ty = y0 - M.NAME_H + 2
  local name_x = x0 + 1
  if opts.target then
    canvas:text(x0 + 1, ty, "TARGET", COL.dim)
    name_x = x0 + 1 + draw.CHAR_W * 7
  end
  canvas:text(name_x, ty, name, COL.text)
  local tail = starred and { perfect and "FRAME-PERFECT" or "CLEAN" } or r.parts
  local tail_colour = starred and COL.gold or (ok and COL.dim or COL.bad)
  local tx = draw.inline(canvas, name_x + draw.CHAR_W * #name + 6, ty, tail, tail_colour)
  if starred and not perfect then
    draw.inline(canvas, tx + 6, ty, r.parts, COL.dim)
  end

  draw.rbox(canvas, x0, y0, x1, y0 + height, COL.panel, verdict)
  draw.rbox(canvas, x0 + 1, y0 + 1, x1 - 1, y0 + height - 1, draw.alpha(verdict, 0x28))

  local ny, ry, my = y0 + 11, y0 + 23, y0 + 37
  local cx = x0 + 5
  for k = 1, last_col do
    local w = col_w(k)
    local mid = cx + math.floor(w / 2)
    if cx + w > x1 - 2 then
      break
    end
    if k > 1 then
      canvas:line(cx - M.GAP / 2, y0 + M.PAD, cx - M.GAP / 2, y0 + height - M.PAD, COL.divider)
    end
    if k > #t.steps then
      local c = ok and COL.good or (r.button and COL.bad or COL.neutral_slot)
      local optional = t.optional or {}
      local bx = mid + #optional * 8
      for i, d in ipairs(optional) do
        local ox = mid - #optional * 8 + (i - 1) * 16 - 1
        draw.rbox(canvas, ox - 6, ny - 6, ox + 6, ny + 6, draw.alpha(COL.dim, 0x30))
        draw.dashed(canvas, ox - 7, ny - 7, ox + 7, ny + 7, COL.dim)
        draw.icon(canvas, d, ox - 4, ny - 4, 9)
      end
      draw.rbox(canvas, bx - 7, ny - 7, bx + 7, ny + 7, draw.alpha(c, 0x40), c)
      local btn = button_icon(attempt)
      if btn then
        draw.icon(canvas, btn, bx - 5, ny - 5, 11)
      end
      local runs = {}
      for _, run in ipairs(M.runs(button_col)) do
        if run.press ~= "" or run.dir ~= 0 then
          table.insert(runs, run)
        end
      end
      draw_runs(canvas, mid, ry, runs)
      if t.complete_at == nil then
        draw.meter(canvas, mid, my, nil, t.button_window, cx, w)
      elseif t.button_at - t.complete_at >= 0 then
        draw.meter(canvas, mid, my, t.button_at - t.complete_at, t.button_window, cx, w)
      else
        canvas:text(mid - 10, my, "EARLY", COL.bad)
      end
    else
      local s = t.steps[k]
      local d = label_dir(s.label)
      local accepted, missed = s.at ~= nil, (not ok and r.step == k)
      local c = missed and COL.bad or (accepted and COL.good or COL.dim)
      draw.rbox(canvas, mid - 7, ny - 7, mid + 7, ny + 7, draw.alpha(c, 0x40), c)
      if d == 5 then
        draw.neutral(canvas, mid - 4, ny - 4, 9)
      elseif d then
        draw.icon(canvas, d, mid - 6, ny - 6, 13)
      else
        canvas:text(mid - 2 * #s.label, ny - 3, s.label, COL.text)
      end
      if s.release then
        draw.neutral(canvas, mid + 3, ny + 2, 7)
      end
      if not accepted and missed and reach[k] == nil then
        canvas:line(mid - 7, ny + 7, mid + 7, ny - 7, COL.bad)
        canvas:line(mid - 6, ny + 7, mid + 7, ny - 6, COL.bad)
      end
      local function culprit(run)
        return (missed and attempt.error.code == "cancelled" and run.dir == 8)
          or (attempt.error ~= nil and attempt.error.code == "early_button" and run.press ~= "")
      end
      local runs = col_runs(k)
      if #runs > 0 then
        draw_runs(canvas, mid, ry, runs, culprit)
      elseif reach[k] == nil then
        canvas:text(mid - 6, ry + 1, "---", COL.bad)
      end
      local prev = reach[k - 1]
      if k > 1 and missed and attempt.error.code == "cancelled" then
        draw.meter(canvas, mid, my, nil, s.window, cx, w, "CANCELLED")
      elseif k > 1 and s.window and prev and reach[k] then
        draw.meter(canvas, mid, my, reach[k] - prev, s.window, cx, w)
      elseif k > 1 and s.window then
        draw.meter(canvas, mid, my, nil, s.window, cx, w)
      end
    end
    cx = cx + w + M.GAP
  end
  if starred then
    draw.star(canvas, x1 - 5, y0 - 3)
  end
  return { x0 = x0, x1 = x1, y0 = y0, y1 = y0 + height }
end

return M
