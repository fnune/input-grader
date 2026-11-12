-- Attaches an app to a platform: the per-frame update, drawing and hotkeys.

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
  platform.on_frame(guarded(platform, "frame", function() app:frame() end))
  platform.on_draw(guarded(platform, "draw", function() app:draw(platform.canvas) end))
  platform.hotkey(M.HOTKEYS.bench, guarded(platform, "bench", function() app:toggle_bench() end))
  platform.hotkey(M.HOTKEYS.target, guarded(platform, "target", function() app:cycle_target() end))
  platform.hotkey(M.HOTKEYS.visible, guarded(platform, "hide", function() app:toggle_visible() end))
end

return M
