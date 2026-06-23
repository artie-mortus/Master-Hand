local state = require("master-hand.state")
local M = {}

local seq = 0
function M.create(action)
  seq = seq + 1
  action.id = action.id or ("act-" .. seq)
  action.status = action.status or "pending"
  state.data.pending_actions[action.id] = action
  return action
end
function M.get(id) return state.data.pending_actions[id] end
function M.list()
  local out={} for _, a in pairs(state.data.pending_actions) do table.insert(out,a) end
  table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
  return out
end
function M.reject(id) local a=M.get(id); if a then a.status="rejected" end; return a end
function M.approve(id) local a=M.get(id); if a then a.status="approved" end; return a end
return M
