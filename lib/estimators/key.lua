-- 12-bin chroma histogram + Krumhansl-Schmuckler → (root, mode, conf)

local Key = {}
Key.__index = Key

local WINDOW = 25.0 -- seconds

-- Krumhansl-Schmuckler key profiles
local MAJOR_PROFILE = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 }
local MINOR_PROFILE = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 }

function Key.new()
  return setmetatable({
    samples = {},     -- { t, pitch_class, weight }
    last_root = 0,
    last_mode = "major",
    last_conf = 0,
  }, Key)
end

-- weighted by amplitude at the moment of the pitch sample (a proxy for
-- pitch-tracking confidence, since Pitch.kr only exposes a boolean hasFreq)
function Key:on_pitch(note, amp, t)
  local pc = math.floor(note + 0.5) % 12
  local weight = util.clamp(amp or 1, 0, 1)
  table.insert(self.samples, { t = t, pc = pc, weight = weight })
end

function Key:_prune(t)
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

local function rotate(profile, root)
  local r = {}
  for i = 0, 11 do
    r[i + 1] = profile[((i - root) % 12) + 1]
  end
  return r
end

local function correlate(chroma, profile)
  local n = 12
  local mean_a, mean_b = 0, 0
  for i = 1, n do
    mean_a = mean_a + chroma[i]
    mean_b = mean_b + profile[i]
  end
  mean_a, mean_b = mean_a / n, mean_b / n

  local num, da, db = 0, 0, 0
  for i = 1, n do
    local x = chroma[i] - mean_a
    local y = profile[i] - mean_b
    num = num + x * y
    da = da + x * x
    db = db + y * y
  end
  local denom = math.sqrt(da * db)
  if denom < 1e-9 then return 0 end
  return num / denom
end

function Key:current(t)
  self:_prune(t)

  local chroma = {}
  for i = 1, 12 do chroma[i] = 0 end
  local total_weight = 0
  for _, s in ipairs(self.samples) do
    chroma[s.pc + 1] = chroma[s.pc + 1] + s.weight
    total_weight = total_weight + s.weight
  end

  if total_weight < 1e-6 then
    self.last_conf = 0
    return self.last_root, self.last_mode, self.last_conf
  end

  local candidates = {}
  for root = 0, 11 do
    table.insert(candidates, { root = root, mode = "major", corr = correlate(chroma, rotate(MAJOR_PROFILE, root)) })
    table.insert(candidates, { root = root, mode = "minor", corr = correlate(chroma, rotate(MINOR_PROFILE, root)) })
  end
  table.sort(candidates, function(a, b) return a.corr > b.corr end)

  local best, second = candidates[1], candidates[2]
  self.last_root = best.root
  self.last_mode = best.mode
  self.last_conf = util.clamp(best.corr - second.corr, 0, 1)

  return self.last_root, self.last_mode, self.last_conf
end

return Key
