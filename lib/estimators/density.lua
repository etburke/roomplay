-- windowed onset rate → (rate, conf)

local Density = {}
Density.__index = Density

local WINDOW = 4.0
local MIN_ONSETS_FOR_FULL_CONF = 3

function Density.new()
  return setmetatable({
    onsets = {},
  }, Density)
end

function Density:on_onset(t)
  table.insert(self.onsets, t)
  self:_prune(t)
end

function Density:_prune(t)
  while #self.onsets > 0 and t - self.onsets[1] > WINDOW do
    table.remove(self.onsets, 1)
  end
end

function Density:current(t)
  self:_prune(t)
  local n = #self.onsets
  if n == 0 then
    return 0, 0
  end
  local span = math.min(WINDOW, t - self.onsets[1] + 1e-6)
  local rate = n / span
  local conf = util.clamp(n / MIN_ONSETS_FOR_FULL_CONF, 0, 1)
  return rate, conf
end

return Density
