local inputs = require("input_grader.games.sfiii3.inputs")
local T = require("helpers")

return {
  {
    "numpad 6 is right when facing right and left when facing left",
    function()
      T.eq(inputs.lever_to_raw(inputs.numpad_to_lever(6), true), 8)
      T.eq(inputs.lever_to_raw(inputs.numpad_to_lever(6), false), 4)
    end,
  },
  {
    "raw and relative levers round-trip for every direction and facing",
    function()
      for digit = 1, 9 do
        for _, facing in ipairs({ true, false }) do
          local raw = inputs.lever_to_raw(inputs.numpad_to_lever(digit), facing)
          T.eq(inputs.lever_to_numpad(inputs.raw_to_lever(raw, facing)), digit)
        end
      end
    end,
  },
  {
    "button words and names",
    function()
      T.eq(inputs.buttons_text(inputs.buttons_word("LPHK")), "LP+HK")
    end,
  },
}
