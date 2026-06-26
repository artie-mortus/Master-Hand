-- Model provider adapters.
local config = require("master-hand.config")
local auth = require("master-hand.auth")
local M = {}

local function curl_cmd(url, body, headers)
  local cmd = { "curl", "-sS", "-X", "POST", url, "-H", "Content-Type: application/json" }
  for _, header in ipairs(headers or {}) do vim.list_extend(cmd, { "-H", header }) end
  vim.list_extend(cmd, { "-d", vim.json.encode(body) })
  return cmd
end

local function decode_response(res, timeout_ms)
  if res.code ~= 0 then
    if res.code == 124 or res.signal == 15 then
      return nil, string.format("provider request timed out after %.1fs", (timeout_ms or 0) / 1000)
    end
    local detail = res.stderr ~= "" and res.stderr or res.stdout
    return nil, detail ~= "" and detail or ("provider request failed (exit " .. tostring(res.code) .. ")")
  end
  local ok, decoded = pcall(vim.json.decode, res.stdout or "")
  if not ok then return nil, "provider returned invalid JSON" end
  return decoded
end

local function post_json(url, body, headers, timeout_ms)
  return decode_response(vim.system(curl_cmd(url, body, headers), { text = true, timeout = timeout_ms }):wait(), timeout_ms)
end

local function post_json_async(url, body, headers, timeout_ms, cb)
  vim.system(curl_cmd(url, body, headers), { text = true, timeout = timeout_ms }, function(res)
    local decoded, err = decode_response(res, timeout_ms)
    vim.schedule(function() cb(decoded, err) end)
  end)
end

local account_cli_commands = {
  codex = { "codex", "exec", "{prompt}" },
  claude = { "claude", "-p", "{prompt}" },
  gemini = { "gemini", "-p", "{prompt}" },
  pi = { "pi", "--no-tools", "--no-session", "-p", "{prompt}" },
}

local function messages_prompt(messages)
  local out = {}
  for _, msg in ipairs(messages or {}) do
    table.insert(out, string.format("%s:\n%s", msg.role or "user", msg.content or ""))
  end
  return table.concat(out, "\n\n")
end

local function split_command(command)
  if type(command) == "table" then return vim.deepcopy(command) end
  if type(command) == "string" and command ~= "" then return vim.split(command, "%s+", { trimempty = true }) end
  return nil
end

local function cli_command(model, prompt)
  local cmd = split_command(model.command) or account_cli_commands[model.provider]
  if not cmd then return nil, nil, "model.command required for cli provider" end
  if model.executable and model.executable ~= "" then cmd[1] = model.executable end
  local used_prompt = false
  for i, arg in ipairs(cmd) do
    if type(arg) == "string" and arg:find("{prompt}", 1, true) then
      cmd[i] = arg:gsub("{prompt}", prompt)
      used_prompt = true
    end
  end
  return cmd, used_prompt and nil or prompt
end

local function decode_cli_response(res, timeout_ms, provider)
  if res.code ~= 0 then
    if res.code == 124 or res.signal == 15 then
      return nil, string.format("provider request timed out after %.1fs", (timeout_ms or 0) / 1000)
    end
    local detail = res.stderr ~= "" and res.stderr or res.stdout
    local hint = provider and account_cli_commands[provider] and ("; run :MHAuth " .. provider .. " login") or ""
    return nil, (detail ~= "" and detail or ("provider request failed (exit " .. tostring(res.code) .. ")")) .. hint
  end
  local content = vim.trim(res.stdout or "")
  if content ~= "" then return content end
  return nil, "cli provider returned empty output"
end

local function account_cli(model, messages)
  local prompt = messages_prompt(messages)
  local cmd, stdin, err = cli_command(model, prompt)
  if not cmd then return nil, err end
  return decode_cli_response(vim.system(cmd, { text = true, stdin = stdin, timeout = model.timeout_ms }):wait(), model.timeout_ms, model.provider)
end

