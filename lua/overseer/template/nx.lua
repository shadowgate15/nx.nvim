---@type overseer.TemplateFileDefinition
local tmpl = {
  name = 'nx',
  priority = 59,
  params = {
    cwd = { optional = true },
    target = { type = 'string', desc = 'Target to run' },
    args = { optional = true, type = 'list', delimiter = ' ' },
    project = { optional = true, type = 'string', desc = 'Project to run' },
  },
  builder = function(params)
    local cmd = { 'nx', params.target }

    if params.project then
      table.insert(cmd, params.project)
    end

    return {
      cmd = cmd,
      cwd = params.cwd,
      args = params.args,
    }
  end,
}

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

  for key, _ in pairs(project.targets) do
    local override = { name = string.format('nx[%s] %s', project.name, key) }

    if project.name == project.name then
      -- Override priority so the nearest show up first
      override.priority = 58
    end

    local overseer = require('overseer')

    table.insert(
      ret,
      overseer.wrap_template(tmpl, override, {
        cwd = cwd,
        target = key,
        project = project.name,
      })
    )
  end

  cb(ret)
end

return M
