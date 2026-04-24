local registry = require('nx.registry')
registry.clear()

local tmp = vim.fn.tempname() .. '.nx-test.txt'
vim.fn.writefile({ 'output line 1', 'output line 2' }, tmp)

registry.put('/ws', 'alpha', 'build', {
  terminal = nil,
  bufnr = nil,
  job_id = nil,
  status = 'exited',
  exit_code = 0,
  output_file = tmp,
  started_at = 1,
  exited_at = 2,
})

local win_called = false
package.loaded['snacks'] = {
  win = function(opts)
    win_called = opts and opts.file == tmp
    return {}
  end,
  terminal = function()
    return {}
  end,
}

local terminal = require('nx.terminal')
terminal.foreground('/ws', 'alpha', 'build')

local pass1 = win_called

local notify_calls = {}
local orig_notify = vim.notify
vim.notify = function(msg, level)
  table.insert(notify_calls, { msg = msg, level = level })
end

registry.put('/ws', 'alpha', 'build2', {
  terminal = nil,
  bufnr = nil,
  job_id = nil,
  status = 'exited',
  exit_code = 1,
  output_file = '/nonexistent/path.txt',
  started_at = 1,
  exited_at = 2,
})
terminal.foreground('/ws', 'alpha', 'build2')

local pass2 = #notify_calls > 0
  and notify_calls[#notify_calls].level == vim.log.levels.ERROR
  and registry.get('/ws', 'alpha', 'build2') == nil

vim.notify = orig_notify
os.remove(tmp)

local ok = pass1 and pass2
local line = ok and 'PASS: AC7-5'
  or (
    'FAIL: AC7-5 :: pass1='
    .. tostring(pass1)
    .. ' pass2='
    .. tostring(pass2)
    .. ' notify='
    .. vim.inspect(notify_calls)
  )
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC7-5.txt')
vim.cmd('qa!')
