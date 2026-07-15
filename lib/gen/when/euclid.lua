-- euclidean rhythm: steps pulses distributed as evenly as possible
-- (bresenham distribution, equivalent to Bjorklund's algorithm)

local M = { name = "euclid" }

function M:params(id)
  self.id = id
  params:add_number(id .. "_steps", "steps", 2, 32, 16)
  params:add_number(id .. "_pulses", "pulses", 0, 32, 5)
  params:add_number(id .. "_rotate", "rotate", 0, 31, 0)
  params:add_number(id .. "_division", "steps/beat", 1, 8, 4)
  params:add_control(id .. "_velocity", "velocity", controlspec.new(0, 1, "lin", 0, 0.8))
  params:add_control(id .. "_duration", "duration (beats)", controlspec.new(0.05, 4, "lin", 0, 0.2, "beats"))
end

local function build_pattern(steps, pulses)
  local pattern = {}
  if pulses <= 0 then
    for i = 1, steps do pattern[i] = false end
    return pattern
  end
  if pulses >= steps then
    for i = 1, steps do pattern[i] = true end
    return pattern
  end
  local bucket = 0
  for i = 1, steps do
    bucket = bucket + pulses
    if bucket >= steps then
      bucket = bucket - steps
      pattern[i] = true
    else
      pattern[i] = false
    end
  end
  return pattern
end

function M:init()
  self.last_gstep = nil
  self.cache_steps = nil
  self.cache_pulses = nil
  self.pattern = {}
end

function M:tick(ctx)
  local steps = params:get(self.id .. "_steps")
  local pulses = math.min(params:get(self.id .. "_pulses"), steps)
  local rotate = params:get(self.id .. "_rotate") % steps
  local division = params:get(self.id .. "_division")

  if steps ~= self.cache_steps or pulses ~= self.cache_pulses then
    self.pattern = build_pattern(steps, pulses)
    self.cache_steps, self.cache_pulses = steps, pulses
  end

  local gstep = math.floor(ctx.beat * division + 1e-6)
  if gstep == self.last_gstep then return nil end
  self.last_gstep = gstep

  local idx = ((gstep + rotate) % steps) + 1
  if not self.pattern[idx] then return nil end

  return {
    velocity = params:get(self.id .. "_velocity"),
    duration = params:get(self.id .. "_duration"),
  }
end

return M
