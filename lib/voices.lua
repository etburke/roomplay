-- note-on/off tracking, fan-out to PolyPerc + MIDI.
-- Voice tracking is central and core-agnostic: note-offs are the harness's
-- job (via this module), never a core's. This is the most likely place for
-- stuck-note bugs when cores switch mid-run, so all cleanup funnels through
-- all_notes_off().

local musicutil = require 'musicutil'

local M = {}

local active = {} -- [note] = { poly = bool, midi = bool, midi_chan = n }
local midi_out = nil

function M.init()
  midi_out = midi.connect(1)
end

function M.set_midi_device(n)
  midi_out = midi.connect(n)
end

local function note_off(note)
  local v = active[note]
  if not v then return end
  if v.poly then
    engine.noteOff(note)
  end
  if v.midi and midi_out then
    midi_out:note_off(note, 0, v.midi_chan)
  end
  active[note] = nil
end

-- output coupling: 0.0 = PolyPerc only, 1.0 = MIDI only, the middle band
-- (columns 8/9 on the grid, ~0.45-0.55) sends both
function M:play(note, velocity, duration, weights)
  note = util.clamp(math.floor(note + 0.5), 0, 127)
  weights = weights or {}
  local output = weights.output or 0
  local use_poly = output <= 0.55
  local use_midi = output >= 0.45

  if active[note] then
    note_off(note)
  end

  local vel01 = util.clamp(velocity or 1, 0, 1)
  if use_poly then
    engine.noteOn(note, musicutil.note_num_to_freq(note), vel01)
  end
  if use_midi and midi_out then
    midi_out:note_on(note, math.floor(vel01 * 127 + 0.5), 1)
  end

  active[note] = { poly = use_poly, midi = use_midi, midi_chan = 1 }

  local dur = math.max(duration or 0.2, 0.02)
  clock.run(function()
    clock.sleep(dur)
    note_off(note)
  end)
end

function M.all_notes_off()
  local notes = {}
  for note, _ in pairs(active) do
    table.insert(notes, note)
  end
  for _, note in ipairs(notes) do
    note_off(note)
  end
end

return M
