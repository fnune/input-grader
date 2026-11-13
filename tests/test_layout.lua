local layout = require("input_grader.core.layout")
local T = require("helpers")

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
}
