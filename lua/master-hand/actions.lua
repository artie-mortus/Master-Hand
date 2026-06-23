-- Pending approval lifecycle for proposed edits and commands.
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
function M.get(id)
  return state.data.pending_actions[id]
end

function M.list()
  local out = {}
  for _, action in pairs(state.data.pending_actions) do
    table.insert(out, action)
  end
  table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
  return out
end

local function set_status(id, status)
  local action = M.get(id)
  if action then action.status = status end
  return action
end

function M.reject(id)
  return set_status(id, "rejected")
end

function M.approve(id)
  return set_status(id, "approved")
end
return M
