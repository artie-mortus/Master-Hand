-- In-memory plugin state plus small persistable subset helpers.
local M = {}

M.data = {
  root = nil,
  goal = nil,
  goal_source = "inferred",
  long_term_goal = nil,
  long_term_goal_source = "inferred",
  short_term_goal = nil,
  short_term_goal_source = "inferred",
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
  local line = ""
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
  if ok and vim.api.nvim_get_current_buf() == bufnr then
    line = (vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or "")
  end
  table.insert(M.data.recent_edits, 1, {
    file = name,
    line = vim.trim(line),
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
  M.data.goal_source = data.goal_source or M.data.goal_source
  M.data.long_term_goal = data.long_term_goal or M.data.long_term_goal or M.data.goal
  M.data.long_term_goal_source = data.long_term_goal_source or M.data.long_term_goal_source or M.data.goal_source
  M.data.short_term_goal = data.short_term_goal or M.data.short_term_goal
  M.data.short_term_goal_source = data.short_term_goal_source or M.data.short_term_goal_source
  M.data.feedback = data.feedback or M.data.feedback
  M.data.dismissed = data.dismissed or M.data.dismissed
end

function M.persistable()
  return {
    goal = M.data.goal,
    goal_source = M.data.goal_source,
    long_term_goal = M.data.long_term_goal,
    long_term_goal_source = M.data.long_term_goal_source,
    short_term_goal = M.data.short_term_goal,
    short_term_goal_source = M.data.short_term_goal_source,
    feedback = M.data.feedback,
    dismissed = M.data.dismissed,
  }
end

return M
