---@mod nx.pickers fzf-lua pickers for Nx projects and tasks

local M = {}

---@return fzf-lua.previewer.Builtin
local function make_previewer(preview_fn)
  local Builtin = require('fzf-lua.previewer.builtin')
  local cls = Builtin.base:extend()

  function cls:new(o, opts)
    cls.super.new(self, o, opts)
    return self
  end

  function cls:populate_preview_buf(entry_str)
    if not entry_str or entry_str == '' then return end
    local co = assert(coroutine.running(), 'populate_preview_buf must run in coroutine')
    local result
    local done = false
    preview_fn(entry_str, function(lines)
      result = lines
      if not done then
        vim.schedule(function()
          coroutine.resume(co, lines)
        end)
      end
    end)
    if not result then
      done = false
      result = coroutine.yield()
    end
    done = true
    if not result then return end
    local buf = self:get_tmp_buffer()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result, '\n', { plain = true }))
    self:set_preview_buf(buf)
  end

  return cls
end

function M._pretty(json_string)
  local ok, decoded = pcall(vim.json.decode, json_string, { luanil = { object = true, array = true } })
  if not ok then
    return json_string
  end
  return vim.inspect(decoded, { newline = '\n', indent = '  ' })
end

function M.projects(workspace_root, on_select)
  local ok, fzf = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify('nx.nvim: fzf-lua is required for pickers (ibhagwan/fzf-lua).', vim.log.levels.ERROR)
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

    vim.schedule(function()
      local previewer = nil
      if preview_enabled then
        previewer = {
          _ctor = function()
            return make_previewer(function(name, cb)
              local cached_entry = cache.state()[workspace_root]
              if cached_entry and cached_entry.project_configs[name] then
                cb(M._pretty(vim.json.encode(cached_entry.project_configs[name])))
                return
              end
              cache.get_project(workspace_root, name, function(r)
                if r.ok and r.project then
                  cb(M._pretty(vim.json.encode(r.project)))
                else
                  cb('(error loading ' .. name .. ')')
                end
              end)
            end)
          end,
        }
      end

      fzf.fzf_exec(projects, {
        prompt = 'Nx Projects> ',
        previewer = previewer,
        actions = {
          ['default'] = {
            fn = function(selected, opts)
              local actions_ok, fzf_actions = pcall(require, 'fzf-lua.actions')
              local project_name
              if actions_ok then
                local _, entries = fzf_actions.normalize_selected(selected, opts)
                project_name = entries and entries[1]
              else
                project_name = selected and selected[1]
              end
              if project_name and on_select then
                vim.schedule(function()
                  on_select(project_name)
                end)
              end
            end,
            header = 'select project',
          },
        },
      })
    end)
  end)
end

function M.tasks(workspace_root, project, on_select)
  local ok, fzf = pcall(require, 'fzf-lua')
  if not ok then
    vim.notify('nx.nvim: fzf-lua is required for pickers (ibhagwan/fzf-lua).', vim.log.levels.ERROR)
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
      local previewer = nil
      if preview_enabled then
        previewer = {
          _ctor = function()
            return make_previewer(function(task_name, cb)
              local target = targets[task_name]
              if target then
                cb(M._pretty(vim.json.encode(target)))
              else
                cb('no task config')
              end
            end)
          end,
        }
      end

      fzf.fzf_exec(task_names, {
        prompt = string.format('Nx Tasks (%s)> ', project),
        previewer = previewer,
        actions = {
          ['default'] = {
            fn = function(selected, opts)
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
            header = 'run task',
          },
        },
      })
    end)
  end)
end

return M
