local Game = require("input_grader.games.sfiii3.game")
local sources = require("input_grader.games.sfiii3.sources")
local inputs = require("input_grader.games.sfiii3.inputs")
local T = require("helpers")

local RYU = 2

local function attempts(script, opts)
  opts = opts or {}
  local source = sources.sim(T.commands(), RYU, 0)
  local game = Game.new(source, T.commands(), { target = opts.target })
  local timeline = inputs.timeline(script, true)
  for _ = 1, 30 do
    table.insert(timeline, 0)
  end
  local found = {}
  for _, raw in ipairs(timeline) do
    source:push(raw, true)
    for _, a in ipairs(game:update()) do
      table.insert(found, a)
    end
  end
  return found
end

local MOVEMENT = {
  { "forward dash, then jab", { { 5, 4 }, { 6, 1 }, { 5, 2 }, { 6, 1 }, { 5, 14 }, { 5, 1, "LP" } } },
  { "back dash, then fierce", { { 5, 4 }, { 4, 1 }, { 5, 2 }, { 4, 1 }, { 5, 14 }, { 5, 1, "HP" } } },
  { "walk back, crouch-block, cr.MK", { { 4, 30 }, { 1, 10 }, { 1, 1, "MK" } } },
  { "crouch, walk forward 20f, jab", { { 2, 10 }, { 6, 20 }, { 6, 1, "LP" } } },
  { "crouch, stand, jab 40f later", { { 2, 10 }, { 5, 40 }, { 5, 1, "LP" } } },
  { "walk forward, crouch, cr.HP anti-air", { { 6, 12 }, { 2, 6 }, { 2, 1, "HP" } } },
  { "walk forward, crouch, cr.LK", { { 6, 12 }, { 2, 6 }, { 2, 1, "LK" } } },
  { "crouching jabs", { { 2, 4, "LP" }, { 2, 4 }, { 2, 1, "LP" }, { 2, 4 }, { 2, 1, "LP" } } },
  { "standing jab spam", { { 5, 1, "LP" }, { 5, 3 }, { 5, 1, "LP" }, { 5, 3 }, { 5, 1, "LP" } } },
  { "forward walk into throw", { { 6, 20 }, { 6, 1, "LPLK" } } },
  { "back walk, down-back, up-forward jump", { { 4, 10 }, { 1, 6 }, { 9, 4 }, { 5, 20 }, { 5, 1, "HK" } } },
  { "crouch, then neutral, then forward jab", { { 2, 8 }, { 5, 6 }, { 6, 4 }, { 6, 1, "MP" } } },
  { "down then MP only (rushed)", { { 5, 5 }, { 2, 2, "LP" } } },
}

local cases = {}
for _, m in ipairs(MOVEMENT) do
  table.insert(cases, {
    "not an attempt: " .. m[1],
    function()
      local found = attempts(m[2])
      local names = {}
      for _, a in ipairs(found) do
        table.insert(names, a.move .. (a.ok and " out" or " missed"))
      end
      T.eq(#found, 0, table.concat(names, ", "))
    end,
  })
end

table.insert(cases, {
  "with the Hadoken as target, a rushed 2+P counts as a missed Hadoken",
  function()
    local found = attempts({ { 5, 5 }, { 2, 2, "LP" } }, { target = "ryu:29" })
    T.eq(#found, 1)
    T.eq(found[1].move, "Hadoken")
    T.eq(found[1].ok, false)
  end,
})

table.insert(cases, {
  "a crouch a moment before a punch is not a Shoryuken attempt, even as target, past the gap",
  function()
    T.eq(#attempts({ { 6, 12 }, { 2, 6 }, { 2, 1, "HP" } }, { target = "ryu:28" }), 0)
  end,
})

table.insert(cases, {
  "a targeted forward dash is graded from its motion: 6, neutral, 6",
  function()
    local found = attempts({ { 5, 4 }, { 6, 1 }, { 5, 2 }, { 6, 1 }, { 5, 20 } }, { target = "ryu:0" })
    T.eq(#found, 1)
    T.eq(found[1].move, "forward dash")
    T.eq(found[1].ok, true)
    T.eq(found[1].button, nil)
  end,
})

table.insert(cases, {
  "a targeted dash whose second 6 comes too late is a miss",
  function()
    local found = attempts({ { 5, 4 }, { 6, 1 }, { 5, 9 }, { 6, 1 }, { 5, 20 } }, { target = "ryu:0" })
    T.eq(#found, 1)
    T.eq(found[1].ok, false)
  end,
})

table.insert(cases, {
  "walking forward is not a failed dash, even with the dash as target",
  function()
    T.eq(#attempts({ { 5, 4 }, { 6, 40 }, { 5, 20 } }, { target = "ryu:0" }), 0)
  end,
})

table.insert(cases, {
  "dashes are not graded unless targeted",
  function()
    T.eq(#attempts({ { 5, 4 }, { 6, 1 }, { 5, 2 }, { 6, 1 }, { 5, 20 } }), 0)
  end,
})

return cases
