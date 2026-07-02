-- Public plugin API used by commands, autocmds, and sidebar actions.
local config = require("master-hand.config")
local state = require("master-hand.state")
local context = require("master-hand.context")
local suggestions = require("master-hand.suggestions")
local ui = require("master-hand.ui")
local storage = require("master-hand.storage")
local actions = require("master-hand.actions")
local diff = require("master-hand.diff")
local runner = require("master-hand.runner")
local search = require("master-hand.search")
local providers = require("master-hand.providers")
local auth = require("master-hand.auth")
local agent = require("master-hand.agent")

local M = {}
local timer = nil
local loading_timer = nil
local loading_id = 0

-- Persist only long-lived user intent/feedback, not volatile context or pending actions.
local function save_state() storage.save(state.persistable()) end

local function refresh_suggestions()
  M.suggest()
end

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

local function stop_loading(id)
  if id and id ~= loading_id then return false end
  if not id then loading_id = loading_id + 1 end
  if loading_timer then
    loading_timer:stop()
    loading_timer:close()
    loading_timer = nil
  end
  state.data.loading = false
  state.data.loading_message = nil
  state.data.loading_frame = 1
  return true
end

local function start_loading(message)
  stop_loading()
  loading_id = loading_id + 1
  local id = loading_id
  state.data.loading = true
  state.data.loading_message = message or "Loading model suggestions..."
  state.data.loading_frame = 1
  loading_timer = vim.uv.new_timer()
  loading_timer:start(80, 80, vim.schedule_wrap(function()
    state.data.loading_frame = (state.data.loading_frame % 10) + 1
    if ui.is_open() then ui.render() end
  end))
  return id
end

local function run_suggest(mode)
  local id = start_loading(mode == "plan" and "Loading model plan..." or "Loading model suggestions...")
  suggestions.generate_async({ mode = mode or "suggest" }, function()
    if stop_loading(id) and ui.is_open() then ui.render() end
  end)
  if ui.is_open() then ui.render() end
end

local function debounce_suggest()
  local opts = config.get()
  if opts.proactivity == "passive" then return end
  stop_timer()
  timer = vim.uv.new_timer()
  timer:start(opts.suggestion_frequency_ms, 0, vim.schedule_wrap(refresh_suggestions))
end

-- Editor events only refresh suggestions; they never edit files or run commands.
local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("MasterHand", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = group,
    callback = function(args)
      state.add_edit(args.buf)
      debounce_suggest()
    end,
  })
  vim.api.nvim_create_autocmd("DiagnosticChanged", { group = group, callback = debounce_suggest })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      stop_timer()
      stop_loading()
      agent.stop_sync_poll()
      save_state()
    end,
  })
end

function M.setup(opts)
  config.setup(opts)
  state.restore(storage.load())
  state.data.root = vim.uv.cwd()
  setup_autocmds()
end

function M.open()
  ui.open()
  if #state.data.suggestions == 0 and not state.data.loading then run_suggest("suggest") end
end

function M.close()
  ui.close()
end

local function refresh_steered_suggestions()
  state.set_suggestions({})
  if ui.is_open() then
    run_suggest("suggest")
  else
    ui.render()
  end
end

function M.set_goal(goal)
  state.data.long_term_goal = vim.trim(goal or "")
  state.data.long_term_goal_source = state.data.long_term_goal ~= "" and "user" or "inferred"
  state.data.short_term_goal_source = state.data.short_term_goal_source == "user" and "user" or "inferred"
  save_state()
  refresh_steered_suggestions()
  vim.notify("Master Hand long-term direction set: " .. state.data.long_term_goal)
end

function M.set_next(goal)
  state.data.short_term_goal = vim.trim(goal or "")
  state.data.short_term_goal_source = state.data.short_term_goal ~= "" and "user" or "inferred"
  save_state()
  refresh_steered_suggestions()
  if state.data.short_term_goal ~= "" then
    vim.notify("Master Hand short-term next step set: " .. state.data.short_term_goal)
  else
    vim.notify("Master Hand short-term next step reset to inferred")
  end
end

function M.plan()
  ui.open()
  run_suggest("plan")
end

