-- effie3rd's fbneo-training-mode.lua, from https://github.com/effie3rd/3rd_training_lua under the
-- GPL-3.0, changed to run Fightcade's 3rd Strike add-ons before its training mode starts, as
-- proposed in https://github.com/effie3rd/3rd_training_lua/issues/20.
if emu.romname() == "sfiii3nr1" then
  local list = io.open("games/sfiii3/addon/addons.lua", "r")
  if list then
    list:close()
    dofile("games/sfiii3/addon/addons.lua")
    for _, name in ipairs(addons_run or {}) do
      dofile("games/sfiii3/addon/" .. name)
    end
  end
  require("src.data.game_data").is_fightcade = true
  require("3rd_training")
else
  local chunk = assert(loadfile("fbneo-training-mode-original.lua"))
  setfenv(chunk, getfenv(1))
  chunk()
end
