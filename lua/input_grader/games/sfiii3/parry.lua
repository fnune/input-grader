local M = {}

M.SLOT = { forward = 3, down = 4, air_forward = 5, air_down = 6, jump_in = 12 }
M.GUARD = { low = 0x01, high = 0x02, air = 0x04 }
M.LATE_GRACE = 8
M.LOOKBACK = 30

local Parry = {}
Parry.__index = Parry

function M.new()
  return setmetatable({ frame = 0, taps = {}, previous = {}, pending = nil }, Parry)
end

local TAP_SLOTS = { M.SLOT.forward, M.SLOT.down, M.SLOT.air_forward, M.SLOT.air_down }
local TAP_DIR = {
  [M.SLOT.forward] = 6,
  [M.SLOT.down] = 2,
  [M.SLOT.air_forward] = 6,
  [M.SLOT.air_down] = 2,
}

local function needed(contact)
  if contact.airborne then
    return contact.opponent_guard % (2 * M.GUARD.air) >= M.GUARD.air and { 6, 2 } or {}
  end
  local dirs = {}
  if contact.opponent_guard % (2 * M.GUARD.high) >= M.GUARD.high then
    table.insert(dirs, 6)
  end
  if contact.opponent_guard % (2 * M.GUARD.low) >= M.GUARD.low then
    table.insert(dirs, 2)
  end
  return dirs
end

local function contains(list, v)
  for _, x in ipairs(list) do
    if x == v then
      return true
    end
  end
  return false
end

-- The tap that decided the parry: the latest before the hit, or else the first one after it.
local function deciding_tap(taps, contact_frame)
  local before, after
  for _, t in ipairs(taps) do
    if t.frame <= contact_frame then
      before = t
    elseif not after then
      after = t
    end
  end
  return before or after
end

local function judge(p)
  local c = p.contact
  local tap = deciding_tap(p.taps, c.frame)
  local result = {
    blocked = c.blocked,
    frame = c.frame,
    parried = c.parried,
    needed = needed(c),
    red = c.red,
    jump_in = c.jump_in,
    tap = tap,
    airborne = c.airborne,
  }
  if tap then
    result.window = (c.jump_in and tap.jump_window) or tap.window
  end
  if c.parried then
    return result
  end
  if not tap then
    result.error = { code = "no_parry", text = "no parry tap before the hit" }
  elseif tap.frame > c.frame then
    result.error = {
      code = "parry_late",
      text = "tapped " .. (tap.frame - c.frame) .. " frames after the hit",
      frames = tap.frame - c.frame,
    }
  elseif not contains(result.needed, tap.dir) then
    result.error = {
      code = "parry_direction",
      text = "this attack needs " .. table.concat(result.needed, " or ") .. ", not " .. tap.dir,
    }
  else
    local used = c.frame - tap.frame
    local window = result.window
    if c.red then
      result.error = {
        code = "parry_early",
        text = "a red parry needs the tap within 2 frames of the hit, came " .. used .. " before",
        frames = used,
      }
    else
      result.error = {
        code = "parry_early",
        text = "tapped " .. (used - window + 1) .. " frames too early (window " .. window .. ")",
        frames = used - window + 1,
      }
    end
  end
  return result
end

--- Feed one check frame. `obs` holds the parry slots' flags (`flag`), the lever (`dir`, numpad)
--- and, on the frame an attack connects, `contact` = { parried, airborne, opponent_guard,
--- red, jump_in }. Returns a judged contact `LATE_GRACE` frames after it, so late taps are seen.
function Parry:update(obs)
  self.frame = self.frame + 1
  local f = self.frame
  for _, slot in ipairs(TAP_SLOTS) do
    local now, before = obs.flag[slot] or 0, self.previous[slot] or 0
    if now > before then
      local tap = { frame = f, slot = slot, dir = TAP_DIR[slot], window = now }
      tap.jump_window = slot == M.SLOT.forward and obs.flag[M.SLOT.jump_in] or nil
      table.insert(self.taps, tap)
    end
    self.previous[slot] = now
  end
  while self.taps[1] and self.taps[1].frame < f - M.LOOKBACK do
    table.remove(self.taps, 1)
  end
  local out
  if self.pending and f - self.pending.contact.frame >= M.LATE_GRACE then
    self.pending.taps = self.taps
    out = judge(self.pending)
    self.pending = nil
    self.taps = {}
  end
  if obs.contact and not self.pending then
    local contact = {}
    for k, v in pairs(obs.contact) do
      contact[k] = v
    end
    contact.frame = f
    self.pending = { contact = contact }
  end
  return out
end

return M
