local M = {}

function M.setup() end

-- Get the jest command
function M.jest_command() 
  if require('nx.workspace').try_workspace() then
    return 'yarn jest'
  end
end

-- Get the jest config file
function M.jest_config_file(file)
  if require('nx.workspace').try_workspace() then
    local project = require('nx.workspace').project_from_path(file)

    if project then
      return project.sourceRoot .. '/jest.config.ts'
    end
  end
end

function M.get_cwd()
  local workspace = require('nx.workspace').try_workspace()

  if workspace then
    return workspace.path
  end
end

return M
