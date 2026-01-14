local M = {}

---@class WindowGeometry
---@field x number Absolute X position in pixels
---@field y number Absolute Y position in pixels
---@field width number Width in pixels
---@field height number Height in pixels

---Get the GUI font dimensions
---@return number, number cell_width, cell_height in pixels
local function get_cell_dimensions()
	-- Try to get actual font metrics from the GUI
	if vim.fn.has("gui_running") == 1 then
		-- For GUI Neovim (if available)
		local width = vim.fn.eval("&guifontwide") or vim.o.guifont
		-- This is a fallback; GUI neovim exposes font metrics differently
	end

	-- For terminal Neovim, we need to query the terminal emulator
	-- This is system-specific. On macOS with supported terminals:

	-- Most reliable method: use a known good default and let users configure
	-- Common defaults: 7-9px width, 14-20px height for typical programming fonts

	-- We'll use a measurement approach via the UI
	-- Get pixel dimensions if running in a GUI context
	if vim.fn.exists("*getwininfo") == 1 then
		local info = vim.fn.getwininfo(vim.fn.win_getid())[1]
		if info and info.textoff then
			-- We have some info, but need terminal-specific queries
		end
	end

	-- Fallback: assume standard terminal cell size
	-- For macOS Terminal.app and iTerm2 with SF Mono / Menlo at default sizes:
	-- Typical: 7-8px wide, 16-18px tall
	local cell_width = 8 -- pixels per character column
	local cell_height = 18 -- pixels per character row

	-- Allow override via global variable for user customization
	if vim.g.rec_cell_width then
		cell_width = vim.g.rec_cell_width
	end
	if vim.g.rec_cell_height then
		cell_height = vim.g.rec_cell_height
	end

	return cell_width, cell_height
end

---Get the absolute screen position of Neovim's top-left corner
---@return number, number x, y in pixels
local function get_nvim_window_position()
	-- This is terminal/GUI specific
	-- For macOS, we need to use AppleScript or query the terminal

	-- Method 1: Try to get from environment if terminal supports it
	-- Some terminals set WINDOWID or similar

	-- Method 2: Use osascript to query the frontmost window position
	local handle = io.popen([[
		osascript -e '
		tell application "System Events"
			set frontApp to first application process whose frontmost is true
			set frontWindow to front window of frontApp
			set windowPosition to position of frontWindow
			return item 1 of windowPosition & "," & item 2 of windowPosition
		end tell
		' 2>/dev/null
	]])

	if handle then
		local result = handle:read("*l")
		handle:close()

		if result and result:match("^%d+,%d+$") then
			local x, y = result:match("(%d+),(%d+)")
			return tonumber(x), tonumber(y)
		end
	end

	-- Fallback: allow user to set manually
	local x = vim.g.rec_window_x or 0
	local y = vim.g.rec_window_y or 0

	return x, y
end

---Get window border information
---@param winid number Window ID
---@return table { top: number, right: number, bottom: number, left: number } border size in cells
local function get_window_border(winid)
	local border = { top = 0, right = 0, bottom = 0, left = 0 }

	-- Check if window has a border via config
	local config = vim.api.nvim_win_get_config(winid)

	if config.border and config.border ~= "none" then
		-- Border exists
		if type(config.border) == "string" then
			-- Preset borders all add 1 cell on each side
			border.top = 1
			border.right = 1
			border.bottom = 1
			border.left = 1
		elseif type(config.border) == "table" then
			-- Custom border array
			-- Format: { top-left, top, top-right, right, bottom-right, bottom, bottom-left, left }
			-- If any element is non-empty, that side has a border
			if config.border[2] and config.border[2] ~= "" then
				border.top = 1
			end
			if config.border[4] and config.border[4] ~= "" then
				border.right = 1
			end
			if config.border[6] and config.border[6] ~= "" then
				border.bottom = 1
			end
			if config.border[8] and config.border[8] ~= "" then
				border.left = 1
			end
		end
	end

	return border
end

