-- Command-line completion for :MHModel / :MHAuth. Position-aware, never blocks:
-- installed ollama model names come from a session cache refreshed in the background.
local providers = require("master-hand.providers")

local M = {}

local provider_names = {
  "auto", "none", "ollama", "ollama-cloud", "openai", "anthropic",
  "openrouter", "openai_compatible", "codex", "claude", "gemini", "pi", "cli",
}

local model_key_stubs = {
  "provider=", "model=", "selection=", "cloud_policy=", "ranking_max_tokens=",
  "endpoint=", "api_key_env=", "api_key=", "executable=", "command=", "login_command=",
}

local kv_values = {
  provider = provider_names,
  selection = { "auto", "fixed" },
  cloud_policy = { "fallback", "best" },
}

local auth_items = {
  "openai", "openrouter", "anthropic", "ollama-cloud", "codex", "claude", "gemini", "pi", "cli",
  "login", "env:OPENAI_API_KEY", "env:OPENROUTER_API_KEY", "env:ANTHROPIC_API_KEY", "env:OLLAMA_API_KEY", "clear",
}

-- Session cache of installed ollama model names; populated asynchronously.
M._ollama_cache = {}
local ollama_refreshed = false
local ollama_inflight = false

local function complete_from(items, arglead)
  local out = {}
  for _, item in ipairs(items) do
    if item:find(arglead, 1, true) == 1 then table.insert(out, item) end
  end
  return out
end

-- Test/setup seam: inject known ollama model names and skip background refresh.
function M.set_ollama_cache(names)
  M._ollama_cache = names or {}
  ollama_refreshed = true
end

-- Refresh the cache in the background at most once per session, unless it is empty.
function M.refresh_ollama_cache(force)
  if ollama_inflight then return end
  if ollama_refreshed and not force and #M._ollama_cache > 0 then return end
  ollama_inflight = true
  ollama_refreshed = true
  providers.list_ollama_models(function(names)
    M._ollama_cache = names or {}
    ollama_inflight = false
  end)
end

local function ollama_complete(arglead)
  if #M._ollama_cache == 0 then
    M.refresh_ollama_cache()
    return {}
  end
  return complete_from(M._ollama_cache, arglead)
end

-- Positional args already completed before the word under the cursor.
local function positional_context(arglead, cmdline)
  local parts = vim.split(cmdline or "", "%s+", { trimempty = true })
  table.remove(parts, 1) -- command name
  if arglead ~= "" and #parts > 0 then table.remove(parts) end
  return parts
end

local function complete_positional(prev, arglead)
  local pos = #prev + 1
  if pos == 1 then
    local items = {}
    vim.list_extend(items, provider_names)
    vim.list_extend(items, { "fixed", "show" })
    vim.list_extend(items, model_key_stubs)
    return complete_from(items, arglead)
  end
  local first = prev[1]
  if first == "fixed" then
    local rest = {}
    for i = 2, #prev do table.insert(rest, prev[i]) end
    return complete_positional(rest, arglead)
  end
  if first == "ollama" and pos == 2 then
    return ollama_complete(arglead)
  end
  return {}
end

function M.model_complete(arglead, cmdline, _)
  if arglead:find("=", 1, true) then
    local key, val = arglead:match("^([^=]+)=(.*)$")
    local values = key and kv_values[key]
    if not values then return {} end
    local out = {}
    for _, v in ipairs(values) do
      if v:find(val, 1, true) == 1 then table.insert(out, key .. "=" .. v) end
    end
    return out
  end
  return complete_positional(positional_context(arglead, cmdline), arglead)
end

function M.auth_complete(arglead)
  return complete_from(auth_items, arglead)
end

return M
