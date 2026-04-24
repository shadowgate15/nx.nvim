local jobstop_calls = {}
local orig_jobstop = vim.fn.jobstop
vim.fn.jobstop = function(jid)
  table.insert(jobstop_calls, jid)
  return 1
end

local registry = require('nx.registry')
registry.clear()

registry.put('/ws', 'alpha', 'build', {
  terminal = nil,
  bufnr = nil,
  job_id = 42,
  status = 'running',
  exit_code = nil,
  output_file = nil,
  started_at = vim.uv.now(),
  exited_at = nil,
})

local terminal = require('nx.terminal')
terminal.kill('/ws', 'alpha', 'build')

vim.fn.jobstop = orig_jobstop

local ok = #jobstop_calls == 1 and jobstop_calls[1] == 42 and registry.get('/ws', 'alpha', 'build') == nil

local line = ok and 'PASS: AC7-6'
  or (
    'FAIL: AC7-6 :: jobstop_calls='
    .. vim.inspect(jobstop_calls)
    .. ' entry='
    .. tostring(registry.get('/ws', 'alpha', 'build'))
  )
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC7-6.txt')
vim.cmd('qa!')
