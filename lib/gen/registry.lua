-- discovers cores, exposes lists for params.
-- Cores are plugins: adding one must touch only this file and the new file.

local M = {}

M.when = {
  { key = "fixed_pulse", module = include('lib/gen/when/fixed_pulse') },
  { key = "euclid",      module = include('lib/gen/when/euclid') },
  { key = "prob_ring",   module = include('lib/gen/when/prob_ring') },
}

M.what = {
  { key = "scale_walk",     module = include('lib/gen/what/scale_walk') },
  { key = "harmonic_field", module = include('lib/gen/what/harmonic_field') },
  { key = "markov",         module = include('lib/gen/what/markov') },
}

local function names(list)
  local out = {}
  for _, entry in ipairs(list) do
    table.insert(out, entry.module.name or entry.key)
  end
  return out
end

function M.when_names() return names(M.when) end
function M.what_names() return names(M.what) end

function M.when_by_index(i) return M.when[i].module end
function M.what_by_index(i) return M.what[i].module end

return M
