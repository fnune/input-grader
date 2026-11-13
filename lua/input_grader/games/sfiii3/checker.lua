local bits = require("input_grader.core.bits")
local C = require("input_grader.games.sfiii3.constants")

local band, bor, lshift, has, bnot16 = bits.band, bits.bor, bits.lshift, bits.has, bits.bnot16

local CK = C.CK

local Checker = {}
Checker.__index = Checker

local function new_work()
  return {
    w_type = 0,
    w_int = 0,
    free1 = 0,
    free2 = 0,
    free3 = 0,
    w_lvr = 0,
    ptr = 1,
    idx = 0,
    flag = 0,
    shot_flag = 0,
    shot_flag2 = 0,
    shot_ok = 0,
    w_dead = 0,
    w_dead2 = 0,
    why = nil,
  }
end

local function active_slots(counts)
  local active = {}
  local groups = { { 0, 20 }, { 20, 24 }, { 24, 28 }, { 28, 38 }, { 38, 42 }, { 42, 46 }, { 46, 56 } }
  for g, range in ipairs(groups) do
    for slot = range[1], math.min(counts[g], range[2]) - 1 do
      active[slot] = true
    end
  end
  return active
end

--- @param fighter table one entry of data/commands.lua `fighters`
function Checker.new(fighter)
  local self = setmetatable({}, Checker)
  self.fighter = fighter
  self.frame_no = 0
  self.lvr = {
    sw_new = 0,
    sw_old = 0,
    sw_chg = 0,
    sw_now = 0,
    old_now = 0,
    now_lvbt = 0,
    old_lvbt = 0,
    new_lvbt = 0,
    sw_lever = 0,
    shot_up = 0,
    shot_down = 0,
    shot_ud = 0,
    waza_no = 0,
    cnt = {},
  }
  for i = 1, 14 do
    self.lvr.cnt[i] = 0
  end
  self.cp = { sw_lvbt = 0, sw_new = 0, sw_old = 0, sw_now = 0, sw_off = 0, sw_chg = 0, old_now = 0 }
  self.flag, self.work, self.records = {}, {}, {}
  local active = active_slots(fighter.slot_counts)
  for slot = 0, C.SLOTS - 1 do
    local record = fighter.slots[slot]
    self.work[slot] = new_work()
    if active[slot] and record then
      self.records[slot] = record
      self.flag[slot] = 0
      self.work[slot].w_dead = record.dead
      self.work[slot].w_dead2 = record.dead2
    else
      self.flag[slot] = -1
    end
  end
  return self
end

local cur_self, cur_slot, cur_work, cur_record

local function lvr()
  return cur_self.lvr
end

local function emit(kind, extra)
  local e = extra or {}
  e.kind, e.slot, e.frame = kind, cur_slot, cur_self.frame_no
  table.insert(cur_self.events, e)
end

local function is_end()
  return cur_work.ptr > #cur_record.steps
end

local function load_step(w, step, reset_flags)
  w.w_type, w.w_int, w.free1, w.free2, w.w_lvr = step[1], step[2], step[3], step[3], bits.u16(step[4])
  if reset_flags then
    w.flag, w.shot_flag, w.shot_flag2, w.shot_ok, w.free3 = 0, 0, 0, 0, 0
  end
end

local dispatch

local function check_init()
  local w = cur_work
  load_step(w, cur_record.steps[1], true)
  w.ptr, w.idx = 2, 1
  dispatch()
end

local function check_next()
  local w = cur_work
  emit("step", { step = w.idx })
  local step = cur_record.steps[w.ptr]
  load_step(w, step, false)
  w.idx, w.ptr = w.ptr, w.ptr + 1
  if w.w_type ~= CK.LEVER_CHANGE then
    dispatch()
  end
end

local function abandon(why)
  cur_work.w_type = 0
  cur_work.why = why
end

local function command_ok()
  local w = cur_work
  emit("step", { step = w.idx })
  cur_self.flag[cur_slot] = cur_record.reset
  if w.w_type ~= CK.UKEMI then
    w.w_type = 0
    w.completed = true
    lvr().waza_no = cur_slot
  end
  emit("complete")
end

local function set_flag_reset()
  cur_self.flag[cur_slot] = cur_record.reset
end

local function dead_lvr_check()
  local w, l = cur_work, lvr()
  if (w.w_dead ~= 0 and w.w_dead == l.sw_new) or (w.w_dead2 ~= 0 and w.w_dead2 == l.sw_new) then
    abandon("dead")
    return true
  end
  return false
