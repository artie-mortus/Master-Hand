-- In-memory plugin state plus small persistable subset helpers.
local M = {}

M.data = {
  root = nil,
  goal = nil,
  recent_edits = {},
  suggestions = {},
  feedback = {},
  dismissed = {},
  pending_actions = {},
  last_context = nil,
  last_command = nil,
}

function M.add_edit(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return
  end
  table.insert(M.data.recent_edits, 1, {
    file = name,
    time = os.time(),
  })
  while #M.data.recent_edits > 20 do
    table.remove(M.data.recent_edits)
  end
end

function M.set_suggestions(items)
  M.data.suggestions = items or {}
end

function M.feedback(id, action)
  M.data.feedback[id] = action
  if action == "dismissed" then
    M.data.dismissed[id] = true
  end
end

function M.restore(data)
  data = data or {}
  M.data.goal = data.goal or M.data.goal
  M.data.feedback = data.feedback or M.data.feedback
  M.data.dismissed = data.dismissed or M.data.dismissed
end

function M.persistable()
  return { goal = M.data.goal, feedback = M.data.feedback, dismissed = M.data.dismissed }
end

return M
