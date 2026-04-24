-- tests/qa/AC3-4.lua
vim.system = function(argv, opts, cb)
  if cb then
    vim.schedule(function()
      cb({ code = 0, stdout = 'not json', stderr = '' })
    end)
  end
end

local cli = require('nx.cli')
cli._bin_cache = { ['/ws'] = '/fake/nx' }

local got
cli.show_projects('/ws', function(r) got = r end)

vim.wait(100, function() return got ~= nil end, 10)

local ok = got ~= nil and got.ok == false
  and type(got.error) == 'string'
  and got.error:find('parse') ~= nil

local line = ok and 'PASS: AC3-4' or ('FAIL: AC3-4 :: got=' .. vim.inspect(got))
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC3-4.txt')
