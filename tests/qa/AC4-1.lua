-- AC4-1: cache hit returns from second call, CLI called only once per kind
local call_count_by_kind = { app = 0, lib = 0, e2e = 0 }
local cli = require('nx.cli')
cli.show_projects_by_type = function(_, kind, on_done)
  call_count_by_kind[kind] = (call_count_by_kind[kind] or 0) + 1
  if kind == 'app' then
    on_done({ ok = true, projects = { 'alpha' } })
  elseif kind == 'lib' then
    on_done({ ok = true, projects = { 'beta' } })
  else
    on_done({ ok = true, projects = {} })
  end
end

local cache = require('nx.cache')
cache.invalidate()

local results = {}
cache.get_projects('/ws', function(r) table.insert(results, r) end)
cache.get_projects('/ws', function(r) table.insert(results, r) end)

vim.defer_fn(function()
  local total_calls = call_count_by_kind.app + call_count_by_kind.lib + call_count_by_kind.e2e
  local ok = total_calls == 3
    and call_count_by_kind.app == 1
    and call_count_by_kind.lib == 1
    and call_count_by_kind.e2e == 1
    and #results == 2
    and results[1].ok == true
    and results[2].ok == true
    and results[1].projects[1] == 'alpha'
    and results[1].projects[2] == 'beta'

  local line = ok and 'PASS: AC4-1'
    or ('FAIL: AC4-1 :: calls=' .. vim.inspect(call_count_by_kind) .. ' results=' .. vim.inspect(results))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC4-1.txt')
  vim.cmd('qa!')
end, 50)