---Calculate the absolute pixel geometry of a window
---@param winid? number Window ID (defaults to current window)
---@return WindowGeometry|nil geometry Absolute pixel coordinates, or nil on error
function M.get_window_geometry(winid)
	winid = winid or vim.api.nvim_get_current_win()

	-- Verify window is valid
	if not vim.api.nvim_win_is_valid(winid) then
		return nil
	end

	local config = vim.api.nvim_win_get_config(winid)

	-- Can only capture normal windows, not floating windows
	if config.relative ~= "" then
		vim.notify("Cannot record floating windows", vim.log.levels.ERROR, { title = "rec.nvim" })
		return nil
	end

	-- Get cell dimensions
	local cell_width, cell_height = get_cell_dimensions()

	-- Get Neovim window position on screen
	local nvim_x, nvim_y = get_nvim_window_position()

	-- Get window position in the Neovim grid (in cells)
	local win_pos = vim.api.nvim_win_get_position(winid)
	local row = win_pos[1] -- 0-indexed row
	local col = win_pos[2] -- 0-indexed column

	-- Get window dimensions (in cells)
	local win_height = vim.api.nvim_win_get_height(winid)
	local win_width = vim.api.nvim_win_get_width(winid)

	-- Account for tabline (adds rows at the top)
	local tabline_height = 0
	if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1) then
		tabline_height = 1
	end

	-- Account for window borders
	local border = get_window_border(winid)

	-- Calculate absolute pixel position
	-- Starting from Neovim window origin, offset by:
	-- 1. Tabline (if present)
	-- 2. Window row position
	-- 3. Window col position
	local pixel_x = nvim_x + (col * cell_width)
	local pixel_y = nvim_y + ((tabline_height + row) * cell_height)

	-- Calculate pixel dimensions
	-- Include borders in the capture
	local pixel_width = (win_width + border.left + border.right) * cell_width
	local pixel_height = (win_height + border.top + border.bottom) * cell_height

	return {
		x = math.floor(pixel_x),
		y = math.floor(pixel_y),
		width = math.floor(pixel_width),
		height = math.floor(pixel_height),
	}
end

---Auto-detect cell dimensions by creating a temporary floating window
---and measuring it (requires GUI support or terminal cooperation)
---@return number, number cell_width, cell_height
function M.calibrate_cell_size()
	-- This is a best-effort calibration
	-- In practice, users should set vim.g.rec_cell_width and vim.g.rec_cell_height

	-- Try to detect from terminfo
	if vim.env.TERM then
		-- Some terminals support pixel queries via escape sequences
		-- CSI 14 t - Report text area size in pixels
		-- Response: CSI 4 ; height ; width t

		-- This is complex and terminal-specific
		-- For now, return a sensible default and document the need for calibration
	end

	-- Default values for common macOS terminals
	return 8, 18
end

---Show a visual preview of the capture area
---@param geometry WindowGeometry
---@param duration_ms number How long to show the preview
function M.show_preview(geometry, duration_ms)
	duration_ms = duration_ms or 2000

	-- Get cell dimensions
	local cell_width, cell_height = get_cell_dimensions()

	-- Convert pixel geometry back to cell coordinates
	local nvim_x, nvim_y = get_nvim_window_position()

	-- Account for tabline
	local tabline_height = 0
	if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1) then
		tabline_height = 1
	end

	local cell_row = math.floor((geometry.y - nvim_y) / cell_height) - tabline_height
	local cell_col = math.floor((geometry.x - nvim_x) / cell_width)
	local cell_width_count = math.ceil(geometry.width / cell_width)
	local cell_height_count = math.ceil(geometry.height / cell_height)

	-- Create a floating window to show the outline
	local buf = vim.api.nvim_create_buf(false, true)

	-- Fill with empty lines
	local lines = {}
	for _ = 1, cell_height_count do
		table.insert(lines, string.rep(" ", cell_width_count))
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Create window with prominent border
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = cell_row,
		col = cell_col,
		width = cell_width_count,
		height = cell_height_count,
		style = "minimal",
		border = "double",
		focusable = false,
		zindex = 1000,
	})

	-- Highlight the border
	vim.api.nvim_set_hl(0, "RecPreviewBorder", {
		fg = "#ff6b6b",
		bold = true,
	})

	vim.api.nvim_set_option_value("winhl", "FloatBorder:RecPreviewBorder", { win = win })
	vim.api.nvim_set_option_value("winblend", 80, { win = win })

	-- Auto-close after duration
	vim.defer_fn(function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end, duration_ms)

	return win
end

local selection_state = {
	active = false,
	winid = nil,
	mouse_save = nil,
	selection_win = nil,
	selection_buf = nil,
	start_row = nil,
	start_col = nil,
	end_row = nil,
	end_col = nil,
	on_done = nil,
}

