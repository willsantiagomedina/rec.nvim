local M = {}
local config = require("rec.config")
local keys = require("rec.keys")

-- 🔧 absolute path (DO NOT RELY ON $PATH)
local REC_CLI = vim.fn.expand("~/dev/rec.nvim/crates/rec-cli/target/debug/rec-cli")

local state = {
	running = false,
	start_time = nil,
	timer = nil,

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

	local elapsed = os.time() - state.start_time

	vim.api.nvim_buf_set_lines(state.hud_buf, 0, -1, false, {
		"",
		"  ● REC",
		"  " .. format_time(elapsed),
		"",
	})

	-- Apply specific highlights
	vim.api.nvim_buf_add_highlight(state.hud_buf, -1, "RecHudTitle", 1, 0, -1)
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

local function run(args)
	if not ensure_executable() then
		return
	end

	-- Add output directory to args if specified
	local cli_args = vim.list_extend({ REC_CLI }, args)
	if config.options.recording.output_dir then
		table.insert(cli_args, "--output-dir")
		table.insert(cli_args, config.get_output_dir())
	end

	vim.fn.jobstart(cli_args, {
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
end

-- ---------- public API ----------

function M.start()
	if state.running then
		notify("Already recording", vim.log.levels.WARN)
		return
	end

	run({ "start" })

	state.running = true
	state.start_time = os.time()
	state.keys = {}

	keys.reset() -- Reset keys processor state

	open_hud()
	open_keys()

	state.timer = vim.loop.new_timer()
	state.timer:start(0, 1000, vim.schedule_wrap(update_hud))

	vim.on_key(on_key, state.key_ns)

	notify("REC_START_OK")
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

	vim.on_key(nil, state.key_ns)
	close_windows()

	state.running = false
	state.start_time = nil
	state.keys = {}

	keys.reset() -- Clean up keys state

	notify("REC_STOP_OK")

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

	vim.api.nvim_create_user_command("RecStart", M.start, {})
	vim.api.nvim_create_user_command("RecStop", M.stop, {})
	vim.api.nvim_create_user_command("RecOpen", M.open_latest, { desc = "Open latest recording" })
end

return M