end

local function finish_or_next()
  if is_end() then
    command_ok()
  else
    check_next()
  end
end

local function tick_timeout()
  local w = cur_work
  w.w_int = w.w_int - 1
  if w.w_int < 0 then
    abandon("timeout")
  end
end

local function lever_changed()
  local l = lvr()
  return band(l.old_lvbt, C.LV_MASK) ~= band(l.new_lvbt, C.LV_MASK)
end

local function lever_match(sw_lever, any_needs_new_press)
  local w = cur_work
  if has(w.w_lvr, C.LV_EXACT) then
    return sw_lever == band(w.w_lvr, C.LV_MASK)
  elseif w.w_lvr == 0 then
    return sw_lever == 0
  elseif any_needs_new_press and not has(lvr().now_lvbt, C.LV_MASK) then
    return false
  end
  return has(sw_lever, w.w_lvr)
end

local checks = {}

checks[CK.INIT] = check_init

checks[CK.LEVER] = function()
  tick_timeout()
  if not dead_lvr_check() and lever_match(band(lvr().sw_lever, C.LV_MASK), true) then
    finish_or_next()
  end
end

checks[CK.CHARGE] = function()
  local w, l = cur_work, lvr()
  if dead_lvr_check() then
    return
  end
  local sw_work = band(w.w_lvr, C.LV_MASK)
  local exact = has(w.w_lvr, C.LV_EXACT)
  local holding = exact and (sw_work == l.sw_lever) or (not exact and has(sw_work, l.sw_lever))
  if holding then
    if exact then
      w.free2 = w.free2 - 1
      if w.flag ~= 0 then
        return
      end
      if w.free2 < 0 then
        w.flag = 1
      end
    else
      if w.flag ~= 0 then
        return
      end
      w.free1 = w.free1 - 1
      if w.free1 < 0 then
        w.flag = 1
      end
    end
  else
    if w.flag ~= 0 then
      w.flag = 0
      finish_or_next()
      return
    end
    w.free2 = w.free1
    tick_timeout()
  end
end

checks[CK.HOLD] = function()
  local w, l = cur_work, lvr()
  local sw_work = band(l.sw_new, w.w_lvr)
  if w.w_lvr == sw_work then
    if w.flag ~= 0 then
      return
    end
    w.free2 = w.free2 - 1
    if w.free2 < 0 then
      w.flag = 1
    end
  else
    if w.flag ~= 0 and sw_work == 0 then
      w.flag = 0
      finish_or_next()
      return
    end
    w.free2 = w.free1
    tick_timeout()
  end
end

local function count_releases(first_counter, n, first_flag, threshold_of)
  local w, l = cur_work, lvr()
  w.shot_flag2 = w.shot_flag
  w.shot_flag = 0
  local flag = first_flag
  for i = 0, n - 1 do
    if threshold_of(l.cnt[first_counter + i]) then
      w.shot_flag = bor(w.shot_flag, flag)
    end
    if has(l.shot_down, flag) and has(w.shot_flag2, flag) then
      w.shot_ok = w.shot_ok + 1
    end
    flag = lshift(flag, 1)
  end
end

checks[CK.SHOT_HOLD] = function()
  local w = cur_work
  count_releases(C.CNT_S1, 6, C.SW_LP, function(c)
    return c >= w.w_int
  end)
  if w.shot_ok ~= 0 then
    w.free2 = w.free2 - 1
    if w.free2 < 0 then
      w.shot_ok, w.free2 = 0, w.free1
    end
  end
  if w.shot_ok >= w.w_lvr then
    w.shot_ok, w.free2 = 0, w.free1
    finish_or_next()
  end
end

