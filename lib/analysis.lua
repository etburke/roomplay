-- poll handling, normalizes engine -> estimator input.
--
-- analysis.current() returns:
-- {
--   tempo    = { bpm = 96.2,  conf = 0.81 },
--   key      = { root = 2, mode = "dorian", conf = 0.64 },  -- root 0..11
--   density  = { rate = 3.4,  conf = 0.72 },                -- onsets/sec
--   register = { note = 57.3, conf = 0.55 },                -- fractional midi
--   dynamics = { level = 0.42, conf = 0.9 },                -- 0..1
--   onset    = false,                                        -- true only on the tick where onset landed
-- }

local musicutil = require 'musicutil'

local Tempo = include('lib/estimators/tempo')
local Key = include('lib/estimators/key')
local Density = include('lib/estimators/density')
local Register = include('lib/estimators/register')
local Dynamics = include('lib/estimators/dynamics')
local FakeAnalysis = include('lib/mock/fake_analysis')

local M = {}

M.mode = "fake" -- "fake" | "live"

local snapshot = {
  tempo = { bpm = 120, conf = 0 },
  key = { root = 0, mode = "major", conf = 0 },
  density = { rate = 0, conf = 0 },
  register = { note = 60, conf = 0 },
  dynamics = { level = 0, conf = 0 },
  onset = false,
}

local estimators = nil
local fake = nil
local pending_onset = false
local last_freq = 0
local polls = {}
local raw_debug = { amp = 0, freq = 0, has_freq = 0, onset_count = 0 }

function M.init(mode)
  M.mode = mode or M.mode
  estimators = {
    tempo = Tempo.new(),
    key = Key.new(),
    density = Density.new(),
    register = Register.new(),
    dynamics = Dynamics.new(),
  }
  fake = FakeAnalysis.new()
  fake:start()
  M.setup_engine_polls()
end

function M.set_mode(mode)
  M.mode = mode
end

-- raw signal ingestion, called from engine polls (live) or exercised directly in tests
function M.on_onset(t)
  pending_onset = true
  estimators.tempo:on_onset(t)
  estimators.density:on_onset(t)
end

function M.on_pitch(hz, has_freq, t)
  if has_freq and hz and hz > 0 then
    local note = musicutil.freq_to_note_num(hz)
    estimators.key:on_pitch(note, raw_debug.amp, t)
    estimators.register:on_pitch(note, raw_debug.amp, t)
  end
end

function M.on_amp(level, t)
  estimators.dynamics:on_amp(level, t)
end

function M.setup_engine_polls()
  local amp_poll = poll.set("amp", function(val)
    raw_debug.amp = val
    M.on_amp(val, util.time())
  end)
  amp_poll.time = 1 / 30
  amp_poll:start()
  table.insert(polls, amp_poll)

  local freq_poll = poll.set("freq", function(val)
    raw_debug.freq = val
    last_freq = val
  end)
  freq_poll.time = 1 / 30
  freq_poll:start()
  table.insert(polls, freq_poll)

  local hasfreq_poll = poll.set("has_freq", function(val)
    raw_debug.has_freq = val
    M.on_pitch(last_freq, val > 0.5, util.time())
  end)
  hasfreq_poll.time = 1 / 30
  hasfreq_poll:start()
  table.insert(polls, hasfreq_poll)

  local onset_poll = poll.set("onset_count", function(val)
    if val > raw_debug.onset_count then
      M.on_onset(util.time())
    end
    raw_debug.onset_count = val
  end)
  onset_poll.time = 1 / 30
  onset_poll:start()
  table.insert(polls, onset_poll)
end

function M.cleanup()
  for _, p in ipairs(polls) do
    p:stop()
  end
  polls = {}
end

function M.debug()
  return raw_debug
end

local function update(t)
  if M.mode == "fake" then
    fake:update(t)
    local f = fake:current()
    snapshot.tempo.bpm, snapshot.tempo.conf = f.tempo.bpm, f.tempo.conf
    snapshot.key.root, snapshot.key.mode, snapshot.key.conf = f.key.root, f.key.mode, f.key.conf
    snapshot.density.rate, snapshot.density.conf = f.density.rate, f.density.conf
    snapshot.register.note, snapshot.register.conf = f.register.note, f.register.conf
    snapshot.dynamics.level, snapshot.dynamics.conf = f.dynamics.level, f.dynamics.conf
    snapshot.onset = f.onset
  else
    snapshot.tempo.bpm, snapshot.tempo.conf = estimators.tempo:current(t)
    snapshot.key.root, snapshot.key.mode, snapshot.key.conf = estimators.key:current(t)
    snapshot.density.rate, snapshot.density.conf = estimators.density:current(t)
    snapshot.register.note, snapshot.register.conf = estimators.register:current(t)
    snapshot.dynamics.level, snapshot.dynamics.conf = estimators.dynamics:current(t)
    snapshot.onset = pending_onset
    pending_onset = false
  end
end

function M.current()
  update(util.time())
  return snapshot
end

return M