local function selection_cleanup()
	if selection_state.selection_win and vim.api.nvim_win_is_valid(selection_state.selection_win) then
		vim.api.nvim_win_close(selection_state.selection_win, true)
	end
	if selection_state.selection_buf and vim.api.nvim_buf_is_valid(selection_state.selection_buf) then
		vim.api.nvim_buf_delete(selection_state.selection_buf, { force = true })
	end

	local map_opts = { silent = true, noremap = true }
	pcall(vim.keymap.del, "n", "<LeftMouse>", map_opts)
	pcall(vim.keymap.del, "n", "<LeftDrag>", map_opts)
	pcall(vim.keymap.del, "n", "<LeftRelease>", map_opts)
	pcall(vim.keymap.del, "n", "<Esc>", map_opts)

	if selection_state.mouse_save ~= nil then
		vim.o.mouse = selection_state.mouse_save
	end

	selection_state.active = false
	selection_state.winid = nil
	selection_state.mouse_save = nil
	selection_state.selection_win = nil
	selection_state.selection_buf = nil
	selection_state.start_row = nil
	selection_state.start_col = nil
	selection_state.end_row = nil
	selection_state.end_col = nil
	selection_state.on_done = nil
end

local function selection_screen_pos()
	local mouse = vim.fn.getmousepos()
	if not mouse or mouse.winid ~= selection_state.winid then
		return nil
	end
	return mouse.screenrow - 1, mouse.screencol - 1
end

local function selection_cursor_screen_pos()
	local row, col = unpack(vim.api.nvim_win_get_cursor(selection_state.winid))
	local win_pos = vim.api.nvim_win_get_position(selection_state.winid)
	return win_pos[1] + (row - 1), win_pos[2] + col
end

local function clamp_screen_pos(row, col)
	local max_row = math.max(0, vim.o.lines - 1)
	local max_col = math.max(0, vim.o.columns - 1)
	return math.min(max_row, math.max(0, row)), math.min(max_col, math.max(0, col))
end

local function selection_update_overlay(r1, c1, r2, c2)
	local row = math.min(r1, r2)
	local col = math.min(c1, c2)
	local height = math.max(1, math.abs(r2 - r1) + 1)
	local width = math.max(1, math.abs(c2 - c1) + 1)

	if not selection_state.selection_buf or not vim.api.nvim_buf_is_valid(selection_state.selection_buf) then
		selection_state.selection_buf = vim.api.nvim_create_buf(false, true)
	end

	if not selection_state.selection_win or not vim.api.nvim_win_is_valid(selection_state.selection_win) then
		selection_state.selection_win = vim.api.nvim_open_win(selection_state.selection_buf, false, {
			relative = "editor",
			row = row,
			col = col,
			width = width,
			height = height,
			style = "minimal",
			border = "rounded",
			focusable = false,
			zindex = 1000,
		})

		vim.api.nvim_set_hl(0, "RecSelectBorder", {
			fg = "#22d3ee",
			bold = true,
		})
		vim.api.nvim_set_option_value("winhl", "FloatBorder:RecSelectBorder", { win = selection_state.selection_win })
		vim.api.nvim_set_option_value("winblend", 65, { win = selection_state.selection_win })
	else
		vim.api.nvim_win_set_config(selection_state.selection_win, {
			relative = "editor",
			row = row,
			col = col,
			width = width,
			height = height,
		})
	end
end

local function selection_finish()
	local row = math.min(selection_state.start_row, selection_state.end_row)
	local col = math.min(selection_state.start_col, selection_state.end_col)
	local height = math.max(1, math.abs(selection_state.end_row - selection_state.start_row) + 1)
	local width = math.max(1, math.abs(selection_state.end_col - selection_state.start_col) + 1)

	local cell_width, cell_height = get_cell_dimensions()
	local nvim_x, nvim_y = get_nvim_window_position()

	local geom = {
		x = math.floor(nvim_x + (col * cell_width)),
		y = math.floor(nvim_y + (row * cell_height)),
		width = math.floor(width * cell_width),
		height = math.floor(height * cell_height),
	}

	local cb = selection_state.on_done
	selection_cleanup()

	if cb then
		cb(geom)
	end
end

