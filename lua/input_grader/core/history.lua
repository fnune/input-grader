local History = {}
History.__index = History

function History.new(size)
  return setmetatable({ size = size, items = {}, last = 0 }, History)
end

function History:push(frame, record)
  record.frame = frame
  self.items[frame % self.size] = record
  self.last = frame
end

--- The record of `frame`, or nil when it has scrolled out.
function History:at(frame)
  if frame > self.last or frame <= self.last - self.size then
    return nil
  end
  local item = self.items[frame % self.size]
  if item and item.frame == frame then
    return item
  end
  return nil
end

--- Records from `first` to `last` (inclusive) that are still kept, oldest first.
function History:range(first, last)
  local out = {}
  for f = math.max(first, self.last - self.size + 1), math.min(last, self.last) do
    local item = self:at(f)
    if item then
      table.insert(out, item)
    end
  end
  return out
end

return History
