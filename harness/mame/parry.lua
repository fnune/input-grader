package.path = "harness/mame/?.lua;lua/?.lua;lua/?/init.lua;" .. package.path

local S = require("session")

local P1, P2 = S.ADDR.p1_base, S.ADDR.p2_base
local CP1 = 0x02026318
local ROUTINE, GUARD_CHUU, KIND_OF_BLOCKING, ATT_GUARD, JUMP_ATT = 0x24, 0x3D3, 0x470, 0x2E1, 0x304
local out_path = os.getenv("PARRY_OUT") or "build/parry.txt"
local ATTACKS = {
  standing_mp = { raw = 0x20 },
  crouching_mk = { raw = 0x200 + 2 },
}
local attack = ATTACKS[os.getenv("ATTACK") or "standing_mp"]
local ATTACK_AT = 15

local function flag(slot)
  return S.s16(CP1 + 0x16 + 2 * slot)
end

local function state()
  return string.format(
    "f3 %3d f4 %3d f12 %3d | p1 rno %d.%d guard_chuu %d blocking %d | p2 rno %d.%d att.guard 0x%02X jump %d",
    flag(3),
    flag(4),
    flag(12),
    S.s16(P1 + ROUTINE + 2),
    S.s16(P1 + ROUTINE + 4),
    S.u8(P1 + GUARD_CHUU),
    S.u8(P1 + KIND_OF_BLOCKING),
    S.s16(P2 + ROUTINE + 2),
    S.s16(P2 + ROUTINE + 4),
    S.u8(P2 + ATT_GUARD),
    S.u8(P2 + JUMP_ATT)
  )
end

-- P2 attacks on frame 1; P1 taps forward on frame `tap` (nil: no tap). Returns the frame log.
local function play(tap, frames)
  local log = {}
  for f = 1, frames do
    local p1 = (tap and f == tap) and 8 or 0
    local p2 = (f >= ATTACK_AT and f <= ATTACK_AT + 1) and attack.raw or 0
    S.hold_raw(p1, p2)
    coroutine.yield()
    log[f] = state()
  end
  S.hold({})
  return log
end

S.spawn(function()
  S.boot_to_match(0)
  S.hold_raw(8)
  S.wait(70)
  S.hold({})
  S.wait(30)
  manager.machine:save("parry")
  S.wait(2)
  local report = { "baseline: no tap" }
  for f, line in ipairs(play(nil, 40)) do
    table.insert(report, string.format("%3d  %s", f, line))
  end
  for tap = 1, 30 do
    manager.machine:load("parry")
    S.wait(2)
    local log = play(tap, 40)
    table.insert(report, "")
    table.insert(report, "tap at " .. tap)
    for f, line in ipairs(log) do
      table.insert(report, string.format("%3d  %s", f, line))
    end
  end
  local f = io.open(out_path, "w")
  f:write(table.concat(report, "\n") .. "\n")
  f:close()
  print(out_path)
  S.exit()
end)