---Interactively select a capture region within the current window.
---@param opts? table { winid?: number, on_done?: fun(geom: WindowGeometry|nil) }
function M.select_region(opts)
	opts = opts or {}
	local winid = opts.winid or vim.api.nvim_get_current_win()
	local on_done = opts.on_done

	if not vim.api.nvim_win_is_valid(winid) then
		if on_done then
			on_done(nil)
		end
		return
	end

	if selection_state.active then
		if on_done then
			on_done(nil)
		end
		return
	end

	selection_state.active = true
	selection_state.winid = winid
	selection_state.mouse_save = vim.o.mouse
	selection_state.on_done = on_done
	vim.o.mouse = "a"

	vim.notify(
		"Drag to select. Use hjkl to resize, HJKL to move. Enter confirms, Esc cancels.",
		vim.log.levels.INFO,
		{ title = "rec.nvim" }
	)

	local map_opts = { silent = true, noremap = true }

	vim.keymap.set("n", "<LeftMouse>", function()
		local row, col = selection_screen_pos()
		if not row or not col then
			return
		end
		selection_state.start_row = row
		selection_state.start_col = col
		selection_state.end_row = row
		selection_state.end_col = col
		selection_update_overlay(row, col, row, col)
	end, map_opts)

	vim.keymap.set("n", "<LeftDrag>", function()
		if not selection_state.start_row then
			return
		end
		local row, col = selection_screen_pos()
		if not row or not col then
			return
		end
		selection_state.end_row = row
		selection_state.end_col = col
		selection_update_overlay(selection_state.start_row, selection_state.start_col, row, col)
	end, map_opts)

	vim.keymap.set("n", "<LeftRelease>", function()
		if not selection_state.start_row then
			return
		end
		local row, col = selection_screen_pos()
		if row and col then
			selection_state.end_row = row
			selection_state.end_col = col
			selection_update_overlay(selection_state.start_row, selection_state.start_col, row, col)
		end
		selection_finish()
	end, map_opts)

	local function ensure_selection()
		if selection_state.start_row then
			return
		end
		local row, col = selection_cursor_screen_pos()
		row, col = clamp_screen_pos(row, col)
		selection_state.start_row = row
		selection_state.start_col = col
		selection_state.end_row = row
		selection_state.end_col = col
		selection_update_overlay(row, col, row, col)
	end

	local function nudge_resize(dr, dc)
		ensure_selection()
		local row = selection_state.end_row + dr
		local col = selection_state.end_col + dc
		row, col = clamp_screen_pos(row, col)
		selection_state.end_row = row
		selection_state.end_col = col
		selection_update_overlay(selection_state.start_row, selection_state.start_col, row, col)
	end

	local function nudge_move(dr, dc)
		ensure_selection()
		local sr = selection_state.start_row + dr
		local sc = selection_state.start_col + dc
		local er = selection_state.end_row + dr
		local ec = selection_state.end_col + dc
		sr, sc = clamp_screen_pos(sr, sc)
		er, ec = clamp_screen_pos(er, ec)
		selection_state.start_row = sr
		selection_state.start_col = sc
		selection_state.end_row = er
		selection_state.end_col = ec
		selection_update_overlay(sr, sc, er, ec)
	end

	vim.keymap.set("n", "h", function()
		nudge_resize(0, -1)
	end, map_opts)
	vim.keymap.set("n", "j", function()
		nudge_resize(1, 0)
	end, map_opts)
	vim.keymap.set("n", "k", function()
		nudge_resize(-1, 0)
	end, map_opts)
	vim.keymap.set("n", "l", function()
		nudge_resize(0, 1)
	end, map_opts)

	vim.keymap.set("n", "H", function()
		nudge_move(0, -1)
	end, map_opts)
	vim.keymap.set("n", "J", function()
		nudge_move(1, 0)
	end, map_opts)
	vim.keymap.set("n", "K", function()
		nudge_move(-1, 0)
	end, map_opts)
	vim.keymap.set("n", "L", function()
		nudge_move(0, 1)
	end, map_opts)

	vim.keymap.set("n", "<CR>", function()
		if not selection_state.start_row then
			return
		end
		selection_finish()
	end, map_opts)

	vim.keymap.set("n", "<Esc>", function()
		local cb = selection_state.on_done
		selection_cleanup()
		if cb then
			cb(nil)
		end
	end, map_opts)
end

return M
