local context = require("master-hand.context")
local state = require("master-hand.state")

local M = {}

local function item(id, title, reason, files, confidence, next_action, action_type)
  return {
    id = id,
    title = title,
    reason = reason,
    files = files or {},
    confidence = confidence,
    next_action = next_action,
    action_type = action_type or "advice",
    requires_approval = action_type == "proposed_edit" or action_type == "command",
  }
end

function M.generate(opts)
  opts = opts or {}
  local snap = context.snapshot()
  local out = {}

  if snap.goal and snap.goal ~= "" then
    table.insert(out, item(
      "goal-plan",
      "Break goal into repo-aware steps",
      "Active goal set; first useful step is identifying touched modules before editing.",
      snap.changed_files,
      0.82,
      "Run targeted search for symbols/config related to: " .. snap.goal,
      "advice"
    ))
  end

  if snap.diagnostics.errors > 0 then
    table.insert(out, item(
      "diagnostics-errors",
      "Resolve current diagnostics before broad changes",
      "Errors in current workspace can hide regressions from recent edits.",
      snap.open_buffers,
      0.88,
      "Open diagnostics list and fix highest-severity errors first.",
      "advice"
    ))
  end

  if #snap.changed_files > 0 then
    table.insert(out, item(
      "review-git-diff",
      "Review coordinated changes",
      "Git diff has modified files; check whether tests/docs/config need matching updates.",
      snap.changed_files,
      0.76,
      "Inspect git diff and list related files that may need synchronized changes.",
      "advice"
    ))
  end

  if #snap.recent_edits > 0 and #snap.changed_files == 0 then
    table.insert(out, item(
      "save-or-check-edits",
      "Recent buffer edits not reflected in git diff",
      "Unsaved buffers may make repository context stale.",
      { snap.recent_edits[1].file },
      0.7,
      "Save relevant buffers or request a fresh suggestion after editing.",
      "advice"
    ))
  end

  if #out == 0 then
    table.insert(out, item(
      "no-obstacle",
      "No immediate obstacle detected",
      "Repository has no visible git changes or diagnostics from current context.",
      snap.open_buffers,
      0.55,
      "Set a goal with :MasterHandGoal or ask for suggestions after next meaningful edit.",
      "advice"
    ))
  end

  state.set_suggestions(out)
  return out
end

return M
