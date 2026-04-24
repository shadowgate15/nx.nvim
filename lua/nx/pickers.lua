---@mod nx.pickers fzf-lua pickers for Nx projects and tasks

local M = {}

-- Display order is fixed (apps → libs → e2e) and the bracket strings are
-- the same width (5 chars) so the picker stays vertically aligned without
-- extra padding logic.
local KIND_LABELS = { app = '[app]', lib = '[lib]', e2e = '[e2e]' }
local KIND_HL = { app = 'NxKindApp', lib = 'NxKindLib', e2e = 'NxKindE2e' }
local DEFAULT_KIND = 'lib'

local _hl_initialized = false

local function _ensure_highlights()
  if _hl_initialized then return end
  _hl_initialized = true
  -- `default = true` lets users override these by defining the group first.
  vim.api.nvim_set_hl(0, 'NxKindApp', { link = 'Function', default = true })
  vim.api.nvim_set_hl(0, 'NxKindLib', { link = 'String', default = true })
  vim.api.nvim_set_hl(0, 'NxKindE2e', { link = 'WarningMsg', default = true })
end

--- Strip the leading `[kind] ` prefix added by M._format_entry.
--- @param entry string
--- @return string
function M._strip_prefix(entry)
  if not entry then return entry end
  local stripped = entry:gsub('^%s*\27%[[%d;]*m?%[%w+%]\27%[[%d;]*m?%s*', '')
  if stripped == entry then
    stripped = entry:gsub('^%s*%[%w+%]%s*', '')
  end
  return stripped
end

--- Build a display row: "<colored-prefix> <project-name>".
--- Falls back to plain text when fzf-lua/utils is unavailable (e.g. in tests).
--- @param name string
--- @param kind 'app'|'lib'|'e2e'
--- @return string
function M._format_entry(name, kind)
  local label = KIND_LABELS[kind] or KIND_LABELS[DEFAULT_KIND]
  local hl = KIND_HL[kind] or KIND_HL[DEFAULT_KIND]
  local ok, utils = pcall(require, 'fzf-lua.utils')
  if ok and type(utils.ansi_from_hl) == 'function' then
    _ensure_highlights()
    local colored = utils.ansi_from_hl(hl, label)
    return colored .. ' ' .. name
  end
  return label .. ' ' .. name
end

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
    -- Render the preview as JSONC so syntax highlighting (and tree-sitter, when
    -- a `jsonc` parser is installed) kicks in on the project/task config dump.
    pcall(vim.api.nvim_set_option_value, 'filetype', 'jsonc', { buf = buf })
    self:set_preview_buf(buf)
  end

  return cls
end

local function _is_array(tbl)
  if vim.islist then return vim.islist(tbl) end
  return vim.tbl_islist(tbl)
end

local function _pretty_value(value, indent_str, depth)
  if value == nil or value == vim.NIL then return 'null' end
  if type(value) ~= 'table' then
    return vim.json.encode(value)
  end

  local pad = string.rep(indent_str, depth + 1)
  local close_pad = string.rep(indent_str, depth)

  if next(value) == nil then
    return getmetatable(value) == nil and '[]' or '{}'
  end

  if _is_array(value) then
    local parts = {}
    for _, item in ipairs(value) do
      table.insert(parts, pad .. _pretty_value(item, indent_str, depth + 1))
    end
    return '[\n' .. table.concat(parts, ',\n') .. '\n' .. close_pad .. ']'
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    local rendered = _pretty_value(value[key], indent_str, depth + 1)
    table.insert(parts, pad .. vim.json.encode(tostring(key)) .. ': ' .. rendered)
  end
  return '{\n' .. table.concat(parts, ',\n') .. '\n' .. close_pad .. '}'
end

function M._pretty(json_string)
  local ok, decoded = pcall(vim.json.decode, json_string, { luanil = { object = true, array = true } })
  if not ok then
    return json_string
  end
  if type(decoded) ~= 'table' then
    return vim.json.encode(decoded)
  end
  return _pretty_value(decoded, '  ', 0)
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

    local kinds = result.project_kinds or {}
    local entries = {}
    for _, name in ipairs(projects) do
      table.insert(entries, M._format_entry(name, kinds[name] or DEFAULT_KIND))
    end

    vim.schedule(function()
      local previewer = nil
      if preview_enabled then
        previewer = {
          _ctor = function()
            return make_previewer(function(entry_str, cb)
              local name = M._strip_prefix(entry_str)
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

      fzf.fzf_exec(entries, {
        prompt = 'Nx Projects> ',
        previewer = previewer,
        actions = {
          ['default'] = {
            fn = function(selected, opts)
              local actions_ok, fzf_actions = pcall(require, 'fzf-lua.actions')
              local raw
              if actions_ok then
                local _, normalized = fzf_actions.normalize_selected(selected, opts)
                raw = normalized and normalized[1]
              else
                raw = selected and selected[1]
              end
              local project_name = raw and M._strip_prefix(raw)
              if project_name and project_name ~= '' and on_select then
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
