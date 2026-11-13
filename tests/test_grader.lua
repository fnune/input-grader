local Game = require("input_grader.games.sfiii3.game")
local sources = require("input_grader.games.sfiii3.sources")
local inputs = require("input_grader.games.sfiii3.inputs")
local T = require("helpers")

local RYU = 2

local function play(script, opts)
  opts = opts or {}
  local source = sources.sim(T.commands(), RYU, opts.super_art or 0)
  local game = Game.new(source, T.commands(), { target = opts.target })
  local facing_right = opts.facing_right ~= false
  local timeline = inputs.timeline(script, facing_right)
  for _ = 1, 30 do
    table.insert(timeline, 0)
  end
  local attempts = {}
  for _, raw in ipairs(timeline) do
    source:push(raw, facing_right)
    for _, a in ipairs(game:update()) do
      table.insert(attempts, a)
    end
  end
  return attempts
end

local function one(script, opts)
  local attempts = play(script, opts)
  T.eq(#attempts, 1, "attempts")
  return attempts[1]
end

return {
  {
    "a clean Hadoken is graded as out, with per-step gaps",
    function()
      local a = one({ { 5, 2 }, { 2, 2 }, { 3, 3 }, { 6, 1, "LP" } })
      T.eq(a.move, "Hadoken")
      T.eq(a.ok, true)
      T.eq(a.steps[2].used, 2)
      T.eq(a.steps[2].window, 10)
      T.eq(a.steps[3].used, 3)
      T.eq(a.button.after, 0)
      T.eq(a.button.window, 10)
      T.eq(a.total, 5)
      T.eq(a.minimum, 2)
      T.eq(a.margin, 7)
      T.eq(a.side, "right")
    end,
  },
  {
    "skipping the diagonal is named",
    function()
      local a = one({ { 5, 2 }, { 2, 2 }, { 6, 1, "LP" }, { 5, 5 } })
      T.eq(a.move, "Hadoken")
      T.eq(a.ok, false)
      T.eq(a.error.code, "skipped_step")
      T.contains(a.error.text, "without 3")
    end,
  },
  {
    "a slow diagonal says by how much",
    function()
      local a = one({ { 5, 2 }, { 2, 1 }, { 1, 12 }, { 3, 1 }, { 6, 1, "LP" } })
      T.eq(a.ok, false)
      T.eq(a.error.code, "too_slow")
      T.contains(a.error.text, "3 came 3 frames too late")
    end,
  },
  {
    "a late button says by how much",
    function()
      local a = one({ { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 14 }, { 6, 1, "LP" } })
      T.eq(a.ok, false)
      T.eq(a.error.code, "late_button")
      T.contains(a.error.text, "4 frames too late")
    end,
  },
  {
    "a button held from before the motion finished, past the window, is early",
    function()
      local a = one({ { 5, 2 }, { 2, 1 }, { 3, 1, "LP" }, { 6, 14, "LP" } })
      T.eq(a.ok, false)
      T.eq(a.error.code, "early_button")
    end,
  },
  {
    "pressing up cancels the motion",
    function()
      local a = one({ { 5, 2 }, { 2, 2 }, { 3, 1 }, { 8, 1 }, { 6, 1, "LP" } })
      T.eq(a.ok, false)
      T.eq(a.error.code, "cancelled")
    end,
  },
  {
    "the super wins and is graded, not the Hadoken inside it",
    function()
      local a = one({ { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" } })
      T.eq(a.move, "SA I Shinkuu Hadoken")
      T.eq(a.ok, true)
      T.eq(a.minimum, 4)
    end,
  },
  {
    "facing left grades the same",
    function()
      local a = one({ { 5, 2 }, { 2, 2 }, { 3, 3 }, { 6, 1, "LP" } }, { facing_right = false })
      T.eq(a.ok, true)
      T.eq(a.side, "left")
    end,
  },
  {
    "a Shoryuken records its 5-frame window after letting go of 6",
    function()
      local a = one({ { 5, 2 }, { 6, 2 }, { 5, 2 }, { 2, 1 }, { 3, 1, "HP" } })
      T.eq(a.move, "Shoryuken")
      T.eq(a.ok, true)
      T.eq(a.steps[2].window, 5)
    end,
  },
  {
    "up-forward does not cancel: the game compares the whole input word with up",
    function()
      local a = one({ { 5, 2 }, { 2, 2 }, { 3, 1 }, { 9, 1 }, { 6, 1, "LP" } })
      T.eq(a.ok, true)
    end,
  },
  {
    "a crouching normal is not an attempt",
    function()
      T.eq(#play({ { 2, 5, "LP" }, { 2, 5 } }), 0)
    end,
  },
  {
    "a plain normal is not an attempt",
    function()
      T.eq(#play({ { 5, 5, "LP" }, { 5, 5 } }), 0)
    end,
  },
  {
    "a target restricts grading to one move",
    function()
      local a = one(
        { { 5, 2 }, { 2, 1 }, { 3, 1 }, { 6, 1 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" } },
        { target = "ryu:29" }
      )
      T.eq(a.move, "Hadoken")
      T.eq(a.ok, false)
      T.eq(a.error.code, "other_move")
    end,
  },
  {
    "the super's last 6 is optional: notation minus the steps the game checks",
    function()
      local opt = Game.optional_directions(T.fighter(2).slots[20])
      T.eq(#opt, 1)
      T.eq(opt[1], 6)
      T.eq(#Game.optional_directions(T.fighter(2).slots[29]), 0)
    end,
  },
  {
    "Ken's Shoryuken with a late 2 is graded as a late Shoryuken, not an unfinished Hadoken",
    function()
      local source = sources.sim(T.commands(), 11, 0)
      local game = Game.new(source, T.commands())
      local found
      local timeline = inputs.timeline({ { 5, 6 }, { 6, 2 }, { 5, 7 }, { 2, 1 }, { 3, 1, "HP" } }, true)
      for _ = 1, 30 do
        table.insert(timeline, 0)
      end
      for _, raw in ipairs(timeline) do
        source:push(raw, true)
        for _, a in ipairs(game:update()) do
          found = found or a
        end
      end
      T.eq(found.move, "Shoryuken")
      T.eq(found.error.code, "too_slow")
    end,
  },
}