checks[CK.RENDA] = function()
  local w, l, flags = cur_work, lvr(), cur_self.flag
  local light, medium, heavy = C.SW_LK, C.SW_MK, C.SW_HK
  if w.w_lvr == C.SW_LP then
    light, medium, heavy = C.SW_LP, C.SW_MP, C.SW_HP
  end
  if has(l.sw_now, light) then
    w.flag = w.flag + 1
  end
  if has(l.sw_now, medium) then
    w.shot_flag = w.shot_flag + 1
  end
  if has(l.sw_now, heavy) then
    w.shot_flag2 = w.shot_flag2 + 1
  end
  w.w_int = w.w_int - 1
  if w.w_int < 0 then
    w.flag, w.shot_flag, w.shot_flag2, w.w_int = 0, 0, 0, w.free1
  end
  local function strength(field, refresh)
    if flags[cur_slot] ~= 0 then
      if w.w_int > 0 and w[field] ~= 0 then
        set_flag_reset()
        w[field], w.w_int = 0, refresh
        return true
      end
    elseif w[field] >= 5 then
      set_flag_reset()
      w[field], w.w_int = 0, refresh
      l.waza_no = cur_slot
      emit("complete")
      return true
    end
    return false
  end
  if strength("shot_flag2", 9) then
    return
  end
  if strength("shot_flag", 12) then
    return
  end
  strength("flag", 15)
end

checks[CK.PRESS] = function()
  tick_timeout()
  if not dead_lvr_check() and cur_work.w_lvr == lvr().sw_now then
    finish_or_next()
  end
end

checks[CK.TURN] = function()
  local w, l = cur_work, lvr()
  w.w_int = w.w_int - 1
  if w.w_int < 0 then
    local step = cur_record.steps[1]
    w.w_type, w.w_int, w.free2, w.w_lvr = step[1], step[2], step[3], bits.u16(step[4])
    w.ptr, w.idx = 2, 1
    w.flag, w.shot_flag, w.shot_flag2, w.free1, w.shot_ok = 0, 0, 0, 14, 0
  else
    w.free1 = w.free1 - 1
    if w.free1 <= 0 then
      w.free1, w.shot_ok = 14, 0
    end
  end
  local lv = 1
  for _ = 1, 4 do
    if l.sw_lever == lv then
      w.shot_ok = bor(w.shot_ok, lv)
      w.free1 = 14
    end
    lv = lshift(lv, 1)
  end
  if w.shot_ok ~= C.LV_MASK then
    return
  end
  if is_end() then
    command_ok()
  else
    w.shot_ok = 0
    check_next()
  end
end

local function check_7()
  local w = cur_work
  w.w_int = w.w_int - 1
  local first_counter, first_flag = C.CNT_S1, C.SW_LP
  if w.w_type ~= CK.SHOT_P then
    -- Game quirk, kept: https://github.com/gibletto/sfIII3-cps3-decomp/blob/d440837/src/cmd_main_2.c#L587
    first_counter, first_flag = C.CNT_S1 + 3, C.SW_LK
  end
  count_releases(first_counter, 3, first_flag, function(c)
    return has(c, w.w_lvr)
  end)
  if w.shot_ok ~= 0 then
    w.free2 = w.free2 - 1
    if w.free2 < 0 then
      w.shot_ok, w.free2, w.shot_flag = 0, w.free1, 0
    end
  end
  if w.shot_ok >= w.w_lvr then
    w.shot_ok, w.free2 = 0, w.free1
    finish_or_next()
  end
end
checks[CK.SHOT_P] = check_7
checks[CK.SHOT_K] = check_7

checks[CK.LEVER_CHANGE] = function()
  local w, l = cur_work, lvr()
  tick_timeout()
  if has(w.w_lvr, C.LV_EXACT) then
    if lever_changed() then
      if l.sw_lever == band(w.w_lvr, C.LV_MASK) then
        finish_or_next()
      else
        abandon("wrong")
      end
    end
  elseif w.w_lvr == 0 then
    if l.new_lvbt == 0 then
      finish_or_next()
    elseif lever_changed() then
      abandon("wrong")
    end
  elseif lever_changed() then
    if has(l.sw_lever, w.w_lvr) then
      finish_or_next()
    else
      abandon("wrong")
    end
  end
end

local PARRY_SLOTS = { 3, 4, 5, 6, 12 }

local function parry_exclude_others()
  local flags, slot = cur_self.flag, cur_slot
  for _, other in ipairs(PARRY_SLOTS) do
    if other ~= slot and flags[slot] > flags[other] then
      flags[other] = 0
    end
  end
  if slot == 5 and cur_self.work[6].free3 > 0 then
    flags[5] = 0
  end
  if slot == 6 and cur_self.work[5].free3 > 0 then
    flags[6] = 0
  end
end

