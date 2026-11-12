-- Bench sessions: count attempts between start and stop, and summarise them per move.
-- Works on the game-agnostic attempt records every game module produces.

local Bench = {}
Bench.__index = Bench

--- @param clock function returning seconds (injected: os.time in the emulator, a fake in tests)
function Bench.new(clock)
  return setmetatable({ clock = clock, running = false, attempts = {} }, Bench)
end

function Bench:start(target)
  self.running, self.attempts, self.target = true, {}, target
  self.started_at, self.stopped_at = self.clock(), nil
end

function Bench:stop()
  self.running = false
  self.stopped_at = self.clock()
  return self:summary()
end

function Bench:record(attempt)
  if not self.running then
    return false
  end
  if self.target and attempt.id ~= self.target then
    return false
  end
  table.insert(self.attempts, attempt)
  return true
end

local function rate(ok, n)
  if n == 0 then
    return nil
  end
  return math.floor(100 * ok / n + 0.5)
end

local function median(values)
  if #values == 0 then
    return nil
  end
  table.sort(values)
  return values[math.floor((#values + 1) / 2)]
end

--- Per move: attempts, successes, rate per side, error counts, median total and margin, and
--- the rate of the first and last ten attempts.
function Bench:summary()
  local moves, order = {}, {}
  for _, a in ipairs(self.attempts) do
    local m = moves[a.id]
    if not m then
      m = {
        id = a.id,
        name = a.move,
        notation = a.notation,
        n = 0,
        ok = 0,
        sides = {},
        errors = {},
        totals = {},
        margins = {},
        results = {},
      }
      moves[a.id] = m
      table.insert(order, m)
    end
    m.n = m.n + 1
    if a.ok then
      m.ok = m.ok + 1
    end
    table.insert(m.results, a.ok)
    local side = m.sides[a.side or "?"] or { n = 0, ok = 0 }
    side.n = side.n + 1
    if a.ok then
      side.ok = side.ok + 1
    end
    m.sides[a.side or "?"] = side
    if a.error then
      m.errors[a.error.code] = (m.errors[a.error.code] or 0) + 1
    end
    if a.total then
      table.insert(m.totals, a.total)
    end
    if a.margin then
      table.insert(m.margins, a.margin)
    end
  end
  for _, m in ipairs(order) do
    m.rate = rate(m.ok, m.n)
    for _, side in pairs(m.sides) do
      side.rate = rate(side.ok, side.n)
    end
    local top, count = nil, 0
    for code, c in pairs(m.errors) do
      if c > count or (c == count and code < (top or "~")) then
        top, count = code, c
      end
    end
    m.top_error = top and { code = top, count = count } or nil
    m.median_total, m.median_margin = median(m.totals), median(m.margins)
    local first, last, nf, nl = 0, 0, 0, 0
    for i, ok in ipairs(m.results) do
      if i <= 10 then
        nf = nf + 1
        if ok then
          first = first + 1
        end
      end
      if i > #m.results - 10 then
        nl = nl + 1
        if ok then
          last = last + 1
        end
      end
    end
    m.first_rate, m.last_rate = rate(first, nf), rate(last, nl)
  end
  table.sort(order, function(a, b)
    return a.n > b.n
  end)
  return {
    running = self.running,
    target = self.target,
    moves = order,
    seconds = (self.stopped_at or self.clock()) - (self.started_at or self.clock()),
  }
end

return Bench
