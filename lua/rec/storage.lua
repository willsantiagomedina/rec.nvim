local M = {}

local config = require("rec.config")

---@class RecordingMetadata
---@field path string Full path to video file
---@field timestamp number Unix timestamp when recording was created
---@field mode string "fullscreen" or "window"
---@field duration number|nil Recording duration in seconds (if available)
---@field title string|nil Auto-generated title

---Get the path to the metadata file
---@return string
local function get_metadata_path()
	local output_dir = config.get_output_dir()
	return output_dir .. "/.rec_metadata.json"
end

---Safely read the metadata file
---@return RecordingMetadata[]
function M.load_recordings()
	local metadata_path = get_metadata_path()

	-- Check if file exists
	local stat = vim.loop.fs_stat(metadata_path)
	if not stat then
		return {}
	end

	-- Read file
	local fd = vim.loop.fs_open(metadata_path, "r", 438) -- 0666
	if not fd then
		return {}
	end

	local stat_result = vim.loop.fs_fstat(fd)
	if not stat_result then
		vim.loop.fs_close(fd)
		return {}
	end

	local data = vim.loop.fs_read(fd, stat_result.size, 0)
	vim.loop.fs_close(fd)

	if not data or data == "" then
		return {}
	end

	-- Parse JSON
	local ok, recordings = pcall(vim.json.decode, data)
	if not ok or type(recordings) ~= "table" then
		return {}
	end

	-- Validate each recording and filter out missing files
	local valid_recordings = {}
	for _, rec in ipairs(recordings) do
		if type(rec) == "table" and rec.path and rec.timestamp then
			-- Check if file still exists
			local file_stat = vim.loop.fs_stat(rec.path)
			if file_stat then
				table.insert(valid_recordings, rec)
			end
		end
	end

	return valid_recordings
end

