local hide_count = 0
local show_count = 0
local focus_count = 0

local fake_term = {
  buf = vim.api.nvim_create_buf(false, true),
  show = function(self)
    show_count = show_count + 1
    return self
  end,
  focus = function(self)
    focus_count = focus_count + 1
    return self
  end,
  hide = function(self)
    hide_count = hide_count + 1
    return self
  end,
  buf_valid = function(self)
    return true
  end,
  win_valid = function(self)
    return true
  end,
}

package.loaded['snacks'] = {
  terminal = function(cmd, opts)
    return fake_term
  end,
}

local cli = require('nx.cli')
cli._bin_cache = { ['/ws'] = '/fake/nx' }

local registry = require('nx.registry')
local terminal = require('nx.terminal')
registry.clear()

terminal.run('/ws', 'alpha', 'build')
terminal.background('/ws', 'alpha', 'build')
terminal.foreground('/ws', 'alpha', 'build')

local ok = hide_count == 1 and show_count == 1 and focus_count == 1
local line = ok and 'PASS: AC7-3'
  or ('FAIL: AC7-3 :: hide=' .. hide_count .. ' show=' .. show_count .. ' focus=' .. focus_count)
vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC7-3.txt')
vim.cmd('qa!')
