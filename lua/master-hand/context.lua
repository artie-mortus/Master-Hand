-- Builds one repo/editor snapshot used by suggestions, prompts, and status UI.
local git = require("master-hand.git")
local state = require("master-hand.state")
local config = require("master-hand.config")
local path = require("master-hand.path")
local search = require("master-hand.search")
local index = require("master-hand.index")

local M = {}

-- Return loaded buffers inside repo root, filtered through project ignores.
local function open_buffers(root)
  if not config.get().observation.buffers then return {} end
  local items = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" and (not root or name == root or name:find(path.normalize(root) .. "/", 1, true) == 1) then
        local rel = path.relative(root, name)
        if not path.is_ignored(rel, config.get().ignore) then table.insert(items, rel) end
      end
    end
  end
  return path.dedupe(items)
end

-- Collapse Neovim diagnostics into counts so prompts/UI stay compact.
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
    if not path.is_ignored(rel, config.get().ignore) then table.insert(out, { file = rel, line = edit.line, time = edit.time }) end
  end
  return out
end

local function infer_goal(edits, changed, diagnostics)
  local long_goal = state.data.long_term_goal or state.data.goal
  local long_source = state.data.long_term_goal_source or state.data.goal_source or "inferred"
  if long_source == "user" and long_goal and long_goal ~= "" then
    -- Keep user intent as steering, not a hard task. Short-term work still follows local evidence.
  elseif state.data.goal_source == "user" and state.data.goal and state.data.goal ~= "" then
    long_goal, long_source = state.data.goal, "user"
  else
    long_goal, long_source = "Improve the current project safely", "inferred"
  end

  local short_goal, short_source
  if state.data.short_term_goal_source == "user" and state.data.short_term_goal and state.data.short_term_goal ~= "" then
    short_goal, short_source = state.data.short_term_goal, "user"
  else
    local edit = edits[1]
    if edit and edit.line and edit.line ~= "" then
      local text = edit.line:gsub("^%s*[%-%/%*#]+%s*", ""):gsub("%s+", " ")
      if #text > 90 then text = text:sub(1, 87) .. "..." end
      short_goal = "Continue implementing: " .. text
    elseif #changed > 0 then
      short_goal = "Review and complete changes in " .. table.concat(changed_file_names(changed), ", ")
    elseif diagnostics.errors > 0 then
      short_goal = "Fix current diagnostics"
    else
      short_goal = "Understand current repo state and suggest next step"
    end
    short_source = "inferred"
  end
  local goal = short_goal .. " (steered by: " .. long_goal .. ")"
  return goal, short_source, short_goal, short_source, long_goal, long_source
end

-- Main context object. Keep deterministic/local; do not call providers from here.
function M.snapshot()
  local root = state.data.root or git.root()
  state.data.root = root
  local changed = config.get().observation.git and git.changed_files(root) or {}
  local names = changed_file_names(changed)
  local edits = recent_edits(root)
  local diag = diagnostics()
  local goal, goal_source, short_goal, short_source, long_goal, long_source = infer_goal(edits, changed, diag)
  state.data.goal = goal
  state.data.goal_source = goal_source
  state.data.short_term_goal = short_goal
  state.data.short_term_goal_source = short_source
  state.data.long_term_goal = long_goal
  state.data.long_term_goal_source = long_source
  local snap = {
    root = root,
    branch = git.branch(root),
    goal = goal,
    goal_source = goal_source,
    short_term_goal = short_goal,
    short_term_goal_source = short_source,
    long_term_goal = long_goal,
    long_term_goal_source = long_source,
    open_buffers = open_buffers(root),
    recent_edits = edits,
    diagnostics = diag,
    git_status = config.get().observation.git and git.status_filtered(root) or "",
    changed_files = names,
    changed = changed,
    diff = config.get().observation.git and git.diff(root, nil, config.get().context.max_diff_bytes) or "",
    repo_files = git.ls_files(root, config.get().context.max_files),
    repo_index = config.get().context.include_index and index.build(root) or {},
    related = config.get().context.include_related_files and search.related_to_goal(root, table.concat({ short_goal or "", long_goal or "" }, " "), config.get().context.max_search_results) or {},
    symbols = config.get().context.include_symbols and search.symbols() or {},
    feedback = state.data.feedback,
  }
  state.data.last_context = snap
  return snap
end

function M.summary(snap)
  snap = snap or M.snapshot()
  return string.format("root=%s branch=%s short=%s (%s) long=%s (%s) buffers=%d changed=%d diagnostics=%dE/%dW", snap.root or "?", snap.branch or "?", snap.short_term_goal or snap.goal or "none", snap.short_term_goal_source or snap.goal_source or "inferred", snap.long_term_goal or "none", snap.long_term_goal_source or "inferred", #snap.open_buffers, #snap.changed_files, snap.diagnostics.errors, snap.diagnostics.warnings)
end

function M.summary_lines(snap)
  snap = snap or M.snapshot()
  return {
    "root: " .. (snap.root or "?"),
    "branch: " .. (snap.branch ~= "" and snap.branch or "?"),
    "short: " .. (snap.short_term_goal or snap.goal or "none") .. " (" .. (snap.short_term_goal_source or snap.goal_source or "inferred") .. ")",
    "long: " .. (snap.long_term_goal or "none") .. " (" .. (snap.long_term_goal_source or "inferred") .. ")",
    string.format("buffers=%d changed=%d diagnostics=%dE/%dW", #snap.open_buffers, #snap.changed_files, snap.diagnostics.errors, snap.diagnostics.warnings),
  }
end

return M
