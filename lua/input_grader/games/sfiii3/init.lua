-- Composition root of the 3rd Strike grader: wires the RAM source, the grader, the bench, the
-- log and the overlay for a platform (FBNeo, MAME).

local App = require("input_grader.core.app")
local Bench = require("input_grader.core.bench")
local csv = require("input_grader.core.csv")
local Overlay = require("input_grader.core.overlay")
local Game = require("input_grader.games.sfiii3.game")
local sources = require("input_grader.games.sfiii3.sources")

local M = {}

-- Japan 990512 is what Fightcade runs; 990608 is what harness/mame was validated on. Both have
-- the same command tables and RAM layout (docs/how-it-works.md).
M.SUPPORTED = { sfiii3nr1 = true, sfiii3n = true }

--- @param platform table see lua/input_grader/platform/fbneo.lua
--- @param options table|nil { player = 1|2, log_path = string|nil, overlay = table|nil }
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
    overlay = Overlay.new(options.overlay),
  })
end

return M
