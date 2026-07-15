-- weighted random walk over a scale derived from analysis.key, biased
-- toward analysis.register.note. key coupling blends scale-tone weight vs.
-- chromatic uniformity; register coupling blends the walk's home center vs.
-- the detected pitch centroid.

local musicutil = require 'musicutil'

local M = { name = "scale_walk" }

function M:params(id)
  self.id = id
  params:add_number(id .. "_own_center", "own center (note)", 24, 96, 60)
  params:add_control(id .. "_span", "walk span (semitones)", controlspec.new(1, 24, "lin", 1, 7))
end

function M:init()
  self.current_note = params and params:get(self.id .. "_own_center") or 60
end

local function in_scale(scale, n)
  local pc = n % 12
  for _, sn in ipairs(scale) do
    if sn % 12 == pc then return true end
  end
  return false
end

function M:pick(ctx, event)
  local root = ctx.analysis.key.root or 0
  local mode = ctx.analysis.key.mode or "major"
  local scale = musicutil.generate_scale(root, mode, 8)

  local key_w = ctx.weights.key
  local reg_w = ctx.weights.register
  local own_center = params:get(self.id .. "_own_center")
  local span = params:get(self.id .. "_span")
  local target_center = own_center + ((ctx.analysis.register.note or own_center) - own_center) * reg_w

  local lo = math.floor(self.current_note - span)
  local hi = math.floor(self.current_note + span)

  local candidates, weights_list, total = {}, {}, 0
  for n = lo, hi do
    local scale_w = in_scale(scale, n) and 1.0 or (1.0 - key_w)
    if scale_w > 0.0001 then
      local dist = math.abs(n - target_center)
      local prox_w = 1.0 / (1.0 + dist * dist * 0.05)
      local w = scale_w * prox_w
      if w > 0.0001 then
        table.insert(candidates, n)
        table.insert(weights_list, w)
        total = total + w
      end
    end
  end

  if total <= 0 or #candidates == 0 then
    return util.clamp(self.current_note, 0, 127)
  end

  local r = math.random() * total
  local acc = 0
  local chosen = candidates[#candidates]
  for i, w in ipairs(weights_list) do
    acc = acc + w
    if r <= acc then
      chosen = candidates[i]
      break
    end
  end

  self.current_note = chosen
  return util.clamp(chosen, 0, 127)
end

return M
