-- AC5-2: BufWipeout self-heals running entry
local registry = require('nx.registry')
registry.clear()
registry.attach_self_healing()

-- Create a real scratch buffer
local bufnr = vim.api.nvim_create_buf(false, true)

registry.put('/ws', 'alpha', 'serve', {
  status = 'running', started_at = vim.uv.now(), bufnr = bufnr,
  job_id = nil, terminal = nil, exit_code = nil, output_file = nil, exited_at = nil,
})

-- Wipe the buffer (triggers BufWipeout)
vim.api.nvim_buf_delete(bufnr, { force = true })

vim.defer_fn(function()
  local entry = registry.get('/ws', 'alpha', 'serve')
  local ok = entry ~= nil
    and entry.status == 'exited'
    and entry.exit_code == -1
    and entry.terminal == nil
    and entry.bufnr == nil

  local line = ok and 'PASS: AC5-2'
    or ('FAIL: AC5-2 :: entry=' .. vim.inspect(entry))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC5-2.txt')
  vim.cmd('qa!')
end, 50)
