-- Model provider adapters.
local config = require("master-hand.config")
local M = {}

local function post_json(url, body, headers, timeout_ms)
  local cmd = { "curl", "-sS", "-X", "POST", url, "-H", "Content-Type: application/json" }
  for _, header in ipairs(headers or {}) do vim.list_extend(cmd, { "-H", header }) end
  vim.list_extend(cmd, { "-d", vim.json.encode(body) })
  local res = vim.system(cmd, { text = true, timeout = timeout_ms }):wait()
  if res.code ~= 0 then return nil, res.stderr ~= "" and res.stderr or "provider request failed" end
  local ok, decoded = pcall(vim.json.decode, res.stdout or "")
  if not ok then return nil, "provider returned invalid JSON" end
  return decoded
end

local function openai_compatible(model, messages)
  if not model.endpoint or not model.name then return nil, "model.endpoint and model.name required" end
  local key = model.api_key_env and os.getenv(model.api_key_env) or nil
  local headers = {}
  if key and key ~= "" then table.insert(headers, "Authorization: Bearer " .. key) end
  local decoded, err = post_json(model.endpoint, {
    model = model.name,
    messages = messages,
    temperature = model.temperature,
    max_tokens = model.max_tokens,
  }, headers, model.timeout_ms)
  if not decoded then return nil, err end
  local content = decoded.choices and decoded.choices[1] and decoded.choices[1].message and decoded.choices[1].message.content
  return content, content and nil or "provider response missing choices[1].message.content"
end

local function openrouter(model, messages)
  model.endpoint = model.endpoint or "https://openrouter.ai/api/v1/chat/completions"
  model.api_key_env = model.api_key_env or "OPENROUTER_API_KEY"
  local key = os.getenv(model.api_key_env) or ""
  if key == "" then return nil, "openrouter api key missing: set model.api_key_env" end
  return openai_compatible(model, messages)
end

local function local_ollama_model()
  local res = vim.system({ "ollama", "list" }, { text = true, timeout = 3000 }):wait()
  if res.code ~= 0 then return nil end
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local name = line:match("^(%S+)")
    if name and name ~= "NAME" then return name end
  end
end

local function ollama(model, messages)
  local endpoint = model.endpoint or "http://localhost:11434/api/chat"
  model.name = model.name or local_ollama_model()
  if not model.name then return nil, "no local ollama model available" end
  local decoded, err = post_json(endpoint, {
    model = model.name,
    messages = messages,
    stream = false,
    options = { temperature = model.temperature, num_predict = model.max_tokens },
  }, {}, model.timeout_ms)
  if not decoded then return nil, err end
  local content = decoded.message and decoded.message.content
  return content, content and nil or "ollama response missing message.content"
end

local function anthropic(model, messages)
  if not model.name then return nil, "model.name required" end
  local endpoint = model.endpoint or "https://api.anthropic.com/v1/messages"
  local key = model.api_key_env and os.getenv(model.api_key_env) or nil
  if not key or key == "" then return nil, "anthropic api key missing: set model.api_key_env" end

  local system_parts, user_messages = {}, {}
  for _, msg in ipairs(messages or {}) do
    if msg.role == "system" then
      table.insert(system_parts, msg.content)
    else
      table.insert(user_messages, { role = msg.role == "assistant" and "assistant" or "user", content = msg.content })
    end
  end

  local decoded, err = post_json(endpoint, {
    model = model.name,
    max_tokens = model.max_tokens,
    temperature = model.temperature,
    system = table.concat(system_parts, "\n\n"),
    messages = user_messages,
  }, {
    "x-api-key: " .. key,
    "anthropic-version: 2023-06-01",
  }, model.timeout_ms)
  if not decoded then return nil, err end
  local content = decoded.content and decoded.content[1] and decoded.content[1].text
  return content, content and nil or "anthropic response missing content[1].text"
end

function M.complete(messages, opts)
  local model = vim.tbl_deep_extend("force", config.get().model, opts or {})
  if model.provider == "auto" then return ollama(model, messages) end
  if model.provider == "openai_compatible" then return openai_compatible(model, messages) end
  if model.provider == "openrouter" then return openrouter(model, messages) end
  if model.provider == "ollama" then return ollama(model, messages) end
  if model.provider == "anthropic" then return anthropic(model, messages) end
  return nil, "provider not implemented: " .. tostring(model.provider)
end

return M