local function account_cli_async(model, messages, cb)
  local prompt = messages_prompt(messages)
  local cmd, stdin, err = cli_command(model, prompt)
  if not cmd then cb(nil, err); return end
  vim.system(cmd, { text = true, stdin = stdin, timeout = model.timeout_ms }, function(res)
    local content, cli_err = decode_cli_response(res, model.timeout_ms, model.provider)
    vim.schedule(function() cb(content, cli_err) end)
  end)
end

local function openai_body(model, messages)
  return {
    model = model.name,
    messages = messages,
    temperature = model.temperature,
    max_tokens = model.max_tokens,
  }
end

local function openai_content(decoded)
  local content = decoded.choices and decoded.choices[1] and decoded.choices[1].message and decoded.choices[1].message.content
  if content then return content end
  return nil, "provider response missing choices[1].message.content"
end

local function openai_compatible(model, messages)
  if not model.endpoint or not model.name then return nil, "model.endpoint and model.name required" end
  local key = auth.key(model)
  local headers = {}
  if key then table.insert(headers, "Authorization: Bearer " .. key) end
  local decoded, err = post_json(model.endpoint, openai_body(model, messages), headers, model.timeout_ms)
  if not decoded then return nil, err end
  return openai_content(decoded)
end

local function openai_compatible_async(model, messages, cb)
  if not model.endpoint or not model.name then cb(nil, "model.endpoint and model.name required"); return end
  local key = auth.key(model)
  local headers = {}
  if key then table.insert(headers, "Authorization: Bearer " .. key) end
  post_json_async(model.endpoint, openai_body(model, messages), headers, model.timeout_ms, function(decoded, err)
    if not decoded then cb(nil, err); return end
    cb(openai_content(decoded))
  end)
end

local function openrouter(model, messages)
  model.endpoint = model.endpoint or "https://openrouter.ai/api/v1/chat/completions"
  model.api_key_env = model.api_key_env or "OPENROUTER_API_KEY"
  local key = auth.key(model)
  if not key then return nil, "openrouter api key missing: set model.api_key_env" end
  return openai_compatible(model, messages)
end

local function openrouter_async(model, messages, cb)
  model.endpoint = model.endpoint or "https://openrouter.ai/api/v1/chat/completions"
  model.api_key_env = model.api_key_env or "OPENROUTER_API_KEY"
  local key = auth.key(model)
  if not key then cb(nil, "openrouter api key missing: set model.api_key_env"); return end
  openai_compatible_async(model, messages, cb)
end

local function pick_ollama_model(stdout)
  local preferred, fallback = {}, {}
  for line in (stdout or ""):gmatch("[^\n]+") do
    local name = line:match("^(%S+)")
    if name and name ~= "NAME" then
      if name:lower():match("coder") or name:lower():match("code") or name:lower():match("qwen") then
        table.insert(preferred, name)
      else
        table.insert(fallback, name)
      end
    end
  end
  return preferred[1] or fallback[1]
end

local function local_ollama_model()
  local res = vim.system({ "ollama", "list" }, { text = true, timeout = 3000 }):wait()
  if res.code ~= 0 then return nil end
  return pick_ollama_model(res.stdout)
end

local function local_ollama_model_async(cb)
  vim.system({ "ollama", "list" }, { text = true, timeout = 3000 }, function(res)
    vim.schedule(function()
      cb(res.code == 0 and pick_ollama_model(res.stdout) or nil)
    end)
  end)
end

local function ollama_body(model, messages)
  return {
    model = model.name,
    messages = messages,
    stream = false,
    options = { temperature = model.temperature, num_predict = model.max_tokens },
  }
end

local function ollama_content(decoded)
  local content = decoded.message and decoded.message.content
  if content then return content end
  return nil, "ollama response missing message.content"
end

local function ollama_headers(model)
  local key = auth.key(model)
  return key and { "Authorization: Bearer " .. key } or {}
end

local function ollama(model, messages)
  local endpoint = model.endpoint or "http://localhost:11434/api/chat"
  model.name = model.name or local_ollama_model()
  if not model.name then return nil, "no local ollama model available" end
  local decoded, err = post_json(endpoint, ollama_body(model, messages), ollama_headers(model), model.timeout_ms)
  if not decoded then return nil, err end
  return ollama_content(decoded)
