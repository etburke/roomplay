-- 16x8 fader surface, LED render.
-- Row = coupling, column = value. Column 1 = 0.0, column 16 = 1.0.
-- Press sets value. LED ramp shows the fader target at brightness 8, plus
-- (rows 1-5 only) a brightness-4 LED at the column matching that row's
-- estimator confidence, so you can see where the analysis is pulling versus
-- where you've set the fader.

local couplings = include('lib/couplings')
local analysis = include('lib/analysis')

local M = {}

local ROWS = { "tempo", "key", "density", "register", "dynamics", "conf_floor", "autonomy", "output" }
local ESTIMATOR_FOR = { tempo = "tempo", key = "key", density = "density", register = "register", dynamics = "dynamics" }
local N_COLS = 16
local REDRAW_HZ = 15

local g = nil
local redraw_metro = nil

local function value_to_col(v)
  return util.clamp(math.floor(v * (N_COLS - 1) + 0.5) + 1, 1, N_COLS)
end

local function col_to_value(x)
  return (x - 1) / (N_COLS - 1)
end

function M.redraw()
  if not g then return end
  local snap = analysis.current()

  for y, row in ipairs(ROWS) do
    local buf = {}
    for x = 1, N_COLS do buf[x] = 0 end

    local target_col = value_to_col(couplings.get_target(row))
    for x = 1, target_col do buf[x] = 8 end

    local est_name = ESTIMATOR_FOR[row]
    if est_name then
      local conf = snap[est_name] and snap[est_name].conf or 0
      local conf_col = value_to_col(conf)
      if buf[conf_col] < 4 then buf[conf_col] = 4 end
    end

    for x = 1, N_COLS do
      g:led(x, y, buf[x])
    end
  end

  g:refresh()
end

local function key_handler(x, y, z)
  if z ~= 1 then return end
  local row = ROWS[y]
  if not row then return end
  couplings.set_target(row, col_to_value(x))
end

function M.init()
  g = grid.connect()
  g.key = key_handler

  redraw_metro = metro.init(function() M.redraw() end, 1 / REDRAW_HZ)
  redraw_metro:start()
end

function M.cleanup()
  if redraw_metro then
    redraw_metro:stop()
    redraw_metro = nil
  end
  if g then
    g:all(0)
    g:refresh()
  end
end

return M
