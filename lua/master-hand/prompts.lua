-- Prompt builders for model-backed suggestions and proposed diffs.
local M = {}

function M.suggestions(snap, mode)
  local payload = vim.json.encode({ mode = mode or "suggest", context = snap })
  return {
    { role = "system", content = "You are Master Hand, a Neovim coding assistant. Return only JSON array of suggestions with title, reason, files, confidence, next_action, action_type." },
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
