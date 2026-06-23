-- Neovim entrypoint: registers :MasterHand commands and short :MH aliases.
if vim.g.loaded_master_hand == 1 then
  return
end
vim.g.loaded_master_hand = 1

local mh = require("master-hand")

local commands = {
  MasterHand = { fn = function() mh.open() end, opts = {}, aliases = { "MH" } },
  MasterHandClose = { fn = function() mh.close() end, opts = {}, aliases = { "MHClose" } },
  MasterHandGoal = { fn = function(opts) mh.set_goal(opts.args) end, opts = { nargs = "+" }, aliases = { "MHGoal" } },
  MasterHandPlan = { fn = function() mh.plan() end, opts = {}, aliases = { "MHPlan" } },
  MasterHandSuggest = { fn = function() mh.suggest() end, opts = {}, aliases = { "MHSuggest" } },
  MasterHandStatus = { fn = function() mh.status() end, opts = {}, aliases = { "MHStatus" } },
  MasterHandContext = { fn = function() mh.context() end, opts = {}, aliases = { "MHContext" } },
  MasterHandIndex = { fn = function() mh.index() end, opts = {}, aliases = { "MHIndex" } },
  MasterHandDiff = { fn = function(opts) mh.prepare_diff(opts.args) end, opts = { nargs = "*" }, aliases = { "MHDiff" } },
  MasterHandApprove = { fn = function(opts) mh.approve(opts.args) end, opts = { nargs = "?" }, aliases = { "MHApprove" } },
  MasterHandReject = { fn = function(opts) mh.reject(opts.args) end, opts = { nargs = "?" }, aliases = { "MHReject" } },
  MasterHandRun = { fn = function(opts) mh.run_command(opts.fargs) end, opts = { nargs = "+" }, aliases = { "MHRun" } },
  MasterHandPending = { fn = function() mh.pending() end, opts = {}, aliases = { "MHPending" } },
  MasterHandSearch = { fn = function(opts) mh.search(opts.args) end, opts = { nargs = "+" }, aliases = { "MHSearch" } },
}

for name, command in pairs(commands) do
  vim.api.nvim_create_user_command(name, command.fn, command.opts)
  for _, alias in ipairs(command.aliases) do
    vim.api.nvim_create_user_command(alias, command.fn, command.opts)
  end
end
