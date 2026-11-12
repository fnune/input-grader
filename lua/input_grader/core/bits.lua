-- Bitwise operations on 16-bit words for every Lua the grader runs on: FBNeo and LuaJIT ship
-- the `bit` library (Lua 5.1 has no operators), Lua 5.3+ has native operators and no `bit`.

local M = {}

if type(bit) == "table" and bit.band then
  M.band, M.bor, M.bxor, M.lshift = bit.band, bit.bor, bit.bxor, bit.lshift
else
  local native = load([[
    return {
      band = function(a, b) return a & b end,
      bor = function(a, b) return a | b end,
      bxor = function(a, b) return a ~ b end,
      lshift = function(a, n) return a << n end,
    }
  ]])()
  M.band, M.bor, M.bxor, M.lshift = native.band, native.bor, native.bxor, native.lshift
end

local band = M.band

function M.u16(v)
  return band(v, 0xFFFF)
end

function M.bnot16(v)
  return band(M.bxor(v, 0xFFFF), 0xFFFF)
end

function M.has(v, mask)
  return band(v, mask) ~= 0
end

return M
