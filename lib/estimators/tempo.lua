-- IOI histogram + autocorrelation → (bpm, conf)
-- Write this yourself; do not use BeatTrack.kr — it locks slowly and is opaque.

local Tempo = {}
Tempo.__index = Tempo

local WINDOW = 8.0        -- seconds of onset history to keep
local BIN = 0.01          -- 10ms bins
local MIN_LAG = 0.2        -- 300 bpm
local MAX_LAG = 1.0        -- 60 bpm
local MIN_ONSETS = 4
local PREFERRED_LO = 60
local PREFERRED_HI = 140

function Tempo.new()
  return setmetatable({
    onsets = {},
    last_bpm = 120,
    last_conf = 0,
  }, Tempo)
end

function Tempo:on_onset(t)
  table.insert(self.onsets, t)
  self:_prune(t)
end

function Tempo:_prune(t)
  while #self.onsets > 0 and t - self.onsets[1] > WINDOW do
    table.remove(self.onsets, 1)
  end
end

-- the histogram of all pairwise onset-time differences within the window
-- *is* the autocorrelation of the onset impulse train; build both in one pass.
local function build_histogram(onsets)
  local n_bins = math.floor((MAX_LAG - MIN_LAG) / BIN) + 1
  local hist = {}
  for i = 1, n_bins do hist[i] = 0 end
  local n = #onsets
  for i = 1, n do
    for j = i + 1, n do
      local dt = onsets[j] - onsets[i]
      if dt > MAX_LAG then break end
      if dt >= MIN_LAG then
        local bin = math.floor((dt - MIN_LAG) / BIN) + 1
        if bin >= 1 and bin <= n_bins then
          hist[bin] = hist[bin] + 1
        end
      end
    end
  end
  return hist, n_bins
end

local function bin_to_lag(bin)
  return MIN_LAG + (bin - 0.5) * BIN
end

local function lag_to_bpm(lag)
  return 60.0 / lag
end

-- prefer the octave (half/double period) that lands the resulting bpm inside
-- the musically likely 60-140 range
local function resolve_octave(bpm)
  while bpm < PREFERRED_LO do bpm = bpm * 2 end
  while bpm > PREFERRED_HI do bpm = bpm / 2 end
  return bpm
end

function Tempo:current(t)
  self:_prune(t)
  if #self.onsets < MIN_ONSETS then
    self.last_conf = 0
    return self.last_bpm, self.last_conf
  end

  local hist, n_bins = build_histogram(self.onsets)
  local peak_bin, peak_val, sum = 1, 0, 0
  for i = 1, n_bins do
    sum = sum + hist[i]
    if hist[i] > peak_val then
      peak_val = hist[i]
      peak_bin = i
    end
  end

  if peak_val <= 0 then
    self.last_conf = 0
    return self.last_bpm, self.last_conf
  end

  local mean = sum / n_bins
  local lag = bin_to_lag(peak_bin)
  local bpm = resolve_octave(lag_to_bpm(lag))
  local sharpness = (peak_val - mean) / (peak_val + mean + 1e-6)

  self.last_bpm = bpm
  self.last_conf = util.clamp(sharpness, 0, 1)
  return self.last_bpm, self.last_conf
end

return Tempo