function M.suggest()
  ui.open()
  run_suggest("suggest")
end

function M.model_suggest()
  M.suggest()
end

function M.status()
  if state.data.last_context then
    vim.notify(context.summary(state.data.last_context))
  else
    vim.notify("Master Hand has no cached context yet; run :MHSuggest to refresh.")
  end
end

local model_providers = {
  none = true,
  auto = true,
  ollama = true,
  openrouter = true,
  anthropic = true,
  openai = true,
  openai_compatible = true,
  ollama_cloud = true,
  ["ollama-cloud"] = true,
  codex = true,
  claude = true,
  gemini = true,
  pi = true,
  cli = true,
}

local function normalize_provider(provider)
  if provider == "openai" then return "openai_compatible" end
  if provider == "ollama_cloud" or provider == "ollama-cloud" then return "ollama" end
  return provider
end

local function is_ollama_cloud(provider)
  return provider == "ollama_cloud" or provider == "ollama-cloud"
end

local function infer_provider(model_name)
  model_name = (model_name or ""):lower()
  if model_name:match("^gpt%-?%d") or model_name:match("^o%d") then return "openai_compatible" end
  return "ollama"
end

local function apply_model_defaults(update)
  if not update.provider and update.name and update.name ~= vim.NIL then update.provider = infer_provider(update.name) end
  if not update.provider then return update end
  local cloud = is_ollama_cloud(update.provider)
  update.provider = normalize_provider(update.provider)
  if cloud then
    update.endpoint = update.endpoint or "https://ollama.com/api/chat"
    update.api_key_env = update.api_key_env or "OLLAMA_API_KEY"
  elseif update.provider == "ollama" then
    update.endpoint = update.endpoint or vim.NIL
    update.api_key_env = update.api_key_env or vim.NIL
  elseif update.provider == "openai_compatible" then
    update.endpoint = update.endpoint or "https://api.openai.com/v1/chat/completions"
    update.api_key_env = update.api_key_env or "OPENAI_API_KEY"
  elseif update.provider == "openrouter" then
    update.endpoint = vim.NIL
    update.api_key_env = update.api_key_env or "OPENROUTER_API_KEY"
  elseif update.provider == "anthropic" then
    update.endpoint = vim.NIL
    update.api_key_env = update.api_key_env or "ANTHROPIC_API_KEY"
  else
    update.endpoint = vim.NIL
    update.api_key_env = vim.NIL
    if auth.is_account_provider(update.provider) then update.api_key = vim.NIL end
  end
  if update.provider == "auto" or update.provider == "none" or update.provider == "codex" or update.provider == "claude" or update.provider == "gemini" or update.provider == "pi" then update.name = vim.NIL end
  return update
end

local function model_summary()
  local model = config.get().model or {}
  local parts = { "provider=" .. tostring(model.provider or "?") }
  if model.selection and model.selection ~= "" then table.insert(parts, "selection=" .. tostring(model.selection)) end
  if model.ranked and #model.ranked > 0 then table.insert(parts, "ranked=" .. tostring(#model.ranked)) end
  if model.name and model.name ~= "" then table.insert(parts, "name=" .. model.name) end
  if model.endpoint and model.endpoint ~= "" then table.insert(parts, "endpoint=" .. model.endpoint) end
  if model.api_key_env and model.api_key_env ~= "" then table.insert(parts, "api_key_env=" .. model.api_key_env) end
  if model.api_key and model.api_key ~= "" then table.insert(parts, "api_key=" .. auth.mask(model.api_key)) end
  if model.executable and model.executable ~= "" then table.insert(parts, "executable=" .. model.executable) end
  return table.concat(parts, " ")
end

