-- roomplay
-- listens to a line-in guitar signal, estimates tempo/key/density/register/
-- dynamics, and generates accompaniment whose coupling to those estimates
-- is performed on a 16x8 monome grid.
--
-- you never place a note. you tune how porous the system is to what
-- you're playing.
--
-- E2/E3 in the params menu, or the grid, sets the 8 coupling faders.
-- K2: toggle debug screen. K3: panic (all notes off).

-- Engine_RoomAnalysis both analyzes the line-in signal and synthesizes
-- output voices: norns loads exactly one SuperCollider engine per script,
-- so the two concerns live in one engine.
engine.name = "RoomAnalysis"

local musicutil = require "musicutil"

local analysis = include("lib/analysis")
local couplings = include("lib/couplings")
local harness = include("lib/harness")
local gridui = include("lib/gridui")
local voices = include("lib/voices")
local registry = include("lib/gen/registry")

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

local screen_debug = false
local screen_metro = nil

local function set_group_visible(prefix, visible)
  for _, p in ipairs(params.params) do
    if p.id and string.sub(p.id, 1, #prefix) == prefix then
      if visible then params:show(p.id) else params:hide(p.id) end
    end
  end
end

local function select_when(index)
  local prev = harness.when_core
  if prev then set_group_visible(prev.id, false) end
  harness.set_when(index)
  set_group_visible(harness.when_core.id, true)
end

local function select_what(index)
  local prev = harness.what_core
  if prev then set_group_visible(prev.id, false) end
  harness.set_what(index)
  set_group_visible(harness.what_core.id, true)
end

function init()
  analysis.init("fake")
  couplings.init()
  voices.init()

  params:add_separator("roomplay_general", "roomplay")
  params:add_option("analysis_source", "analysis source", { "fake", "live" }, 1)
  params:add_number("base_tempo", "base tempo (free-running)", 20, 300, 120)
  params:add_number("midi_device", "midi device", 1, 16, 1)

  params:add_separator("roomplay_engine", "engine tuning")
  params:add_control("pitch_amp_threshold", "pitch amp threshold", controlspec.new(0, 1, "lin", 0, 0.02))
  params:add_control("pitch_median", "pitch median filter", controlspec.new(1, 7, "lin", 1, 1))

  params:add_separator("roomplay_cores", "generative cores")
  params:add_option("when_core", "when core", registry.when_names(), 1)
  params:add_option("what_core", "what core", registry.what_names(), 1)

  params:add_separator("roomplay_core_params", "core params")
  for _, entry in ipairs(registry.when) do
    entry.module.id = "when_" .. entry.key
    entry.module:params(entry.module.id)
  end
  for _, entry in ipairs(registry.what) do
    entry.module.id = "what_" .. entry.key
    entry.module:params(entry.module.id)
  end
  for _, entry in ipairs(registry.when) do set_group_visible(entry.module.id, false) end
  for _, entry in ipairs(registry.what) do set_group_visible(entry.module.id, false) end

  params:set_action("analysis_source", function(i)
    analysis.set_mode(i == 2 and "live" or "fake")
  end)
  params:set_action("midi_device", function(v) voices.set_midi_device(v) end)
  params:set_action("pitch_amp_threshold", function(v) engine.ampThreshold(v) end)
  params:set_action("pitch_median", function(v) engine.pitchMedian(v) end)
  params:set_action("when_core", function(v) select_when(v) end)
  params:set_action("what_core", function(v) select_what(v) end)

  select_when(params:get("when_core"))
  select_what(params:get("what_core"))

  gridui.init()
  harness.start()

  screen_metro = metro.init(function() redraw() end, 1 / 15)
  screen_metro:start()
end

function key(n, z)
  if z ~= 1 then return end
  if n == 2 then
    screen_debug = not screen_debug
  elseif n == 3 then
    voices.all_notes_off()
  end
end

function enc(n, d) end

local function redraw_normal(snap)
  screen.level(15)
  screen.move(0, 8)
  screen.text(string.format("%.1f bpm  (%.2f)", snap.tempo.bpm, snap.tempo.conf))
  screen.move(0, 18)
  screen.text(string.format("%s %s  (%.2f)", NOTE_NAMES[(snap.key.root % 12) + 1], snap.key.mode, snap.key.conf))
  screen.move(0, 28)
  screen.text(string.format("density %.2f/s  (%.2f)", snap.density.rate, snap.density.conf))
  screen.move(0, 38)
  screen.text(string.format("register %.1f  (%.2f)", snap.register.note, snap.register.conf))
  screen.move(0, 48)
  screen.text(string.format("dynamics %.2f  (%.2f)", snap.dynamics.level, snap.dynamics.conf))

  screen.level(4)
  screen.move(0, 60)
  local when_name = harness.when_core and harness.when_core.name or "?"
  local what_name = harness.what_core and harness.what_core.name or "?"
  screen.text(when_name .. " -> " .. what_name)
end

local function redraw_debug()
  local d = analysis.debug()
  screen.level(15)
  screen.move(0, 8)
  screen.text("DEBUG raw engine values")
  screen.move(0, 20)
  screen.text(string.format("amp        %.3f", d.amp))
  screen.move(0, 30)
  screen.text(string.format("freq       %.1f", d.freq))
  screen.move(0, 40)
  screen.text(string.format("has_freq   %.2f", d.has_freq))
  screen.move(0, 50)
  screen.text(string.format("onset ct   %d", d.onset_count))
end

function redraw()
  screen.clear()
  if screen_debug then
    redraw_debug()
  else
    redraw_normal(analysis.current())
  end
  screen.update()
end

function cleanup()
  harness.stop()
  gridui.cleanup()
  analysis.cleanup()
  if screen_metro then screen_metro:stop() end
end
