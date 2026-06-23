-- Public plugin API used by commands, autocmds, and sidebar actions.
local config = require("master-hand.config")
local state = require("master-hand.state")
local context = require("master-hand.context")
local suggestions = require("master-hand.suggestions")
local ui = require("master-hand.ui")
local git = require("master-hand.git")
local storage = require("master-hand.storage")
local actions = require("master-hand.actions")
local diff = require("master-hand.diff")
local runner = require("master-hand.runner")
local search = require("master-hand.search")
local index = require("master-hand.index")

local M = {}
local timer = nil

-- Persist only long-lived user intent/feedback, not volatile context or pending actions.
local function save_state() storage.save(state.persistable()) end

local function refresh_suggestions()
  suggestions.generate()
  ui.render()
end

local function debounce_suggest()
  local opts = config.get()
  if opts.proactivity == "passive" then return end
  if timer then
    timer:stop()
    timer:close()
  end
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
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = save_state })
end

function M.setup(opts)
  config.setup(opts)
  state.restore(storage.load())
  state.data.root = git.root()
  setup_autocmds()
end

function M.open()
  if #state.data.suggestions == 0 then suggestions.generate() end
  ui.open()
end

function M.close()
  ui.close()
end

function M.set_goal(goal)
  state.data.long_term_goal = vim.trim(goal or "")
  state.data.long_term_goal_source = state.data.long_term_goal ~= "" and "user" or "inferred"
  state.data.short_term_goal_source = state.data.short_term_goal_source == "user" and "user" or "inferred"
  suggestions.generate({ mode = "goal" })
  save_state()
  ui.render()
  vim.notify("Master Hand steering goal set: " .. state.data.long_term_goal)
end

function M.plan()
  suggestions.generate({ mode = "plan" })
  ui.open()
end

function M.suggest()
  suggestions.generate()
  ui.open()
end

function M.status()
  vim.notify(context.summary())
end

function M.context()
  ui.show_text("Master Hand Context", vim.inspect(context.snapshot()))
end

function M.index()
  ui.show_text("Master Hand Index", vim.inspect(index.build(state.data.root)))
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
