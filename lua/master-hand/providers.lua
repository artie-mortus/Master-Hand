local config = require("master-hand.config")
local M = {}

function M.complete(messages, opts)
  local model = vim.tbl_deep_extend("force", config.get().model, opts or {})
  if model.provider == "none" then return nil, "no model provider configured" end
  if model.provider ~= "openai_compatible" then return nil, "provider not implemented: " .. tostring(model.provider) end
  if not model.endpoint or not model.name then return nil, "model.endpoint and model.name required" end
  local key = model.api_key_env and os.getenv(model.api_key_env) or nil
  local body = vim.json.encode({ model = model.name, messages = messages, temperature = model.temperature, max_tokens = model.max_tokens })
  local cmd = { "curl", "-sS", "-X", "POST", model.endpoint, "-H", "Content-Type: application/json", "-d", body }
  if key and key ~= "" then vim.list_extend(cmd, { "-H", "Authorization: Bearer " .. key }) end
  local res = vim.system(cmd, { text = true, timeout = model.timeout_ms }):wait()
  if res.code ~= 0 then return nil, res.stderr ~= "" and res.stderr or "provider request failed" end
  local ok, decoded = pcall(vim.json.decode, res.stdout or "")
  if not ok then return nil, "provider returned invalid JSON" end
  local content = decoded.choices and decoded.choices[1] and decoded.choices[1].message and decoded.choices[1].message.content
  return content, content and nil or "provider response missing choices[1].message.content"
end

return M
