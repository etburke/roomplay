# roomplay

A norns script that listens to a line-in guitar signal, estimates tempo,
key, density, register, and dynamics, and generates accompaniment whose
*coupling* to those estimates is performed live on a 16×8 monome grid.

You never place a note. You tune how porous the system is to what you're
playing.

## Requirements

- norns (or fates)
- 16×8 (or larger) monome grid
- a guitar (or any line-in signal) — optional; the script runs on scripted
  fake analysis data with nothing plugged in
- optionally, a MIDI output device

## Install

```
;install https://github.com/etburke/roomplay
```

or clone into `dust/code/roomplay` on the norns.

## Use

On first run the script drives itself from `fake_analysis` — a scripted
20s ramp-up / hold / drop-off of confidence values — so you can hear how
the couplings behave with no guitar plugged in. Flip `analysis source` to
`live` in the params menu once you've plugged in a guitar.

**Grid**: row = coupling, column = value (col 1 = 0.0, col 16 = 1.0). Press
a cell to set that row's fader. A dim (brightness 4) LED on rows 1–5 shows
where the live estimator's confidence currently sits, so you can see where
the analysis is pulling versus where you've set the fader.

| Row | Coupling | 0.0 | 1.0 |
|---|---|---|---|
| 1 | tempo | free-running clock | locked to detected BPM |
| 2 | key | chromatic | strictly detected key |
| 3 | density | fixed event rate | rate tracks playing |
| 4 | register | holds own range | follows pitch centroid |
| 5 | dynamics | flat velocity | tracks amplitude |
| 6 | conf_floor | always believe analysis | only strong detections |
| 7 | autonomy | mirrors input | ignores everything |
| 8 | output | PolyPerc only | MIDI only (cols 8/9 = both) |

Row 6 (`conf_floor`) is the master listening threshold: for any of rows
1–5, if that row's estimator confidence is below the `conf_floor` value,
the coupling reads as 0 regardless of where its fader is set. All 8 faders
are slewed targets (~200ms), not switches — moving one produces a smooth
transition, never a jump.

**Norns keys**: `K2` toggles a debug screen of raw engine values (amp,
freq, has_freq, onset count). `K3` is a panic button — all notes off.

**Params**: `when core` and `what core` pick the generative pair driving
playback; each core's own params appear once selected. `base_tempo` is the
free-running clock speed used when the tempo coupling is at 0.

## Architecture

```
roomplay.lua        entry: init, key, enc, redraw
lib/analysis.lua     poll handling, normalizes engine -> estimator input
lib/estimators/       tempo / key / density / register / dynamics
lib/couplings.lua     8 weights, slew, confidence gating
lib/gridui.lua        16x8 fader surface, LED render
lib/voices.lua         note-on/off tracking, fan-out to PolyPerc + MIDI
lib/harness.lua        clock, ctx assembly, when -> what dispatch
lib/gen/registry.lua   discovers cores, exposes lists for params
lib/gen/when/           fixed_pulse, euclid, prob_ring
lib/gen/what/           scale_walk, harmonic_field, markov
lib/mock/fake_analysis.lua  scripted analysis stream for guitar-free testing
engine/Engine_RoomAnalysis.sc
```

A tick is dispatched at 1/16-note resolution:

```lua
local ctx = { analysis = analysis.current(), weights = couplings.get(), beat = beat }
local ev = when:tick(ctx)
if ev then
  local note = ev.note or what:pick(ctx, ev)
  if note then voices:play(note, ev.velocity, ev.duration) end
end
```

If `when:tick()` returns a table containing `note`, the `what` core is
skipped — an escape hatch for joint pitch/rhythm cores (`prob_ring` uses
it; `markov` is a `what` core trained on the player's register instead).

### Adding a core

Add a new file to `lib/gen/when/` or `lib/gen/what/` implementing:

```lua
{
  name   = "my_core",
  params = function(self, id_prefix) end,  -- namespaced params
  init   = function(self) end,
  tick   = function(self, ctx) end,  -- when: -> nil | { velocity, duration [, note] }
  pick   = function(self, ctx, event) end,  -- what: -> midi note | nil
  redraw = function(self, ctx) end,  -- optional
}
```

then register it in `lib/gen/registry.lua`. Nothing else needs to change —
params get registered (and hidden until selected) automatically.

## Standing decisions

- Own tempo estimator, not `BeatTrack.kr` (it locks slowly and is opaque).
- Confidence gates everything; row 6 is the master listening threshold.
- Weights are slewed targets, not switches.
- No feedback loop concerns — line-in analysis and output are separate
  paths; no echo cancellation.
- Cores are plugins: adding one touches only `registry.lua` and the new
  file.
- Voice tracking is central and core-agnostic — note-offs are the
  harness's job, never a core's.
- Key detection is slow (~25s window), tempo is fast (~8s window).

## Out of scope for v1

- 256 grid: right half as scene storage, bottom row scene-morphing.
- Softcut layer granulating the captured guitar as a third output.
- Call-and-response mode (needs a phrase-boundary detector).
