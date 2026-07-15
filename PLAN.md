# `roomplay` — Implementation Plan

A norns script that listens to a line-in guitar signal, estimates tempo/key/density/register/dynamics, and generates accompaniment whose *coupling* to those estimates is performed on a 16×8 monome grid.

The user is a metaprogrammer: they never place a note. They tune how porous the system is to what they're playing.

---

## Repo layout

```
roomplay/
├── roomplay.lua              # entry: init, key, enc, redraw
├── lib/
│   ├── analysis.lua          # poll handling, normalizes engine → estimator input
│   ├── estimators/
│   │   ├── tempo.lua         # IOI histogram + autocorrelation → (bpm, conf)
│   │   ├── key.lua           # chroma histogram + Krumhansl → (root, mode, conf)
│   │   ├── density.lua       # onsets/sec windowed → (rate, conf)
│   │   ├── register.lua      # rolling pitch centroid → (midi_note, conf)
│   │   └── dynamics.lua      # amplitude envelope → (level, conf)
│   ├── couplings.lua         # 8 weights, slew, confidence gating
│   ├── gridui.lua            # 16×8 fader surface, LED render
│   ├── voices.lua            # note-on/off tracking, fan-out to PolyPerc + MIDI
│   ├── harness.lua           # clock, ctx assembly, when→what dispatch
│   └── gen/
│       ├── registry.lua      # discovers cores, exposes lists for params
│       ├── when/
│       │   ├── fixed_pulse.lua
│       │   ├── euclid.lua
│       │   └── prob_ring.lua
│       └── what/
│           ├── scale_walk.lua
│           ├── harmonic_field.lua
│           └── markov.lua
├── lib/mock/
│   └── fake_analysis.lua     # scripted analysis streams for guitar-free testing
├── engine/
│   └── Engine_RoomAnalysis.sc
└── README.md
```

---

## Core contracts

Freeze these before writing anything else. Everything downstream depends on them.

### Analysis snapshot

```lua
-- analysis.current() returns:
{
  tempo    = { bpm = 96.2,  conf = 0.81 },
  key      = { root = 2, mode = "dorian", conf = 0.64 },  -- root 0..11
  density  = { rate = 3.4,  conf = 0.72 },                -- onsets/sec
  register = { note = 57.3, conf = 0.55 },                -- fractional midi
  dynamics = { level = 0.42, conf = 0.9 },                -- 0..1
  onset    = false,                                        -- true only on tick where onset landed
}
```

Every estimator returns `(value, conf)`. `conf` is 0..1. No exceptions — the confidence gate in `couplings.lua` depends on universality.

### Couplings

```lua
-- couplings.get() returns 8 slewed, confidence-gated weights 0..1
{ tempo=, key=, density=, register=, dynamics=, conf_floor=, autonomy=, output= }
```

Gating rule: for coupling `c` associated with estimator `e`, effective weight is `w[c]` if `e.conf >= w.conf_floor`, else `0`. Slew all weights toward their grid target with a ~200ms time constant. `conf_floor`, `autonomy`, and `output` are ungated.

### Generative cores

```lua
-- when core
{
  name = "euclid",
  params = function(self, id_prefix) end,   -- adds namespaced params
  init   = function(self) end,
  tick   = function(self, ctx) end,   -- → nil | { velocity, duration [, note] }
  redraw = function(self, ctx) end,   -- optional
}

-- what core
{
  name = "scale_walk",
  params = function(self, id_prefix) end,
  init   = function(self) end,
  pick   = function(self, ctx, event) end,  -- → midi note | nil
  redraw = function(self, ctx) end,
}
```

`ctx = { analysis, weights, beat, phase }`.

**Escape hatch:** if `when:tick()` returns a table containing `note`, the `what` core is skipped. This exists for joint pitch/rhythm models (Markov on `(pitch, IOI)` pairs). Do not remove it in the name of purity.

### Dispatch

```lua
function on_tick(beat)
  local ctx = { analysis = analysis.current(), weights = couplings.get(), beat = beat }
  local ev = when:tick(ctx)
  if ev then
    local note = ev.note or what:pick(ctx, ev)
    if note then voices:play(note, ev.velocity, ev.duration) end
  end
end
```

---

## Grid: 16×8

Row = coupling, column = value. Column 1 = 0.0, column 16 = 1.0. Press sets value.

| Row | Coupling | 0.0 | 1.0 |
|---|---|---|---|
| 1 | tempo | free-running clock | locked to detected BPM |
| 2 | key | chromatic | strictly detected key |
| 3 | density | fixed event rate | rate tracks playing |
| 4 | register | holds own range | follows pitch centroid |
| 5 | dynamics | flat velocity | tracks amplitude |
| 6 | conf_floor | always believe analysis | only strong detections |
| 7 | autonomy | mirrors input | ignores everything |
| 8 | output | PolyPerc only | MIDI only (col 8/9 = both) |

**LED rendering:** filled ramp to current value at brightness 8. Additionally, a brightness-4 LED at the column corresponding to the *estimator's current confidence* for that row — so you can see where the analysis is pulling versus where you've set the fader. Rows 6–8 have no such indicator.

