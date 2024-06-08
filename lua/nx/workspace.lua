local cache = require('nx.cache')
local files = require('nx.files')

---@class nx.NxWorkspace
---@field name string
---@field path string

---@class nx.NxProject
---@field name string
---@field projectType? string
---@field sourceRoot? string
---@field targets? table<string, table>[]

---@param path string
local function load_project(path)
  local project = files.read_json(path)

  cache.set('project.' .. project.name, project)
  cache.set('project.' .. path, project)

  return project
end

local M = {}

-- Attempt to get the current workspace
---@return nx.NxWorkspace?
function M.try_workspace()
  -- Check the cache
  ---@type nx.NxWorkspace
  local workspace = cache.get('workspace')

  if workspace then
    return workspace
  end

  -- Get the workspace
  local path = files.find_nearest('nx.json')

  if not path then
    return
  end

  path = vim.fs.dirname(path)
  workspace = {
    name = vim.fs.basename(path),
    path = path,
  }

  cache.set('workspace', workspace)

  return workspace
end

-- Get the current workspace
---@return nx.NxWorkspace
function M.workspace()
  local workspace = M.try_workspace()

  if not workspace then
    error('Failed to find an NX Workspace')
  end

  return workspace
end

-- Get all the projects
---@return nx.NxProject[]
function M.projects()
  local workspace = M.workspace()

  ---@type nx.NxProject[]
  local projects = cache.get_match('project.') or {}

  if #projects > 0 then
    return projects
  end

  local project_paths = files.find_all('project.json', {
    dir = workspace.path,
    children = true,
  })

  for _, path in ipairs(project_paths) do
    table.insert(projects, load_project(path))
  end

  return projects
end

-- Get the neearest project to the given path
---@param path string?
function M.project_from_path(path)
  -- Check for this paths cache
  local project = cache.get('project.' .. path)

  if project then
    return project
  end

  -- Find the project
  local project_path = files.find_nearest('project.json', {
    dir = path,
  })

  if project_path then
    project = load_project(project_path)

    cache.set('project.' .. path, project)

    return project
  end
end

return M
