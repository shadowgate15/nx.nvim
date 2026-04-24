-- AC5-3: remove cleans up output_file; graceful on missing file
local registry = require('nx.registry')
registry.clear()

-- Create a real tempfile
local tmp = vim.fn.tempname() .. '.nx-test.txt'
vim.fn.writefile({ 'test output' }, tmp)
assert(vim.fn.filereadable(tmp) == 1, 'tempfile should exist')

registry.put('/ws', 'alpha', 'build', {
  status = 'exited', started_at = 1, bufnr = nil, job_id = nil,
  terminal = nil, exit_code = 0, output_file = tmp, exited_at = 2,
})
registry.remove('/ws', 'alpha', 'build')

local removed_file = vim.fn.filereadable(tmp) == 0
local removed_entry = registry.get('/ws', 'alpha', 'build') == nil

-- Also test: remove when file already gone (no error)
registry.put('/ws', 'alpha', 'build2', {
  status = 'exited', started_at = 1, bufnr = nil, job_id = nil,
  terminal = nil, exit_code = 0, output_file = '/nonexistent/fake.txt', exited_at = 2,
})
local ok2, err = pcall(registry.remove, '/ws', 'alpha', 'build2')

local ok = removed_file and removed_entry and ok2
local line = ok and 'PASS: AC5-3'
  or ('FAIL: AC5-3 :: removed_file=' .. tostring(removed_file) .. ' removed_entry=' .. tostring(removed_entry) .. ' ok2=' .. tostring(ok2) .. ' err=' .. tostring(err))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC5-3.txt')
vim.cmd('qa!')
