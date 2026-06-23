local git = require("master-hand.git")
local state = require("master-hand.state")

local M = {}

local function open_buffers(root)
  local items = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" and (not root or name:find(root, 1, true) == 1) then
        table.insert(items, vim.fn.fnamemodify(name, ":."))
      end
    end
  end
  return items
end

local function diagnostics()
  local counts = { errors = 0, warnings = 0, info = 0, hints = 0 }
  for _, d in ipairs(vim.diagnostic.get()) do
    if d.severity == vim.diagnostic.severity.ERROR then
      counts.errors = counts.errors + 1
    elseif d.severity == vim.diagnostic.severity.WARN then
      counts.warnings = counts.warnings + 1
    elseif d.severity == vim.diagnostic.severity.INFO then
      counts.info = counts.info + 1
    elseif d.severity == vim.diagnostic.severity.HINT then
      counts.hints = counts.hints + 1
    end
  end
  return counts
end

function M.snapshot()
  local root = state.data.root or git.root()
  state.data.root = root
  local snap = {
    root = root,
    goal = state.data.goal,
    open_buffers = open_buffers(root),
    recent_edits = state.data.recent_edits,
    diagnostics = diagnostics(),
    git_status = git.status(root),
    changed_files = git.changed_files(root),
  }
  state.data.last_context = snap
  return snap
end

function M.summary(snap)
  snap = snap or M.snapshot()
  return string.format(
    "root=%s goal=%s buffers=%d changed=%d diagnostics=%dE/%dW",
    snap.root or "?",
    snap.goal or "none",
    #snap.open_buffers,
    #snap.changed_files,
    snap.diagnostics.errors,
    snap.diagnostics.warnings
  )
end

return M
