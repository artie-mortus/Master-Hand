-- API key and account CLI auth helpers for model providers.
local M = {}

local default_env_by_provider = {
  openrouter = "OPENROUTER_API_KEY",
  anthropic = "ANTHROPIC_API_KEY",
}

local account_cli_by_provider = {
  codex = "codex",
  claude = "claude",
  gemini = "gemini",
  pi = "pi",
  cli = "cli",
}

local login_command_by_provider = {
  codex = { "codex", "login" },
  claude = { "claude", "login" },
  gemini = { "gemini", "auth", "login" },
}

local function split_command(command)
  if type(command) == "table" then return vim.deepcopy(command) end
  if type(command) == "string" and command ~= "" then return vim.split(command, "%s+", { trimempty = true }) end
  return nil
end

local function is_ollama_cloud(model)
  return model and model.provider == "ollama" and model.endpoint and model.endpoint:match("ollama%.com")
end

function M.default_env(model)
  model = model or {}
  if model.api_key_env and model.api_key_env ~= "" then return model.api_key_env end
  if is_ollama_cloud(model) then return "OLLAMA_API_KEY" end
  if model.provider == "openai_compatible" and (not model.endpoint or model.endpoint:match("api%.openai%.com")) then return "OPENAI_API_KEY" end
  return default_env_by_provider[model.provider]
end

function M.key(model)
  model = model or {}
  if model.api_key and model.api_key ~= "" then return model.api_key, nil end
  local env = M.default_env(model)
  if not env or env == "" then return nil, nil end
  local key = os.getenv(env)
  if key and key ~= "" then return key, env end
  return nil, env
end

function M.is_account_provider(provider)
  return account_cli_by_provider[provider] ~= nil
end

function M.login_command(model)
  model = model or {}
  local cmd = split_command(model.login_command) or login_command_by_provider[model.provider]
  if not cmd then return nil, "login command not configured for provider: " .. tostring(model.provider) end
  if model.executable and model.executable ~= "" then cmd[1] = model.executable end
  return cmd
end

function M.mask(value)
  if not value or value == "" then return "" end
  if #value <= 8 then return string.rep("*", #value) end
  return value:sub(1, 4) .. "…" .. value:sub(-4)
end

function M.status(model)
  model = model or {}
  local key, env = M.key(model)
  local parts = { "provider=" .. tostring(model.provider or "?") }
  if M.is_account_provider(model.provider) then
    table.insert(parts, "auth=account-cli")
    if model.executable and model.executable ~= "" then table.insert(parts, "executable=" .. model.executable) end
    return table.concat(parts, " ")
  end
  if env then table.insert(parts, "api_key_env=" .. env) end
  if key then
    table.insert(parts, "auth=set")
  elseif env then
    table.insert(parts, "auth=missing")
  else
    table.insert(parts, "auth=not-required")
  end
  return table.concat(parts, " ")
end

return M
