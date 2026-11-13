-- Writes design/scenarios.js: real grader output for scripted attempts, for the overlay mock.
-- Usage (repo root): lua design/export_scenarios.lua > design/scenarios.js

package.path = "lua/?.lua;lua/?/init.lua;tests/?.lua;" .. package.path

local Game = require("input_grader.games.sfiii3.game")
local sources = require("input_grader.games.sfiii3.sources")
local inputs = require("input_grader.games.sfiii3.inputs")
local T = require("helpers")

local SCENARIOS = {
  { "Clean Hadoken", { { 5, 6 }, { 2, 2 }, { 3, 2 }, { 6, 1, "LP" } } },
  { "cr.LK held into Hadoken", { { 5, 4 }, { 2, 1, "LK" }, { 2, 18 }, { 3, 2 }, { 6, 1, "LP" } } },
  { "Skipped diagonal", { { 5, 6 }, { 2, 3 }, { 6, 1, "LP" } } },
  { "Slow diagonal", { { 5, 6 }, { 2, 1 }, { 1, 12 }, { 3, 1 }, { 6, 1, "LP" } } },
  { "Late button", { { 5, 6 }, { 2, 1 }, { 3, 1 }, { 6, 14 }, { 6, 1, "LP" } } },
  { "Early button", { { 5, 6 }, { 2, 1 }, { 3, 1, "LP" }, { 6, 14, "LP" } } },
  { "Up cancels", { { 5, 6 }, { 2, 2 }, { 3, 1 }, { 8, 1 }, { 6, 1, "LP" } } },
  { "Shoryuken", { { 5, 6 }, { 6, 2 }, { 5, 2 }, { 2, 1 }, { 3, 1, "HP" } } },
  { "Super, fast", { { 5, 6 }, { 2, 1 }, { 3, 1 }, { 6, 1 }, { 2, 1 }, { 3, 1 }, { 6, 1, "LP" } } },
  { "Super without the last 6", { { 5, 6 }, { 2, 1 }, { 3, 1 }, { 6, 1 }, { 2, 1 }, { 3, 1, "LP" } } },
  { "Super, 6 then punch", { { 5, 6 }, { 2, 1 }, { 3, 1 }, { 6, 1 }, { 2, 1 }, { 3, 1 }, { 6, 3 }, { 6, 1, "LP" } } },
  { "Super, sloppy but in", { { 5, 6 }, { 2, 3 }, { 3, 4 }, { 6, 6 }, { 2, 9 }, { 3, 5 }, { 6, 2, "LP" } } },
}

local function json(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local parts = {}
      for _, x in ipairs(v) do
        table.insert(parts, json(x))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do
      table.insert(keys, k)
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      table.insert(parts, string.format("%q:%s", k, json(v[k])))
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then
    return string.format("%q", v)
  elseif t == "nil" then
    return "null"
  end
  return tostring(v)
end

local out = {}
for _, sc in ipairs(SCENARIOS) do
  local src = sources.sim(T.commands(), 2, 0)
  local game = Game.new(src, T.commands())
  local timeline = inputs.timeline(sc[2], true)
  for _ = 1, 30 do
    table.insert(timeline, 0)
  end
  local attempt
  for _, raw in ipairs(timeline) do
    src:push(raw, true)
    for _, a in ipairs(game:update()) do
      attempt = attempt or a
    end
  end
  table.insert(out, { name = sc[1], attempt = attempt })
end
print("window.SCENARIOS = " .. json(out) .. ";")