local function parry_tail(w, l, strict)
  local flags = cur_self.flag
  if w.shot_ok == 2 then
    w.w_int = w.w_int - 1
    w.free3 = w.free3 - 1
    if w.w_int > 0 then
      if l.sw_lever == 0 then
        w.shot_ok = w.shot_ok + 1
      elseif has(l.sw_lever, C.LV_BACK) then
        flags[cur_slot] = 0
        w.shot_ok = w.shot_ok + 1
      elseif l.sw_lever ~= w.w_lvr then
        flags[cur_slot] = 0
        if strict then
          abandon("wrong")
        else
          w.shot_ok = w.shot_ok + 1
        end
      end
    else
      flags[cur_slot] = 0
      w.shot_ok = w.shot_ok + 1
    end
  elseif w.shot_ok == 3 then
    w.free3 = w.free3 - 1
    if w.free3 < 0 then
      abandon("timeout")
    elseif has(l.sw_now, C.LV_BACK) or l.sw_now == w.w_lvr then
      flags[cur_slot] = 0
    elseif has(l.sw_now, C.LV_MASK) then
      flags[cur_slot] = 0
      if strict then
        abandon("wrong")
      else
        w.shot_ok = w.shot_ok + 1
      end
    end
  elseif w.shot_ok == 4 and not strict then
    w.free3 = w.free3 - 1
    if w.free3 < 0 then
      abandon("timeout")
    end
  end
end

local function parry(in_air_only)
  return function(ctx)
    local w, l = cur_work, lvr()
    if w.shot_ok == 0 then
      if l.sw_lever == 0 then
        w.shot_ok = 1
      end
    elseif w.shot_ok == 1 then
      local slot = cur_slot
      local tap = has(l.now_lvbt, C.LV_MASK)
      local allowed
      if in_air_only then
        allowed = ctx.airborne and tap
      else
        allowed = tap and not (not ctx.airborne and (slot == 5 or slot == 6))
      end
      if allowed then
        if l.sw_lever == w.w_lvr then
          w.shot_ok = 2
          set_flag_reset()
          w.free3 = cur_record.reset + 10
          w.w_int = 6
          parry_exclude_others()
          emit("complete")
        else
          w.shot_ok = 0
        end
      end
    else
      parry_tail(w, l, false)
    end
  end
end
checks[CK.PARRY] = parry(false)
checks[CK.AIR_PARRY] = parry(true)

checks[CK.BACK_DOWN] = function()
  local w, l = cur_work, lvr()
  if dead_lvr_check() then
    w.free3, w.flag = 0, 0
    cur_self.flag[cur_slot] = 0
    return
  end
  if w.flag == 0 then
    w.flag = has(l.sw_lever, C.LV_BACK) and 1 or 0
  elseif l.sw_lever == C.LV_DOWN then
    check_next()
  elseif not has(l.sw_lever, C.LV_BACK) then
    w.flag = 0
  end
end

checks[CK.UKEMI] = function()
  local w, l, flags = cur_work, lvr(), cur_self.flag
  if w.free3 > 0 then
    w.free3 = w.free3 - 1
    if w.free3 <= 0 then
      abandon("timeout")
    end
  end
  local function trigger()
    flags[cur_slot] = 16 - C.UKEMI_TIME[flags[cur_slot] + 1]
    w.free3 = 16
    l.waza_no = cur_slot
    emit("complete")
  end
  if lever_changed() and l.sw_lever == C.LV_DOWN then
    trigger()
  end
  if band(bor(l.sw_now, l.old_now), C.SW_PUNCH) == C.SW_PUNCH then
    trigger()
  end
end

checks[CK.RENDA3] = function()
  local w, l, flags = cur_work, lvr(), cur_self.flag
  w.w_int = w.w_int - 1
  local group = (w.w_lvr == C.SW_LP) and C.SW_PUNCH or C.SW_KICK
  if has(l.sw_now, group) then
    w.flag = w.flag + 1
  end
  local refresh = (cur_slot % 2 == 1) and 10 or 6
  if flags[cur_slot] ~= 0 then
    if w.w_int <= 0 then
      if w.flag ~= 0 then
        set_flag_reset()
        w.flag, w.w_int = 0, refresh
      else
        w.flag, w.w_int = 0, w.free1
      end
    end
  elseif w.flag >= 3 then
    set_flag_reset()
    w.flag, w.w_int = 0, refresh
    l.waza_no = cur_slot
    emit("complete")
  elseif w.w_int < 0 then
    w.flag, w.w_int = 0, w.free1
  end
