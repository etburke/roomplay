-- amplitude envelope → (level, conf)

local Dynamics = {}
Dynamics.__index = Dynamics

local WINDOW = 0.3 -- smoothing time constant, seconds
local STALE_AFTER = WINDOW * 4

function Dynamics.new()
  return setmetatable({
    level = 0,
    last_t = nil,
    has_data = false,
  }, Dynamics)
end

function Dynamics:on_amp(level, t)
  local dt = self.last_t and math.max(t - self.last_t, 0) or WINDOW
  self.last_t = t
  local alpha = 1 - math.exp(-dt / WINDOW)
  self.level = self.level + (util.clamp(level, 0, 1) - self.level) * alpha
  self.has_data = true
end

function Dynamics:current(t)
  if not self.has_data then
    return 0, 0
  end
  local age = t - self.last_t
  local conf = util.clamp(1 - (age / STALE_AFTER), 0, 1)
  return util.clamp(self.level, 0, 1), conf
end

return Dynamics
