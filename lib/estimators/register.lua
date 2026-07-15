-- rolling pitch centroid → (midi_note, conf)

local Register = {}
Register.__index = Register

local WINDOW = 4.0
local FULL_CONF_SAMPLES = 10

function Register.new()
  return setmetatable({
    samples = {}, -- { t, note, weight }
    last_note = 60,
  }, Register)
end

function Register:on_pitch(note, amp, t)
  table.insert(self.samples, { t = t, note = note, weight = util.clamp(amp or 1, 0, 1) })
end

function Register:_prune(t)
  local i = 1
  while i <= #self.samples and t - self.samples[i].t > WINDOW do
    i = i + 1
  end
  if i > 1 then
    local kept = {}
    for j = i, #self.samples do table.insert(kept, self.samples[j]) end
    self.samples = kept
  end
end

function Register:current(t)
  self:_prune(t)
  local n = #self.samples
  if n == 0 then
    return self.last_note, 0
  end

  local sum_w, sum_wn = 0, 0
  for _, s in ipairs(self.samples) do
    sum_w = sum_w + s.weight
    sum_wn = sum_wn + s.weight * s.note
  end

  if sum_w < 1e-6 then
    return self.last_note, 0
  end

  self.last_note = sum_wn / sum_w
  local conf = util.clamp(n / FULL_CONF_SAMPLES, 0, 1)
  return self.last_note, conf
end

return Register
