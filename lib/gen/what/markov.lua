-- order-1/2 Markov model trained on the player's pitch stream (the rolling
-- register centroid, sampled once per distinct value), gated on its
-- confidence. Needs a warmup gate: returns nil until enough mass has
-- accumulated in the transition table.

local M = { name = "markov" }

function M:params(id)
  self.id = id
  params:add_number(id .. "_order", "order", 1, 2, 1)
  params:add_number(id .. "_warmup", "warmup transitions", 4, 200, 20)
end

function M:init()
  self.table = {}       -- [state_key] = { total = n, [note] = count }
  self.history = {}     -- recent observed player notes
  self.last_train_note = nil
  self.total_transitions = 0
end

local function state_key(order, hist)
  local n = #hist
  if n < order then return nil end
  local parts = {}
  for i = n - order + 1, n do table.insert(parts, hist[i]) end
  return table.concat(parts, ":")
end

function M:_train(ctx)
  local order = params:get(self.id .. "_order")
  local reg = ctx.analysis.register
  if not reg or reg.conf < 0.3 then return end

  local note = math.floor(reg.note + 0.5)
  if note == self.last_train_note then return end
  self.last_train_note = note

  local key = state_key(order, self.history)
  table.insert(self.history, note)
  while #self.history > order + 8 do table.remove(self.history, 1) end

  if key then
    self.table[key] = self.table[key] or { total = 0 }
    self.table[key][note] = (self.table[key][note] or 0) + 1
    self.table[key].total = self.table[key].total + 1
    self.total_transitions = self.total_transitions + 1
  end
end

function M:pick(ctx, event)
  self:_train(ctx)

  local warmup = params:get(self.id .. "_warmup")
  if self.total_transitions < warmup then return nil end

  local order = params:get(self.id .. "_order")
  local ctx_hist = {}
  for i = math.max(1, #self.history - order + 1), #self.history do
    table.insert(ctx_hist, self.history[i])
  end
  local key = state_key(order, ctx_hist)
  local bucket = key and self.table[key]
  if not bucket or bucket.total == 0 then return nil end

  local r = math.random() * bucket.total
  local acc = 0
  local chosen = nil
  for note, count in pairs(bucket) do
    if note ~= "total" then
      acc = acc + count
      if r <= acc then
        chosen = note
        break
      end
    end
  end

  return chosen and util.clamp(chosen, 0, 127) or nil
end

return M
