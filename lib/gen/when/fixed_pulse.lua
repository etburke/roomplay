-- fires every N beats, regardless of tick granularity

local M = { name = "fixed_pulse" }

function M:params(id)
  self.id = id
  params:add_control(id .. "_every", "every (beats)", controlspec.new(0.125, 8, "lin", 0.125, 1, "beats"))
  params:add_control(id .. "_velocity", "velocity", controlspec.new(0, 1, "lin", 0, 0.8))
  params:add_control(id .. "_duration", "duration (beats)", controlspec.new(0.05, 4, "lin", 0, 0.25, "beats"))
end

function M:init()
  self.last_index = nil
end

function M:tick(ctx)
  local every = params:get(self.id .. "_every")
  if every <= 0 then return nil end
  local index = math.floor(ctx.beat / every + 1e-6)
  if index == self.last_index then return nil end
  self.last_index = index
  return {
    velocity = params:get(self.id .. "_velocity"),
    duration = params:get(self.id .. "_duration"),
  }
end

return M
