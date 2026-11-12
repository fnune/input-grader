local Bench = require("input_grader.core.bench")
local T = require("helpers")

local function attempt(ok, side, code, margin)
  return { id = "ryu:29", move = "Hadoken", notation = "236+P", ok = ok, side = side,
    error = code and { code = code } or nil, total = 4, margin = margin }
end

return {
  { "records only while running", function()
    local b = Bench.new(function() return 0 end)
    T.eq(b:record(attempt(true, "right")), false)
    b:start()
    T.eq(b:record(attempt(true, "right")), true)
  end },
  { "summarises rate, sides and the most common error", function()
    local t = 0
    local b = Bench.new(function() return t end)
    b:start()
    b:record(attempt(true, "right", nil, 5))
    b:record(attempt(false, "right", "skipped_step"))
    b:record(attempt(false, "left", "skipped_step"))
    b:record(attempt(true, "left", nil, 3))
    b:record(attempt(false, "left", "late_button"))
    t = 42
    local s = b:stop()
    local m = s.moves[1]
    T.eq(m.n, 5)
    T.eq(m.ok, 2)
    T.eq(m.rate, 40)
    T.eq(m.sides.right.rate, 50)
    T.eq(m.sides.left.rate, 33)
    T.eq(m.top_error.code, "skipped_step")
    T.eq(m.top_error.count, 2)
    T.eq(m.median_margin, 3)
    T.eq(s.seconds, 42)
  end },
  { "a target ignores other moves", function()
    local b = Bench.new(function() return 0 end)
    b:start("ryu:28")
    T.eq(b:record(attempt(true, "right")), false)
  end },
}
