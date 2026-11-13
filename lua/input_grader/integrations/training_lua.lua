-- Reads where 3rd_training_lua draws its input history, when both scripts share a Lua state
-- (tools/training_launcher.lua.in). Geometry from its src/input_history.lua: one 10 px row per
-- entry from y 49, a 9 px direction icon and up to six 8 px button icons, 14 px from the edge.

local M = {}

local TOP, ROW, WIDTH = 49, 10, 78

--- @param env table the shared global table (training_settings, input_history, player_objects)
--- @return function returning a list of rectangles to keep clear this frame
function M.avoid(env)
  return function()
    local settings, history = env.training_settings, env.input_history
    if not settings or not history then
      return {}
    end
    local function column(player, right)
      local rows = history[player] and #history[player] or 0
      if rows == 0 then
        return nil
      end
      local x1 = right and (env.screen_width or 384) - WIDTH - 4 or 0
      return { x1 = x1, y1 = TOP, x2 = x1 + WIDTH + 4, y2 = TOP + rows * ROW }
    end
    local rects = {}
    if settings.display_p1_input_history then
      local right = false
      if settings.display_p1_input_history_dynamic then
        local p1 = env.player_objects and env.player_objects[1]
        right = p1 ~= nil and p1.pos_x ~= nil and p1.pos_x < 320
      end
      rects[#rects + 1] = column(1, right)
    end
    if settings.display_p2_input_history and not settings.display_p1_input_history_dynamic then
      rects[#rects + 1] = column(2, true)
    end
    return rects
  end
end

return M
