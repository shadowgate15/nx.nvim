-- AC5-1: put/get/list round-trip, sorted by started_at desc
local registry = require('nx.registry')
registry.clear()

registry.put('/ws', 'alpha', 'build', {
  status = 'running', started_at = 100, bufnr = nil, job_id = nil,
  terminal = nil, exit_code = nil, output_file = nil, exited_at = nil,
})
registry.put('/ws', 'beta', 'test', {
  status = 'exited', started_at = 200, bufnr = nil, job_id = nil,
  terminal = nil, exit_code = 0, output_file = nil, exited_at = 200,
})

local got_alpha = registry.get('/ws', 'alpha', 'build')
local got_beta = registry.get('/ws', 'beta', 'test')
local lst = registry.list('/ws')

local ok = got_alpha ~= nil
  and got_beta ~= nil
  and #lst == 2
  and lst[1].task == 'test'   -- started_at=200 comes first
  and lst[2].task == 'build'

local line = ok and 'PASS: AC5-1'
  or ('FAIL: AC5-1 :: got_alpha=' .. tostring(got_alpha ~= nil) .. ' lst=' .. #lst)
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC5-1.txt')
vim.cmd('qa!')