end

checks[CK.LEVER_COUNT] = function()
  local w, l = cur_work, lvr()
  w.w_int = w.w_int - 1
  if w.w_int < 0 then
    abandon("timeout")
    return
  end
  if dead_lvr_check() then
    return
  end
  local hit
  if has(w.w_lvr, C.LV_EXACT) then
    hit = l.sw_lever == band(w.w_lvr, C.LV_MASK)
  elseif w.w_lvr == 0 then
    hit = l.sw_lever == 0
  else
    hit = lever_changed() and has(l.sw_lever, w.w_lvr)
  end
  if hit then
    w.shot_ok = w.shot_ok + 1
    if w.shot_ok >= w.free1 then
      finish_or_next()
    end
  end
end

local function check_16()
  local w, l = cur_work, lvr()
  w.w_int = w.w_int - 1
  if w.w_int < 0 then
    abandon("timeout")
    w.shot_ok = 0
    return
  end
  local sw_work, flag = band(l.sw_now, C.SW_KICK), C.SW_LK
  if w.w_type == CK.PRESS_P then
    sw_work, flag = band(l.sw_now, C.SW_PUNCH), C.SW_LP
  end
  w.shot_flag2 = w.shot_flag
  w.shot_flag = 0
  for _ = 1, 3 do
    if has(sw_work, flag) then
      w.shot_ok = w.shot_ok + 1
    end
    flag = lshift(flag, 1)
  end
  if w.shot_ok >= w.w_lvr then
    w.shot_ok = 0
    finish_or_next()
  end
end
checks[CK.PRESS_P] = check_16
checks[CK.PRESS_K] = check_16

checks[CK.LEVER_REPEAT] = function()
  local w, l = cur_work, lvr()
  w.w_int = w.w_int - 1
  if w.w_int < 0 then
    abandon("timeout")
    return
  end
  if dead_lvr_check() then
    return
  end
  local sw_lever = band(l.sw_lever, C.LV_MASK)
  local hit
  if has(w.w_lvr, C.LV_EXACT) then
    hit = lever_changed() and sw_lever == band(w.w_lvr, C.LV_MASK)
  elseif w.w_lvr == 0 then
    hit = l.sw_lever == 0
  else
    hit = lever_changed() and has(sw_lever, w.w_lvr)
  end
  if hit then
    w.w_int = w.free1
    set_flag_reset()
    emit("complete")
  end
end

checks[CK.LEVER_SET] = function()
  local w, l = cur_work, lvr()
  tick_timeout()
  if dead_lvr_check() then
    return
  end
  local sw_lever = band(l.sw_lever, C.LV_MASK)
  local hit
  if has(w.w_lvr, C.LV_EXACT) then
    hit = has(l.now_lvbt, C.LV_MASK) and sw_lever == band(w.w_lvr, C.LV_MASK)
  elseif w.w_lvr == 0 then
    hit = l.sw_lever == 0
  else
    hit = has(l.now_lvbt, C.LV_MASK) and has(sw_lever, w.w_lvr)
  end
  if hit then
    set_flag_reset()
    emit("complete")
    check_next()
  end
end

checks[CK.NONE] = function() end

checks[CK.LEVER_PRESS] = function()
  local w, l = cur_work, lvr()
  tick_timeout()
  if dead_lvr_check() then
    return
  end
  local sw_lever = band(l.sw_lever, C.LV_MASK)
  local hit
  if has(w.w_lvr, C.LV_EXACT) then
    local want = band(w.w_lvr, C.LV_MASK)
    if want == 0 then
      hit = sw_lever == 0
    else
      hit = has(l.now_lvbt, C.LV_MASK) and sw_lever == want
    end
  elseif w.w_lvr == 0 then
    hit = sw_lever == 0
  else
    hit = has(l.now_lvbt, C.LV_MASK) and has(sw_lever, w.w_lvr)
  end
  if hit then
    finish_or_next()
  end
end

checks[CK.ROTATE] = function()
  local w, l = cur_work, lvr()
  w.w_int = w.w_int - 1
  if w.w_int < 0 then
    load_step(w, cur_record.steps[1], true)
    w.ptr, w.idx = 2, 1
  end
  for i = 1, 8 do
    if l.sw_lever == C.ROTATE_DIRS[i] then
      w.free3 = bor(w.free3, lshift(1, i - 1))
    end
  end
  if w.free3 == 0xFF then
    if is_end() then
      command_ok()
    else
      w.free3 = 0
      check_next()
    end
  end
