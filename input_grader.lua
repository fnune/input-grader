-- Load this script in Fightcade/FBNeo: Game > Lua Scripting > New Lua Script Window > Browse.
-- FBNeo runs scripts with the working directory set to the script's folder.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

require("input_grader.core.hooks").install()
local platform = require("input_grader.platform.fbneo").new()
local app = require("input_grader.games.sfiii3").build(platform, { log_path = "logs/attempts.csv" })
require("input_grader.core.run").attach(platform, app)
platform.print("input_grader loaded: Alt+7 bench, Alt+8 target move, Alt+9 hide")
