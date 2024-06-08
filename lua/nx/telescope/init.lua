local action_state = require('telescope.actions.state')
local actions = require('telescope.actions')
local conf = require('telescope.config').values
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')

local displayers = require('nx.telescope.displayers')
local workspace = require('nx.workspace')

local M = {}

function M.projects(opts)
  opts = opts or {}

  pickers
    .new(opts, {
      prompt_title = 'Nx Projects',
      finder = finders.new_dynamic({
        fn = function()
          return workspace.projects()
        end,
        ---@param entry nx.NxProject
        entry_maker = function(entry)
          return {
            value = entry,
            display = function(e)
              local projectType

              if e.value.projectType then
                projectType = { e.value.projectType }
              else
                projectType = { '-', 'TelescopeResultsComment' }
              end

              return displayers.projects({
                { e.value.name, 'TelescopeResultsIdentifier' },
                projectType,
                { e.value.sourceRoot },
              })
            end,
            ordinal = entry.name,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

return M
