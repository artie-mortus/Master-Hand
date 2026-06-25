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

local M = {}
local timer = nil
local loading_timer = nil

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

local function stop_loading()
  if loading_timer then
    loading_timer:stop()
    loading_timer:close()
    loading_timer = nil
  end
  state.data.loading = false
  state.data.loading_message = nil
  state.data.loading_frame = 1
end

local function start_loading(message)
  stop_loading()
  state.data.loading = true
  state.data.loading_message = message or "Loading model suggestions..."
  state.data.loading_frame = 1
  loading_timer = vim.loop.new_timer()
  loading_timer:start(80, 80, vim.schedule_wrap(function()
    state.data.loading_frame = (state.data.loading_frame % 10) + 1
    if ui.win and vim.api.nvim_win_is_valid(ui.win) then ui.render() end
  end))
end

local function run_suggest(mode)
  start_loading(mode == "plan" and "Loading model plan..." or "Loading model suggestions...")
  suggestions.generate_async({ mode = mode or "suggest" }, function()
    stop_loading()
    if ui.win and vim.api.nvim_win_is_valid(ui.win) then ui.render() end
  end)
  if ui.win and vim.api.nvim_win_is_valid(ui.win) then ui.render() end
end

local function debounce_suggest()
  local opts = config.get()
  if opts.proactivity == "passive" then return end
  stop_timer()
  timer = vim.loop.new_timer()
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
      save_state()
    end,
  })
end

function M.setup(opts)
  config.setup(opts)
  state.restore(storage.load())
  state.data.root = vim.loop.cwd()
  setup_autocmds()
end

function M.open()
  ui.open()
  if #state.data.suggestions == 0 and not state.data.loading then run_suggest("suggest") end
end

function M.close()
  ui.close()
end

function M.set_goal(goal)
  state.data.long_term_goal = vim.trim(goal or "")
  state.data.long_term_goal_source = state.data.long_term_goal ~= "" and "user" or "inferred"
  state.data.short_term_goal_source = state.data.short_term_goal_source == "user" and "user" or "inferred"
  save_state()
  ui.render()
  vim.notify("Master Hand steering goal set: " .. state.data.long_term_goal)
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
  openai_compatible = true,
}

local function model_summary()
  local model = config.get().model or {}
  local parts = { "provider=" .. tostring(model.provider or "?") }
  if model.name and model.name ~= "" then table.insert(parts, "name=" .. model.name) end
  if model.endpoint and model.endpoint ~= "" then table.insert(parts, "endpoint=" .. model.endpoint) end
  if model.api_key_env and model.api_key_env ~= "" then table.insert(parts, "api_key_env=" .. model.api_key_env) end
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
    return update
  end

  local first = args[1]
  local provider = model_providers[first] and first or "ollama"
  update.provider = provider
  if provider ~= "openai_compatible" then
    update.endpoint = vim.NIL
    update.api_key_env = vim.NIL
  end
  local next_arg = model_providers[first] and 2 or 1
  if provider == "openai_compatible" and args[next_arg] and args[next_arg]:match("^https?://") then
    update.endpoint = args[next_arg]
    update.name = args[next_arg + 1] or vim.NIL
  else
    update.name = args[next_arg] or vim.NIL
  end
  return update
end

function M.model(args)
  local update = parse_model_args(args)
  if update then
    config.set_model(update)
    state.set_suggestions({})
    ui.render()
  end
  vim.notify("Master Hand model: " .. model_summary())
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
  actions.approve(action.id)
  if action.type == "proposed_edit" then
    local ok, err = diff.apply(action.root, action.diff)
    vim.notify(ok and ("Applied " .. action.id) or ("Apply failed: " .. tostring(err)), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  elseif action.type == "command" then
    local res, err = runner.run(state.data.root, action.argv)
    if not res then
      vim.notify("Command failed: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
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
