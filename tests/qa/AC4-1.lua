-- AC4-1: cache hit returns from second call, CLI called only once
local call_count = 0
local cli = require('nx.cli')
cli.show_projects = function(ws_root, on_done)
  call_count = call_count + 1
  on_done({ ok = true, projects = { 'alpha', 'beta' } })
end

local cache = require('nx.cache')
cache.invalidate()  -- start clean

local results = {}
cache.get_projects('/ws', function(r) table.insert(results, r) end)
-- Second call (cache should be hot now)
cache.get_projects('/ws', function(r) table.insert(results, r) end)

-- Small defer to let vim.schedule fire
vim.defer_fn(function()
  local ok = call_count == 1
    and #results == 2
    and results[1].ok == true
    and results[2].ok == true
    and results[1].projects[1] == 'alpha'

  local line = ok and 'PASS: AC4-1' or ('FAIL: AC4-1 :: call_count=' .. call_count .. ' results=' .. #results)
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC4-1.txt')
  vim.cmd('qa!')
end, 50)
