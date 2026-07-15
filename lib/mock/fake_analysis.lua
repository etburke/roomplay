-- scripted analysis snapshot stream for guitar-free testing.
-- Not throwaway: it's the only way to test cores deterministically, keep it working.
--
-- Timeline (loops every LOOP_LEN seconds):
--   0..20s   all confidences ramp 0 -> 1, steady 96bpm D dorian
--   20..30s  hold at high confidence
--   30..40s  confidences collapse (tempo first, key holds longer) — simulates
--            the player stopping / an ambient swell
--   40..44s  silence
local FakeAnalysis = {}
FakeAnalysis.__index = FakeAnalysis

local LOOP_LEN = 44.0
local BASE_BPM = 96.2
local BASE_ROOT = 2 -- D
local BASE_MODE = "dorian"
local BASE_RATE = 3.4
local BASE_REGISTER = 57.3

local function ease(x)
  x = util.clamp(x, 0, 1)
  return x * x * (3 - 2 * x)
end

function FakeAnalysis.new()
  return setmetatable({
    t0 = nil,
    next_onset = 0,
    snapshot = {
      tempo = { bpm = BASE_BPM, conf = 0 },
      key = { root = BASE_ROOT, mode = BASE_MODE, conf = 0 },
      density = { rate = BASE_RATE, conf = 0 },
      register = { note = BASE_REGISTER, conf = 0 },
      dynamics = { level = 0, conf = 0 },
      onset = false,
    },
  }, FakeAnalysis)
end

function FakeAnalysis:start()
  self.t0 = util.time()
  self.next_onset = self.t0
end

function FakeAnalysis:current()
  return self.snapshot
end

function FakeAnalysis:update(t)
  if not self.t0 then self:start() end
  local phase = (t - self.t0) % LOOP_LEN

  local overall_conf, tempo_conf, key_conf
  if phase < 20 then
    overall_conf = ease(phase / 20)
    tempo_conf, key_conf = overall_conf, overall_conf
  elseif phase < 30 then
    overall_conf = 1.0
    tempo_conf, key_conf = 1.0, 1.0
  elseif phase < 40 then
    local drop = ease((phase - 30) / 10)
    tempo_conf = util.clamp(1.0 - drop * 1.2, 0.02, 1.0)
    key_conf = util.clamp(1.0 - drop * 0.6, 0.15, 1.0)
    overall_conf = key_conf
  else
    tempo_conf, key_conf = 0.03, 0.1
    overall_conf = 0.05
  end

  local wobble = math.sin((t - self.t0) * 0.35)
  local snap = self.snapshot
  snap.tempo.bpm = BASE_BPM + wobble * 1.5
  snap.tempo.conf = tempo_conf
  snap.key.root = BASE_ROOT
  snap.key.mode = BASE_MODE
  snap.key.conf = key_conf
  snap.density.rate = BASE_RATE * (0.5 + 0.5 * overall_conf) + wobble * 0.3
  snap.density.conf = overall_conf
  snap.register.note = BASE_REGISTER + wobble * 4
  snap.register.conf = overall_conf
  snap.dynamics.level = util.clamp(0.35 + 0.3 * math.sin((t - self.t0) * 1.7) * overall_conf, 0, 1)
  snap.dynamics.conf = util.clamp(overall_conf + 0.2, 0, 1)

  snap.onset = false
  if overall_conf > 0.05 and snap.density.rate > 0 then
    if t >= self.next_onset then
      snap.onset = true
      self.next_onset = t + (1.0 / snap.density.rate)
    end
  end
end

return FakeAnalysis
