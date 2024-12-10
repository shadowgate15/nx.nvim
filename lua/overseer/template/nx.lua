---@type overseer.TemplateFileDefinition
local tmpl = {
  name = 'nx',
  priority = 59,
  params = {
    cwd = { optional = true },
    target = { type = 'string', desc = 'Target to run' },
    args = { optional = true, type = 'list', delimiter = ' ' },
    project = { optional = true, type = 'string', desc = 'Project to run' },
    configuration = { optional = true, type = 'string', desc = 'Configuration' },
  },
  builder = function(params)
    local cmd = { 'nx', params.target }

    if params.project then
      table.insert(cmd, params.project)
    end

    if params.configuration then
      table.insert(cmd, '--configuration ' .. params.configuration)
    end

    return {
      cmd = cmd,
      cwd = params.cwd,
      args = params.args,
    }
  end,
}

local function shallowcopy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in pairs(orig) do
      copy[orig_key] = orig_value
    end
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

---@type overseer.TemplateProvider
local M = { name = 'nx', module = 'nx' }

function M.cache_key(opts)
  local workspace = require('nx.workspace')

  local project = workspace.project_from_path(opts.dir)

  if project then
    return project.name
  end
end

M.condition = {
  callback = function()
    local workspace = require('nx.workspace')

    local w = workspace.try_workspace()

    if not w then
      return false, 'No NX workspace found'
    end

    if vim.fn.executable('nx') == 0 then
      return false, "Could not find command 'nx'"
    end

    return true
  end,
}

function M.generator(opts, cb)
  local workspace = require('nx.workspace')

  local cwd = workspace.workspace().path
  local project = workspace.project_from_path(opts.dir)

  if not project then
    return cb({})
  end

  ---@type overseer.TemplateDefinition[]
  local ret = {}

  for key, val in pairs(project.targets) do
    local override = {
      name = string.format('nx[%s] %s', project.name, key),
      priority = 58,
    }

    local overseer = require('overseer')

    table.insert(
      ret,
      overseer.wrap_template(tmpl, override, {
        cwd = cwd,
        target = key,
        project = project.name,
      })
    )

    if val.configurations ~= nil then
      for configKey, _ in pairs(val.configurations) do
        local configOverride = shallowcopy(override)
        configOverride.name = string.format('nx[%s] %s:%s', project.name, key, configKey)

        table.insert(
          ret,
          overseer.wrap_template(tmpl, configOverride, {
            cwd = cwd,
            target = key,
            project = project.name,
            configuration = configKey,
          })
        )
      end
    end
  end

  cb(ret)
end

return M
