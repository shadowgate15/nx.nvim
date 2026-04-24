-- AC10-4: register() creates NxProject, NxProjectTasks, NxRefresh commands
local commands = require('nx.commands')
commands.register()

local ok = vim.fn.exists(':NxProject') == 2
  and vim.fn.exists(':NxProjectTasks') == 2
  and vim.fn.exists(':NxRefresh') == 2

local line = ok and 'PASS: AC10-4'
  or ('FAIL: AC10-4 :: NxProject=' .. vim.fn.exists(':NxProject')
      .. ' NxProjectTasks=' .. vim.fn.exists(':NxProjectTasks')
      .. ' NxRefresh=' .. vim.fn.exists(':NxRefresh'))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC10-4.txt')
vim.cmd('qa!')
