local git = require("master-hand.git")
local state = require("master-hand.state")
local config = require("master-hand.config")
local path = require("master-hand.path")

local M = {}

local function open_buffers(root)
  if not config.get().observation.buffers then return {} end
  local items = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" and (not root or name:find(root, 1, true) == 1) then
        local rel = path.relative(root, name)
        if not path.is_ignored(rel, config.get().ignore) then table.insert(items, rel) end
      end
    end
  end
  return path.dedupe(items)
end

local function diagnostics()
  if not config.get().observation.diagnostics then return { errors=0, warnings=0, info=0, hints=0, files={} } end
  local counts = { errors = 0, warnings = 0, info = 0, hints = 0, files = {} }
  for _, d in ipairs(vim.diagnostic.get()) do
    local name = vim.api.nvim_buf_get_name(d.bufnr)
    local file = path.relative(state.data.root, name)
    counts.files[file] = counts.files[file] or { errors=0, warnings=0, info=0, hints=0 }
    local bucket = d.severity == vim.diagnostic.severity.ERROR and "errors" or d.severity == vim.diagnostic.severity.WARN and "warnings" or d.severity == vim.diagnostic.severity.INFO and "info" or "hints"
    counts[bucket] = counts[bucket] + 1
    counts.files[file][bucket] = counts.files[file][bucket] + 1
  end
  return counts
end

local function changed_file_names(changed)
  local out = {}
  for _, item in ipairs(changed or {}) do table.insert(out, item.file or item) end
  return out
end

local function recent_edits(root)
  if not config.get().observation.edits then return {} end
  local out = {}
  for _, edit in ipairs(state.data.recent_edits or {}) do
    local rel = path.relative(root, edit.file)
    if not path.is_ignored(rel, config.get().ignore) then table.insert(out, { file = rel, time = edit.time }) end
  end
  return out
end

function M.snapshot()
  local root = state.data.root or git.root()
  state.data.root = root
  local changed = config.get().observation.git and git.changed_files(root) or {}
  local names = changed_file_names(changed)
  local snap = {
    root = root,
    branch = git.branch(root),
    goal = state.data.goal,
    open_buffers = open_buffers(root),
    recent_edits = recent_edits(root),
    diagnostics = diagnostics(),
    git_status = config.get().observation.git and git.status_filtered(root) or "",
    changed_files = names,
    changed = changed,
    diff = config.get().observation.git and git.diff(root, nil, config.get().context.max_diff_bytes) or "",
    repo_files = git.ls_files(root, config.get().context.max_files),
    feedback = state.data.feedback,
  }
  state.data.last_context = snap
  return snap
end

function M.summary(snap)
  snap = snap or M.snapshot()
  return string.format("root=%s branch=%s goal=%s buffers=%d changed=%d diagnostics=%dE/%dW", snap.root or "?", snap.branch or "?", snap.goal or "none", #snap.open_buffers, #snap.changed_files, snap.diagnostics.errors, snap.diagnostics.warnings)
end

return M
