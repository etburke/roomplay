-- N steps, each with a fire probability + a pitch weight. The vectors slowly
-- random-walk (mutation rate <- autonomy). Global probability multiplier <-
-- density. Uses the when:tick() escape hatch to emit pitch directly, since
-- the pitch weight lives on the step, not in a `what` core.

local M = { name = "prob_ring" }

function M:params(id)
  self.id = id
  params:add_number(id .. "_steps", "steps", 2, 32, 16)
  params:add_number(id .. "_division", "steps/beat", 1, 8, 4)
  params:add_control(id .. "_mutate_amt", "mutation amount", controlspec.new(0, 1, "lin", 0, 0.15))
  params:add_control(id .. "_velocity", "velocity", controlspec.new(0, 1, "lin", 0, 0.7))
  params:add_control(id .. "_duration", "duration (beats)", controlspec.new(0.05, 4, "lin", 0, 0.2, "beats"))
end

function M:init()
  self.prob = {}
  self.pitch_bias = {}
  self.last_gstep = nil
  self.last_mutate_beat = 0
end

function M:_ensure(idx)
  if not self.prob[idx] then
    self.prob[idx] = math.random()
    self.pitch_bias[idx] = math.random() * 2 - 1
  end
end

function M:_mutate(ctx, steps)
  if ctx.beat - self.last_mutate_beat < 1 then return end
  self.last_mutate_beat = ctx.beat
  local amt = params:get(self.id .. "_mutate_amt")
  local autonomy = ctx.weights.autonomy
  for i = 1, steps do
    self:_ensure(i)
    if math.random() < autonomy * 0.3 then
      self.prob[i] = util.clamp(self.prob[i] + (math.random() * 2 - 1) * amt, 0, 1)
      self.pitch_bias[i] = util.clamp(self.pitch_bias[i] + (math.random() * 2 - 1) * amt, -1, 1)
    end
  end
end

-- 0.0 = fixed baseline density, 1.0 = multiplier tracks the measured onset rate
local function density_multiplier(ctx)
  local base_mult = 0.5
  local rate_mult = util.clamp((ctx.analysis.density.rate or 0) / 4, 0, 2)
  return base_mult + (rate_mult - base_mult) * ctx.weights.density
end

function M:tick(ctx)
  local steps = params:get(self.id .. "_steps")
  local division = params:get(self.id .. "_division")
  self:_mutate(ctx, steps)

  local gstep = math.floor(ctx.beat * division + 1e-6)
  if gstep == self.last_gstep then return nil end
  self.last_gstep = gstep

  local idx = (gstep % steps) + 1
  self:_ensure(idx)

  local p = util.clamp(self.prob[idx] * density_multiplier(ctx), 0, 1)
  if math.random() > p then return nil end

  local center = ctx.analysis.register.note or 60
  local note = util.clamp(math.floor(center + self.pitch_bias[idx] * 12 + 0.5), 0, 127)

  return {
    velocity = params:get(self.id .. "_velocity"),
    duration = params:get(self.id .. "_duration"),
    note = note,
  }
end

return M
