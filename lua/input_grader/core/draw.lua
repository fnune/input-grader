local M = {}

M.COL = {
  panel = 0x101018C8,
  edge = 0x5A5A6AFF,
  dim = 0x8A8A9AFF,
  text = 0xFFFFFFFF,
  black = 0x000000FF,
  gold = 0xFFD23CFF,
  good = 0x4CD964FF,
  bad = 0xFF5A5AFF,
  warn = 0xFFA030FF,
  neutral_slot = 0x8A8A9AFF,
  cell = 0x2A2A36FF,
  divider = 0xFFFFFF18,
  tick = 0xFFFFFF60,
  overrun = 0xA03A3AFF,
}
local COL = M.COL

M.CHAR_W = 4
M.RADIUS = 3

--- The colour with another alpha.
function M.alpha(c, a)
  return c - c % 256 + a
end

local DIR_KEYS = { [1] = "dl", [2] = "d", [3] = "dr", [4] = "l", [6] = "r", [7] = "ul", [8] = "u", [9] = "ur" }
function M.dir_key(d)
  return DIR_KEYS[d]
end

local function dir_vec(d)
  return ((d - 1) % 3) - 1, -(math.floor((d - 1) / 3) - 1)
end

local function arrow(canvas, cx, cy, d, r, c)
  local vx, vy = dir_vec(d)
  local tx, ty = cx + vx * r, cy + vy * r
  canvas:line(cx - vx * r, cy - vy * r, tx, ty, c)
  if vx == 0 or vy == 0 then
    canvas:line(cx - vx * r + vy, cy - vy * r + vx, tx + vy, ty + vx, c)
  end
  local h = math.max(2, r - 1)
  for _, b in ipairs({ { -vx - vy, -vy + vx }, { -vx + vy, -vy - vx } }) do
    local n = math.max(math.abs(b[1]), math.abs(b[2]))
    canvas:line(tx, ty, tx + math.floor(b[1] / n * h + 0.5), ty + math.floor(b[2] / n * h + 0.5), c)
  end
end

--- A direction (numpad digit) or button ("LP") icon with its top-left at (x, y), `size` px.
function M.icon(canvas, what, x, y, size)
  if type(what) == "number" then
    if what == 5 then
      M.neutral(canvas, x + math.floor((size - 9) / 2), y + math.floor((size - 9) / 2), size >= 11 and 9 or 7)
      return
    end
    if not canvas:icon(M.dir_key(what), x, y, size) then
      local c = math.floor(size / 2)
      arrow(canvas, x + c, y + c, what, math.max(2, c - 1), COL.text)
    end
  elseif not canvas:icon(what, x, y, size) then
    canvas:text(x + math.floor(size / 2) - 2, y + math.floor(size / 2) - 3, what:sub(2, 2), COL.text)
  end
end

--- A box with the game HUD's bevelled corners: the border steps in one pixel per row for 3 rows,
--- or fewer when the box is too small.
function M.rbox(canvas, x1, y1, x2, y2, fill, outline)
  outline = outline or fill
  local r = math.max(0, math.min(M.RADIUS, math.floor((x2 - x1) / 2), math.floor((y2 - y1) / 2)))
  if fill % 256 > 0 then
    for y = y1 + 1, y2 - 1 do
      local inset = math.max(0, r - math.min(y - y1, y2 - y))
      if x1 + inset + 1 <= x2 - inset - 1 then
        canvas:line(x1 + inset + 1, y, x2 - inset - 1, y, fill)
      end
    end
  end
  canvas:line(x1 + r, y1, x2 - r, y1, outline)
  canvas:line(x1 + r, y2, x2 - r, y2, outline)
  canvas:line(x1, y1 + r, x1, y2 - r, outline)
  canvas:line(x2, y1 + r, x2, y2 - r, outline)
  if r > 0 then
    canvas:line(x1, y1 + r, x1 + r, y1, outline)
    canvas:line(x2 - r, y1, x2, y1 + r, outline)
    canvas:line(x1, y2 - r, x1 + r, y2, outline)
    canvas:line(x2 - r, y2, x2, y2 - r, outline)
  end
end

