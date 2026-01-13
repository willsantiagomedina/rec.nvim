local M = {}

local recordings_file = "recordings.json"
local config = require("rec.config")
local Path = require("plenary.path")

-- Helper function to get the path for the index file
local function get_recordings_path()
  local recordings_dir = Path:new(config.get_output_dir())
  return recordings_dir:joinpath(recordings_file):absolute()
end

--- Load recordings from disk
---@return table[]
function M.load_recordings()
  local path = get_recordings_path()
  local file = io.open(path, "r")
  if not file then
    return {}
  end

  local content = file:read("*a")
  file:close()

  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok then
    vim.notify("Failed to decode recordings file", vim.log.levels.ERROR)
    return {}
  end

  -- Sort by most recent timestamp
  table.sort(data, function(a, b) return a.created_at > b.created_at end)
  return data
end

--- Append a new recording to the index
---@param recording table
function M.add_recording(recording)
  local path = get_recordings_path()

  -- Load existing recordings
  local recordings = M.load_recordings()
  table.insert(recordings, recording)

  -- Save back to disk
  local file = io.open(path, "w")
  if not file then
    vim.notify("Failed to open recordings file for writing", vim.log.levels.ERROR)
    return
  end

  file:write(vim.fn.json_encode(recordings))
  file:close()
end

return M