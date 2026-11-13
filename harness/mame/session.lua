local M = {}

local machine = manager.machine
local space = machine.devices[":maincpu"].spaces["program"]

local fields = {}
for _, port in pairs(machine.ioport.ports) do
  for name, field in pairs(port.fields) do
    fields[name] = field
  end
end

M.ADDR = {
  frame_number = 0x02007F00,
  match_state = 0x020154A7,
  p1_base = 0x02068C6C,
  p2_base = 0x02069104,
  select_state = { 0x0201553D, 0x02015545 },
  select_id = { 0x02011387, 0x02011388 },
  select_sa = { 0x020154D3, 0x020154D5 },
}

function M.u8(a)
  return space:read_u8(a)
end
function M.u16(a)
  return space:read_u16(a)
end
function M.s16(a)
  return space:read_i16(a)
end
function M.u32(a)
  return space:read_u32(a)
end
function M.w8(a, v)
  space:write_u8(a, v)
end

M.P1 = {
  up = "P1 Up",
  down = "P1 Down",
  left = "P1 Left",
  right = "P1 Right",
  LP = "P1 Jab Punch",
  MP = "P1 Strong Punch",
  HP = "P1 Fierce Punch",
  LK = "P1 Short Kick",
  MK = "P1 Forward Kick",
  HK = "P1 Roundhouse Kick",
}
M.P2 = {
  up = "P2 Up",
  down = "P2 Down",
  left = "P2 Left",
  right = "P2 Right",
  LP = "P2 Jab Punch",
  MP = "P2 Strong Punch",
  HP = "P2 Fierce Punch",
  LK = "P2 Short Kick",
  MK = "P2 Forward Kick",
  HK = "P2 Roundhouse Kick",
}

local held = {}

function M.hold(names)
  held = {}
  for _, n in ipairs(names or {}) do
    held[n] = true
  end
end

-- Raw input word (up 1, down 2, left 4, right 8, LP 0x10 ... HK 0x400) to control names.
local function raw_names(raw, controls, names)
  local bitmap = {
    { 1, "up" },
    { 2, "down" },
    { 4, "left" },
    { 8, "right" },
    { 0x10, "LP" },
    { 0x20, "MP" },
    { 0x40, "HP" },
    { 0x100, "LK" },
    { 0x200, "MK" },
    { 0x400, "HK" },
  }
  for _, pair in ipairs(bitmap) do
    if math.floor(raw / pair[1]) % 2 == 1 then
      table.insert(names, controls[pair[2]])
    end
  end
  return names
end

function M.hold_raw(raw, p2_raw)
  M.hold(raw_names(p2_raw or 0, M.P2, raw_names(raw, M.P1, {})))
end

local function apply_inputs()
  for name, field in pairs(fields) do
    field:set_value(held[name] and 1 or 0)
  end
end

local tasks = {}

function M.spawn(fn)
  table.insert(tasks, coroutine.create(fn))
end

function M.wait(frames)
  for _ = 1, frames do
    coroutine.yield()
  end
end

function M.wait_until(pred, limit)
  for _ = 1, limit or 36000 do
    if pred() then
      return true
    end
    coroutine.yield()
  end
  error("timed out waiting")
end

function M.press(names, frames)
  M.hold(names)
  M.wait(frames or 4)
  M.hold({})
  M.wait(4)
end

local subscription
subscription = emu.add_machine_frame_notifier(function()
  for i = #tasks, 1, -1 do
    local ok, err = coroutine.resume(tasks[i])
    if not ok then
      print("harness error: " .. tostring(err))
      machine:exit()
    end
    if coroutine.status(tasks[i]) == "dead" then
      table.remove(tasks, i)
    end
  end
  apply_inputs()
end)
M.subscription = subscription

function M.exit()
  machine:exit()
end

--- Coin up two players, pick a character for P1 (command table row, Ryu by default) with the
--- given super art index and Ryu for P2, and return once the round accepts input.
function M.boot_to_match(super_art, p1_row)
  local A = M.ADDR
  M.wait(300)
  M.wait_until(function()
    if M.u8(A.select_state[1]) == 2 and M.u8(A.select_state[2]) == 2 then
      return true
    end
    M.press({ "Coin 1" })
    M.press({ "Coin 2" })
    M.press({ "1 Player Start" })
    M.press({ "2 Players Start" })
    M.wait(60)
    return false
  end, 200)
  for player = 1, 2 do
    local lp = player == 1 and M.P1.LP or M.P2.LP
    M.press({ lp })
    M.wait(20)
    M.w8(A.select_id[player], player == 1 and (p1_row or 2) or 2)
    M.wait_until(function()
      return M.u8(A.select_state[player]) == 4
    end, 600)
    M.wait(30)
    if player == 1 then
      M.w8(A.select_sa[1], super_art or 0)
    end
    M.press({ lp })
  end
  M.wait_until(function()
    return M.u8(A.match_state) == 2
  end, 6000)
  M.wait(240)
end

return M