end

checks[CK.PARRY_STRICT] = function()
  local w, l = cur_work, lvr()
  if w.shot_ok == 0 then
    if l.sw_lever == 0 then
      w.shot_ok = 1
    end
  elseif w.shot_ok == 1 then
    if lever_changed() and l.sw_lever == w.w_lvr then
      w.shot_ok = 2
      set_flag_reset()
      w.free3 = cur_record.reset + 3
      w.w_int = 6
      emit("complete")
    end
  else
    parry_tail(w, l, true)
  end
end

checks[CK.LEVER_NEW] = function()
  tick_timeout()
  if not dead_lvr_check() and lever_match(band(lvr().now_lvbt, C.LV_MASK), false) then
    finish_or_next()
  end
end

checks[CK.LEVER_HELD] = function()
  tick_timeout()
  if not dead_lvr_check() and lever_match(band(lvr().sw_lever, C.LV_MASK), false) then
    finish_or_next()
  end
end

checks[CK.LEVER_OFF] = function()
  local w, l = cur_work, lvr()
  if dead_lvr_check() then
    return
  end
  local want = band(w.w_lvr, C.LV_MASK)
  if band(l.sw_now, C.LV_MASK) ~= want then
    if band(l.sw_lever, C.LV_MASK) ~= want and w.flag ~= 0 then
      finish_or_next()
    end
  else
    w.flag = 1
  end
end

local cur_ctx

dispatch = function()
  local f = checks[cur_work.w_type]
  if not f then
    error(string.format("unknown check routine %d in %s slot %d", cur_work.w_type, cur_self.fighter.name, cur_slot))
  end
  f(cur_ctx)
end

local function command_ok_move(slot)
  if dead_lvr_check() then
    cur_self.flag[slot] = 0
  else
    cur_self.flag[slot] = cur_self.flag[slot] - 1
  end
end

local function pl_lvr_set(self, raw, facing_right)
  local l, cp = self.lvr, self.cp
  cp.sw_lvbt = raw
  local sw_0 = raw
  if facing_right then
    local lr = band(sw_0, 0xC)
    if lr ~= 0 then
      sw_0 = bor(band(sw_0, 0xFF3), bits.bxor(lr, 0xC))
    end
  end
  cp.old_now = l.sw_now
  l.old_now = l.sw_now
  l.old_lvbt = l.new_lvbt
  local sw_work = band(cp.sw_lvbt, bnot16(l.old_lvbt))
  local sw_hana = band(l.sw_new, bnot16(sw_0))
  local function two_buttons(group, together, together_bit, keep_mask)
    if together[band(sw_work, group)] or together[band(sw_hana, group)] then
      cp.sw_lvbt = bor(cp.sw_lvbt, together_bit)
      sw_0 = bor(sw_0, together_bit)
    else
      cp.sw_lvbt = band(cp.sw_lvbt, keep_mask)
      sw_0 = band(sw_0, keep_mask)
    end
  end
  two_buttons(0xF0, C.TWO_PUNCHES, C.SW_PP, 0xFF7F)
  two_buttons(0xF00, C.TWO_KICKS, C.SW_KK, 0xF7FF)
  l.new_lvbt = cp.sw_lvbt
  l.sw_old = l.sw_new
  l.sw_new = sw_0
  l.sw_now = band(sw_0, bnot16(l.sw_old))
  l.now_lvbt = band(cp.sw_lvbt, bnot16(l.old_lvbt))
  l.sw_chg = bor(l.sw_now, band(l.sw_old, bnot16(sw_0)))
  l.sw_lever = band(sw_0, C.LV_MASK)
  l.shot_up = band(l.sw_now, C.SW_SHOT)
  l.shot_down = band(band(l.sw_old, bnot16(sw_0)), C.SW_SHOT)
  l.shot_ud = bor(l.shot_up, l.shot_down)
end

