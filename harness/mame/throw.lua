package.path = "harness/mame/?.lua;lua/?.lua;lua/?/init.lua;" .. package.path

local S = require("session")
local inputs = require("input_grader.games.sfiii3.inputs")

local P1 = S.ADDR.p1_base
local ROUTINE, CG_TYPE = 0x24, 533
local out_path = os.getenv("THROW_OUT") or "build/throw.txt"
local LP, LK = 0x10, 0x100

local function state()
  return string.format(
    "rno %d.%d.%d cg_type %d",
    S.s16(P1 + ROUTINE + 2),
    S.s16(P1 + ROUTINE + 4),
    S.s16(P1 + ROUTINE + 6),
    S.u8(P1 + CG_TYPE)
  )
end

-- Holds `script` (one raw word per frame) and logs P1's state after each frame.
local function play(words, extra)
  local log = {}
  for f = 1, #words + (extra or 30) do
    S.hold_raw(words[f] or 0)
    coroutine.yield()
    log[f] = state()
  end
  S.hold({})
  return log
end

local function dump(report, title, log, from, to)
  table.insert(report, title)
  for f = from or 1, math.min(to or #log, #log) do
    table.insert(report, string.format("%3d  %s", f, log[f]))
  end
end

S.spawn(function()
  S.boot_to_match(0)
  local report = {}
  S.hold_raw(8)
  S.wait(70)
  S.hold({})
  S.wait(30)
  S.save("close")

  -- Throw buttons k frames apart, at throw range.
  for k = 0, 3 do
    S.load("close")
    local words = {}
    for f = 1, 10 do
      words[f] = 0
    end
    words[5] = LP
    words[5 + k] = (words[5 + k] or 0) + LK
    dump(report, "LP on 5, LK on " .. (5 + k), play(words, 20), 4, 14)
  end

  -- Out of range: back off first.
  S.load("close")
  S.hold_raw(4)
  S.wait(60)
  S.hold({})
  S.wait(20)
  S.save("far")
  S.load("close")
  S.hold_raw(4)
  S.wait(tonumber(os.getenv("BACK") or "16"))
  S.hold({})
  S.wait(20)
  S.save("mid")
  S.load("far")
  local words = { 0, 0, 0, 0, LP + LK }
  dump(report, "LP+LK out of range", play(words, 25), 4, 20)

  -- Dash in, then LP+LK `at` frames after the dash's last input.
  for _, at in ipairs({ 0, 10, 11, 12, 13, 14, 15, 16, 17, 18 }) do
    S.load("mid")
    local dash = inputs.timeline({ { 6, 1 }, { 5, 2 }, { 6, 1 } }, true)
    local w = {}
    for _, raw in ipairs(dash) do
      table.insert(w, raw)
    end
    for f = 1, 30 do
      w[#dash + f] = (f == at) and (LP + LK) or 0
    end
    if at == 0 then
      dump(report, "dash, no press", play(w, 10), 1, 30)
    else
      local log = play(w, 10)
      table.insert(report, string.format("dash, LP+LK %d after: %s / %s", at, log[#dash + at + 1], log[#dash + at + 5]))
    end
  end

  S.load("mid")
  local back = inputs.timeline({ { 4, 1 }, { 5, 2 }, { 4, 1 }, { 5, 40 } }, true)
  dump(report, "back dash, no press", play(back, 0), 1, 44)

  local f = io.open(out_path, "w")
  f:write(table.concat(report, "\n") .. "\n")
  f:close()
  print(out_path)
  S.exit()
end)
