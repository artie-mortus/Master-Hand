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

-- Infer goals from local evidence and mirror them into state. Shared by the
-- sync and async snapshot paths so both steer identically.
local function apply_goals(edits, changed, diag)
  local goal, goal_source, short_goal, short_source, long_goal, long_source = infer_goal(edits, changed, diag)
  state.data.goal = goal
  state.data.goal_source = goal_source
  state.data.short_term_goal = short_goal
  state.data.short_term_goal_source = short_source
  state.data.long_term_goal = long_goal
  state.data.long_term_goal_source = long_source
  return {
    goal = goal,
    goal_source = goal_source,
    short_term_goal = short_goal,
    short_term_goal_source = short_source,
    long_term_goal = long_goal,
    long_term_goal_source = long_source,
  }
end

local function git_status_text(changed)
  if not config.get().observation.git then return "" end
  return table.concat(vim.tbl_map(function(item) return string.format("%s %s", item.status, item.file) end, changed), "\n")
end

-- Main context object. Keep deterministic/local; do not call providers from here.
function M.snapshot(opts)
  opts = opts or {}
  local root = state.data.root or git.root()
  state.data.root = root
  local changed = config.get().observation.git and git.changed_files(root) or {}
  local names = changed_file_names(changed)
  local edits = recent_edits(root)
  local diag = diagnostics()
  local quick = opts.quick == true
  local goals = apply_goals(edits, changed, diag)
  local snap = {
    root = root,
    branch = quick and "" or git.branch(root),
    goal = goals.goal,
    goal_source = goals.goal_source,
    short_term_goal = goals.short_term_goal,
    short_term_goal_source = goals.short_term_goal_source,
    long_term_goal = goals.long_term_goal,
    long_term_goal_source = goals.long_term_goal_source,
    open_buffers = open_buffers(root),
    recent_edits = edits,
    diagnostics = diag,
    git_status = git_status_text(changed),
    changed_files = names,
    changed = changed,
    diff = (not quick and config.get().observation.git) and git.diff(root, nil, config.get().context.max_diff_bytes) or "",
    repo_files = quick and {} or git.ls_files(root, config.get().context.max_files),
    repo_index = (not quick and config.get().context.include_index) and index.build(root) or {},
    related = (not quick and config.get().context.include_related_files) and search.related_to_goal(root, table.concat({ goals.short_term_goal or "", goals.long_term_goal or "" }, " "), config.get().context.max_search_results) or {},
    symbols = (not quick and config.get().context.include_symbols) and search.symbols() or {},
    feedback = state.data.feedback,
  }
  state.data.last_context = snap
  return snap
end

local function first_n(list, n)
  if not n or #list <= n then return list end
  local out = {}
  for i = 1, n do out[i] = list[i] end
  return out
end

-- Async snapshot build: same fields as M.snapshot, but every external process
-- (git branch/status/diff/ls-files, rg) runs through non-blocking vim.system
-- callbacks with the same argv tables and bounded timeouts as the sync path.
-- Bounded pure-Lua work (index.build over pre-fetched files, small file heads,
-- table assembly) stays synchronous inside the callback chain; only process
-- :wait() is banned here. `done(snap)` runs on the main loop via vim.schedule.
local function build_async(quick, done)
  local cfg = config.get()
  local observe_git = cfg.observation.git and true or false
  local index_limit = (cfg.context.index or {}).max_files or 500
  -- One ls-files run covers both repo_files and the index; slices below keep
  -- each consumer at its own configured bound.
  local files_limit = math.max(cfg.context.max_files or 80, index_limit)

  -- Stage C (main loop): editor state + bounded local reads, then hand off.
  local function finish(root, branch, changed, all_files, diff_text, related, edits, diag, goals)
    local snap = {
      root = root,
      branch = quick and "" or branch,
      goal = goals.goal,
      goal_source = goals.goal_source,
      short_term_goal = goals.short_term_goal,
      short_term_goal_source = goals.short_term_goal_source,
      long_term_goal = goals.long_term_goal,
      long_term_goal_source = goals.long_term_goal_source,
      open_buffers = open_buffers(root),
      recent_edits = edits,
      diagnostics = diag,
      git_status = git_status_text(changed),
      changed_files = changed_file_names(changed),
      changed = changed,
      diff = diff_text,
      repo_files = quick and {} or first_n(all_files, cfg.context.max_files),
      repo_index = (not quick and cfg.context.include_index) and index.build(root, first_n(all_files, index_limit)) or {},
      related = related,
      symbols = (not quick and cfg.context.include_symbols) and search.symbols() or {},
      feedback = state.data.feedback,
    }
    state.data.last_context = snap
    done(snap)
  end

  -- Stage B (main loop): infer goals from stage-A data, then fan out the
  -- goal-dependent process work (per-file diff, rg over goal terms).
  local function stage_goal(root, branch, changed, all_files)
    state.data.root = root
    local edits = recent_edits(root)
    local diag = diagnostics()
    local goals = apply_goals(edits, changed, diag)
    local diff_text, related = "", {}
    local pending = 1
    local function arrive()
      pending = pending - 1
      if pending > 0 then return end
      vim.schedule(function() finish(root, branch, changed, all_files, diff_text, related, edits, diag, goals) end)
    end
    if not quick and observe_git then
      pending = pending + 1
      git.diff_async(root, changed_file_names(changed), cfg.context.max_diff_bytes, function(text)
        diff_text = text
        arrive()
      end)
    end
    if not quick and cfg.context.include_related_files then
      pending = pending + 1
      search.related_to_goal_async(root, table.concat({ goals.short_term_goal or "", goals.long_term_goal or "" }, " "), cfg.context.max_search_results, function(hits)
        related = hits
        arrive()
      end)
    end
    arrive()
  end

  -- Stage A: goal-independent repo facts, fanned out. Any failure degrades to
  -- the same empty defaults the sync path produces.
  local function stage_repo(root)
    local branch, changed, all_files = "", {}, {}
    local pending = 1
    local function arrive()
      pending = pending - 1
      if pending > 0 then return end
      vim.schedule(function() stage_goal(root, branch, changed, all_files) end)
    end
    if not quick then
      pending = pending + 2
      git.branch_async(root, function(name) branch = name; arrive() end)
      git.ls_files_async(root, files_limit, function(files) all_files = files; arrive() end)
    end
    if observe_git then
      pending = pending + 1
      git.changed_files_async(root, function(items) changed = items; arrive() end)
    end
    arrive()
  end

  local root = state.data.root
  if root then stage_repo(root) else git.root_async(stage_repo) end
