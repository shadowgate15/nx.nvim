---@mod nx.registry Background task registry

local M = {}

-- Registry: { [key_string] = entry_table }
local _entries = {}

--- Build canonical registry key.
--- @param workspace_root string
--- @param project string
--- @param task string
--- @return string
function M.key(workspace_root, project, task)
  return workspace_root .. '::' .. project .. '::' .. task
end

--- Insert or replace a registry entry.
--- @param workspace_root string
--- @param project string
--- @param task string
--- @param entry table  {terminal, bufnr, job_id, status, exit_code, output_file, started_at, exited_at, workspace_root, project, task}
function M.put(workspace_root, project, task, entry)
  local k = M.key(workspace_root, project, task)
  entry.workspace_root = workspace_root
  entry.project = project
  entry.task = task
  _entries[k] = entry
end

--- Get a registry entry. Returns nil if not found.
--- @param workspace_root string
--- @param project string
--- @param task string
--- @return table|nil
function M.get(workspace_root, project, task)
  return _entries[M.key(workspace_root, project, task)]
end

--- Remove a registry entry, cleaning up tempfile and buffer.
--- @param workspace_root string
--- @param project string
--- @param task string
function M.remove(workspace_root, project, task)
  local k = M.key(workspace_root, project, task)
  local entry = _entries[k]
  if not entry then
    return
  end
  _entries[k] = nil

  -- Clean up output file
  if entry.output_file then
    pcall(os.remove, entry.output_file)
  end

  -- Try to delete the buffer if still valid
  if entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
    pcall(vim.api.nvim_buf_delete, entry.bufnr, { force = true })
  end
end

--- List entries, optionally filtered by workspace_root.
--- Returns entries sorted by started_at descending (most recent first).
--- @param workspace_root? string
--- @return table[]
function M.list(workspace_root)
  local result = {}
  for _, entry in pairs(_entries) do
    if not workspace_root or entry.workspace_root == workspace_root then
      table.insert(result, entry)
    end
  end
  table.sort(result, function(a, b)
    return (a.started_at or 0) > (b.started_at or 0)
  end)
  return result
end

--- List only 'running' entries.
--- @param workspace_root? string
--- @return table[]
function M.find_running(workspace_root)
  local result = {}
  for _, entry in pairs(_entries) do
    if entry.status == 'running' then
      if not workspace_root or entry.workspace_root == workspace_root then
        table.insert(result, entry)
      end
    end
  end
  return result
end

--- Attach BufWipeout autocmd to self-heal dangling registry entries.
--- Call this from setup().
function M.attach_self_healing()
  local group = vim.api.nvim_create_augroup('nx.registry', { clear = true })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(args)
      local bufnr = args.buf
      -- Find any registry entry tracking this buffer
      for _, entry in pairs(_entries) do
        if entry.bufnr == bufnr then
          -- Self-heal: mark as exited
          entry.terminal = nil
          entry.bufnr = nil
          if entry.status == 'running' then
            entry.status = 'exited'
            entry.exit_code = -1
            entry.exited_at = vim.uv.now()
          end
          break
        end
      end
    end,
    desc = 'nx.nvim: self-heal registry on buffer wipeout',
  })
end

--- Test helper: returns a deep copy of the internal entries table.
--- @return table
function M.state()
  return vim.deepcopy(_entries)
end

--- Test helper: remove all entries.
function M.clear()
  local all = {}
  for _, entry in pairs(_entries) do
    table.insert(all, entry)
  end
  for _, entry in ipairs(all) do
    M.remove(entry.workspace_root, entry.project, entry.task)
  end
end

return M
