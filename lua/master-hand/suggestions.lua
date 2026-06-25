-- Suggestion generation: local heuristics first, optional model suggestions second.
local context = require("master-hand.context")
local state = require("master-hand.state")
local schema = require("master-hand.schema")
local prompts = require("master-hand.prompts")
local providers = require("master-hand.providers")
local config = require("master-hand.config")
local path = require("master-hand.path")

local M = {}

local function item(id, title, reason, files, confidence, next_action, action_type, extra)
  extra = extra or {}
  extra.id, extra.title, extra.reason, extra.files = id, title, reason, files or {}
  extra.confidence, extra.next_action, extra.action_type = confidence, next_action, action_type or "advice"
  return schema.suggestion(extra)
end

-- Cheap local suggestions. These must work even when no model is configured.
local function heuristic(snap)
  local out = {}
  if snap.short_term_goal and snap.short_term_goal ~= "" then table.insert(out, item("goal-plan", "Break steering goal into repo-aware steps", "Short-term goal is " .. (snap.short_term_goal_source or "inferred") .. "; long-term steering is " .. (snap.long_term_goal or "unspecified") .. ".", snap.changed_files, 0.82, "Review related search hits for: " .. table.concat({ snap.short_term_goal, snap.long_term_goal or "" }, " "), "advice")) end
  if snap.related and #snap.related > 0 then
    local files, seen = {}, {}
    for _, hit in ipairs(snap.related) do if not seen[hit.file] then seen[hit.file] = true; table.insert(files, hit.file) end end
    table.insert(out, item("related-files", "Review related files", "Goal terms appear in these files; they may need coordinated changes.", files, 0.78, "Open :MHContext and inspect related hits before editing.", "advice"))
  end
  if snap.diagnostics.errors > 0 then table.insert(out, item("diagnostics-errors", "Resolve current diagnostics before broad changes", "Errors can hide regressions from recent edits.", snap.open_buffers, 0.88, "Open diagnostics list and fix highest-severity errors first.", "advice")) end
  if #snap.changed_files > 0 then table.insert(out, item("review-git-diff", "Review coordinated changes", "Git diff has modified files; tests/docs/config may need sync.", snap.changed_files, 0.76, "Inspect git diff and list related files that may need changes.", "advice")) end
  if #snap.recent_edits > 0 and #snap.changed_files == 0 then table.insert(out, item("save-or-check-edits", "Recent buffer edits not reflected in git diff", "Unsaved buffers may make repository context stale.", { snap.recent_edits[1].file }, 0.7, "Save buffers or refresh suggestions after editing.", "advice")) end
  if #out == 0 then table.insert(out, item("no-obstacle", "No immediate obstacle detected", "No visible git changes or diagnostics.", snap.open_buffers, 0.55, "Keep typing for inferred goal updates or override with :MasterHandGoal.", "advice")) end
  return out
end

local function add_candidate(candidates, seen, file)
  if not file or file == "" or seen[file] or path.is_ignored(file, config.get().ignore) then return end
  seen[file] = true
  table.insert(candidates, file)
end

local function code_context(snap)
  local opts = config.get().context
  local candidates, seen = {}, {}
  for _, file in ipairs(snap.changed_files or {}) do add_candidate(candidates, seen, file) end
  for _, file in ipairs(snap.open_buffers or {}) do add_candidate(candidates, seen, file) end
  for _, hit in ipairs(snap.related or {}) do add_candidate(candidates, seen, hit.file) end
  for _, file in ipairs((snap.repo_index or {}).entrypoints or {}) do add_candidate(candidates, seen, file) end

  local out = {}
  for _, file in ipairs(candidates) do
    if #out >= (opts.max_model_code_files or 8) then break end
    local full = (snap.root or "") .. "/" .. file
    local stat = vim.loop.fs_stat(full)
    if stat and stat.type == "file" and stat.size <= (opts.max_model_file_bytes or 12000) then
      local ok, lines = pcall(vim.fn.readfile, full, "", 500)
      if ok then table.insert(out, { file = file, text = table.concat(lines, "\n") }) end
    end
  end
  return out
end

