-- clock, ctx assembly, when->what dispatch
--
-- function on_tick(beat)
--   local ctx = { analysis = analysis.current(), weights = couplings.get(), beat = beat }
--   local ev = when:tick(ctx)
--   if ev then
--     local note = ev.note or what:pick(ctx, ev)
--     if note then voices:play(note, ev.velocity, ev.duration) end
--   end
-- end

local registry = include('lib/gen/registry')
local couplings = include('lib/couplings')
local analysis = include('lib/analysis')
local voices = include('lib/voices')

local M = {}

M.when_core = nil
M.what_core = nil

local tick_clock_id = nil

function M.set_when(index)
  if M.when_core then
    voices.all_notes_off()
  end
  M.when_core = registry.when_by_index(index)
  M.when_core:init()
end

function M.set_what(index)
  M.what_core = registry.what_by_index(index)
  M.what_core:init()
end

local function tick(beat, ctx)
  local ev = M.when_core:tick(ctx)
  if ev then
    local note = ev.note or (M.what_core and M.what_core:pick(ctx, ev))
    if note then
      voices:play(note, ev.velocity, ev.duration, ctx.weights)
    end
  end
end

-- coupling row 1 (tempo): 0.0 = free-running (params base_tempo), 1.0 =
-- locked to the detected bpm. The slewed weight makes this a continuous
-- blend, not a switch, so the master clock never jumps.
local function apply_tempo_coupling(ctx)
  local base = params:get("base_tempo")
  local detected = ctx.analysis.tempo.bpm
  local w = ctx.weights.tempo
  clock.tempo = base + (detected - base) * w
end

local function clock_loop()
  while true do
    clock.sync(1 / 16)
    couplings.update()
    local ctx = {
      analysis = analysis.current(),
      weights = couplings.get(),
      beat = clock.get_beats(),
    }
    ctx.phase = ctx.beat - math.floor(ctx.beat)
    apply_tempo_coupling(ctx)
    tick(ctx.beat, ctx)
  end
end

function M.start()
  if tick_clock_id then clock.cancel(tick_clock_id) end
  tick_clock_id = clock.run(clock_loop)
end

function M.stop()
  if tick_clock_id then
    clock.cancel(tick_clock_id)
    tick_clock_id = nil
  end
  voices.all_notes_off()
end

return M
