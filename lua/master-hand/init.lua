local config = require("master-hand.config")
local state = require("master-hand.state")
local context = require("master-hand.context")
local suggestions = require("master-hand.suggestions")
local ui = require("master-hand.ui")
local git = require("master-hand.git")

local M = {}
local timer = nil

local function debounce_suggest()
  local opts = config.get()
  if opts.proactivity == "passive" then
    return
  end
  if timer then
    timer:stop()
    timer:close()
  end
  timer = vim.loop.new_timer()
  timer:start(opts.suggestion_frequency_ms, 0, vim.schedule_wrap(function()
    suggestions.generate()
    ui.render()
  end))
end

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("MasterHand", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = group,
    callback = function(args)
      state.add_edit(args.buf)
      debounce_suggest()
    end,
  })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = debounce_suggest,
  })
end

function M.setup(opts)
  config.setup(opts)
  state.data.root = git.root()
  setup_autocmds()
end

function M.open()
  if #state.data.suggestions == 0 then
    suggestions.generate()
  end
  ui.open()
end

function M.close()
  ui.close()
end

function M.set_goal(goal)
  state.data.goal = vim.trim(goal or "")
  suggestions.generate({ mode = "goal" })
  ui.render()
  vim.notify("Master Hand goal set: " .. state.data.goal)
end

function M.plan()
  local goal = state.data.goal
  if not goal or goal == "" then
    vim.notify("Set goal first: :MasterHandGoal <goal>", vim.log.levels.WARN)
    return
  end
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

function M.feedback(action)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local idx = nil
  for i = line, 1, -1 do
    local text = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1] or ""
    idx = tonumber(text:match("^(%d+)%."))
    if idx then
      break
    end
  end
  local suggestion = state.data.suggestions[idx or 0]
  if not suggestion then
    vim.notify("No suggestion under cursor", vim.log.levels.WARN)
    return
  end
  state.feedback(suggestion.id, action)
  if action == "dismissed" then
    table.remove(state.data.suggestions, idx)
  end
  ui.render()
  vim.notify("Suggestion " .. action .. ": " .. suggestion.title)
end

return M
