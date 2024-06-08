local overseer = require('overseer')

local M = {}

function M.setup()
  overseer.load_template('nx')
end

return M
