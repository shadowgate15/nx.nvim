-- AC-INTEG-2: cache + BufWritePost autocmd integration.

require('nx').setup({})

local cli = require('nx.cli')
cli._bin_cache = { ['/ws-integ2'] = '/fake/nx' }
cli.resolve_bin = function() return '/fake/nx' end
local call_count = 0
cli.show_projects = function(_, on_done)
  call_count = call_count + 1
  on_done({ ok = true, projects = { 'alpha' } })
end

local ws = require('nx.workspace')
ws.find_root = function() return '/ws-integ2' end

local cache = require('nx.cache')
cache.invalidate()
cache.get_projects('/ws-integ2', function() end)

vim.defer_fn(function()
  local had_cache = cache.state()['/ws-integ2'] ~= nil

  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, 'p')
  local nx_file = tmp_dir .. '/nx.json'
  vim.fn.writefile({ '{}' }, nx_file)

  vim.api.nvim_exec_autocmds('BufWritePost', {
    pattern = nx_file,
    data = { file = nx_file },
  })

  vim.defer_fn(function()
    local cleared = cache.state()['/ws-integ2'] == nil

    cache.get_projects('/ws-integ2', function() end)

    vim.defer_fn(function()
      local ok = had_cache and cleared and call_count == 2
      local line = ok and 'PASS: AC-INTEG-2'
        or ('FAIL: AC-INTEG-2 :: had_cache=' .. tostring(had_cache)
            .. ' cleared=' .. tostring(cleared) .. ' call_count=' .. call_count)
      vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC-INTEG-2.txt')
      vim.cmd('qa!')
    end, 100)
  end, 100)
end, 100)
