local layout = require("input_grader.core.layout")
local training = require("input_grader.integrations.training_lua")
local T = require("helpers")

local function history(n)
  local h = {}
  for i = 1, n do
    h[i] = {}
  end
  return h
end

return {
  {
    "nothing to avoid: full width, not compact",
    function()
      local p = layout.panel(150, 200, {})
      T.eq(p.x1, 8)
      T.eq(p.x2, 376)
      T.eq(p.compact, false)
    end,
  },
  {
    "a left column that reaches the panel pushes it right and makes it compact",
    function()
      local p = layout.panel(150, 200, { { x1 = 0, y1 = 49, x2 = 82, y2 = 199 } })
      T.eq(p.x1, 86)
      T.eq(p.compact, true)
    end,
  },
  {
    "a short column above the panel is ignored",
    function()
      local p = layout.panel(150, 200, { { x1 = 0, y1 = 49, x2 = 82, y2 = 99 } })
      T.eq(p.x1, 8)
    end,
  },
  {
    "the training script's P1 history is found from its own settings",
    function()
      local env = { training_settings = { display_p1_input_history = true }, input_history = { history(15), {} } }
      local rects = training.avoid(env)()
      T.eq(#rects, 1)
      T.eq(rects[1].x1, 0)
      T.eq(rects[1].y2, 49 + 150)
    end,
  },
  {
    "dynamic history follows P1 to the right edge",
    function()
      local env = {
        training_settings = { display_p1_input_history = true, display_p1_input_history_dynamic = true },
        input_history = { history(3), {} },
        player_objects = { { pos_x = 200 } },
      }
      local r = training.avoid(env)()[1]
      T.truthy(r.x1 > 192, "on the right")
    end,
  },
  {
    "no training script: nothing to avoid",
    function()
      T.eq(#training.avoid({})(), 0)
    end,
  },
}