local function infer_model_goal(snap, opts)
  if opts and opts.skip_model then return snap end
  if (config.get().model or {}).provider == "none" then return snap end
  if snap.long_term_goal_source == "user" and snap.short_term_goal_source == "user" then return snap end
  local enriched = vim.deepcopy(snap)
  enriched.code = code_context(enriched)
  local content = providers.complete(prompts.goal(enriched))
  if not content then return snap end
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then return snap end
  local confidence = math.max(0, math.min(1, tonumber(decoded.confidence) or 0.5))
  if confidence < 0.45 then return snap end
  if type(decoded.long_term_goal) == "string" and vim.trim(decoded.long_term_goal) ~= "" and snap.long_term_goal_source ~= "user" then
    snap.long_term_goal = vim.trim(decoded.long_term_goal)
    snap.long_term_goal_source = "model"
  end
  if type(decoded.short_term_goal) == "string" and vim.trim(decoded.short_term_goal) ~= "" and snap.short_term_goal_source ~= "user" then
    snap.short_term_goal = vim.trim(decoded.short_term_goal)
    snap.short_term_goal_source = "model"
  elseif type(decoded.goal) == "string" and vim.trim(decoded.goal) ~= "" and snap.short_term_goal_source ~= "user" then
    snap.short_term_goal = vim.trim(decoded.goal)
    snap.short_term_goal_source = "model"
  end
  snap.goal = (snap.short_term_goal or "") .. " (steered by: " .. (snap.long_term_goal or "") .. ")"
  snap.goal_source = snap.short_term_goal_source
  state.data.goal = snap.goal
  state.data.goal_source = snap.goal_source
  state.data.short_term_goal = snap.short_term_goal
  state.data.short_term_goal_source = snap.short_term_goal_source
  state.data.long_term_goal = snap.long_term_goal
  state.data.long_term_goal_source = snap.long_term_goal_source
  return snap
end

-- Optional model suggestions. Auto is opportunistic; explicit providers surface failures.
local function provider_items(snap, mode, local_suggestions, opts)
  local model = config.get().model or {}
  if opts and opts.skip_model then return {} end
  if model.provider == "none" then return {} end

  snap = vim.deepcopy(snap)
  snap.code = code_context(snap)
  local content, err = providers.complete(prompts.suggestions(snap, mode, local_suggestions))
  if not content then
    if model.provider == "auto" then return {} end
    return { item("provider-error", "Model provider failed", err, {}, 0.3, "Check model config or continue with heuristic suggestions.", "advice") }
  end
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then return { item("provider-parse-error", "Model suggestions malformed", "Provider did not return JSON array.", {}, 0.3, "Retry or adjust provider prompt/model.", "advice") } end
  return schema.list(decoded)
end

local function set_filtered(items)
  local filtered = {}
  for _, s in ipairs(items) do if not state.data.dismissed[s.id] then table.insert(filtered, s) end end
  state.set_suggestions(filtered)
  return filtered
end

function M.generate(opts)
  opts = opts or {}
  local snap = infer_model_goal(context.snapshot({ quick = opts.skip_model == true }), opts)
  local out = {}
  local local_suggestions = heuristic(snap)
  vim.list_extend(out, local_suggestions)
  vim.list_extend(out, provider_items(snap, opts.mode or "suggest", local_suggestions, opts))
  return set_filtered(out)
end

function M.generate_async(opts, cb)
  opts = opts or {}
  cb = cb or function() end
  local snap = context.snapshot({ quick = true })
  local local_suggestions = heuristic(snap)
  set_filtered(local_suggestions)

  local model = config.get().model or {}
  if model.provider == "none" then cb(local_suggestions); return local_suggestions end

  local request = vim.deepcopy(snap)
  request.code = code_context(request)
  providers.complete_async(prompts.suggestions(request, opts.mode or "suggest", local_suggestions), nil, function(content, err)
    local out = vim.deepcopy(local_suggestions)
    if not content then
      if model.provider ~= "auto" then
        table.insert(out, item("provider-error", "Model provider failed", err, {}, 0.3, "Check model config or continue with heuristic suggestions.", "advice"))
      end
      cb(set_filtered(out), err)
      return
    end
    local ok, decoded = pcall(vim.json.decode, content)
    if ok then
      vim.list_extend(out, schema.list(decoded))
      cb(set_filtered(out))
    else
      table.insert(out, item("provider-parse-error", "Model suggestions malformed", "Provider did not return JSON array.", {}, 0.3, "Retry or adjust provider prompt/model.", "advice"))
      cb(set_filtered(out), "Provider did not return JSON array")
    end
  end)
  return local_suggestions
end

return M
