local M = {}
local config = require("rec.config")
local keys = require("rec.keys")
local geometry = require("rec.geometry")
local storage = require("rec.storage")
local dashboard = require("rec.dashboard")

-- 🔧 absolute path (DO NOT RELY ON $PATH)
local REC_CLI = vim.fn.expand("~/dev/rec.nvim/crates/rec-cli/target/debug/rec-cli")
local PID_FILE = "/tmp/rec.nvim.pid"
local OUT_FILE = "/tmp/rec.nvim.outpath"

local state = {
	running = false,
	paused = false,
	start_time = nil,
	pause_time = nil,
	total_paused_duration = 0,
	timer = nil,
	recording_mode = nil, -- "fullscreen" or "window"
	capture_geometry = nil, -- For window recordings
	job_id = nil, -- Track the rec-cli job
	output_file = nil, -- Track the output file path for this session

	hud_win = nil,
	hud_buf = nil,

	keys_win = nil,
	keys_buf = nil,
	keys = {},

	key_ns = vim.api.nvim_create_namespace("rec.nvim.keys"),
}

vim.api.nvim_set_hl(0, "RecKeysBorder", { fg = "#5fd7ff" })
vim.api.nvim_set_hl(0, "RecKeysBg", { bg = "#0b1220" })
vim.api.nvim_set_hl(0, "RecKeysText", {
	fg = "#ffffff",
	bg = "#0b1220",
	bold = true,
})

-- ---------- utils ----------

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "rec.nvim" })
end

local function ensure_executable()
	if vim.fn.executable(REC_CLI) == 0 then
		notify("rec-cli not executable:\n" .. REC_CLI, vim.log.levels.ERROR)
		return false
	end
	return true
end

local function format_time(sec)
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%02d:%02d", m, s)
end

local function read_pid()
	local ok, lines = pcall(vim.fn.readfile, PID_FILE)
	if not ok or not lines or not lines[1] then
		return nil
	end
	local pid = tonumber(lines[1])
	return pid
end

local function read_outpath()
	local ok, lines = pcall(vim.fn.readfile, OUT_FILE)
	if not ok or not lines or not lines[1] then
		return nil
	end
	local path = lines[1]
	if path == "" then
		return nil
	end
	return path
end

local function send_signal(sig)
	local pid = read_pid()
	if not pid then
		return false, "PID not found"
	end
	vim.fn.system({ "kill", "-" .. sig, tostring(pid) })
	if vim.v.shell_error ~= 0 then
		return false, "kill failed"
	end
	return true
end

local function sanitize_title(text)
	if not text or text == "" then
		return ""
	end
	local clean = text:gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if #clean > 60 then
		clean = clean:sub(1, 60):gsub("%s+$", "")
	end
	return clean
end

local function base_dir_from_buffer()
	local buf = vim.api.nvim_get_current_buf()
	local name = vim.api.nvim_buf_get_name(buf)
	if name ~= "" then
		local dir = vim.fn.fnamemodify(name, ":p:h")
		if dir and dir ~= "" then
			return dir
		end
	end
	return vim.fn.getcwd()
end

local function git_cmd(args)
	local base = base_dir_from_buffer()
	local cmd = { "git", "-C", base }
	vim.list_extend(cmd, args)
	local out = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return out
end

local function title_from_branch()
	local out = git_cmd({ "rev-parse", "--abbrev-ref", "HEAD" })
	if not out or not out[1] then
		return nil
	end
	local branch = out[1]
	if branch == "main" or branch == "master" or branch == "dev" then
		return nil
	end
	branch = branch:gsub("^origin/", "")
	local kind, rest = branch:match("^([%w%-_]+)%/(.+)$")
	if kind and rest then
		rest = rest:gsub("[-_]+", " ")
		return sanitize_title(string.format("%s: %s", kind, rest))
	end
	return sanitize_title(branch:gsub("[-_]+", " "))
end