local function parse_model_args(args)
  args = args or {}
  if #args == 0 then return nil end
  local update = {}
  local has_kv = false
  for _, arg in ipairs(args) do if arg:find("=", 1, true) then has_kv = true end end
  if has_kv then
    for _, arg in ipairs(args) do
      local k, v = arg:match("^([^=]+)=(.*)$")
      if k then
        if k == "model" then k = "name" end
        update[k] = v ~= "" and v or vim.NIL
      end
    end
    return apply_model_defaults(update)
  end

  local first = args[1]
  if first == "fixed" then
    update.selection = "fixed"
    if #args == 1 then return update end
    table.remove(args, 1)
    local nested = parse_model_args(args) or {}
    nested.selection = "fixed"
    return nested
  end
  local explicit_provider = model_providers[first]
  update.provider = explicit_provider and first or infer_provider(first)
  update.name = explicit_provider and (args[2] or vim.NIL) or first
  if update.provider == "openai_compatible" and args[2] and args[2]:match("^https?://") then
    update.endpoint = args[2]
    update.name = args[3] or vim.NIL
  elseif explicit_provider and args[3] and args[3]:match("^https?://") then
    update.endpoint = args[3]
  end
  return apply_model_defaults(update)
end

-- Which picker label the current stored provider corresponds to (config normalizes
-- openai->openai_compatible and ollama-cloud->ollama, so disambiguate by endpoint).
local function current_provider_label()
  local m = config.get().model or {}
  if m.provider == "openai_compatible" then
    if m.endpoint and not m.endpoint:match("api%.openai%.com") then return "openai_compatible" end
    return "openai"
  end
  if m.provider == "ollama" then
    if m.endpoint and m.endpoint:match("ollama%.com") then return "ollama-cloud" end
    return "ollama"
  end
  return m.provider
end

-- Reuse the CLI parse path so picker choices share defaults with :MHModel args.
local function apply_model(args)
  local update = parse_model_args(args)
  if update then
    config.set_model(update)
    state.set_suggestions({})
    ui.render()
  end
  local summary = model_summary()
  if auth.status(config.get().model):find("auth=missing", 1, true) then
    summary = summary .. " — run :MHAuth " .. tostring(config.get().model.provider)
  end
  vim.notify("Master Hand model: " .. summary)
end

local function notify_current_model()
  vim.notify("Master Hand model: " .. model_summary())
end

local provider_choices = {
  { value = "auto", desc = "auto — pick best available" },
  { value = "none", desc = "none — disable model calls" },
  { value = "ollama", desc = "ollama — local models" },
  { value = "ollama-cloud", desc = "ollama-cloud — Ollama Cloud API" },
  { value = "openai", desc = "openai — OpenAI-compatible API" },
  { value = "anthropic", desc = "anthropic — Anthropic API" },
  { value = "openrouter", desc = "openrouter — OpenRouter API" },
  { value = "openai_compatible", desc = "openai_compatible — custom OpenAI-compatible endpoint" },
  { value = "codex", desc = "codex — Codex CLI account login" },
  { value = "claude", desc = "claude — Claude CLI account login" },
  { value = "gemini", desc = "gemini — Gemini CLI account login" },
  { value = "pi", desc = "pi — Pi read-only background model" },
  { value = "cli", desc = "cli — custom CLI command" },
}

-- Providers whose model name is entered free-form via vim.ui.input.
local input_providers = {
  ["ollama-cloud"] = true,
  openai = true,
  anthropic = true,
  openrouter = true,
  openai_compatible = true,
  cli = true,
}

local function pick_model_name_input(provider)
  local default = current_provider_label() == provider and (config.get().model or {}).name or ""
  vim.ui.input({ prompt = "Model name (empty = default): ", default = default }, function(input)
    -- Empty or cancelled input applies the provider only.
    if not input or input == "" then apply_model({ provider }) else apply_model({ provider, input }) end
  end)
end

local function pick_ollama_model()
  providers.list_ollama_models(function(names)
    if not names or #names == 0 then
      vim.ui.input({ prompt = "Ollama model name (empty = auto-pick): " }, function(input)
        if not input or input == "" then apply_model({ "ollama" }) else apply_model({ "ollama", input }) end
      end)
      return
    end
    local auto = "(auto-pick best local model)"
    local items = { auto }
    vim.list_extend(items, names)
    vim.ui.select(items, { prompt = "Ollama model" }, function(choice)
      if not choice then notify_current_model(); return end
      if choice == auto then apply_model({ "ollama" }) else apply_model({ "ollama", choice }) end
    end)
  end)
end

