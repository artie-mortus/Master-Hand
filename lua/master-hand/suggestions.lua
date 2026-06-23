local context = require("master-hand.context")
local state = require("master-hand.state")
local schema = require("master-hand.schema")
local prompts = require("master-hand.prompts")
local providers = require("master-hand.providers")
local config = require("master-hand.config")

local M = {}

local function item(id, title, reason, files, confidence, next_action, action_type, extra)
  extra = extra or {}
  extra.id, extra.title, extra.reason, extra.files = id, title, reason, files or {}
  extra.confidence, extra.next_action, extra.action_type = confidence, next_action, action_type or "advice"
  return schema.suggestion(extra)
end

local function heuristic(snap)
  local out = {}
  if snap.goal and snap.goal ~= "" then table.insert(out, item("goal-plan", "Break goal into repo-aware steps", "Active goal set; identify touched modules before editing.", snap.changed_files, 0.82, "Search symbols/config related to: " .. snap.goal, "advice")) end
  if snap.diagnostics.errors > 0 then table.insert(out, item("diagnostics-errors", "Resolve current diagnostics before broad changes", "Errors can hide regressions from recent edits.", snap.open_buffers, 0.88, "Open diagnostics list and fix highest-severity errors first.", "advice")) end
  if #snap.changed_files > 0 then table.insert(out, item("review-git-diff", "Review coordinated changes", "Git diff has modified files; tests/docs/config may need sync.", snap.changed_files, 0.76, "Inspect git diff and list related files that may need changes.", "advice")) end
  if #snap.recent_edits > 0 and #snap.changed_files == 0 then table.insert(out, item("save-or-check-edits", "Recent buffer edits not reflected in git diff", "Unsaved buffers may make repository context stale.", { snap.recent_edits[1].file }, 0.7, "Save buffers or refresh suggestions after editing.", "advice")) end
  if #out == 0 then table.insert(out, item("no-obstacle", "No immediate obstacle detected", "No visible git changes or diagnostics.", snap.open_buffers, 0.55, "Set a goal with :MasterHandGoal or request suggestions after editing.", "advice")) end
  return out
end

local function provider_items(snap, mode)
  if config.get().model.provider == "none" then return {} end
  local content, err = providers.complete(prompts.suggestions(snap, mode))
  if not content then return { item("provider-error", "Model provider failed", err, {}, 0.3, "Check model config or continue with heuristic suggestions.", "advice") } end
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then return { item("provider-parse-error", "Model suggestions malformed", "Provider did not return JSON array.", {}, 0.3, "Retry or adjust provider prompt/model.", "advice") } end
  return schema.list(decoded)
end

function M.generate(opts)
  opts = opts or {}
  local snap = context.snapshot()
  local out = {}
  vim.list_extend(out, heuristic(snap))
  vim.list_extend(out, provider_items(snap, opts.mode or "suggest"))
  local filtered = {}
  for _, s in ipairs(out) do if not state.data.dismissed[s.id] then table.insert(filtered, s) end end
  state.set_suggestions(filtered)
  return filtered
end

return M
