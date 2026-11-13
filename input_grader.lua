package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

require("input_grader.core.hooks").install()
local platform = require("input_grader.platform.fbneo").new()
local app = require("input_grader.games.sfiii3").build(platform, { log_path = "logs/attempts.csv" })
require("input_grader.core.run").attach(platform, app)
platform.print("input_grader loaded: M menu, H hide, Page Up/Down history")
