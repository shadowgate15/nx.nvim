-- AC9-3: previewer returns formatted target config using _ctor + stringify_data API
-- (Updated after fix: pickers.lua now uses shell.stringify_data + _ctor, not .fn)

local captured_previewer = nil
package.loaded['fzf-lua'] = {
  fzf_exec = function(contents, opts)
    captured_previewer = opts and opts.previewer
  end,
}
package.loaded['fzf-lua.actions'] = { normalize_selected = function(s, o) return nil, s end }

-- Stub shell.stringify_data to capture the Lua function and call it directly
local shell_fn_captured = nil
package.loaded['fzf-lua.shell'] = {
  stringify_data = function(fn, opts, field_index)
    shell_fn_captured = fn
    return 'stub_shell_cmd'
  end,
}

local cache = require('nx.cache')
local orig_get = cache.get_project
cache.get_project = function(ws, name, on_done)
  on_done({ ok = true, project = {
    targets = {
      build = { executor = 'nx:run-commands', options = { command = 'echo hi' } },
    },
  } })
end

package.loaded['nx.pickers'] = nil
local pickers = require('nx.pickers')
pickers.tasks('/ws', 'alpha', function() end)

vim.defer_fn(function()
  cache.get_project = orig_get

  -- Verify previewer has _ctor shape (not .fn)
  local has_ctor = captured_previewer ~= nil and type(captured_previewer._ctor) == 'function'

  -- Instantiate via _ctor to get the previewer object, then call cmdline()
  -- This invokes stringify_data which captures our fn
  local preview_result = nil
  if has_ctor then
    local previewer_obj = captured_previewer._ctor()
    if previewer_obj and previewer_obj.new and previewer_obj.cmdline then
      previewer_obj:new({})
      previewer_obj:cmdline()  -- triggers stringify_data, which captures shell_fn_captured
    end
  end

  -- Now call the captured inner function with {'build'} to get the preview text
  if shell_fn_captured then
    preview_result = shell_fn_captured({ 'build' })
  end

  local ok = preview_result ~= nil
    and type(preview_result) == 'string'
    and preview_result:find('nx:run%-commands') ~= nil
    and preview_result:find('echo hi') ~= nil

  local line = ok and 'PASS: AC9-3' or ('FAIL: AC9-3 :: result=' .. vim.inspect(preview_result) .. ' has_ctor=' .. tostring(has_ctor) .. ' shell_fn=' .. tostring(shell_fn_captured ~= nil))
  vim.fn.writefile({ line }, '.sisyphus/evidence/qa-AC9-3.txt')
  vim.cmd('qa!')
end, 100)
