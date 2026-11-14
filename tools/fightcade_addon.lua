local HOME = "games/sfiii3/addon/input_grader/"
package.path = HOME .. "lua/?.lua;" .. HOME .. "lua/?/init.lua;" .. package.path

local platform = require("input_grader.platform.fbneo").new()
platform.on_before = function(fn)
  table.insert(registers.registerbefore, fn)
end
platform.on_frame = function(fn)
  table.insert(registers.registerafter, fn)
end
platform.on_draw = function(fn)
  table.insert(registers.guiregister, fn)
end

local app = require("input_grader.games.sfiii3").build(platform, { log_path = HOME .. "attempts.csv" })
require("input_grader.core.run").attach(platform, app)
print("input_grader " .. require("input_grader.version") .. " loaded: M menu, H hide, Page Up/Down history")