---Save recordings metadata to disk
---@param recordings RecordingMetadata[]
---@return boolean success
local function save_recordings(recordings)
	local output_dir = config.get_output_dir()

	vim.notify(string.format("Storage: Output directory: %s", output_dir), vim.log.levels.DEBUG, { title = "rec.nvim" })

	-- Ensure directory exists
	if vim.fn.isdirectory(output_dir) == 0 then
		vim.notify("Storage: Creating output directory", vim.log.levels.DEBUG, { title = "rec.nvim" })
		local success = vim.fn.mkdir(output_dir, "p")
		if success == 0 then
			vim.notify("Storage: Failed to create output directory", vim.log.levels.ERROR, { title = "rec.nvim" })
			return false
		end
	end

	local metadata_path = get_metadata_path()

	vim.notify(string.format("Storage: Metadata path: %s", metadata_path), vim.log.levels.DEBUG, { title = "rec.nvim" })

	-- Encode to JSON
	local ok, json_data = pcall(vim.json.encode, recordings)
	if not ok then
		vim.notify(
			string.format("Storage: JSON encoding failed: %s", tostring(json_data)),
			vim.log.levels.ERROR,
			{ title = "rec.nvim" }
		)
		return false
	end

	vim.notify(
		string.format("Storage: JSON data length: %d bytes", #json_data),
		vim.log.levels.DEBUG,
		{ title = "rec.nvim" }
	)

	-- Write to file
	local fd = vim.loop.fs_open(metadata_path, "w", 438) -- 0666
	if not fd then
		vim.notify("Storage: Failed to open metadata file for writing", vim.log.levels.ERROR, { title = "rec.nvim" })
		return false
	end

	local write_ok = vim.loop.fs_write(fd, json_data, 0)
	vim.loop.fs_close(fd)

	if not write_ok then
		vim.notify("Storage: Failed to write to metadata file", vim.log.levels.ERROR, { title = "rec.nvim" })
		return false
	end

	vim.notify("Storage: Metadata file written successfully", vim.log.levels.DEBUG, { title = "rec.nvim" })

	return true
end

---Add a new recording to the metadata
---@param filepath string Full path to the video file
---@param mode string Recording mode ("fullscreen" or "window")
---@param duration number|nil Recording duration in seconds
---@param title string|nil Recording title
---@return boolean success
function M.add_recording(filepath, mode, duration, title)
	-- Debug: Log what we're trying to add
	vim.notify(
		string.format(
			"Storage: Attempting to add recording\nPath: %s\nMode: %s\nDuration: %s",
			filepath,
			mode or "nil",
			tostring(duration)
		),
		vim.log.levels.DEBUG,
		{ title = "rec.nvim" }
	)

	-- Verify file exists
	local stat = vim.loop.fs_stat(filepath)
	if not stat then
		vim.notify(
			string.format("Storage: File does not exist: %s", filepath),
			vim.log.levels.ERROR,
			{ title = "rec.nvim" }
		)
		return false
	end

	-- Load existing recordings
	local recordings = M.load_recordings()

	vim.notify(
		string.format("Storage: Loaded %d existing recordings", #recordings),
		vim.log.levels.DEBUG,
		{ title = "rec.nvim" }
	)

	-- Check if already exists (avoid duplicates)
	for _, rec in ipairs(recordings) do
		if rec.path == filepath then
			vim.notify("Storage: Recording already exists in metadata", vim.log.levels.INFO, { title = "rec.nvim" })
			return true -- Already recorded
		end
	end

	-- Add new recording
	table.insert(recordings, {
		path = filepath,
		timestamp = os.time(),
		mode = mode or "fullscreen",
		duration = duration,
		title = title,
	})

	vim.notify(
		string.format("Storage: Added recording to array, total count: %d", #recordings),
		vim.log.levels.DEBUG,
		{ title = "rec.nvim" }
	)

	-- Save
	local success = save_recordings(recordings)

	if success then
		vim.notify(
			string.format("Storage: Successfully saved metadata to disk"),
			vim.log.levels.DEBUG,
			{ title = "rec.nvim" }
		)
	else
		vim.notify(
			string.format("Storage: Failed to save metadata to disk"),
			vim.log.levels.ERROR,
			{ title = "rec.nvim" }
		)
	end

	return success
end

---Get the most recent recording
---@return RecordingMetadata|nil
function M.get_latest()
	local recordings = M.load_recordings()

	if #recordings == 0 then
		return nil
	end

	-- Sort by timestamp descending
	table.sort(recordings, function(a, b)
		return a.timestamp > b.timestamp
	end)

	return recordings[1]
end

---Delete a recording (both file and metadata)
---@param filepath string Full path to the video file
---@return boolean success
function M.delete_recording(filepath)
	-- Delete the file
	local file_deleted = vim.loop.fs_unlink(filepath)
	if not file_deleted then
		return false
	end

	-- Remove from metadata
	local recordings = M.load_recordings()
	local filtered = {}

	for _, rec in ipairs(recordings) do
		if rec.path ~= filepath then
			table.insert(filtered, rec)
		end
	end

	return save_recordings(filtered)
end

---Update a recording's metadata fields
---@param filepath string Full path to the video file
---@param updates table Fields to update
---@return boolean success
function M.update_recording(filepath, updates)
	if not filepath or filepath == "" then
		return false
	end

	local recordings = M.load_recordings()
	local updated = false

	for _, rec in ipairs(recordings) do
		if rec.path == filepath then
			for key, value in pairs(updates or {}) do
				rec[key] = value
			end
			updated = true
			break
		end
	end

	if not updated then
		return false
	end

	return save_recordings(recordings)
end

---Get all recordings sorted by timestamp (newest first)
---@return RecordingMetadata[]
function M.get_all_sorted()
	local recordings = M.load_recordings()

	table.sort(recordings, function(a, b)
		return a.timestamp > b.timestamp
	end)

	return recordings
end

return M
