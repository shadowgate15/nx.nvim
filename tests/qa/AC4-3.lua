-- AC4-3: invalidate(root) clears entry, next call re-fetches
local call_count = 0
local cli = require('nx.cli')
cli.show_projects_by_type = function(_, kind, on_done)
  call_count = call_count + 1
  on_done({ ok = true, projects = (kind == 'app') and { 'alpha' } or {} })
end

local cache = require('nx.cache')
cache.invalidate()

cache.get_projects('/ws2', function() end)

vim.defer_fn(function()
  cache.invalidate('/ws2')
  cache.get_projects('/ws2', function() end)

  vim.defer_fn(function()
    -- 3 calls per get_projects (one per kind), invoked twice (pre + post invalidate) = 6.
    local ok = call_count == 6
    local line = ok and 'PASS: AC4-3' or ('FAIL: AC4-3 :: call_count=' .. call_count)
    vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC4-3.txt')
    vim.cmd('qa!')
  end, 50)
end, 50)