--- A bevelled outline drawn every other pixel: something optional.
function M.dashed(canvas, x1, y1, x2, y2, c)
  local r = math.max(0, math.min(M.RADIUS, math.floor((x2 - x1) / 2), math.floor((y2 - y1) / 2)))
  local function segment(ax, ay, bx, by)
    local n = math.max(math.abs(bx - ax), math.abs(by - ay))
    for i = 0, n, 2 do
      canvas:pixel(ax + math.floor((bx - ax) * i / n + 0.5), ay + math.floor((by - ay) * i / n + 0.5), c)
    end
  end
  segment(x1 + r, y1, x2 - r, y1)
  segment(x2, y1 + r, x2, y2 - r)
  segment(x2 - r, y2, x1 + r, y2)
  segment(x1, y2 - r, x1, y1 + r)
  if r > 1 then
    segment(x2 - r + 1, y1 + 1, x2 - 1, y1 + r - 1)
    segment(x2 - 1, y2 - r + 1, x2 - r + 1, y2 - 1)
    segment(x1 + r - 1, y2 - 1, x1 + 1, y2 - r + 1)
    segment(x1 + 1, y1 + r - 1, x1 + r - 1, y1 + 1)
  end
end

local function sprite(canvas, x, y, rows, colours)
  for j, row in ipairs(rows) do
    for i = 1, #row do
      local c = colours[row:sub(i, i)]
      if c then
        canvas:pixel(x + i - 1, y + j - 1, c)
      end
    end
  end
end

local NEUTRAL = {
  [9] = {
    "..#####..",
    ".#WWWWW#.",
    "#WWWWWWW#",
    "#WWWWWWW#",
    "#WWWWWWW#",
    "#WWWWWWS#",
    "#WWWWWWS#",
    ".#WWSSS#.",
    "..#####..",
  },
  [7] = {
    "..###..",
    ".#WWW#.",
    "#WWWWW#",
    "#WWWWW#",
    "#WWWWS#",
    ".#WSS#.",
    "..###..",
  },
}
local NEUTRAL_COLOURS = { ["#"] = COL.black, W = 0xFFFFFFFF, S = 0xA8A8B0FF }

function M.neutral(canvas, x, y, size)
  sprite(canvas, x, y, NEUTRAL[size], NEUTRAL_COLOURS)
end

local STAR = {
  "....H....",
  "....H....",
  "...HYS...",
  "..HYYYS..",
  "HHYYYYYSS",
  "..HYYYS..",
  "...HYS...",
  "....S....",
  "....S....",
}
local STAR_COLOURS = { H = 0xFFF2A8FF, Y = COL.gold, S = 0xD9921EFF }

local function outline_of(canvas, x, y, rows, body)
  for j = 0, #rows + 1 do
    for i = 0, #rows[1] + 1 do
      local function is(a, b)
        local row = rows[b]
        return row ~= nil and body[row:sub(a, a)] ~= nil
      end
      if not is(i, j) and (is(i - 1, j) or is(i + 1, j) or is(i, j - 1) or is(i, j + 1)) then
        canvas:pixel(x + i - 1, y + j - 1, COL.black)
      end
    end
  end
end

function M.star(canvas, x, y)
  outline_of(canvas, x, y, STAR, STAR_COLOURS)
  sprite(canvas, x, y, STAR, STAR_COLOURS)
end

local PLUS = { ".#.", "###", ".#." }
local PLUS_COLOURS = { ["#"] = COL.gold }
function M.gold_plus(canvas, cx, cy)
  outline_of(canvas, cx - 1, cy - 1, PLUS, PLUS_COLOURS)
  sprite(canvas, cx - 1, cy - 1, PLUS, PLUS_COLOURS)
end

--- A pearl: `n` x `n` (5, or 7 when shown), rounded corners, a black outline around its colour.
function M.pearl(canvas, x, y, c, n)
  local e = n - 1
  canvas:line(x + 1, y, x + e - 1, y, COL.black)
  canvas:line(x + 1, y + e, x + e - 1, y + e, COL.black)
  canvas:line(x, y + 1, x, y + e - 1, COL.black)
  canvas:line(x + e, y + 1, x + e, y + e - 1, COL.black)
  canvas:box(x + 1, y + 1, x + e - 1, y + e - 1, c, c)
