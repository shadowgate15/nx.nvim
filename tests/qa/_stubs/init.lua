-- tests/qa/_stubs/init.lua
-- Reusable stub helpers for nx.nvim headless QA tests.

local M = {}

--- Stub a module by setting package.loaded[name] = replacement.
--- Returns a restore function.
--- @param name string module name
--- @param replacement any replacement value
--- @return fun() restore function
function M.stub_module(name, replacement)
  local orig = package.loaded[name]
  package.loaded[name] = replacement
  return function()
    package.loaded[name] = orig
  end
end

--- Stub a method on a table.
--- Returns a restore function.
--- @param tbl table
--- @param key string
--- @param replacement any
--- @return fun() restore function
function M.stub_method(tbl, key, replacement)
  local orig = tbl[key]
  tbl[key] = replacement
  return function()
    tbl[key] = orig
  end
end

--- Capture vim.notify calls. Returns { calls = {...}, restore = fun() }.
--- @return { calls: table, restore: fun() }
function M.notify_capture()
  local calls = {}
  local orig = vim.notify
  vim.notify = function(msg, level)
    table.insert(calls, { msg = msg, level = level })
  end
  return {
    calls = calls,
    restore = function()
      vim.notify = orig
    end,
  }
end

--- Stub vim.system to return canned results synchronously.
--- canned_results: list of {code, stdout, stderr} tables, consumed in order.
--- Returns a restore function plus the captured calls table.
--- @param canned_results table[]
--- @return fun() restore, table captured
function M.system_capture(canned_results)
  local idx = 0
  local captured = {}
  local orig = vim.system
  vim.system = function(argv, opts, cb)
    table.insert(captured, { argv = argv, opts = opts })
    idx = idx + 1
    local result = canned_results[idx] or { code = 0, stdout = '', stderr = '' }
    if cb then
      cb(result)
    end
    return {
      wait = function()
        return result
      end,
    }
  end
  return function()
    vim.system = orig
  end, captured
end

return M