local function title_from_git_diff()
	local out = git_cmd({ "diff", "--stat" })
	if not out then
		return nil
	end
	for _, line in ipairs(out) do
		local path = line:match("^%s*([^|]+)%s+|")
		if path then
			local filename = vim.fn.fnamemodify(path, ":t")
			local base = filename:gsub("%.%w+$", ""):gsub("[-_]+", " ")
			if base ~= "" then
				return sanitize_title("update: " .. base)
			end
			break
		end
	end
	return nil
end

local function title_from_buffer()
	local buf = vim.api.nvim_get_current_buf()
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		return nil
	end
	local filename = vim.fn.fnamemodify(name, ":t")
	local base = filename:gsub("%.%w+$", ""):gsub("[-_]+", " ")
	if base == "" then
		return nil
	end
	return sanitize_title(base)
end

local function generate_title()
	local title = title_from_branch()
	if title and title ~= "" then
		return title
	end

	title = title_from_git_diff()
	if title and title ~= "" then
		return title
	end

	title = title_from_buffer()
	if title and title ~= "" then
		return title
	end

	return sanitize_title("Recording " .. os.date("%Y-%m-%d %H:%M"))
end

-- ---------- floating windows ----------

local function open_hud()
	state.hud_buf = vim.api.nvim_create_buf(false, true)

	state.hud_win = vim.api.nvim_open_win(state.hud_buf, false, {
		relative = "editor",
		anchor = "NE",
		row = 1,
		col = vim.o.columns - 2,
		width = 20,
		height = 4,
		style = "minimal",
		border = "rounded",
	})

	-- Enhanced HUD styling
	vim.api.nvim_set_hl(0, "RecHudTitle", {
		fg = "#ef4444", -- Red
		bg = "#0f172a",
		bold = true,
	})

	vim.api.nvim_set_hl(0, "RecHudPaused", {
		fg = "#f59e0b", -- Amber/orange for paused state
		bg = "#0f172a",
		bold = true,
	})

	vim.api.nvim_set_hl(0, "RecHudTime", {
		fg = "#10b981", -- Green
		bg = "#0f172a",
		bold = true,
	})

	vim.api.nvim_set_hl(0, "RecHudBorder", {
		fg = "#ef4444", -- Red border to match
	})

	vim.api.nvim_set_option_value("winhl", "Normal:RecHudTitle,FloatBorder:RecHudBorder", { win = state.hud_win })
	vim.api.nvim_set_option_value("winblend", 5, { win = state.hud_win })
end

local function open_keys()
	-- Only show overlay if configured
	if not config.options.keys.show_overlay then
		return
	end

	-- ALWAYS recreate
	if state.keys_win and vim.api.nvim_win_is_valid(state.keys_win) then
		vim.api.nvim_win_close(state.keys_win, true)
	end

	state.keys_buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_lines(state.keys_buf, 0, -1, false, {
		"",
		"  ⌨  KEYSTROKES  ",
		"",
		"",
		"",
	})

	-- Get position from config
	local pos = config.get_overlay_position()
	local opts = config.options.overlay

	state.keys_win = vim.api.nvim_open_win(state.keys_buf, false, {
		relative = "editor",
		anchor = pos.anchor,
		row = pos.row,
		col = pos.col,
		width = opts.width,
		height = opts.height,
		style = "minimal",
		border = "rounded",
	})

	-- Enhanced styling with better colors and bigger text effect
	vim.api.nvim_set_hl(0, "RecKeysTitle", {
		fg = "#60a5fa", -- Bright blue
		bg = "#0f172a", -- Dark blue-black
		bold = true,
	})

	vim.api.nvim_set_hl(0, "RecKeysBig", {
		fg = "#fbbf24", -- Amber/yellow for keypresses
		bg = "#0f172a",
		bold = true,
	})

	vim.api.nvim_set_hl(0, "RecKeysBorder", {
		fg = "#3b82f6", -- Blue border
	})

	vim.api.nvim_set_option_value("winhl", "Normal:RecKeysBig,FloatBorder:RecKeysBorder", { win = state.keys_win })
	vim.api.nvim_set_option_value("winblend", config.get_window_blend(), { win = state.keys_win })
