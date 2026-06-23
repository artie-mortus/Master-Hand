local M = {}

M.data = {
  root = nil,
  goal = nil,
  recent_edits = {},
  suggestions = {},
  feedback = {},
  last_context = nil,
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
end

return M
