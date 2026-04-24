-- tests/qa/AC3-3.lua
vim.system = function(argv, opts, cb)
  if cb then
    vim.schedule(function()
      cb({ code = 0, stdout = '["alpha","beta"]', stderr = '' })
    end)
  end
end

local cli = require('nx.cli')
cli._bin_cache = { ['/ws'] = '/fake/nx' }

local got
cli.show_projects('/ws', function(r) got = r end)

vim.wait(100, function() return got ~= nil end, 10)

local ok = got ~= nil and got.ok == true
  and type(got.projects) == 'table'
  and got.projects[1] == 'alpha'
  and got.projects[2] == 'beta'

local line = ok and 'PASS: AC3-3' or ('FAIL: AC3-3 :: got=' .. vim.inspect(got))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC3-3.txt')
