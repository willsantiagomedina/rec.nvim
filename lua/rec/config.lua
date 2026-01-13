local M = {}

---@class RecConfig
---@field overlay RecOverlayConfig
---@field recording RecRecordingConfig
---@field keys RecKeysConfig
local defaults = {
	overlay = {
		-- Position: "bottom-right", "bottom-center", "top-right", "top-center", or custom function
		position = "bottom-right",

		-- Maximum keystrokes to show in overlay
		max_keys = 5,

		-- Overlay opacity (0-100, where 0 is transparent, 100 is opaque)
		opacity = 95,

		-- Window dimensions
		width = 32,
		height = 5,

		-- Padding from edges (rows/cols)
		padding = {
			row = 1,
			col = 2,
		},

		-- Custom position function (overrides position if set)
		-- Should return { row = number, col = number, anchor = string }
		custom_position = nil,
	},

	recording = {
		-- Output directory for recordings (supports ~/ expansion)
		output_dir = "~/Videos/nvim-recordings",

		-- Auto-open video after stopping recording
		auto_open = false,

		-- Command to open video (leave nil for system default)
		-- Examples: "vlc", "mpv", "open" (macOS), "xdg-open" (Linux)
		open_command = nil,
	},

	keys = {
		-- Enable keystroke overlay
		show_overlay = true,

		-- Maximum repeat count before collapsing (e.g., jjj -> j×5)
		max_repeat_count = 3,

		-- Ignore navigation key repetition (h,j,k,l,w,b,e)
		ignore_navigation = true,

		-- Ignore mouse events
		ignore_mouse = true,

		-- Key separator in overlay
		separator = "  ·  ",
	},
}

---@type RecConfig
M.options = {}

---Preset position calculators
local positions = {
	["bottom-right"] = function(config, opts)
		local total_lines = vim.o.lines
		local statusline_height = vim.o.laststatus > 0 and 1 or 0
		local cmdline_height = vim.o.cmdheight

		return {
			anchor = "SE",
			row = total_lines - statusline_height - cmdline_height - (opts.padding.row or 1),
			col = vim.o.columns - (opts.padding.col or 2),
		}
	end,

	["bottom-center"] = function(config, opts)
		local total_lines = vim.o.lines
		local statusline_height = vim.o.laststatus > 0 and 1 or 0
		local cmdline_height = vim.o.cmdheight
		local width = opts.width or 32

		return {
			anchor = "SW",
			row = total_lines - statusline_height - cmdline_height - (opts.padding.row or 1),
			col = math.floor((vim.o.columns - width) / 2),
		}
	end,

	["top-right"] = function(config, opts)
		return {
			anchor = "NE",
			row = 1 + (opts.padding.row or 1),
			col = vim.o.columns - (opts.padding.col or 2),
		}
	end,

	["top-center"] = function(config, opts)
		local width = opts.width or 32

		return {
			anchor = "NW",
			row = 1 + (opts.padding.row or 1),
			col = math.floor((vim.o.columns - width) / 2),
		}
	end,
}

---Get the calculated position for the keystroke overlay
---@return { anchor: string, row: number, col: number }
function M.get_overlay_position()
	local overlay_opts = M.options.overlay

	-- If custom position function is provided, use it
	if overlay_opts.custom_position and type(overlay_opts.custom_position) == "function" then
		return overlay_opts.custom_position(M.options)
	end

	-- Use preset position
	local pos_fn = positions[overlay_opts.position]
	if not pos_fn then
		vim.notify(
			string.format("Invalid overlay position '%s', using 'bottom-right'", overlay_opts.position),
			vim.log.levels.WARN,
			{ title = "rec.nvim" }
		)
		pos_fn = positions["bottom-right"]
	end

	return pos_fn(M.options, overlay_opts)
end

---Get the expanded output directory path
---@return string
function M.get_output_dir()
	return vim.fn.expand(M.options.recording.output_dir)
end

---Get the window blend value (inverse of opacity)
---@return number blend value (0-100)
function M.get_window_blend()
	return 100 - M.options.overlay.opacity
end

---Validate configuration options
---@param opts table User-provided options
---@return boolean, string? success, error message
local function validate_config(opts)
	if opts.overlay then
		if opts.overlay.opacity and (opts.overlay.opacity < 0 or opts.overlay.opacity > 100) then
			return false, "overlay.opacity must be between 0 and 100"
		end

		if opts.overlay.max_keys and opts.overlay.max_keys < 1 then
			return false, "overlay.max_keys must be at least 1"
		end

		if opts.overlay.position then
			local pos = opts.overlay.position
			if type(pos) == "string" and not positions[pos] then
				return false,
					string.format(
						"Invalid overlay.position '%s'. Valid options: %s",
						pos,
						table.concat(vim.tbl_keys(positions), ", ")
					)
			end
		end
	end

	if opts.keys then
		if opts.keys.max_repeat_count and opts.keys.max_repeat_count < 1 then
			return false, "keys.max_repeat_count must be at least 1"
		end
	end

	return true
end

---Setup configuration with user options
---@param opts? RecConfig User configuration options
function M.setup(opts)
	opts = opts or {}

	-- Validate configuration
	local valid, err = validate_config(opts)
	if not valid then
		vim.notify("Invalid configuration: " .. err, vim.log.levels.ERROR, { title = "rec.nvim" })
		return
	end

	-- Deep merge user options with defaults
	M.options = vim.tbl_deep_extend("force", defaults, opts)

	-- Create output directory if it doesn't exist
	local output_dir = M.get_output_dir()
	if vim.fn.isdirectory(output_dir) == 0 then
		vim.fn.mkdir(output_dir, "p")
	end

	-- Configure keys module if it's loaded
	local ok, keys = pcall(require, "rec.keys")
	if ok then
		keys.configure({
			max_repeat_count = M.options.keys.max_repeat_count,
			ignore_navigation = M.options.keys.ignore_navigation,
			ignore_mouse = M.options.keys.ignore_mouse,
		})
	end
end

---Get current configuration
---@return RecConfig
function M.get()
	return M.options
end

---Reset to default configuration
function M.reset()
	M.options = vim.deepcopy(defaults)
end

-- Initialize with defaults
M.reset()

return M
