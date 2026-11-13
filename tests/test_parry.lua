local Parry = require("input_grader.games.sfiii3.parry")
local T = require("helpers")

local HIGH, LOW = 0x3E, 0x2D

-- Plays frames 1..n: a tap at `tap` (slot 3 rises to 10 and counts down, slot 12 to 5), the
-- attack connecting at `hit`. Returns the judged contact.
local function play(opts)
  local p = Parry.new()
  local flags = {}
  local judged
  for f = 1, opts.hit + Parry.LATE_GRACE + 2 do
    for slot, v in pairs(flags) do
      flags[slot] = math.max(0, v - 1)
    end
    if opts.tap and f == opts.tap then
      local slot = opts.slot or Parry.SLOT.forward
      flags[slot] = 10
      if slot == Parry.SLOT.forward then
        flags[Parry.SLOT.jump_in] = 5
      end
    end
    local contact
    if f == opts.hit then
      local window = (opts.jump_in and flags[Parry.SLOT.jump_in]) or flags[opts.slot or Parry.SLOT.forward] or 0
      contact = {
        parried = opts.guard ~= LOW and window > 0,
        airborne = false,
        opponent_guard = opts.guard or HIGH,
        jump_in = opts.jump_in or false,
        red = opts.red or false,
      }
    end
    local out = p:update({ flag = flags, contact = contact })
    judged = judged or out
  end
  return judged
end

return {
  {
    "a tap 4 frames before the hit parries, in a 10-frame window",
    function()
      local j = play({ tap = 6, hit = 10 })
      T.eq(j.parried, true)
      T.eq(j.frame - j.tap.frame, 4)
      T.eq(j.window, 10)
    end,
  },
  {
    "a tap 12 frames before the hit is 3 frames too early",
    function()
      local j = play({ tap = 3, hit = 15 })
      T.eq(j.parried, false)
      T.eq(j.error.code, "parry_early")
      T.eq(j.error.frames, 3)
    end,
  },
  {
    "a tap after the hit is late, and says by how much",
    function()
      local j = play({ tap = 13, hit = 10 })
      T.eq(j.error.code, "parry_late")
      T.eq(j.error.frames, 3)
    end,
  },
  {
    "forward against a low attack names the direction it needed",
    function()
      local j = play({ tap = 8, hit = 10, guard = LOW })
      T.eq(j.error.code, "parry_direction")
      T.eq(j.needed[1], 2)
    end,
  },
  {
    "a jump-in uses the short window: 5 frames, so a tap 6 frames before is early",
    function()
      local j = play({ tap = 4, hit = 10, jump_in = true })
      T.eq(j.window, 5)
      T.eq(j.error.code, "parry_early")
      T.eq(j.error.frames, 2)
    end,
  },
  {
    "no tap at all is a missed parry",
    function()
      local j = play({ hit = 10 })
      T.eq(j.error.code, "no_parry")
    end,
  },
}
