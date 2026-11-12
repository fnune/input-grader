-- MAME adapter (headless validation, screenshots). Same interface as platform/fbneo.lua.
-- MAME draws in screen coordinates of the emulated screen; colors are ARGB.

local M = {}

local COLORS = {
  text = 0xFFFFFFFF, dim = 0xFFB0B0B0, good = 0xFF50E070, bad = 0xFFFF6060,
  warn = 0xFFFFD050, panel = 0xB0000000, edge = 0xFF606060,
}

function M.new(manager, emu)
  local machine = manager.machine
  local space = machine.devices[":maincpu"].spaces["program"]
  local screen = machine.screens[":screen"]
  local p = { name = "mame", romname = emu.romname() }
  p.mem = {
    u8 = function(a) return space:read_u8(a) end,
    u16 = function(a) return space:read_u16(a) end,
    s16 = function(a) return space:read_i16(a) end,
    u32 = function(a) return space:read_u32(a) end,
  }
  p.canvas = {
    text = function(_, x, y, s, color) screen:draw_text(x, y, s, COLORS[color] or COLORS.text, 0) end,
    box = function(_, x1, y1, x2, y2, fill, edge) screen:draw_box(x1, y1, x2, y2, COLORS[edge] or 0, COLORS[fill] or 0) end,
  }
  local frame_fns, draw_fns = {}, {}
  -- MAME cancels a notifier when its subscription object is garbage-collected, so the
  -- subscriptions live in the module table, which package.loaded keeps alive.
  M.subscriptions = M.subscriptions or {}
  p.subscriptions = {
    emu.add_machine_frame_notifier(function() for _, fn in ipairs(frame_fns) do fn() end end),
    emu.register_frame_done(function() for _, fn in ipairs(draw_fns) do fn() end end),
  }
  table.insert(M.subscriptions, p.subscriptions)
  function p.on_frame(fn) table.insert(frame_fns, fn) end
  function p.on_draw(fn) table.insert(draw_fns, fn) end
  function p.hotkey() end
  function p.clock() return machine.time.seconds end
  function p.timestamp() return os.date("!%Y-%m-%dT%H:%M:%SZ") end
  function p.print(s) print(s) end
  function p.appender() return function() end end
  return p
end

return M
