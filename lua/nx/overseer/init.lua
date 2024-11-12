local M = {}

function M.setup()
  local overseer = require('overseer')

  overseer.load_template('nx')
end

return M