local function sw_pick_up(self, raw, facing_right)
  pl_lvr_set(self, raw, facing_right)
  local l, cp = self.lvr, self.cp
  local bit_ = 1
  for i = 1, 10 do
    if has(l.sw_new, bit_) then
      l.cnt[i] = l.cnt[i] + 1
    else
      l.cnt[i] = 0
    end
    bit_ = lshift(bit_, 1)
  end
  for i = 1, 4 do
    if has(l.sw_new, C.LVR_CHK[i]) then
      l.cnt[10 + i] = l.cnt[10 + i] + 1
    else
      l.cnt[10 + i] = 0
    end
  end
  cp.sw_new, cp.sw_old, cp.sw_chg, cp.sw_now, cp.sw_off = l.sw_new, l.sw_old, l.sw_chg, l.sw_now, l.shot_down
end

--- Advance one game frame.
--- @param raw number the input word with absolute directions: up 1, down 2, left 4, right 8,
---   LP 0x10, MP 0x20, HP 0x40, LK 0x100, MK 0x200, HK 0x400
--- @param ctx table { facing_right = bool, airborne = bool }
--- @return table events of this frame: { kind = "step"|"complete"|"reset", slot, frame, ... }
function Checker:frame(raw, ctx)
  self.frame_no = self.frame_no + 1
  self.events = {}
  cur_self, cur_ctx = self, ctx
  sw_pick_up(self, raw, ctx.facing_right)
  for slot = 0, C.SLOTS - 1 do
    if self.flag[slot] ~= -1 then
      cur_slot, cur_work, cur_record = slot, self.work[slot], self.records[slot]
      local before_idx, was_waiting = cur_work.idx, cur_work.w_type ~= 0
      cur_work.completed, cur_work.why = false, nil
      dispatch()
      if was_waiting and cur_work.w_type == 0 and not cur_work.completed and before_idx >= 2 then
        emit("reset", { step = cur_work.idx, why = cur_work.why or "timeout" })
      end
    end
  end
  for slot = 0, C.SLOTS - 1 do
    local f = self.flag[slot]
    if f ~= -1 and f ~= 0 then
      cur_slot, cur_work, cur_record = slot, self.work[slot], self.records[slot]
      command_ok_move(slot)
    end
  end
  cur_self, cur_ctx, cur_work, cur_record = nil, nil, nil, nil
  return self.events
end

local function conpane(cp, index)
  local field = C.CONPANE[index]
  return field and cp[field] or 0
end

local function strength_fires(self, slot)
  local record = self.records[slot]
  if not record or self.flag[slot] == -1 or self.flag[slot] == 0 then
    return nil
  end
  local index = band(record.btix, C.BT_INDEX)
  if index == C.BT_NONE then
    return nil
  end
  local cusw = conpane(self.cp, index)
  for j = 3, 0, -1 do
    local ex = record.exdt[j + 1]
    if not (j == 3 and not has(record.btix, C.BT_STRENGTH4)) then
      if band(cusw, C.SHOT_CONV[ex + 1]) == C.SHOT_CONV[band(ex, C.EX_BUTTON) + 1] then
        return j
      end
    end
  end
  return nil
end

--- The move the game would start this frame: the selected super art first, then the special
--- moves in slot order. Meter, projectile and super-art-only conditions are not checked.
--- @param opts table { airborne = bool, super_art = { ground = slot, air = slot } | nil }
--- @return table|nil { slot, strength (0 light .. 3 EX) }
function Checker:start(opts)
  local sa = opts.super_art or {}
  local super_slot = opts.airborne and sa.air or sa.ground
  if super_slot and super_slot ~= 0 then
    local j = strength_fires(self, super_slot)
    if j then
      return { slot = super_slot, strength = j, super = true }
    end
  end
  local first, last = C.SP_GROUND, C.SA_AIR - 1
  if opts.airborne then
    first, last = C.SP_AIR, C.SLOTS - 1
  end
  for slot = first, last do
    local j = strength_fires(self, slot)
    if j then
      return { slot = slot, strength = j }
    end
  end
  return nil
end

--- Clear the command work the way the game does once a move starts (waza_compel_init for a
--- special move, waza_compel_all_init2 for a super art).
function Checker:consume(started)
  if started.super then
    for slot = 0, C.SLOTS - 1 do
      if self.flag[slot] ~= -1 then
        self.work[slot].w_type = 0
      end
    end
    return
  end
  local w, record = self.work[started.slot], self.records[started.slot]
  load_step(w, record.steps[1], true)
  w.ptr, w.idx = 2, 1
  self.flag[started.slot] = 0
end

function Checker:buttons_pressed()
  return band(self.lvr.sw_now, C.SW_SHOT)
end

function Checker:lever()
  return self.lvr.sw_lever
end

return Checker
