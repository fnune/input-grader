local C = require("input_grader.games.sfiii3.constants")
local Checker = require("input_grader.games.sfiii3.checker")
local ram = require("input_grader.games.sfiii3.ram")

local M = {}

local ROUTINE_NO, PLAYER_ATTACK = 36, 4

local RamSource = {}
RamSource.__index = RamSource

--- @param mem table { u8, u16, s16, u32 } readers of emulator memory
--- @param commands table games/sfiii3/commands.lua
function M.ram(mem, commands, player)
  local self = setmetatable({ mem = mem, commands = commands, player = player or 1 }, RamSource)
  self.ram = ram.new(mem, self.player)
  return self
end

function RamSource:fighter()
  return self.commands.fighters[self.ram:fighter_row()]
end

local function rno_slot(fighter, flags, rno)
  local fallback
  for slot, record in pairs(fighter.slots) do
    if slot >= C.SA_GROUND then
      for j = 1, 4 do
        if record.rno[j] == rno then
          if flags[slot] and flags[slot] > 0 then
            return { slot = slot, strength = j - 1 }
          end
          fallback = fallback or { slot = slot, strength = j - 1 }
        end
      end
    end
  end
  return fallback
end

function RamSource:poll()
  local base = ram.PLAYER[self.player]
  local r1, r2 = self.mem.s16(base + ROUTINE_NO + 2), self.mem.s16(base + ROUTINE_NO + 4)
  local was = self.routine
  self.routine = { r1, r2 }
  if not self.ram:in_match() or not self.ram:check_ran() then
    return nil
  end
  local fighter = self:fighter()
  if not fighter then
    return nil
  end
  local raw, ctx = self.ram:read_input()
  local state = self.ram:read_commands(fighter.slots)
  local started
  if r1 == PLAYER_ATTACK and (not was or was[1] ~= PLAYER_ATTACK or was[2] ~= r2) then
    started = rno_slot(fighter, (self.previous_flags or state.flag), r2)
  end
  self.previous_flags = state.flag
  return {
    raw = raw,
    facing_right = ctx.facing_right,
    airborne = ctx.airborne,
    sw_new = self.mem.u16(ram.WORK_CP[self.player] + 2),
    state = state,
    started = started,
    fighter_row = self.ram:fighter_row(),
    super_art = self.ram:selected_super_art(),
  }
end

local SimSource = {}
SimSource.__index = SimSource

--- A scripted source: the Lua checker fed with raw words, starting moves the way the game
--- would when nothing else (meter, recovery) stands in the way.
function M.sim(commands, fighter_row, super_art)
  local self = setmetatable({}, SimSource)
  self.fighter_row, self.super_art = fighter_row, super_art or 0
  self.fighter = commands.fighters[fighter_row]
  self.checker = Checker.new(self.fighter)
  self.queue = {}
  self.busy = 0
  return self
end

SimSource.BUSY_FRAMES = 30

function SimSource:push(raw, facing_right, airborne)
  table.insert(self.queue, { raw = raw, facing_right = facing_right ~= false, airborne = airborne or false })
end

function SimSource:poll()
  local input = table.remove(self.queue, 1)
  if not input then
    return nil
  end
  local checker = self.checker
  checker:frame(input.raw, input)
  local art = self.fighter.super_arts[self.super_art + 1]
  local started
  if self.busy > 0 then
    self.busy = self.busy - 1
  else
    started = checker:start({ airborne = input.airborne, super_art = art })
    if started then
      self.busy = SimSource.BUSY_FRAMES
    end
  end
  local state = { flag = {}, work = {} }
  for slot = 0, C.SLOTS - 1 do
    state.flag[slot] = checker.flag[slot]
    local w = checker.work[slot]
    state.work[slot] = { w_type = w.w_type, ptr = w.ptr, w_int = w.w_int }
  end
  if started then
    checker:consume(started)
  end
  return {
    raw = input.raw,
    facing_right = input.facing_right,
    airborne = input.airborne,
    sw_new = checker.lvr.sw_new,
    state = state,
    started = started,
    fighter_row = self.fighter_row,
    super_art = self.super_art,
  }
end

return M
