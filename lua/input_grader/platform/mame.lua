local font = require("input_grader.core.font")

local M = {}

local function argb(rgba)
  local a = rgba % 256
  return a * 0x1000000 + math.floor(rgba / 256)
end

function M.new(manager, emu)
  local machine = manager.machine
  local space = machine.devices[":maincpu"].spaces["program"]
  local screen = machine.screens[":screen"]
  local p = { name = "mame", romname = emu.romname(), has_icons = false }
  p.mem = {
    u8 = function(a)
      return space:read_u8(a)
    end,
    u16 = function(a)
      return space:read_u16(a)
    end,
    s16 = function(a)
      return space:read_i16(a)
    end,
    u32 = function(a)
      return space:read_u32(a)
    end,
  }

  local function fill(x1, y1, x2, y2, c)
    if c % 256 == 0 then
      return
    end
    screen:draw_box(math.min(x1, x2), math.min(y1, y2), math.max(x1, x2) + 1, math.max(y1, y2) + 1, 0, argb(c))
  end

  local canvas = {}
  function canvas.pixel(_, x, y, c)
    fill(x, y, x, y, c)
  end
  function canvas.line(_, x1, y1, x2, y2, c)
    x1, y1, x2, y2 = math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2)
    if x1 == x2 or y1 == y2 then
      fill(x1, y1, x2, y2, c)
      return
    end
    local dx, dy = math.abs(x2 - x1), -math.abs(y2 - y1)
    local sx, sy = x1 < x2 and 1 or -1, y1 < y2 and 1 or -1
    local e = dx + dy
    while true do
      fill(x1, y1, x1, y1, c)
      if x1 == x2 and y1 == y2 then
        break
      end
      local e2 = 2 * e
      if e2 >= dy then
        e, x1 = e + dy, x1 + sx
      end
      if e2 <= dx then
        e, y1 = e + dx, y1 + sy
      end
    end
  end
  function canvas.box(_, x1, y1, x2, y2, f, outline)
    fill(x1 + 1, y1 + 1, x2 - 1, y2 - 1, f)
    outline = outline or f
    fill(x1, y1, x2, y1, outline)
    fill(x1, y2, x2, y2, outline)
    fill(x1, y1 + 1, x1, y2 - 1, outline)
    fill(x2, y1 + 1, x2, y2 - 1, outline)
  end
  function canvas.text(_, x, y, s, c)
    for i = 1, #s do
      local glyph = font[s:byte(i) - 31]
      if glyph then
        local function on(gx, gy)
          local row = glyph[gy + 1]
          return gx >= 0 and gx < 4 and row ~= nil and math.floor(row / 2 ^ gx) % 2 == 1
        end
        for gy = -1, 7 do
          for gx = -1, 4 do
            if on(gx, gy) then
              fill(x + gx, y + gy, x + gx, y + gy, c)
            elseif
              on(gx - 1, gy)
              or on(gx + 1, gy)
              or on(gx, gy - 1)
              or on(gx, gy + 1)
              or on(gx - 1, gy - 1)
              or on(gx + 1, gy - 1)
              or on(gx - 1, gy + 1)
              or on(gx + 1, gy + 1)
            then
              fill(x + gx, y + gy, x + gx, y + gy, 0x000000FF)
            end
          end
        end
      end
      x = x + 4
    end
  end
  function canvas.icon(_)
    return false
  end
  p.canvas = canvas

  M.subscriptions_kept_from_gc = M.subscriptions_kept_from_gc or {}
  local frame_fns, draw_fns = {}, {}
  table.insert(M.subscriptions_kept_from_gc, {
    emu.add_machine_frame_notifier(function()
      for _, fn in ipairs(frame_fns) do
        fn()
      end
    end),
    emu.register_frame_done(function()
      for _, fn in ipairs(draw_fns) do
        fn()
      end
    end),
  })
  function p.on_frame(fn)
    table.insert(frame_fns, fn)
  end
  function p.on_draw(fn)
    table.insert(draw_fns, fn)
  end
  function p.timestamp()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
  end
  function p.print(s)
    print(s)
  end
  function p.appender()
    return function() end
  end
  return p
end

return M
