local Followup = require("input_grader.games.sfiii3.followup")
local T = require("helpers")

-- A forward dash as measured: routine 0.5 for 16 frames, animation type 2 from its 13th frame,
-- then standing. `press` = { frame, buttons, routine after it }.
local function play(press)
  local f = Followup.new()
  local done
  local after
  for frame = 1, 60 do
    local routine, cg = { 0, 1 }, 0
    if frame >= 3 and frame < 19 then
      routine = { 0, 5 }
      cg = frame >= 15 and 2 or 0
    end
    local pressed = {}
    if press and frame == press.frame then
      pressed = press.buttons
      after = press.routine
    end
    if after and press.routine_from and frame >= press.routine_from then
      routine = after
    end
    done = done or f:update({ routine = routine, cg_type = cg, pressed = pressed })
  end
  return done
end

return {
  {
    "the first frame to act is the first whose animation frame allows it",
    function()
      local d = play({ frame = 15, buttons = { "LP", "LK" }, routine = { 2, 2 }, routine_from = 16 })
      T.eq(d.action, "forward_dash")
      T.eq(d.actionable, 15)
      T.eq(d.press.frame - d.actionable, 0)
      T.eq(d.result, "threw")
    end,
  },
  {
    "a press before that is early, by how many frames",
    function()
      local d = play({ frame = 14, buttons = { "LP", "LK" } })
      T.eq(d.press.frame - d.actionable, -1)
      T.eq(d.result, "nothing")
    end,
  },
  {
    "a whiffed throw that becomes a throw counts as a throw",
    function()
      local d = play({ frame = 18, buttons = { "LP", "LK" }, routine = { 4, 14 }, routine_from = 19 })
      T.eq(d.result, "throw_whiffed")
      d = play({ frame = 18, buttons = { "LP", "LK" }, routine = { 2, 2 }, routine_from = 19 })
      T.eq(d.result, "threw")
    end,
  },
  {
    "a dash with no press after it ends without a press",
    function()
      local d = play(nil)
      T.eq(d.press, nil)
      T.eq(d.result, "no_press")
    end,
  },
}
