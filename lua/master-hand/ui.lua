local state = require("master-hand.state")
local config = require("master-hand.config")
local context = require("master-hand.context")
local actions = require("master-hand.actions")

local M = { win = nil, buf = nil }

local function lines()
  local out = { "Master Hand", string.rep("─", 32), context.summary(), "" }
  if state.data.goal then table.insert(out, "Goal: " .. state.data.goal); table.insert(out, "") end
  table.insert(out, "Suggestions")
  for i, s in ipairs(state.data.suggestions) do
    table.insert(out, string.format("%d. %s", i, s.title))
    table.insert(out, "   " .. s.reason)
    table.insert(out, string.format("   confidence: %.2f | action: %s", s.confidence or 0, s.action_type))
    if s.requires_approval then table.insert(out, "   approval required") end
    if #s.files > 0 then table.insert(out, "   files: " .. table.concat(s.files, ", ")) end
    table.insert(out, "   next: " .. s.next_action)
    table.insert(out, "")
  end
  table.insert(out, "Pending approvals")
  for _, a in ipairs(actions.list()) do table.insert(out, string.format("- %s [%s] %s", a.id, a.status, a.title or a.type)) end
  if state.data.last_command then table.insert(out, ""); table.insert(out, "Last command: exit " .. state.data.last_command.code) end
  table.insert(out, "")
  table.insert(out, "Keys: a accept  d dismiss  p postpone  r refresh  v view  q close")
  return out
end

function M.render()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.buf].buftype = "nofile"; vim.bo[M.buf].bufhidden = "wipe"; vim.bo[M.buf].filetype = "masterhand"
  end
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines())
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
end

function M.open()
  M.render()
  if M.win and vim.api.nvim_win_is_valid(M.win) then vim.api.nvim_set_current_win(M.win); return end
  local opts = config.get().ui
  vim.cmd(opts.side == "left" and "topleft vertical new" or "botright vertical new")
  M.win = vim.api.nvim_get_current_win(); vim.api.nvim_win_set_buf(M.win, M.buf); vim.api.nvim_win_set_width(M.win, opts.width); vim.wo[M.win].wrap = true
  local map = function(lhs, rhs) vim.keymap.set("n", lhs, rhs, { buffer = M.buf, silent = true }) end
  map("q", require("master-hand.ui").close); map("r", require("master-hand").suggest)
  map("a", function() require("master-hand").feedback("accepted") end)
  map("d", function() require("master-hand").feedback("dismissed") end)
  map("p", function() require("master-hand").feedback("postponed") end)
  map("v", require("master-hand.ui").view_selected)
end

function M.close() if M.win and vim.api.nvim_win_is_valid(M.win) then vim.api.nvim_win_close(M.win, true) end; M.win = nil end

function M.suggestion_under_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for i = line, 1, -1 do
    local text = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1] or ""
    local idx = tonumber(text:match("^(%d+)%."))
    if idx then return state.data.suggestions[idx] end
  end
end

function M.show_text(title, text)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text or "", "\n", { plain = true }))
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.cmd("vnew"); vim.api.nvim_win_set_buf(0, buf); vim.api.nvim_buf_set_name(buf, title)
end

function M.view_selected()
  local s = M.suggestion_under_cursor()
  if s then M.show_text(s.title, vim.inspect(s)); return end
  if state.data.last_command then M.show_text("Master Hand Command Output", vim.inspect(state.data.last_command)) end
end

return M
