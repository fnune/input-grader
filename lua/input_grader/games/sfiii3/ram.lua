-- Reads 3rd Strike's player and command state from emulator memory (Japan 990512 set, the one
-- Fightcade runs). Addresses come from the arcade decomp's struct layouts, located in RAM with
-- harness/mame (see docs/how-it-works.md); the player object offsets are 3rd_training_lua's.

local bits = require("input_grader.core.bits")
local C = require("input_grader.games.sfiii3.constants")

local M = {}

M.SLOT_TABLE = 0x06613968 -- pl_cmd_list in the program ROM: 21 fighters x 56 record pointers
M.WORK_CP = { 0x02026318, 0x0202671E }
M.WAZA_WORK = { 0x020256C4, 0x02025CE4 }
M.PLAYER = { 0x02068C6C, 0x02069104 }
M.SELECTED_SA = { 0x020154D3, 0x020154D5 }
M.WAZA_FLAG, M.WORK_SIZE = 0x16, 28

local Ram = {}
Ram.__index = Ram

--- @param mem table { u8 = fn(addr), u16 = fn(addr), s16 = fn(addr), u32 = fn(addr) }
--- @param player number 1 or 2
function M.new(mem, player)
  return setmetatable({ mem = mem, player = player, records = {} }, Ram)
end

function Ram:fighter_row()
  return self.mem.u16(M.PLAYER[self.player] + M.PLAYER_NUMBER)
end

-- PLW offsets, from offsetof() over the decomp's structs.h (tools/offsets.c).
M.RL_FLAG, M.RL_WAZA, M.POS_Y = 0x0A, 0x0B, 0x68
M.PLAYER_NUMBER, M.SA_STOP_FLAG, M.DO_NOT_MOVE = 0x3C0, 0x41C, 0x455

--- The facing the command check uses: rl_waza, which can differ from the sprite's rl_flag
--- for a few frames around a cross-up.
function Ram:facing_right()
  return self.mem.u8(M.PLAYER[self.player] + M.RL_WAZA) == 1
end

--- Whether the game ran the command check for this player this frame: Player_move is skipped
--- while do_not_move is set, and super freeze swaps waza_check for key_thru.
function Ram:check_ran()
  local base = M.PLAYER[self.player]
  return self.mem.u8(base + M.DO_NOT_MOVE) == 0 and self.mem.u8(base + M.SA_STOP_FLAG) ~= 1
end

function Ram:airborne()
  return self.mem.s16(M.PLAYER[self.player] + M.POS_Y) > 0
end

-- The command check runs before the frame moves the player, so it sees the height the
-- previous frame ended with.
function Ram:airborne_at_check()
  local was = self.was_airborne
  self.was_airborne = self:airborne()
  if was == nil then return self.was_airborne end
  return was
end

function Ram:selected_super_art()
  return self.mem.u8(M.SELECTED_SA[self.player])
end

--- The input word the game read this frame (WORK_CP.sw_lvbt without the derived PP/KK bits),
--- and the facing and height the command check uses.
function Ram:read_input()
  local raw = bits.band(self.mem.u16(M.WORK_CP[self.player]), bits.bnot16(C.SW_PP + C.SW_KK))
  return raw, { facing_right = self:facing_right(), airborne = self:airborne_at_check() }
end

local function record_address(self, slot)
  local row = self:fighter_row()
  local key = row * 64 + slot
  if not self.records[key] then
    self.records[key] = self.mem.u32(M.SLOT_TABLE + 4 * (row * C.SLOTS + slot))
  end
  return self.records[key]
end

--- Every command slot's state: waza_flag and the WAZA_WORK fields, with w_ptr turned into the
--- checker's 1-based index of the next step to load.
function Ram:read_commands(active)
  local mem = self.mem
  local cp, work = M.WORK_CP[self.player], M.WAZA_WORK[self.player]
  local state = { flag = {}, work = {} }
  for slot = 0, C.SLOTS - 1 do
    state.flag[slot] = mem.s16(cp + M.WAZA_FLAG + 2 * slot)
    if active == nil or active[slot] then
      local a = work + M.WORK_SIZE * slot
      local w_ptr = mem.u32(a + 8)
      state.work[slot] = {
        w_type = mem.s16(a), w_int = mem.s16(a + 2), free1 = mem.s16(a + 4),
        w_lvr = mem.u16(a + 6), free2 = mem.s16(a + 12),
        flag = mem.s16(a + 18), shot_flag = mem.s16(a + 20), shot_flag2 = mem.s16(a + 22),
        free3 = mem.s16(a + 24), shot_ok = mem.s16(a + 26),
        ptr = math.floor((w_ptr - record_address(self, slot) - 24) / 8) + 1,
      }
    end
  end
  return state
end

return M
