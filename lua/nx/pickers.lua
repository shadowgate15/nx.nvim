---@mod nx.pickers fzf-lua pickers for Nx projects and tasks

local M = {}

--- Pure-Lua pretty-printer for JSON strings.
--- Uses vim.inspect (produces Lua-table syntax, readable for preview pane).
--- @param json_string string
--- @return string
function M._pretty(json_string)
  local ok, decoded = pcall(vim.json.decode, json_string, { luanil = { object = true, array = true } })
  if not ok then
    return json_string
  end
  return vim.inspect(decoded, { newline = '\n', indent = '  ' })
end

--- Open a fzf-lua picker showing all Nx projects in the workspace.
--- @param workspace_root string
--- @param on_select fun(project_name: string) callback when a project is selected
function M.projects(workspace_root, on_select)
  local ok, fzf = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify(
      'nx.nvim: fzf-lua is required for pickers (ibhagwan/fzf-lua).',
      vim.log.levels.ERROR
    )
    return
  end

  local cache = require('nx.cache')
  local conf_ok, conf = pcall(require, 'nx.config')
  local preview_enabled = (conf_ok and conf.pickers and conf.pickers.preview ~= false)

  cache.get_projects(workspace_root, function(result)
    if not result.ok then
      vim.notify('nx.nvim: Failed to load projects: ' .. (result.error or 'unknown'), vim.log.levels.ERROR)
      return
    end

    local projects = result.projects or {}
    if #projects == 0 then
      vim.notify('nx.nvim: No projects found in workspace.', vim.log.levels.WARN)
      return
    end

    -- Pre-warm the config cache for all projects so preview fn has data immediately.
    for _, name in ipairs(projects) do
      cache.get_project(workspace_root, name, function() end)
    end

    vim.schedule(function()
      local preview = nil
      if preview_enabled then
        preview = {
          fn = function(items)
            local name = items and items[1]
            if not name then
              return ''
            end
            local cached_entry = cache.state()[workspace_root]
            if cached_entry and cached_entry.project_configs[name] then
              return M._pretty(vim.json.encode(cached_entry.project_configs[name]))
            end
            return '(Loading ' .. name .. '...)'
          end,
          field_index = '{}',
        }
      end

      fzf.fzf_exec(projects, {
        prompt = 'Nx Projects> ',
        preview = preview,
        actions = {
          ['default'] = function(selected, opts)
            local actions_ok, fzf_actions = pcall(require, 'fzf-lua.actions')
            local project_name
            if actions_ok then
              local _, entries = fzf_actions.normalize_selected(selected, opts)
              project_name = entries and entries[1]
            else
              -- Fallback for older versions
              project_name = selected and selected[1]
            end
            if project_name and on_select then
              vim.schedule(function()
                on_select(project_name)
              end)
            end
          end,
        },
      })
    end)
  end)
end

--- Open a fzf-lua picker showing tasks/targets for a given Nx project.
--- @param workspace_root string
--- @param project string project name
--- @param on_select fun(task_name: string) callback when a task is selected
function M.tasks(workspace_root, project, on_select)
  local ok, fzf = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify(
      'nx.nvim: fzf-lua is required for pickers (ibhagwan/fzf-lua).',
      vim.log.levels.ERROR
    )
    return
  end

  local cache = require('nx.cache')
  local conf_ok, conf = pcall(require, 'nx.config')
  local preview_enabled = (conf_ok and conf.pickers and conf.pickers.preview ~= false)

  cache.get_project(workspace_root, project, function(result)
    if not result.ok then
      vim.notify(
        'nx.nvim: Failed to load project "' .. project .. '": ' .. (result.error or 'unknown'),
        vim.log.levels.ERROR
      )
      return
    end

    local targets = (result.project and result.project.targets) or {}
    local task_names = vim.tbl_keys(targets)
    table.sort(task_names)

    if #task_names == 0 then
      vim.notify('nx.nvim: No tasks for project ' .. project, vim.log.levels.WARN)
      return
    end

    vim.schedule(function()
      local preview = nil
      if preview_enabled then
        preview = {
          fn = function(items)
            local task_name = items and items[1]
            if not task_name then
              return ''
            end
            local target = targets[task_name]
            if not target then
              return 'no task config'
            end
            return M._pretty(vim.json.encode(target))
          end,
          field_index = '{}',
        }
      end

      fzf.fzf_exec(task_names, {
        prompt = string.format('Nx Tasks (%s)> ', project),
        preview = preview,
        actions = {
          ['default'] = function(selected, opts)
            local actions_ok, fzf_actions = pcall(require, 'fzf-lua.actions')
            local task_name
            if actions_ok then
              local _, entries = fzf_actions.normalize_selected(selected, opts)
              task_name = entries and entries[1]
            else
              task_name = selected and selected[1]
            end
            if task_name and on_select then
              vim.schedule(function()
                on_select(task_name)
              end)
            end
          end,
        },
      })
    end)
  end)
end

return M