end

local function ollama_async(model, messages, cb)
  local endpoint = model.endpoint or "http://localhost:11434/api/chat"
  local function post()
    if not model.name then cb(nil, "no local ollama model available"); return end
    post_json_async(endpoint, ollama_body(model, messages), ollama_headers(model), model.timeout_ms, function(decoded, err)
      if not decoded then cb(nil, err); return end
      cb(ollama_content(decoded))
    end)
  end
  if model.name then post(); return end
  local_ollama_model_async(function(name)
    model.name = name
    post()
  end)
end

local function anthropic_payload(model, messages)
  local system_parts, user_messages = {}, {}
  for _, msg in ipairs(messages or {}) do
    if msg.role == "system" then
      table.insert(system_parts, msg.content)
    else
      table.insert(user_messages, { role = msg.role == "assistant" and "assistant" or "user", content = msg.content })
    end
  end
  return {
    model = model.name,
    max_tokens = model.max_tokens,
    temperature = model.temperature,
    system = table.concat(system_parts, "\n\n"),
    messages = user_messages,
  }
end

local function anthropic_content(decoded)
  local content = decoded.content and decoded.content[1] and decoded.content[1].text
  if content then return content end
  return nil, "anthropic response missing content[1].text"
end

local function anthropic_headers(key)
  return { "x-api-key: " .. key, "anthropic-version: 2023-06-01" }
end

local function anthropic(model, messages)
  if not model.name then return nil, "model.name required" end
  local endpoint = model.endpoint or "https://api.anthropic.com/v1/messages"
  local key = auth.key(model)
  if not key then return nil, "anthropic api key missing: set model.api_key_env" end
  local decoded, err = post_json(endpoint, anthropic_payload(model, messages), anthropic_headers(key), model.timeout_ms)
  if not decoded then return nil, err end
  return anthropic_content(decoded)
end

local function anthropic_async(model, messages, cb)
  if not model.name then cb(nil, "model.name required"); return end
  local endpoint = model.endpoint or "https://api.anthropic.com/v1/messages"
  local key = auth.key(model)
  if not key then cb(nil, "anthropic api key missing: set model.api_key_env"); return end
  post_json_async(endpoint, anthropic_payload(model, messages), anthropic_headers(key), model.timeout_ms, function(decoded, err)
    if not decoded then cb(nil, err); return end
    cb(anthropic_content(decoded))
  end)
end

function M.complete(messages, opts)
  local model = vim.tbl_deep_extend("force", config.get().model, opts or {})
  if model.provider == "none" then return nil, "model provider disabled" end
  if model.provider == "auto" then return ollama(model, messages) end
  if model.provider == "openai_compatible" then return openai_compatible(model, messages) end
  if model.provider == "openrouter" then return openrouter(model, messages) end
  if model.provider == "ollama" then return ollama(model, messages) end
  if model.provider == "anthropic" then return anthropic(model, messages) end
  if model.provider == "codex" or model.provider == "claude" or model.provider == "gemini" or model.provider == "pi" or model.provider == "cli" then return account_cli(model, messages) end
  return nil, "provider not implemented: " .. tostring(model.provider)
end

function M.complete_async(messages, opts, cb)
  local model = vim.tbl_deep_extend("force", config.get().model, opts or {})
  if model.provider == "none" then cb(nil, "model provider disabled"); return end
  if model.provider == "auto" then ollama_async(model, messages, cb); return end
  if model.provider == "openai_compatible" then openai_compatible_async(model, messages, cb); return end
  if model.provider == "openrouter" then openrouter_async(model, messages, cb); return end
  if model.provider == "ollama" then ollama_async(model, messages, cb); return end
  if model.provider == "anthropic" then anthropic_async(model, messages, cb); return end
  if model.provider == "codex" or model.provider == "claude" or model.provider == "gemini" or model.provider == "pi" or model.provider == "cli" then account_cli_async(model, messages, cb); return end
  cb(nil, "provider not implemented: " .. tostring(model.provider))
end

return M
