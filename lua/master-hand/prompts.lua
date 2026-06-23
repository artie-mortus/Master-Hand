-- Prompt builders for model-backed suggestions and proposed diffs.
local M = {}

function M.suggestions(snap, mode, local_suggestions)
  local payload = vim.json.encode({ mode = mode or "suggest", context = snap, local_suggestions = local_suggestions or {} })
  return {
    { role = "system", content = "You are Master Hand, a Neovim coding assistant. First review local_suggestions, then inspect provided repo context and code excerpts. Return only JSON array of suggestions with title, reason, files, confidence, next_action, action_type. Act as an assistant: never claim to edit files or run commands directly; use proposed_edit or command only as suggestions requiring approval." },
    { role = "user", content = payload },
  }
end

function M.diff(snap, request)
  return {
    { role = "system", content = "Return only a unified diff. Do not explain. Modify only repo-relative paths." },
    { role = "user", content = vim.json.encode({ context = snap, request = request }) },
  }
end

return M
