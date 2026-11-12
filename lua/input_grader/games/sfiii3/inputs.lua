-- Conversions between numpad notation and the game's input words.

local bits = require("input_grader.core.bits")
local C = require("input_grader.games.sfiii3.constants")

local band, bor = bits.band, bits.bor

local M = {}

M.BUTTONS = { LP = C.SW_LP, MP = C.SW_MP, HP = C.SW_HP, LK = C.SW_LK, MK = C.SW_MK, HK = C.SW_HK }
M.BUTTON_ORDER = { "LP", "MP", "HP", "LK", "MK", "HK" }

-- Numpad digit to relative lever bits (up 1, down 2, forward 4, back 8).
local RELATIVE = {
  [1] = C.LV_DOWN + C.LV_BACK, [2] = C.LV_DOWN, [3] = C.LV_DOWN + C.LV_FORWARD,
  [4] = C.LV_BACK, [5] = 0, [6] = C.LV_FORWARD,
  [7] = C.LV_UP + C.LV_BACK, [8] = C.LV_UP, [9] = C.LV_UP + C.LV_FORWARD,
}

local NUMPAD = {}
for digit, lever in pairs(RELATIVE) do NUMPAD[lever] = digit end

--- Relative lever bits (as the command tables use them) to a numpad digit.
function M.lever_to_numpad(lever)
  return NUMPAD[band(lever, C.LV_MASK)] or 5
end

function M.numpad_to_lever(digit)
  return RELATIVE[digit]
end

--- Swap forward and back into absolute left and right, as the game's pl_lvr_set undoes it.
function M.lever_to_raw(lever, facing_right)
  local vertical = band(lever, C.LV_UP + C.LV_DOWN)
  local forward, back = bits.has(lever, C.LV_FORWARD), bits.has(lever, C.LV_BACK)
  local raw = vertical
  if forward then raw = bor(raw, facing_right and C.RAW_RIGHT or C.RAW_LEFT) end
  if back then raw = bor(raw, facing_right and C.RAW_LEFT or C.RAW_RIGHT) end
  return raw
end

function M.raw_to_lever(raw, facing_right)
  local lever = band(raw, C.LV_UP + C.LV_DOWN)
  local left, right = bits.has(raw, C.RAW_LEFT), bits.has(raw, C.RAW_RIGHT)
  if (facing_right and right) or (not facing_right and left) then lever = bor(lever, C.LV_FORWARD) end
  if (facing_right and left) or (not facing_right and right) then lever = bor(lever, C.LV_BACK) end
  return lever
end

function M.buttons_word(names)
  local word = 0
  for name in string.gmatch(names or "", "%a%a") do
    local b = M.BUTTONS[name]
    if not b then error("unknown button " .. name) end
    word = bor(word, b)
  end
  return word
end

function M.buttons_text(word)
  local parts = {}
  for _, name in ipairs(M.BUTTON_ORDER) do
    if bits.has(word, M.BUTTONS[name]) then table.insert(parts, name) end
  end
  return table.concat(parts, "+")
end

--- Expand a script into one raw word per frame.
--- A script is a list of { numpad digit, frames, buttons? }, e.g. { {2, 3}, {3, 1}, {6, 1, "LP"} }.
function M.timeline(script, facing_right)
  local frames = {}
  for _, entry in ipairs(script) do
    local word = bor(M.lever_to_raw(RELATIVE[entry[1]], facing_right), M.buttons_word(entry[3]))
    for _ = 1, entry[2] do table.insert(frames, word) end
  end
  return frames
end

--- Numpad text of a record's steps, e.g. "2 3 6", for steps that ask for a lever word.
function M.step_text(step)
  local sw = bits.u16(step[4])
  if band(sw, C.LV_EXACT) ~= 0 or sw == 0 then
    return tostring(M.lever_to_numpad(sw))
  end
  if band(sw, C.SW_SHOT + C.SW_PP + C.SW_KK) ~= 0 and band(sw, C.LV_MASK) == 0 then
    return M.buttons_text(sw)
  end
  return "any " .. M.lever_to_numpad(sw)
end

return M