end

--- A soft oval shadow, 5 px wide, under a lifted pearl.
function M.lift_shadow(canvas, x, y)
  canvas:pixel(x, y, 0x00000068)
  canvas:line(x + 1, y, x + 3, y, 0x000000B0)
  canvas:pixel(x + 4, y, 0x00000068)
  canvas:line(x + 1, y + 1, x + 3, y + 1, 0x00000060)
end

--- An input used at most half its window is safe (5 of 10, 2 of 5).
function M.safe_use(used, window)
  return used <= math.floor(window / 2)
end

--- "used/allowed" over a square bar spanning the column. The bar covers the window, or window
--- plus overrun when late, with a tick at its half and a notch where the window ends. Green while
--- safe, orange past half the window, red past the end. `used` nil: the part never happened; the
--- bar still shows the window, empty, under "-/10" or `text`.
function M.meter(canvas, x, y, used, window, left, width, text)
  if used == nil then
    local label = text or ("-/" .. window)
    canvas:text(x - #label * 2, y, label, text and COL.bad or COL.dim)
    canvas:box(left, y + 9, left + width - 1, y + 11, COL.cell, COL.edge)
    local half = left + math.floor((width - 1) / 2 + 0.5)
    canvas:line(half, y + 8, half, y + 12, COL.tick)
    return
  end
  local label = used .. "/" .. window
  local c = used > window and COL.bad or (M.safe_use(used, window) and COL.good or COL.warn)
  canvas:text(x - #label * 2, y, label, c)
  local span = math.max(window, used)
  local function at(f)
    return left + math.floor(f / span * (width - 1) + 0.5)
  end
  canvas:box(left, y + 9, left + width - 1, y + 11, COL.cell, COL.edge)
  if used > 0 then
    canvas:box(left, y + 9, at(math.min(used, window)), y + 11, c, c)
  end
  canvas:line(at(window / 2), y + 8, at(window / 2), y + 12, COL.tick)
  if used > window then
    canvas:box(at(window) + 2, y + 9, at(used), y + 11, COL.overrun, COL.overrun)
    canvas:line(at(window) + 1, y + 7, at(window) + 1, y + 13, COL.text)
  end
end

--- Width of a line of parts: strings, { dir = digit } and { btn = "LP" }.
function M.parts_width(parts)
  local w = 0
  for _, p in ipairs(parts) do
    w = w + (type(p) == "string" and M.CHAR_W * #p or 10)
  end
  return w
end

--- Draws text and 9 px icons on one line; returns the x after it.
function M.inline(canvas, x, y, parts, colour)
  for _, p in ipairs(parts) do
    if type(p) == "string" then
      canvas:text(x, y, p, colour)
      x = x + M.CHAR_W * #p
    else
      M.icon(canvas, p.dir or p.btn, x, y - 1, 9)
      x = x + 10
    end
  end
  return x
end

--- "236+P" as parts: directions as icons, "+", and a fist (P) or foot (K) in the light button's
--- icon. 360 and 720 stay text.
function M.notation_parts(notation)
  local parts, i = {}, 1
  while i <= #notation do
    local spin = notation:match("^%d%d0", i)
    if spin == "360" or spin == "720" then
      table.insert(parts, spin)
      i = i + 3
    else
      local ch = notation:sub(i, i)
      local pair = notation:sub(i, i + 1)
      if ch:match("%d") then
        table.insert(parts, ch == "5" and "5" or { dir = tonumber(ch) })
        i = i + 1
      elseif pair == "PP" or pair == "KK" then
        local b = pair == "PP" and "LP" or "LK"
        table.insert(parts, { btn = b })
        table.insert(parts, { btn = b })
        i = i + 2
      elseif (ch == "P" or ch == "K") and not notation:sub(i + 1, i + 1):match("%l") then
        table.insert(parts, { btn = ch == "P" and "LP" or "LK" })
        i = i + 1
      else
        table.insert(parts, ch)
        i = i + 1
      end
    end
  end
  return parts
end

return M