end

local function close_windows()
	for _, win in ipairs({ state.hud_win, state.keys_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	state.hud_win = nil
	state.hud_buf = nil
	state.keys_win = nil
	state.keys_buf = nil
end

-- ---------- HUD update ----------

local function update_hud()
	if not (state.hud_buf and vim.api.nvim_buf_is_valid(state.hud_buf)) then
		return
	end

	local elapsed
	if state.paused then
		-- While paused, show time at pause moment
		elapsed = state.pause_time - state.start_time - state.total_paused_duration
	else
		-- While recording, show current time minus any paused duration
		elapsed = os.time() - state.start_time - state.total_paused_duration
	end

	local status = state.paused and "⏸ PAUSED" or "● REC"

	vim.api.nvim_buf_set_lines(state.hud_buf, 0, -1, false, {
		"",
		"  " .. status,
		"  " .. format_time(elapsed),
		"",
	})

	-- Apply specific highlights
	local hl_group = state.paused and "RecHudPaused" or "RecHudTitle"
	vim.api.nvim_buf_add_highlight(state.hud_buf, -1, hl_group, 1, 0, -1)
	vim.api.nvim_buf_add_highlight(state.hud_buf, -1, "RecHudTime", 2, 0, -1)
end

-- ---------- keystroke capture ----------
local function redraw_keys()
	if not (state.keys_buf and vim.api.nvim_buf_is_valid(state.keys_buf)) then
		return
	end

	-- Format keystrokes with configured separator
	local separator = config.options.keys.separator
	local keys_display = table.concat(state.keys, separator)

	vim.api.nvim_buf_set_lines(state.keys_buf, 0, -1, false, {
		"",
		"  ⌨  KEYSTROKES  ",
		"",
		"  " .. keys_display,
		"",
	})

	-- Apply title highlight to the header line
	vim.api.nvim_buf_add_highlight(state.keys_buf, -1, "RecKeysTitle", 1, 0, -1)
end

local function on_key(key)
	if not state.running then
		return
	end

	local normalized = keys.process(key)

	if not normalized then
		return
	end

	table.insert(state.keys, normalized)

	-- Use configured max_keys
	local max_keys = config.options.overlay.max_keys
	if #state.keys > max_keys then
		table.remove(state.keys, 1)
	end

	redraw_keys()
end

-- ---------- rust runner ----------

local function run(args, geometry_args)
	if not ensure_executable() then
		return nil
	end

	-- Add output directory to args if specified
	local cli_args = vim.list_extend({ REC_CLI }, args)

	local output_dir = config.get_output_dir()

	if config.options.recording.output_dir then
		table.insert(cli_args, "--output-dir")
		table.insert(cli_args, output_dir)
	end

	-- Add geometry args if provided (for window recording)
	if geometry_args then
		table.insert(cli_args, "--x")
		table.insert(cli_args, tostring(geometry_args.x))
		table.insert(cli_args, "--y")
		table.insert(cli_args, tostring(geometry_args.y))
		table.insert(cli_args, "--width")
		table.insert(cli_args, tostring(geometry_args.width))
		table.insert(cli_args, "--height")
		table.insert(cli_args, tostring(geometry_args.height))
	end

	local job_id = vim.fn.jobstart(cli_args, {
		stdout_buffered = true,
		stderr_buffered = true,

		on_stdout = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						-- Check if rec-cli outputs the filename
						-- Expected format: "Recording saved: /path/to/file.mp4"
						local filepath = line:match("Recording saved: (.+)")
						if filepath then
							state.output_file = filepath
						end
						notify(line)
					end
				end
			end
		end,

		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						notify(line, vim.log.levels.WARN)
					end
				end
			end
		end,
	})

	return job_id
end

-- ---------- public API ----------

function M.start()
	if state.running then
		notify("Already recording", vim.log.levels.WARN)
		return
	end

	local job_id = run({ "start" })
	if not job_id then
		return
	end

	state.running = true
	state.paused = false
	state.recording_mode = "fullscreen"
	state.capture_geometry = nil
	state.start_time = os.time()
	state.pause_time = nil
	state.total_paused_duration = 0
	state.job_id = job_id
	state.keys = {}

	keys.reset() -- Reset keys processor state

	open_hud()
	open_keys()

	state.timer = vim.loop.new_timer()
	state.timer:start(0, 1000, vim.schedule_wrap(update_hud))

	vim.on_key(on_key, state.key_ns)

	notify("REC_START_OK (fullscreen)")
end

function M.win(opts)
	opts = opts or {}

	if state.running then
		notify("Already recording", vim.log.levels.WARN)
		return
	end

	geometry.select_region({
		winid = vim.api.nvim_get_current_win(),
		on_done = function(geom)
			if not geom then
				notify("Window selection canceled", vim.log.levels.WARN)
				return
			end

			-- Store geometry for potential use
			state.capture_geometry = geom

			-- Show preview if enabled (default: true)
			local show_preview = opts.preview ~= false
			local preview_duration = opts.preview_duration or 1500

			if show_preview then
				geometry.show_preview(geom, preview_duration)

				notify(
					string.format(
						"Recording window: %dx%d at (%d,%d) - Starting in %.1fs...",
						geom.width,
						geom.height,
						geom.x,
						geom.y,
						preview_duration / 1000
					)
				)

				-- Delay start until preview is done
				vim.defer_fn(function()
					M.start_window_recording(geom)
				end, preview_duration)
			else
				M.start_window_recording(geom)
			end
		end,
	})
end

function M.fullwin(opts)
	opts = opts or {}

	if state.running then
		notify("Already recording", vim.log.levels.WARN)
		return
	end

	local geom = geometry.get_window_geometry()

	if not geom then
		notify("Could not calculate window geometry", vim.log.levels.ERROR)
		return
	end

	state.capture_geometry = geom

	local show_preview = opts.preview ~= false
	local preview_duration = opts.preview_duration or 1500

	if show_preview then
		geometry.show_preview(geom, preview_duration)

		notify(
			string.format(
				"Recording window: %dx%d at (%d,%d) - Starting in %.1fs...",
				geom.width,
				geom.height,
				geom.x,
				geom.y,
				preview_duration / 1000
			)
		)

		vim.defer_fn(function()
			M.start_window_recording(geom)
		end, preview_duration)
	else
		M.start_window_recording(geom)
	end
end

function M.start_window_recording(geom)
	-- Start recording with geometry
	local job_id = run({ "start" }, geom)
	if not job_id then
		return
	end

	state.running = true
	state.paused = false
	state.recording_mode = "window"
	state.start_time = os.time()
	state.pause_time = nil
	state.total_paused_duration = 0
	state.job_id = job_id
	state.keys = {}

	keys.reset()

	open_hud()
	open_keys()

	state.timer = vim.loop.new_timer()
	state.timer:start(0, 1000, vim.schedule_wrap(update_hud))

	vim.on_key(on_key, state.key_ns)

	notify(string.format("REC_START_OK (window: %dx%d)", geom.width, geom.height))
end

function M.pause()
	if not state.running then
		notify("Not recording", vim.log.levels.WARN)
		return
	end

	if state.paused then
		notify("Already paused", vim.log.levels.INFO)
		return
	end

	local ok, err = send_signal("STOP")
	if not ok then
		notify("Failed to pause recording: " .. (err or "unknown"), vim.log.levels.ERROR)
		return
	end

	state.paused = true
	state.pause_time = os.time()

	-- Update HUD immediately to show paused state
	update_hud()

	notify("Recording paused")
end

function M.resume()
	if not state.running then
		notify("Not recording", vim.log.levels.WARN)
		return
	end

	if not state.paused then
		notify("Not paused", vim.log.levels.INFO)
		return
	end

	local ok, err = send_signal("CONT")
	if not ok then
		notify("Failed to resume recording: " .. (err or "unknown"), vim.log.levels.ERROR)
		return
	end

	-- Calculate how long we were paused and add to total
	local pause_duration = os.time() - state.pause_time
	state.total_paused_duration = state.total_paused_duration + pause_duration

	state.paused = false
	state.pause_time = nil

	-- Update HUD immediately to show recording state
	update_hud()

	notify("Recording resumed")
end
function M.stop()
	if not state.running then
		notify("REC_NOT_RUNNING", vim.log.levels.WARN)
		return
	end

	if state.paused then
		send_signal("CONT")
	end

	run({ "stop" })

	if state.timer then
		state.timer:stop()
		state.timer:close()
		state.timer = nil
	end

	vim.on_key(nil, state.key_ns)
	close_windows()

	local mode = state.recording_mode or "unknown"
	local output_file = state.output_file

	-- Calculate actual recording duration (excluding paused time)
	local duration = nil
	if state.start_time then
		duration = os.time() - state.start_time - state.total_paused_duration
	end

	state.running = false
	state.paused = false
	state.recording_mode = nil
	state.capture_geometry = nil
	state.start_time = nil
	state.pause_time = nil
	state.total_paused_duration = 0
	state.job_id = nil
	state.output_file = nil
	state.keys = {}

	keys.reset() -- Clean up keys state

	notify(string.format("REC_STOP_OK (%s)", mode))

	-- Persist recording metadata
	vim.defer_fn(function()
		-- If output_file wasn't set, try to find the latest file
		if not output_file then
			local output_dir = config.get_output_dir()

			-- Find the most recent .mp4 file
			local files = vim.fn.globpath(output_dir, "*.mp4", false, true)

			if #files > 0 then
				-- Sort by modification time
				table.sort(files, function(a, b)
					local stat_a = vim.loop.fs_stat(a)
					local stat_b = vim.loop.fs_stat(b)
					if stat_a and stat_b then
						return stat_a.mtime.sec > stat_b.mtime.sec
					end
					return false
				end)

				output_file = files[1]
				notify("Detected recording file: " .. vim.fn.fnamemodify(output_file, ":t"), vim.log.levels.INFO)
			end
		end

	if output_file then
			local title = generate_title()
			local success = storage.add_recording(output_file, mode, duration, title)
			if success then
				vim.notify("Recording saved to dashboard", vim.log.levels.INFO, { title = "rec.nvim" })
			else
				vim.notify(
					"Warning: Recording file exists but metadata not persisted",
					vim.log.levels.WARN,
					{ title = "rec.nvim" }
				)
				vim.notify("File: " .. output_file, vim.log.levels.WARN, { title = "rec.nvim" })
			end

			-- Auto-open if configured
			if config.options.recording.auto_open then
				vim.defer_fn(function()
					M.open_latest()
				end, 200)
			end
		else
			vim.notify("Warning: Could not locate recording file", vim.log.levels.WARN, { title = "rec.nvim" })
		end
	end, 1000) -- Increased delay to ensure file is written
end

function M.cancel()
	if not state.running then
		notify("REC_NOT_RUNNING", vim.log.levels.WARN)
		return
	end

	local choice = vim.fn.confirm("Cancel recording and discard file?", "&Yes\n&No", 2)
	if choice ~= 1 then
		notify("Cancel aborted", vim.log.levels.INFO)
		return
	end

	if state.paused then
		send_signal("CONT")
	end

	run({ "stop" })

	if state.timer then
		state.timer:stop()
		state.timer:close()
		state.timer = nil
	end

	vim.on_key(nil, state.key_ns)
	close_windows()

	local output_file = state.output_file or read_outpath()

	state.running = false
	state.paused = false
	state.recording_mode = nil
	state.capture_geometry = nil
	state.start_time = nil
	state.pause_time = nil
	state.total_paused_duration = 0
	state.job_id = nil
	state.output_file = nil
	state.keys = {}

	keys.reset()

	notify("REC_CANCELED")

	vim.defer_fn(function()
		if output_file then
			local ok = vim.loop.fs_unlink(output_file)
			if ok then
				notify("Canceled recording deleted: " .. vim.fn.fnamemodify(output_file, ":t"))
			end
		end
	end, 700)
end

-- ---------- statusline ----------

function M.status()
	return state.running and "🔴 REC" or ""
end

-- ---------- video opener ----------

function M.open_latest()
	local latest = storage.get_latest()

	if not latest then
		notify("No recordings found", vim.log.levels.WARN)
		return
	end

	-- Verify file exists
	local stat = vim.loop.fs_stat(latest.path)
	if not stat then
		notify("Recording file not found: " .. latest.path, vim.log.levels.ERROR)
		return
	end

	-- Determine open command
	local open_cmd = config.options.recording.open_command

	if not open_cmd then
		-- Auto-detect based on OS
		if vim.fn.has("mac") == 1 then
			open_cmd = "open"
		elseif vim.fn.has("unix") == 1 then
			open_cmd = "xdg-open"
		elseif vim.fn.has("win32") == 1 then
			open_cmd = "start"
		else
			notify("Could not determine video player command", vim.log.levels.ERROR)
			return
		end
	end

	-- Open video
	vim.fn.jobstart({ open_cmd, latest.path }, { detach = true })

	local filename = vim.fn.fnamemodify(latest.path, ":t")
	notify("Opening: " .. filename)
end

function M.setup(opts)
	config.setup(opts)

	vim.api.nvim_create_user_command("RecStart", M.start, { desc = "Start fullscreen recording" })
	vim.api.nvim_create_user_command("RecFullWin", function()
		M.fullwin({ preview = true })
	end, { desc = "Record full current window" })
	vim.api.nvim_create_user_command("RecWin", function()
		M.win({ preview = true })
	end, { desc = "Record current window only" })
	vim.api.nvim_create_user_command("RecPause", M.pause, { desc = "Pause recording" })
	vim.api.nvim_create_user_command("RecResume", M.resume, { desc = "Resume recording" })
	vim.api.nvim_create_user_command("RecStop", M.stop, { desc = "Stop recording" })
	vim.api.nvim_create_user_command("RecCancel", M.cancel, { desc = "Cancel recording and discard file" })
	vim.api.nvim_create_user_command("RecOpen", M.open_latest, { desc = "Open latest recording" })
	vim.api.nvim_create_user_command("RecDashboard", dashboard.toggle, { desc = "Toggle recordings dashboard" })
	vim.api.nvim_create_user_command("RecDebug", function()
		local output_dir = config.get_output_dir()
		local metadata_path = output_dir .. "/.rec_metadata.json"

		-- Check output directory
		local dir_exists = vim.fn.isdirectory(output_dir) == 1

		-- Check metadata file
		local metadata_stat = vim.loop.fs_stat(metadata_path)

		-- List video files
		local files = vim.fn.globpath(output_dir, "*.mp4", false, true)

		-- Load recordings
		local recordings = storage.get_all_sorted()

		local info = string.format(
			[[
rec.nvim Debug Info
===================

Output Directory: %s
Directory exists: %s

Metadata file: %s
Metadata exists: %s

Video files found: %d
Recordings in metadata: %d

Current state:
  Running: %s
  Output file: %s
]],
			output_dir,
			dir_exists and "YES" or "NO",
			metadata_path,
			metadata_stat and "YES" or "NO",
			#files,
			#recordings,
			state.running and "YES" or "NO",
			state.output_file or "nil"
		)

		vim.notify(info, vim.log.levels.INFO, { title = "rec.nvim Debug" })

		-- Also print to messages
		print(info)
	end, { desc = "Show debug information" })

	vim.api.nvim_create_user_command("RecCalibrate", function()
		local w, h = geometry.calibrate_cell_size()
		vim.notify(
			string.format(
				"Cell size: %dx%d pixels\nSet manually: vim.g.rec_cell_width=%d, vim.g.rec_cell_height=%d",
				w,
				h,
				w,
				h
			),
			vim.log.levels.INFO,
			{ title = "rec.nvim" }
		)
	end, { desc = "Show cell size calibration info" })
end

return M
