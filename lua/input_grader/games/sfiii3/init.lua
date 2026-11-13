-- Composition root of the 3rd Strike grader: wires the RAM source, the grader, the bench, the
-- log and the overlay for a platform (FBNeo, MAME).

local App = require("input_grader.core.app")
local Bench = require("input_grader.core.bench")
local csv = require("input_grader.core.csv")
local Game = require("input_grader.games.sfiii3.game")
local sources = require("input_grader.games.sfiii3.sources")

local M = {}

-- Japan 990512 is what Fightcade runs; 990608 is what harness/mame was validated on. Both have
-- the same command tables and RAM layout (docs/how-it-works.md).
M.SUPPORTED = { sfiii3nr1 = true, sfiii3n = true }

-- Where Fightcade's training mode draws P1's input display at its defaults (13 rows of 10 px from
-- y 60, icons 12.86 px wide from x 12). The card always leaves this clear, so it never moves
-- when the display is toggled. Room for two icons per row (a direction and a button).
M.FIGHTCADE_INPUT_DISPLAY = { x1 = 0, y1 = 60, x2 = 40, y2 = 190 }

--- @param platform table see lua/input_grader/platform/fbneo.lua
--- @param options table|nil { player = 1|2, log_path = string|nil }
function M.build(platform, options)
  options = options or {}
  if not M.SUPPORTED[platform.romname] then
    platform.print(
      "input_grader: ROM '" .. tostring(platform.romname) .. "' is untested; grading may be wrong. Use sfiii3nr1."
    )
  end
  local commands = require("input_grader.games.sfiii3.commands")
  local source = sources.ram(platform.mem, commands, options.player or 1)
  return App.new({
    game = Game.new(source, commands),
    bench = Bench.new(platform.clock),
    clock = platform.clock,
    timestamp = platform.timestamp,
    log = options.log_path and platform.appender(options.log_path, csv.HEADER) or nil,
    avoid = { M.FIGHTCADE_INPUT_DISPLAY },
  })
end

return M
