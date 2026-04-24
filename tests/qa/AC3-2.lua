-- tests/qa/AC3-2.lua
local captured = nil
vim.system = function(argv, opts, cb)
  captured = { argv = argv, opts = opts }
  if cb then
    cb({ code = 0, stdout = '[]', stderr = '' })
  end
end

-- Stub resolve_bin to return a fake path
local cli = require('nx.cli')
cli._bin_cache = { ['/tmp'] = '/fake/nx' }

cli.exec({ 'show', 'projects', '--json' }, {
  cwd = '/tmp',
  on_done = function() end,
})

local ok = captured ~= nil
  and type(captured.argv) == 'table'
  and captured.argv[1] == '/fake/nx'
  and captured.argv[2] == 'show'
  and captured.argv[3] == 'projects'
  and captured.argv[4] == '--json'
  and captured.opts.cwd == '/tmp'

local line = ok and 'PASS: AC3-2' or 'FAIL: AC3-2 :: captured=' .. vim.inspect(captured)
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC3-2.txt')
