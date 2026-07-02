-- Model provider adapters.
local config = require("master-hand.config")
local auth = require("master-hand.auth")
local M = {}

local function config_escape(value)
  return (value:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

-- Auth headers and the JSON body both go through `--config -` on stdin: API keys
-- never appear in the process argv (visible to any local user via ps), and a large
-- context body cannot hit the kernel's per-argument exec limit (E2BIG at ~128KiB).
local function curl_cmd(url, body, headers)
  local cmd = { "curl", "-sS", "-X", "POST", url, "-H", "Content-Type: application/json", "--config", "-" }
  local lines = {}
  for _, header in ipairs(headers or {}) do
    table.insert(lines, string.format('header = "%s"', config_escape(header)))
  end
  -- vim.json.encode emits one line (control chars stay JSON-escaped), so the
  -- quoted config value never contains a raw newline.
  table.insert(lines, string.format('data-raw = "%s"', config_escape(vim.json.encode(body))))
  return cmd, table.concat(lines, "\n") .. "\n"
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
  if type(decoded) ~= "table" then return nil, "provider returned unexpected JSON type" end
  return decoded
end

-- vim.system throws on spawn failure (missing binary, E2BIG argv, ...). Callers
-- need (nil, err) so async suggestion chains degrade instead of dying mid-callback
-- with the loading spinner stuck on.
local function spawn(cmd, opts, on_exit)
  local ok, proc = pcall(vim.system, cmd, opts, on_exit)
  if ok then return proc end
  return nil, tostring(proc)
end

local function post_json(url, body, headers, timeout_ms)
  local cmd, stdin = curl_cmd(url, body, headers)
  local proc, spawn_err = spawn(cmd, { text = true, stdin = stdin, timeout = timeout_ms })
  if not proc then return nil, spawn_err end
  return decode_response(proc:wait(), timeout_ms)
end

local function post_json_async(url, body, headers, timeout_ms, cb)
  local cmd, stdin = curl_cmd(url, body, headers)
  local proc, spawn_err = spawn(cmd, { text = true, stdin = stdin, timeout = timeout_ms }, function(res)
    local decoded, err = decode_response(res, timeout_ms)
    vim.schedule(function() cb(decoded, err) end)
  end)
  if not proc then vim.schedule(function() cb(nil, spawn_err) end) end
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
  local proc, spawn_err = spawn(cmd, { text = true, stdin = stdin, timeout = model.timeout_ms })
  if not proc then return nil, spawn_err end
  return decode_cli_response(proc:wait(), model.timeout_ms, model.provider)
end

local function account_cli_async(model, messages, cb)
  local prompt = messages_prompt(messages)
  local cmd, stdin, err = cli_command(model, prompt)
  if not cmd then cb(nil, err); return end
  local proc, spawn_err = spawn(cmd, { text = true, stdin = stdin, timeout = model.timeout_ms }, function(res)
    local content, cli_err = decode_cli_response(res, model.timeout_ms, model.provider)
    vim.schedule(function() cb(content, cli_err) end)
  end)
  if not proc then vim.schedule(function() cb(nil, spawn_err) end) end
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

-- Parse `ollama list` stdout into installed model names, preferred coder/code/qwen
-- names first (preserving their listed order), then the rest. pick_ollama_model
-- takes the first; completion/pickers use the full list.
function M.parse_ollama_names(stdout)
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
  local names = {}
  for _, name in ipairs(preferred) do table.insert(names, name) end
  for _, name in ipairs(fallback) do table.insert(names, name) end
  return names
end

local function pick_ollama_model(stdout)
  return M.parse_ollama_names(stdout)[1]
end

-- Async list of installed ollama model names; cb(names_or_nil) runs on the main loop.
function M.list_ollama_models(cb)
  local proc = spawn({ "ollama", "list" }, { text = true, timeout = 3000 }, function(res)
    vim.schedule(function()
      cb(res.code == 0 and M.parse_ollama_names(res.stdout) or nil)
    end)
  end)
  if not proc then vim.schedule(function() cb(nil) end) end
end

local function local_ollama_model()
  local proc = spawn({ "ollama", "list" }, { text = true, timeout = 3000 })
  if not proc then return nil end
  local res = proc:wait()
  if res.code ~= 0 then return nil end
  return pick_ollama_model(res.stdout)
end

local function local_ollama_model_async(cb)
  M.list_ollama_models(function(names)
    cb(names and names[1] or nil)
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

local sync_handlers = {
  auto = ollama,
  openai_compatible = openai_compatible,
  openrouter = openrouter,
  ollama = ollama,
  anthropic = anthropic,
}

local async_handlers = {
  auto = ollama_async,
  openai_compatible = openai_compatible_async,
  openrouter = openrouter_async,
  ollama = ollama_async,
  anthropic = anthropic_async,
}

local function infer_provider(model_name)
  model_name = (model_name or ""):lower()
  if model_name:match("^gpt%-?%d") or model_name:match("^o%d") then return "openai_compatible" end
  return "ollama"
end

local function is_ollama_cloud(provider)
  return provider == "ollama_cloud" or provider == "ollama-cloud"
end

local function normalize_provider(provider)
  if provider == "openai" then return "openai_compatible" end
  if is_ollama_cloud(provider) then return "ollama" end
  return provider
end

local function apply_provider_defaults(model)
  model = vim.deepcopy(model or {})
  if not model.provider and model.name then model.provider = infer_provider(model.name) end
  local cloud = is_ollama_cloud(model.provider)
  model.provider = normalize_provider(model.provider)
  if cloud then
    model.endpoint = model.endpoint or "https://ollama.com/api/chat"
    model.api_key_env = model.api_key_env or "OLLAMA_API_KEY"
  elseif model.provider == "openai_compatible" then
    model.endpoint = model.endpoint or "https://api.openai.com/v1/chat/completions"
    model.api_key_env = model.api_key_env or "OPENAI_API_KEY"
  elseif model.provider == "openrouter" then
    model.api_key_env = model.api_key_env or "OPENROUTER_API_KEY"
  elseif model.provider == "anthropic" then
    model.api_key_env = model.api_key_env or "ANTHROPIC_API_KEY"
  end
  return model
end

local function is_cloud_model(model)
  if model.cloud ~= nil then return model.cloud == true end
  if model.is_local == true or model["local"] == true then return false end
  local provider = model.provider
  if provider == "auto" then return false end
  if provider == "ollama" then
    local endpoint = model.endpoint or "http://localhost:11434/api/chat"
    return not (endpoint:match("^https?://localhost") or endpoint:match("^https?://127%.0%.0%.1"))
  end
  return provider == "openai_compatible" or provider == "openrouter" or provider == "anthropic" or auth.is_account_provider(provider)
end

local function rank_value(model)
  return tonumber(model.rank or model.tier or model.score or 0) or 0
end

local function common_model(model)
  local out = vim.deepcopy(model or {})
  for _, key in ipairs({ "ranked", "candidates", "ranking_model", "selection", "cloud_policy", "provider", "name", "endpoint", "api_key_env", "api_key", "executable", "command", "login_command", "rank", "tier", "score", "local", "is_local", "cloud" }) do
    out[key] = nil
  end
  return out
end

local function routed_candidates(model)
  if model.selection == "fixed" then return nil end
  local ranked = model.ranked or model.candidates
  if type(ranked) ~= "table" or #ranked == 0 then return nil end

  local common = common_model(model)
  local candidates = {}
  for index, candidate in ipairs(ranked) do
    if type(candidate) == "table" then
      local merged = apply_provider_defaults(vim.tbl_deep_extend("force", common, candidate))
      merged.selection = "fixed"
      merged._rank_index = index
      table.insert(candidates, merged)
    end
  end

  local best_first = model.cloud_policy == "best"
  table.sort(candidates, function(a, b)
    if not best_first then
      local a_cloud, b_cloud = is_cloud_model(a), is_cloud_model(b)
      if a_cloud ~= b_cloud then return not a_cloud end
    end
    local ar, br = rank_value(a), rank_value(b)
    if ar ~= br then return ar > br end
    return (a._rank_index or 0) < (b._rank_index or 0)
  end)
  return candidates
end

local function model_label(model)
  return table.concat({ tostring(model.provider or "?"), tostring(model.name or "auto") }, "/")
end

local function complete_one(model, messages)
  if model.provider == "none" then return nil, "model provider disabled" end
  local handler = sync_handlers[model.provider]
  if handler then return handler(model, messages) end
  if auth.is_account_provider(model.provider) then return account_cli(model, messages) end
  return nil, "provider not implemented: " .. tostring(model.provider)
end

local function complete_one_async(model, messages, cb)
  if model.provider == "none" then cb(nil, "model provider disabled"); return end
  local handler = async_handlers[model.provider]
  if handler then handler(model, messages, cb); return end
  if auth.is_account_provider(model.provider) then account_cli_async(model, messages, cb); return end
  cb(nil, "provider not implemented: " .. tostring(model.provider))
end

local function request_excerpt(messages)
  local text = messages_prompt(messages)
  text = text:gsub("%s+", " ")
  if #text > 2000 then text = text:sub(1, 2000) .. "…" end
  return text
end

local function ranking_request(model, messages, candidates)
  local instruction = model.cloud_policy == "best"
    and "Pick strongest best-fit model candidate for this request. Return only one number."
    or "Pick best model candidate for this request. Prefer local models unless task clearly needs stronger cloud reasoning. Return only one number."
  local lines = {
    instruction,
    "Request: " .. request_excerpt(messages),
    "Candidates:",
  }
  for i, candidate in ipairs(candidates) do
    table.insert(lines, string.format("%d. provider=%s name=%s local=%s rank=%s", i, tostring(candidate.provider), tostring(candidate.name or "auto"), tostring(not is_cloud_model(candidate)), tostring(rank_value(candidate))))
  end
  return { { role = "user", content = table.concat(lines, "\n") } }
end

local function default_ranking_model(model, candidates)
  if type(model.ranking_model) == "table" then
    return apply_provider_defaults(vim.tbl_deep_extend("force", common_model(model), model.ranking_model, { selection = "fixed" }))
  end
  local best
  for _, candidate in ipairs(candidates) do
    if is_cloud_model(candidate) and (not best or rank_value(candidate) > rank_value(best)) then best = candidate end
  end
  if not best then return nil end
  local ranker = vim.deepcopy(best)
  ranker.selection = "fixed"
  ranker.max_tokens = math.min(tonumber(model.ranking_max_tokens or ranker.max_tokens or 24) or 24, 64)
  ranker.temperature = 0
  return ranker
end

local function reorder_candidates(candidates, picked)
  picked = tonumber((picked or ""):match("%d+"))
  if not picked or not candidates[picked] then return candidates end
  local ordered = { candidates[picked] }
  for i, candidate in ipairs(candidates) do if i ~= picked then table.insert(ordered, candidate) end end
  return ordered
end

local function cloud_rank(model, messages, candidates)
  local ranker = default_ranking_model(model, candidates)
  if not ranker or not is_cloud_model(ranker) then return candidates end
  local choice = complete_one(ranker, ranking_request(model, messages, candidates))
  return reorder_candidates(candidates, choice)
end

local function cloud_rank_async(model, messages, candidates, cb)
  local ranker = default_ranking_model(model, candidates)
  if not ranker or not is_cloud_model(ranker) then cb(candidates); return end
  complete_one_async(ranker, ranking_request(model, messages, candidates), function(choice)
    cb(reorder_candidates(candidates, choice))
  end)
end

local function routed_error(errors)
  return "all routed model candidates failed: " .. table.concat(errors, "; ")
end

local function complete_routed(model, messages, candidates)
  local errors = {}
  for _, candidate in ipairs(cloud_rank(model, messages, candidates)) do
    local content, err = complete_one(candidate, messages)
    if content then return content end
    table.insert(errors, model_label(candidate) .. " " .. tostring(err))
  end
  return nil, routed_error(errors)
end

local function complete_routed_ordered(messages, candidates, cb)
  local errors = {}
  local index = 1
  local function next_candidate()
    local candidate = candidates[index]
    index = index + 1
    if not candidate then cb(nil, routed_error(errors)); return end
    complete_one_async(candidate, messages, function(content, err)
      if content then cb(content); return end
      table.insert(errors, model_label(candidate) .. " " .. tostring(err))
      next_candidate()
    end)
  end
  next_candidate()
end

local function complete_routed_async(model, messages, candidates, cb)
  cloud_rank_async(model, messages, candidates, function(ordered)
    complete_routed_ordered(messages, ordered, cb)
  end)
end

function M.complete(messages, opts)
  local model = apply_provider_defaults(vim.tbl_deep_extend("force", config.get().model, opts or {}))
  local candidates = routed_candidates(model)
  if candidates then return complete_routed(model, messages, candidates) end
  return complete_one(model, messages)
end

function M.complete_async(messages, opts, cb)
  local model = apply_provider_defaults(vim.tbl_deep_extend("force", config.get().model, opts or {}))
  local candidates = routed_candidates(model)
  if candidates then complete_routed_async(model, messages, candidates, cb); return end
  complete_one_async(model, messages, cb)
end

return M
