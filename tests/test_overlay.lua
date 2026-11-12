local Overlay = require("input_grader.core.overlay")
local csv = require("input_grader.core.csv")
local T = require("helpers")

local ATTEMPT = {
  move = "Hadoken", notation = "236+P", ok = false, total = 5, minimum = 2, margin = 7,
  error = { code = "skipped_step", text = "went from 2 to 6 without 3" },
  steps = { { label = "2" }, { label = "3", used = 2, window = 10 }, { label = "6", used = 3, window = 10 } },
  button = { label = "LP", after = 0, window = 10 },
}

local function canvas()
  local c = { texts = {}, boxes = 0 }
  function c:text(_, _, s, color) table.insert(self.texts, { s, color }) end
  function c:box() self.boxes = self.boxes + 1 end
  return c
end

return {
  { "steps line shows frames used over frames allowed", function()
    T.eq(Overlay.steps_line(ATTEMPT), "2  3 2/10  6 3/10  LP 0/10")
  end },
  { "a missed attempt names the error in red and explains it", function()
    local c = canvas()
    Overlay.new():draw(c, { attempt = ATTEMPT, attempt_age = 0 })
    T.contains(c.texts[1][1], "MISSED: skipped a direction")
    T.eq(c.texts[1][2], "bad")
    T.eq(c.texts[3][1], "went from 2 to 6 without 3")
    T.eq(c.boxes, 1)
  end },
  { "the card disappears after a few seconds", function()
    local c = canvas()
    Overlay.new():draw(c, { attempt = ATTEMPT, attempt_age = 30 })
    T.eq(#c.texts, 0)
  end },
  { "csv rows quote fields with commas", function()
    local row = csv.row("t", { game = "sfiii3", character = "ryu", move = "a,b", notation = "236+P", ok = true, steps = {} })
    T.contains(row, '"a,b"')
    T.contains(row, ",out,")
  end },
}