local function on_provider_chosen(provider)
  if provider == "ollama" then
    pick_ollama_model()
  elseif input_providers[provider] then
    pick_model_name_input(provider)
  else
    apply_model({ provider })
  end
end

local function open_model_picker()
  local current = current_provider_label()
  vim.ui.select(provider_choices, {
    prompt = "Master Hand model (" .. model_summary() .. ")",
    format_item = function(item)
      if item.value == current then return item.desc .. "  (current)" end
      return item.desc
    end,
  }, function(choice)
    if not choice then notify_current_model(); return end
    on_provider_chosen(choice.value)
  end)
end

function M.model(args)
  args = args or {}
  if #args == 0 then
    open_model_picker()
    return
  end
  if args[1] == "show" then
    notify_current_model()
    return
  end
  apply_model(args)
end

local function current_model_with(update)
  return vim.tbl_deep_extend("force", config.get().model or {}, update or {})
end

local function auth_env_for(update)
  local env = update.api_key_env or auth.default_env(current_model_with(update))
  return env or "MASTER_HAND_API_KEY"
end

local function run_login_background(argv)
  local ok, err = pcall(vim.system, argv, { text = true, timeout = config.get().model.timeout_ms }, function(res)
    vim.schedule(function()
      local output = vim.trim((res.stdout or "") .. (res.stderr or ""))
      if res.code == 0 then
        vim.notify("Master Hand auth login complete" .. (output ~= "" and (": " .. output) or ""))
      else
        vim.notify("Master Hand auth login failed" .. (output ~= "" and (": " .. output) or (" (exit " .. tostring(res.code) .. ")")), vim.log.levels.ERROR)
      end
    end)
  end)
  if not ok then
    vim.notify("Master Hand auth login failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.auth(args)
  args = vim.deepcopy(args or {})
  if #args == 0 then
    vim.notify("Master Hand auth: " .. auth.status(config.get().model))
    return
  end

  if args[1] == "clear" then
    local env = auth.default_env(config.get().model)
    if env then vim.env[env] = nil end
    config.set_model({ api_key = vim.NIL, api_key_env = vim.NIL })
    vim.notify("Master Hand auth cleared: " .. auth.status(config.get().model))
    return
  end

  local update = {}
  if model_providers[args[1]] and args[1] ~= "auto" and args[1] ~= "none" then
    update = apply_model_defaults({ provider = args[1] })
    table.remove(args, 1)
  end

  local value = args[1]
  if value == "login" then
    config.set_model(update)
    local argv, login_err = auth.login_command(config.get().model)
    if not argv then
      vim.notify("Master Hand auth login failed: " .. tostring(login_err), vim.log.levels.ERROR)
      return
    end
    run_login_background(argv)
    vim.notify("Master Hand auth login started in background for " .. tostring(config.get().model.provider) .. "; browser may open if provider requires it")
    return
  end
  if auth.is_account_provider(current_model_with(update).provider) then
    config.set_model(update)
    if not value or value == "" or value == "status" then
      vim.notify("Master Hand auth: " .. auth.status(config.get().model) .. " (run :MHAuth " .. tostring(config.get().model.provider) .. " login if needed)")
    else
      vim.notify("Master Hand auth: " .. tostring(config.get().model.provider) .. " uses account login, not API keys. Run :MHAuth " .. tostring(config.get().model.provider) .. " login", vim.log.levels.WARN)
    end
    return
  end
  if value and value:match("^env:") then
    update.api_key_env = value:sub(5)
    update.api_key = vim.NIL
    config.set_model(update)
    vim.notify("Master Hand auth: " .. auth.status(config.get().model))
    return
  end

  if not value or value == "" then
    value = vim.fn.inputsecret("Master Hand API key: ")
  end
  if not value or value == "" then
    vim.notify("Master Hand auth unchanged", vim.log.levels.WARN)
    return
  end

  local env = auth_env_for(update)
  vim.env[env] = value
  update.api_key_env = env
  update.api_key = vim.NIL
  config.set_model(update)
  vim.notify("Master Hand auth: " .. auth.status(config.get().model))
end

function M.model_status()
  local content, err = providers.complete({ { role = "user", content = "Return exactly: ok" } }, { max_tokens = 8 })
  if content then
    vim.notify("Master Hand model connected: " .. tostring(content):gsub("%s+", " "))
  else
    vim.notify("Master Hand model failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.context()
  if state.data.last_context then
    ui.show_text("Master Hand Context", vim.inspect(state.data.last_context))
  else
    vim.notify("Master Hand has no cached context yet; run :MHSuggest to refresh.")
  end
end

function M.index()
  if state.data.last_context and state.data.last_context.repo_index then
    ui.show_text("Master Hand Index", vim.inspect(state.data.last_context.repo_index))
  else
    vim.notify("Master Hand has no cached index yet; run :MHModelSuggest for full context.")
  end
end
function M.search(query)
  local hits = search.rg(state.data.root, query, config.get().context.max_search_results)
  ui.show_text("Master Hand Search", vim.inspect(hits))
end

function M.sync()
  agent.sync()
  ui.render()
  vim.notify("Master Hand checked external file changes")
end

function M.approve_suggestion(index)
  local suggestion = state.suggestion(index)
  if not suggestion then
    suggestion = ui.suggestion_under_cursor()
  end
  if not suggestion then
    vim.notify("No suggestion selected", vim.log.levels.WARN)
    return
  end
  state.feedback(suggestion.id, "accepted")
  save_state()
  local res, err = agent.dispatch(suggestion)
  if not res then
    vim.notify("Agent handoff failed: " .. tostring(err), vim.log.levels.ERROR)
    ui.render()
    return
  end
  vim.notify("Sent suggestion to agent; watching files for changes")
  ui.render()
end

function M.accept_suggestion()
  M.approve_suggestion()
end

function M.prepare_diff(request)
  local patch, err = diff.prepare(request)
  if not patch then
    vim.notify("Diff prepare failed: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  local action = actions.create({ type = "proposed_edit", title = "Proposed diff", diff = patch, root = state.data.root })
  ui.show_text("Master Hand Diff " .. action.id, patch)
  ui.render()
end

-- Apply approved actions. This is the only path that executes commands or applies diffs.
function M.approve(id)
  id = id and id ~= "" and id or nil
  local action = id and actions.get(id) or actions.list()[1]
  if not action then
    vim.notify("No pending action", vim.log.levels.WARN)
    return
  end
  if action.type == "proposed_edit" then
    local ok, err = diff.apply(action.root, action.diff)
    if not ok then
      vim.notify("Apply failed: " .. tostring(err), vim.log.levels.ERROR)
      ui.render()
      return
    end
    actions.approve(action.id)
    vim.notify("Applied " .. action.id, vim.log.levels.INFO)
  elseif action.type == "command" then
    local res, err = runner.run(state.data.root, action.argv)
    if not res then
      vim.notify("Command failed: " .. tostring(err), vim.log.levels.ERROR)
      ui.render()
      return
    end
    actions.approve(action.id)
    state.data.last_command = res
    ui.show_text("Master Hand Command Output", table.concat({ "$ " .. table.concat(res.argv, " "), "", res.stdout, res.stderr }, "\n"))
  end
  ui.render()
end

function M.reject(id)
  local action = actions.reject(id)
  vim.notify(action and ("Rejected " .. id) or "No such action")
end

function M.pending()
  ui.open()
end

function M.run_command(args)
  local argv, err = runner.validate(args)
  if not argv then
    vim.notify("Command rejected: " .. err, vim.log.levels.ERROR)
    return
  end
  local action = actions.create({ type = "command", title = "Run command", argv = argv })
  vim.notify("Command pending approval: " .. action.id)
  ui.render()
end

function M.feedback(action)
  local suggestion = ui.suggestion_under_cursor()
  if not suggestion then
    vim.notify("No suggestion under cursor", vim.log.levels.WARN)
    return
  end
  state.feedback(suggestion.id, action)
  save_state()
  if action == "dismissed" then
    for i, s in ipairs(state.data.suggestions) do
      if s.id == suggestion.id then
        table.remove(state.data.suggestions, i)
        break
      end
    end
  end
  ui.render()
  vim.notify("Suggestion " .. action .. ": " .. suggestion.title)
end

return M
