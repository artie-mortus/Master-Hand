local config = require("master-hand.config")

local M = {}

function M.complete(_messages)
  local model = config.get().model
  if model.provider == "none" then
    return nil, "no model provider configured"
  end
  return nil, "provider not implemented: " .. tostring(model.provider)
end

return M
