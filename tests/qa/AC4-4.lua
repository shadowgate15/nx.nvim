-- AC4-4: BufWritePost on nx.json triggers invalidation
local cli = require('nx.cli')
cli.show_projects = function(ws_root, on_done)
  on_done({ ok = true, projects = { 'alpha' } })
end

local ws = require('nx.workspace')
local orig_find_root = ws.find_root
ws.find_root = function() return '/ws-autocmd' end

local cache = require('nx.cache')
cache.attach_autocmds()
cache.get_projects('/ws-autocmd', function() end)

vim.defer_fn(function()
  local state_before = cache.state()
  local had_entry = state_before['/ws-autocmd'] ~= nil

  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, 'p')
  local nx_file = tmp_dir .. '/nx.json'
  vim.fn.writefile({ '{}' }, nx_file)

  ws.find_root = function(dir) return '/ws-autocmd' end

  vim.api.nvim_exec_autocmds('BufWritePost', {
    pattern = nx_file,
    data = { file = nx_file },
  })

  vim.defer_fn(function()
    local state_after = cache.state()
    local cleared = state_after['/ws-autocmd'] == nil
    ws.find_root = orig_find_root

    local ok = had_entry and cleared
    local line = ok and 'PASS: AC4-4'
      or ('FAIL: AC4-4 :: had_entry=' .. tostring(had_entry) .. ' cleared=' .. tostring(cleared))
    vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC4-4.txt')
    vim.cmd('qa!')
  end, 50)
end, 100)
