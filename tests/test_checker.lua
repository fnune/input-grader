local Checker = require("input_grader.games.sfiii3.checker")
local inputs = require("input_grader.games.sfiii3.inputs")
local T = require("helpers")

local RYU = 2
local HADOKEN, SHORYUKEN, TATSU, SA1 = 29, 28, 30, 20

local function starts(script, opts)
  opts = opts or {}
  local checker = Checker.new(T.fighter(RYU))
  local facing_right = opts.facing_right ~= false
  for frame, raw in ipairs(inputs.timeline(script, facing_right)) do
    checker:frame(raw, { facing_right = facing_right, airborne = false })
    local started = checker:start({ airborne = false, super_art = { ground = opts.sa or SA1 } })
    if started then
      return started.slot, frame, started.strength
    end
  end
  return nil
end

return {
  {
    "Hadoken: 236+LP starts the Hadoken",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" } }), HADOKEN)
    end,
  },
  {
    "Hadoken: works facing left too",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" } }, { facing_right = false }), HADOKEN)
    end,
  },
  {
    "Hadoken: skipping the diagonal fails",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 3 }, { 6, 1, "LP" } }), nil)
    end,
  },
  {
    "Hadoken: holding down is fine",
    function()
      T.eq(starts({ { 2, 30 }, { 3, 1 }, { 6, 1, "LP" } }), HADOKEN)
    end,
  },
  {
    "Hadoken: 3 may come 10 frames after 2, not 11",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 1, 9 }, { 3, 1 }, { 6, 1, "LP" } }), HADOKEN)
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 1, 10 }, { 3, 1 }, { 6, 1, "LP" } }), nil)
    end,
  },
  {
    "Hadoken: the button may come up to 10 frames after the motion completes",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 10 }, { 6, 1, "LP" } }), HADOKEN)
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 11 }, { 6, 1, "LP" } }), nil)
    end,
  },
  {
    "Hadoken: a button pressed on 3 and held is too early",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 3, 1, "LP" }, { 6, 3, "LP" } }), nil)
    end,
  },
  {
    "Hadoken: a button pressed on 3 and let go on 6 works (negative edge)",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 3, 1, "LP" }, { 6, 1 } }), HADOKEN)
    end,
  },
  {
    "Hadoken: releasing the button counts (negative edge)",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1, "LP" }, { 3, 1, "LP" }, { 6, 1 } }), HADOKEN)
    end,
  },
  {
    "Hadoken: two punches give the EX version",
    function()
      local slot, _, strength = starts({ { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LPMP" } })
      T.eq(slot, HADOKEN)
      T.eq(strength, 3)
    end,
  },
  {
    "Tatsumaki: 214+K",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 1, 1 }, { 4, 1, "LK" } }), TATSU)
    end,
  },
  {
    "Shoryuken: 623+P",
    function()
      T.eq(starts({ { 5, 2 }, { 6, 1 }, { 2, 1 }, { 3, 1, "HP" } }), SHORYUKEN)
    end,
  },
  {
    "Shoryuken: 2 must come within 5 frames of letting go of 6",
    function()
      T.eq(starts({ { 5, 2 }, { 6, 1 }, { 5, 5 }, { 2, 1 }, { 3, 1, "HP" } }), SHORYUKEN)
      T.eq(starts({ { 5, 2 }, { 6, 1 }, { 5, 6 }, { 2, 1 }, { 3, 1, "HP" } }), nil)
    end,
  },
  {
    "Shoryuken: 6 may be held as long as you like",
    function()
      T.eq(starts({ { 5, 2 }, { 6, 120 }, { 2, 1 }, { 3, 1, "HP" } }), SHORYUKEN)
    end,
  },
  {
    "Super art I: 23623+P is enough, the last 6 is not checked",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1 }, { 2, 1 }, { 3, 1, "LP" } }), SA1)
    end,
  },
  {
    "Super art: the selected art wins over the Hadoken",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" } }), SA1)
    end,
  },
  {
    "Jumping cancels the Hadoken motion (dead input)",
    function()
      T.eq(starts({ { 5, 2 }, { 2, 1 }, { 3, 1 }, { 8, 1 }, { 6, 1, "LP" } }), nil)
    end,
  },
  {
    "Holding 2 re-arms the window every 11 frames, so a detour after a long hold can fail",
    function()
      local function hadoken_after_hold(n)
        return starts({ { 5, 3 }, { 2, n }, { 1, 6 }, { 3, 1 }, { 6, 1, "LP" } }) == HADOKEN
      end
      T.eq(hadoken_after_hold(4), true)
      T.eq(hadoken_after_hold(5), false)
      T.eq(hadoken_after_hold(12), true)
      T.eq(hadoken_after_hold(16), false)
    end,
  },
}
