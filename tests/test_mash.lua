local Game = require("input_grader.games.sfiii3.game")
local sources = require("input_grader.games.sfiii3.sources")
local inputs = require("input_grader.games.sfiii3.inputs")
local card = require("input_grader.core.card")
local T = require("helpers")

local CHUN = 16

local function play(presses, opts)
  opts = opts or {}
  local source = sources.sim(T.commands(), CHUN, 0)
  local game = Game.new(source, T.commands(), { target = opts.target })
  local script = { { 5, 10 } }
  for _, b in ipairs(presses) do
    table.insert(script, { 5, 2, b })
    table.insert(script, { 5, opts.gap or 2 })
  end
  table.insert(script, { 5, 60 })
  local attempts = {}
  for _, raw in ipairs(inputs.timeline(script, true)) do
    source:push(raw, true)
    for _, a in ipairs(game:update()) do
      table.insert(attempts, a)
    end
  end
  return attempts
end

return {
  {
    "five LK presses are one Hyakuretsukyaku, not a miss for each press",
    function()
      local attempts = play({ "LK", "LK", "LK", "LK", "LK" })
      T.eq(#attempts, 1)
      T.eq(attempts[1].move, "Hyakuretsu Kyaku")
      T.eq(attempts[1].ok, true)
      T.eq(attempts[1].mash.count, 5)
    end,
  },
  {
    "five kicks of mixed strengths do not add up, and the card says so",
    function()
      local attempts = play({ "LK", "LK", "LK", "MK", "MK" })
      T.eq(#attempts, 1)
      T.eq(attempts[1].ok, false)
      T.eq(attempts[1].error.code, "mash_mixed")
      local texts = {}
      local c = {
        text = function(_, _, _, t)
          texts[t] = true
        end,
        icon = function()
          return true
        end,
        box = function() end,
        line = function() end,
        pixel = function() end,
      }
      card.draw(c, attempts[1], { x0 = 44, y0 = 145 })
      T.truthy(texts["MIXED STRENGTHS"], "reason on the card")
    end,
  },
  {
    "with the target set, three presses are a short attempt",
    function()
      local attempts = play({ "LK", "LK", "LK" }, { target = "chun:29" })
      T.eq(#attempts, 1)
      T.eq(attempts[1].error.code, "mash_short")
      T.eq(attempts[1].mash.count, 3)
    end,
  },
  {
    "without a target, two kicks are just kicks",
    function()
      T.eq(#play({ "LK", "LK" }), 0)
    end,
  },
}
