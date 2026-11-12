local M = {}

local data

function M.commands()
  data = data or dofile("lua/input_grader/games/sfiii3/commands.lua")
  return data
end

function M.fighter(row)
  return M.commands().fighters[row]
end

local function show(v)
  if type(v) == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end

function M.eq(actual, expected, label)
  if actual ~= expected then
    error((label and (label .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

function M.truthy(v, label)
  if not v then
    error((label or "expected a truthy value") .. ", got " .. show(v), 2)
  end
end

function M.contains(haystack, needle)
  if not string.find(haystack, needle, 1, true) then
    error("expected " .. show(haystack) .. " to contain " .. show(needle), 2)
  end
end

return M
