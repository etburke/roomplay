-- slow-drifting chord tones within the detected key, changing every few
-- bars. Drift rate <- autonomy: more autonomy drifts faster/on its own,
-- less autonomy holds a chord longer (mirrors input by staying put).

local musicutil = require 'musicutil'

local M = { name = "harmonic_field" }

function M:params(id)
  self.id = id
  params:add_number(id .. "_own_center", "own center (note)", 24, 96, 60)
  params:add_control(id .. "_bars_min", "change every (bars, min)", controlspec.new(1, 16, "lin", 1, 2))
  params:add_control(id .. "_bars_max", "change every (bars, max)", controlspec.new(1, 32, "lin", 1, 8))
  params:add_number(id .. "_beats_per_bar", "beats/bar", 2, 12, 4)
end

function M:init()
  self.chord = { 0, 2, 4 } -- scale-degree indices
  self.next_change_beat = 0
end

function M:pick(ctx, event)
  local root = ctx.analysis.key.root or 0
  local mode = ctx.analysis.key.mode or "major"
  local scale = musicutil.generate_scale(root, mode, 4)
  local autonomy = ctx.weights.autonomy

  if ctx.beat >= self.next_change_beat then
    local bpb = params:get(self.id .. "_beats_per_bar")
    local bmin = params:get(self.id .. "_bars_min")
    local bmax = params:get(self.id .. "_bars_max")
    local bars = bmax - (bmax - bmin) * autonomy
    self.next_change_beat = ctx.beat + bars * bpb
    local degree = math.random(0, #scale - 1)
    self.chord = { degree, (degree + 2) % #scale, (degree + 4) % #scale }
  end

  local own_center = params:get(self.id .. "_own_center")
  local reg_w = ctx.weights.register
  local target = own_center + ((ctx.analysis.register.note or own_center) - own_center) * reg_w

  local best, best_dist = nil, math.huge
  for octave = -2, 2 do
    for _, deg in ipairs(self.chord) do
      local note = scale[(deg % #scale) + 1] + octave * 12
      local d = math.abs(note - target)
      if d < best_dist then
        best, best_dist = note, d
      end
    end
  end

  return best and util.clamp(best, 0, 127) or nil
end

return M
