local M = {}
local config = require("rec.config")
local keys = require("rec.keys")
local geometry = require("rec.geometry")
local dashboard = require("rec.dashboard")

-- 🔧 absolute path (DO NOT RELY ON $PATH)
local REC_CLI = vim.fn.expand("~/dev/rec.nvim/crates/rec-cli/target/debug/rec-cli")

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
	if config.options.recording.output_dir then
		table.insert(cli_args, "--output-dir")
		table.insert(cli_args, config.get_output_dir())
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

	-- Get current window geometry
	local geom = geometry.get_window_geometry()

	if not geom then
		notify("Could not calculate window geometry", vim.log.levels.ERROR)
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

	-- Send pause command to rec-cli
	if state.job_id then
		-- Send the pause command via job stdin or separate command
		-- Option 1: Use a control socket/pipe (requires rec-cli support)
		-- Option 2: Send to stdin if rec-cli listens for commands
		-- Option 3: Call rec-cli pause subcommand

		-- Using approach 3: call rec-cli with pause subcommand
		local result = vim.fn.system({ REC_CLI, "pause" })
		if vim.v.shell_error ~= 0 then
			notify("Failed to pause recording: " .. result, vim.log.levels.ERROR)
			return
		end
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

	-- Send resume command to rec-cli
	if state.job_id then
		local result = vim.fn.system({ REC_CLI, "resume" })
		if vim.v.shell_error ~= 0 then
			notify("Failed to resume recording: " .. result, vim.log.levels.ERROR)
			return
		end
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

	run({ "stop" })

	if state.timer then
		state.timer:stop()
		state.timer:close()
		state.timer = nil
	end

if state.hud_win and vim.api.nvim_win_is_valid(state.hud_win) then
		vim.api.nvim_win_close(state.hud_win, true)
		state.hud_win = nil
	end

if state.hud_buf and vim.api.nvim_buf_is_valid(state.hud_buf) then
		vim.api.nvim_buf_delete(state.hud_buf, {force=true})
		state.hud_buf = nil
	end

vim.on_key(nil, state.key_ns)

	vim.on_key(nil, state.key_ns)
	close_windows()

	local mode = state.recording_mode or "unknown"

	state.running = false
	state.paused = false
	state.recording_mode = nil
	state.capture_geometry = nil
	state.start_time = nil
	state.pause_time = nil
	state.total_paused_duration = 0
	state.job_id = nil
	state.keys = {}

	keys.reset() -- Clean up keys state

	notify(string.format("REC_STOP_OK (%s)", mode))

    -- Persist the recording after stop
    local time = os.date("!%Y-%m-%dT%H:%M:%S", os.time())
    local filename = string.format("recording_%s.mp4", time)
    storage.add_recording({
        filename = filename,
        absolute_path = config.get_output_dir() .. "/" .. filename,
        created_at = os.time()
    })

	-- Auto-open video if configured
	if config.options.recording.auto_open then
		vim.defer_fn(function()
			M.open_latest()
		end, 500) -- Small delay to ensure file is written
	end
end

-- ---------- statusline ----------

function M.status()
	return state.running and "🔴 REC" or ""
end

-- ---------- video opener ----------

function M.open_latest()
	local output_dir = config.get_output_dir()

	-- Find latest video file
	local handle = io.popen(string.format('ls -t "%s"/*.mp4 2>/dev/null | head -1', output_dir))

	if not handle then
		notify("Could not find recordings", vim.log.levels.WARN)
		return
	end

	local latest = handle:read("*l")
	handle:close()

	if not latest or latest == "" then
		notify("No recordings found in " .. output_dir, vim.log.levels.WARN)
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
	vim.fn.jobstart({ open_cmd, latest }, { detach = true })
	notify("Opening: " .. vim.fn.fnamemodify(latest, ":t"))
end

function M.setup(opts)
	config.setup(opts)

	vim.api.nvim_create_user_command("RecStart", M.start, { desc = "Start fullscreen recording" })
	vim.api.nvim_create_user_command("RecWin", function()
		M.win({ preview = true })
	end, { desc = "Record current window only" })
	vim.api.nvim_create_user_command("RecPause", M.pause, { desc = "Pause recording" })
	vim.api.nvim_create_user_command("RecResume", M.resume, { desc = "Resume recording" })
	vim.api.nvim_create_user_command("RecStop", M.stop, { desc = "Stop recording" })
	vim.api.nvim_create_user_command("RecOpen", M.open_latest, { desc = "Open latest recording" })
	vim.api.nvim_create_user_command("RecDashboard", dashboard.toggle, { desc = "Toggle recordings dashboard" })
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