Core selection lives in **params**, not the grid. `when_core` and `what_core` are option params, PSET-saved. Switching rebuilds that core's param group.

---

## Build phases

Each phase ends in something runnable and verifiable. Do not proceed on a phase whose exit criterion is unmet.

### Phase 0 — harness, no audio

Build `harness.lua`, `voices.lua`, `couplings.lua`, `gen/registry.lua`, `lib/mock/fake_analysis.lua`, plus `when/fixed_pulse.lua` and `what/scale_walk.lua`.

`fake_analysis` emits a scripted snapshot stream (e.g. 96bpm, D dorian, conf ramping 0→1 over 20s, then dropping). This is how the whole system gets tested with no guitar and no SC engine.

`fixed_pulse` fires every N beats. `scale_walk` picks a note from `analysis.key` via `musicutil.generate_scale`, biased toward `analysis.register.note`.

**Exit:** norns makes plausible, boring music driven entirely by fake data. Note-offs are correct — no stuck notes when you switch cores mid-run.

### Phase 1 — SC analysis engine

`Engine_RoomAnalysis.sc`:

- `Onsets.kr` — use `\wphase` or `\complex`. `\rcomplex` handles distortion badly.
- `Pitch.kr` — expose `ampThreshold`, `median` as engine commands.
- `Amplitude.kr` → `Lag.kr`.
- All three → `SendReply.kr` at a fixed rate (suggest 30Hz for pitch/amp, plus event-driven `SendReply` on onset trigger).

`analysis.lua` sets up polls, normalizes into the snapshot shape. A DEBUG screen mode shows raw values.

**Exit:** plug in the guitar, watch raw numbers, confirm they respond sensibly to playing. **Budget real time here.** This is where you discover what your effects chain does to onset detection. Tempo-synced delay will pollute the IOI histogram — note the delay time, you may need to notch it.

### Phase 2 — estimators

- **tempo.lua** — collect inter-onset intervals over an 8s window, histogram at ~10ms bins, autocorrelate, pick peak, resolve octave ambiguity (prefer 60–140bpm). Confidence = peak sharpness relative to histogram mean. **Write this yourself; do not use `BeatTrack.kr`** — it locks slowly and is opaque.
- **key.lua** — accumulate a 12-bin chroma histogram from the pitch stream over ~25s, weighted by pitch confidence and amplitude. Correlate against Krumhansl–Schmuckler major/minor profiles at all 12 rotations. Confidence = best correlation minus second-best.
- **density / register / dynamics** — windowed averages, cheap.

Window lengths: key ~25s, tempo ~8s, density ~4s, register ~4s, dynamics ~0.3s.

**Exit:** play a riff, screen reports the right BPM and key with rising confidence. Play an ambient swell, tempo confidence correctly collapses while key confidence holds.

### Phase 3 — grid

`gridui.lua`. Eight faders → `couplings.lua` targets. Slew. Confidence indicator LEDs.

**Exit:** it's an instrument. Move faders while playing, hear the coupling change.

### Phase 4 — remaining cores

`euclid`, `prob_ring`, `harmonic_field`, `markov`. Each independently testable against `fake_analysis` and A/B-switchable via param against live guitar.

- `prob_ring` — N steps, per-step probability + pitch weight, slow random walk on the vectors. Mutation rate ← `autonomy`. Global probability multiplier ← `density`.
- `harmonic_field` — slow-drifting chord tones within detected key, changing every few bars; drift rate ← `autonomy`.
- `markov` — order-1 or order-2 on the incoming pitch stream. Needs a warmup gate: return `nil` until the table has enough mass. Gate on `pitch.conf` when training.

### Phase 5 — polish

MIDI device param, PSET save/load, screen UI showing detected values + core states, README.

---

## Standing decisions

- **Own tempo estimator, not `BeatTrack.kr`.**
- **Confidence gates everything.** Row 6 is the master listening threshold.
- **Weights are slewed targets, not switches.** A fader jump must not produce a discontinuity.
- **No feedback loop concerns** — line-in analysis, separate output path. Do not add echo cancellation.
- **Cores are plugins.** Adding one must touch only `registry.lua` and the new file.
- **Voice tracking is central and core-agnostic.** MIDI note-offs are the harness's job, never a core's.
- **Key detection is slow, tempo is fast.** Key changes rarely; tempo can shift.

---

## Notes for the implementer

- Norns Lua is 5.3-ish. No `goto` abuse, watch integer/float division.
- `musicutil` gives you `generate_scale`, `note_num_to_freq`, `snap_note_to_array`. Use them.
- Grid press → weight target must be non-blocking; don't do estimator work in the grid handler.
- Guard every core against `conf = 0` on all estimators — that's the startup state and the ambient-swell state, and it must sound intentional rather than broken.
- `fake_analysis` is not throwaway. Keep it working; it's the only way to test cores deterministically.
- Test core switching under load. Stuck MIDI notes on switch is the most likely bug in the whole project.

---

## Future (explicitly out of scope for v1)

- 256 grid → right half becomes scene storage; each pad recalls a saved coupling matrix, bottom row morphs between two scenes.
- Softcut layer — granulate the captured guitar back at itself as a third output destination.
- Call-and-response mode — requires a phrase-boundary detector.