end

-- Reentrancy: rapid timer fires coalesce instead of stacking snapshot chains.
-- Requests queue as waiters; while a run is in flight, new requests only join
-- the queue. A full run satisfies every waiter (a full snapshot is a superset
-- of a quick one); a quick run satisfies quick waiters only, and any full
-- waiters that queued meanwhile get one follow-up full run.
local inflight = false
local waiters = {}
local start_run

start_run = function(quick)
  inflight = true
  build_async(quick, function(snap)
    local served, remaining = {}, {}
    for _, waiter in ipairs(waiters) do
      if not quick or waiter.quick then table.insert(served, waiter) else table.insert(remaining, waiter) end
    end
    waiters = remaining
    inflight = false
    -- pcall each waiter so one failing callback cannot hang the others or
    -- skip the follow-up run queued full waiters rely on.
    for _, waiter in ipairs(served) do
      local ok, err = pcall(waiter.cb, snap)
      if not ok then vim.notify("Master Hand snapshot callback failed: " .. tostring(err), vim.log.levels.ERROR) end
    end
    if not inflight and #waiters > 0 then start_run(false) end
  end)
end

-- Async twin of M.snapshot. Produces the same snapshot table (deterministic,
-- bounded, no LLM) without any blocking process :wait(); cb(snap) runs on the
-- main loop. Concurrent requests coalesce onto the in-flight run (see above).
function M.snapshot_async(opts, cb)
  opts = opts or {}
  cb = cb or function() end
  table.insert(waiters, { cb = cb, quick = opts.quick == true })
  if inflight then return end
  start_run(opts.quick == true)
end

function M.summary(snap)
  snap = snap or M.snapshot()
  return string.format("root=%s branch=%s next_step=%s (%s) direction=%s (%s) buffers=%d changed=%d diagnostics=%dE/%dW", snap.root or "?", snap.branch or "?", snap.short_term_goal or snap.goal or "none", snap.short_term_goal_source or snap.goal_source or "inferred", snap.long_term_goal or "none", snap.long_term_goal_source or "inferred", #snap.open_buffers, #snap.changed_files, snap.diagnostics.errors, snap.diagnostics.warnings)
end

function M.summary_lines(snap)
  snap = snap or M.snapshot()
  return {
    "root: " .. (snap.root or "?"),
    "branch: " .. (snap.branch ~= "" and snap.branch or "?"),
    "next step (short-term): " .. (snap.short_term_goal or snap.goal or "none") .. " (" .. (snap.short_term_goal_source or snap.goal_source or "inferred") .. ")",
    "direction (long-term): " .. (snap.long_term_goal or "none") .. " (" .. (snap.long_term_goal_source or "inferred") .. ")",
    string.format("buffers=%d changed=%d diagnostics=%dE/%dW", #snap.open_buffers, #snap.changed_files, snap.diagnostics.errors, snap.diagnostics.warnings),
  }
end

return M
