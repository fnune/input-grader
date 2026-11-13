-- Attaches an app to a platform. Before each frame: read the keyboard and the player's real
-- controls, handle them, and keep them from the game while the picker is open. After each frame:
-- grade. On redraw: draw. Lua hotkeys 7-9 are offered too, for players who map them in the
-- emulator (FBNeo maps none by default).

local M = {}

M.HOTKEYS = { bench = 7, target = 8, visible = 9 }

-- An error in a callback makes FBNeo unload the script (and MAME drop the callback), so each
-- one is contained: the first error of each kind is printed, and the next frame tries again.
local function guarded(platform, name, fn)
  local reported = false
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported then
      reported = true
      platform.print("input_grader: " .. name .. " failed: " .. tostring(err))
    end
  end
end

function M.attach(platform, app)
  if platform.on_before then
    platform.on_before(guarded(platform, "controls", function()
      app:controls(platform.keys(), platform.pad())
      if app:blocks_input() then
        platform.block()
      end
    end))
  end
  platform.on_frame(guarded(platform, "frame", function()
    app:frame()
  end))
  platform.on_draw(guarded(platform, "draw", function()
    app:draw(platform.canvas)
  end))
  if platform.hotkey then
    platform.hotkey(
      M.HOTKEYS.bench,
      guarded(platform, "bench", function()
        app:toggle_bench()
      end)
    )
    platform.hotkey(
      M.HOTKEYS.target,
      guarded(platform, "target", function()
        app:toggle_picker()
      end)
    )
    platform.hotkey(
      M.HOTKEYS.visible,
      guarded(platform, "hide", function()
        app:toggle_visible()
      end)
    )
  end
end

return M
