local registry = require('nx.registry')
registry.clear()

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line A', 'line B', 'line C' })

registry.put('/ws', 'alpha', 'build', {
  terminal = nil,
  bufnr = bufnr,
  job_id = nil,
  status = 'running',
  exit_code = nil,
  output_file = nil,
  started_at = vim.uv.now(),
  exited_at = nil,
})

local terminal = require('nx.terminal')
terminal._on_exit('/ws', 'alpha', 'build', 0)

vim.defer_fn(function()
  local entry = registry.get('/ws', 'alpha', 'build')
  local ok = entry ~= nil
    and entry.status == 'exited'
    and entry.exit_code == 0
    and entry.output_file ~= nil
    and vim.fn.filereadable(entry.output_file) == 1

  if ok then
    local content = vim.fn.readfile(entry.output_file)
    ok = ok and #content == 3 and content[1] == 'line A' and content[3] == 'line C'
  end

  local line = ok and 'PASS: AC7-4' or ('FAIL: AC7-4 :: entry=' .. vim.inspect(entry))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC7-4.txt')
  vim.cmd('qa!')
end, 100)
