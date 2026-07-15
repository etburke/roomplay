-- 8 weights, slew, confidence gating.
--
-- couplings.get() returns 8 slewed, confidence-gated weights 0..1
-- { tempo=, key=, density=, register=, dynamics=, conf_floor=, autonomy=, output= }
--
-- Gating rule: for coupling c associated with estimator e, effective weight
-- is w[c] if e.conf >= w.conf_floor, else 0. conf_floor/autonomy/output are
-- ungated. Weights are slewed targets, not switches — a fader jump must not
-- produce a discontinuity.

local analysis = include('lib/analysis')

local M = {}

local KEYS = { "tempo", "key", "density", "register", "dynamics", "conf_floor", "autonomy", "output" }
local ESTIMATOR_FOR = { tempo = "tempo", key = "key", density = "density", register = "register", dynamics = "dynamics" }

local SLEW_TAU = 0.2 -- seconds

local target = {}
local value = {}
local last_t = nil

local function reset()
  for _, k in ipairs(KEYS) do
    target[k] = 0.0
    value[k] = 0.0
  end
  last_t = nil
end
reset()

function M.init()
  reset()
end

function M.set_target(name, v)
  target[name] = util.clamp(v, 0, 1)
end

function M.get_target(name)
  return target[name]
end

function M.update()
  local t = util.time()
  if not last_t then
    last_t = t
    return
  end
  local dt = t - last_t
  last_t = t
  if dt <= 0 then return end
  local alpha = 1 - math.exp(-dt / SLEW_TAU)
  for _, k in ipairs(KEYS) do
    value[k] = value[k] + (target[k] - value[k]) * alpha
  end
end

function M.get()
  local snap = analysis.current()
  local out = {}
  for _, k in ipairs(KEYS) do
    out[k] = value[k]
  end
  local floor = value.conf_floor
  for c, est_name in pairs(ESTIMATOR_FOR) do
    local est = snap[est_name]
    local conf = est and est.conf or 0
    if conf < floor then
      out[c] = 0
    end
  end
  return out
end

return M
