local M = {}

local storage = require("rec.storage")
local config = require("rec.config")

-- Dashboard state
local state = {
	buf = nil,
	win = nil,
	recordings = {},
	selected_idx = 1,
	search_query = "",
	filtered = {},
}

---Format timestamp as human-readable date
---@param timestamp number Unix timestamp
---@return string
local function format_date(timestamp)
	return os.date("%Y-%m-%d %H:%M:%S", timestamp)
end

---Expand ~ and make absolute paths consistent
---@param p string
---@return string
local function normalize_path(p)
	if not p or p == "" then
		return ""
	end
	return vim.fn.fnamemodify(vim.fn.expand(p), ":p")
end

---Default output dir used by rec-cli (match backend)
---@return string
local function default_output_dir()
	local home = vim.loop.os_homedir() or "~"
	return normalize_path(home .. "/Videos/nvim-recordings")
end

---Scan output directory for mp4 files (fallback when metadata is missing)
---@return table[]
local function scan_recordings_dir()
	local dir = config.options and config.options.recording and config.options.recording.output_dir
		or default_output_dir()

	dir = normalize_path(dir)
	if dir == "" then
		return {}
	end

	local files = vim.fn.globpath(dir, "*.mp4", false, true) or {}
	local out = {}

	for _, path in ipairs(files) do
		local p = normalize_path(path)
		local st = vim.loop.fs_stat(p)
		if st then
			table.insert(out, {
				path = p,
				timestamp = st.mtime.sec or os.time(),
				mode = "fullscreen",
			})
		end
	end

	table.sort(out, function(a, b)
		return (a.timestamp or 0) > (b.timestamp or 0)
	end)

	return out
end

---Load recordings: prefer metadata, fallback to disk scan, and prune missing
---@return table[]
local function load_recordings()
	local recs = storage.get_all_sorted() or {}

	-- normalize + prune missing
	local filtered = {}
	for _, rec in ipairs(recs) do
		if rec and rec.path then
			rec.path = normalize_path(rec.path)
			local st = vim.loop.fs_stat(rec.path)
			if st then
				-- If storage timestamp missing, derive from mtime
				rec.timestamp = rec.timestamp or (st.mtime.sec or os.time())
				rec.mode = rec.mode or "fullscreen"
				table.insert(filtered, rec)
			end
		end
	end

	if #filtered > 0 then
		table.sort(filtered, function(a, b)
			return (a.timestamp or 0) > (b.timestamp or 0)
		end)
		return filtered
	end

	-- No metadata or all stale -> fallback to scanning directory
	return scan_recordings_dir()
end

local function filter_recordings()
	local query = (state.search_query or ""):lower()
	if query == "" then
		state.filtered = state.recordings
		return
	end

	local filtered = {}
	for _, rec in ipairs(state.recordings or {}) do
		local filename = vim.fn.fnamemodify(rec.path or "", ":t"):lower()
		local path = (rec.path or ""):lower()
		local mode = (rec.mode or ""):lower()
		if filename:find(query, 1, true) or path:find(query, 1, true) or mode:find(query, 1, true) then
			table.insert(filtered, rec)
		end
	end

	state.filtered = filtered
end

---Build the dashboard content lines
---@return string[]
local function build_content()
	local lines = {}
	local width = math.floor(vim.o.columns * 0.62)
	width = math.max(64, math.min(width, 100))

	local function pad_center(text, inner_width)
		local pad = inner_width - #text
		if pad <= 0 then
			return text:sub(1, inner_width)
		end
		local left = math.floor(pad / 2)
		local right = pad - left
		return string.rep(" ", left) .. text .. string.rep(" ", right)
	end

	-- Header
	table.insert(lines, "")
	table.insert(lines, "  ┌" .. string.rep("─", width - 4) .. "┐")
	table.insert(lines, "  │" .. pad_center("REC.NVIM", width - 4) .. "│")
	table.insert(lines, "  │" .. pad_center("Recordings Dashboard", width - 4) .. "│")
	table.insert(lines, "  └" .. string.rep("─", width - 4) .. "┘")
	table.insert(lines, "")

	-- Stats
	local count = #state.filtered
	table.insert(lines, string.format("  Total recordings: %d", count))
	if (state.search_query or "") ~= "" then
		table.insert(lines, string.format("  Search: %s", state.search_query))
	end
	table.insert(lines, "")
	table.insert(lines, "  " .. string.rep("─", width - 2))
	table.insert(lines, "")

	-- Recordings list
	if count == 0 then
		table.insert(lines, "  " .. pad_center("No recordings found", width - 2))
		table.insert(lines, "")
		if (state.search_query or "") ~= "" then
			table.insert(lines, "  " .. pad_center("Clear search with / then empty", width - 2))
		else
			table.insert(lines, "  " .. pad_center("Start recording with :RecStart or :RecWin", width - 2))
		end
		table.insert(lines, "")
	else
		for i, rec in ipairs(state.filtered) do
			local is_selected = i == state.selected_idx
			local prefix = is_selected and "  ❯ " or "    "

			local filename = vim.fn.fnamemodify(rec.path, ":t")
			local date = format_date(rec.timestamp or os.time())
			local mode_str = (rec.mode == "window") and "[WIN]" or "[FULL]"

			table.insert(lines, string.format("%s%s %s", prefix, mode_str, filename))
			table.insert(lines, string.format("     %s", date))
			table.insert(lines, string.format("     %s", rec.path))

			if i < count then
				table.insert(lines, "")
			end
		end
	end

	-- Footer
	table.insert(lines, "")
	table.insert(lines, "  " .. string.rep("─", width - 2))
	table.insert(lines, "")
	table.insert(lines, "  Controls: <Enter> Open  •  d Delete  •  / Search  •  q Quit")
	table.insert(lines, "")

	return lines
end

---Refresh the dashboard display
local function refresh()
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return
	end

	state.recordings = load_recordings()
	filter_recordings()

	if #state.filtered > 0 then
		if state.selected_idx > #state.filtered then
			state.selected_idx = #state.filtered
		end
		if state.selected_idx < 1 then
			state.selected_idx = 1
		end
	else
		state.selected_idx = 1
	end

	local lines = build_content()

	vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(state.buf, "modifiable", false)

	for i, line in ipairs(lines) do
		local lnum = i - 1

		if line:match("^  ❯") then
			vim.api.nvim_buf_add_highlight(state.buf, -1, "RecDashboardSelected", lnum, 0, -1)
		end

		if line:match("%[WIN%]") or line:match("%[FULL%]") then
			local s, e = line:find("%[.-%]")
			if s then
				local hl = line:match("%[WIN%]") and "RecDashboardBadgeWin" or "RecDashboardBadgeFull"
				vim.api.nvim_buf_add_highlight(state.buf, -1, hl, lnum, s - 1, e)
			end
		end

		if line:match("^     %d%d%d%d%-%d%d%-%d%d") then
			vim.api.nvim_buf_add_highlight(state.buf, -1, "RecDashboardDate", lnum, 0, -1)
		end

		if line:match("^     /") or line:match("^     ~") then
			vim.api.nvim_buf_add_highlight(state.buf, -1, "RecDashboardPath", lnum, 0, -1)
		end

		if line:match("^  [┌└│]") or line:match("^  ──") then
			vim.api.nvim_buf_add_highlight(state.buf, -1, "RecDashboardBorder", lnum, 0, -1)
		end

		if line:match("REC.NVIM") then
			vim.api.nvim_buf_add_highlight(state.buf, -1, "RecDashboardTitle", lnum, 0, -1)
		end

		if line:match("Recordings Dashboard") then
			vim.api.nvim_buf_add_highlight(state.buf, -1, "RecDashboardSubtitle", lnum, 0, -1)
		end
	end
end

---@return table|nil
local function get_selected()
	if #state.filtered == 0 then
		return nil
	end
	if state.selected_idx > 0 and state.selected_idx <= #state.filtered then
		return state.filtered[state.selected_idx]
	end
	return nil
end

local function open_recording()
	local rec = get_selected()
	if not rec then
		return
	end

	rec.path = normalize_path(rec.path)
	local stat = vim.loop.fs_stat(rec.path)
	if not stat then
		vim.notify("File not found: " .. rec.path, vim.log.levels.ERROR, { title = "rec.nvim" })
		refresh()
		return
	end

	local open_cmd = config.options.recording.open_command
	if not open_cmd then
		if vim.fn.has("mac") == 1 then
			open_cmd = "open"
		elseif vim.fn.has("unix") == 1 then
			open_cmd = "xdg-open"
		elseif vim.fn.has("win32") == 1 then
			open_cmd = "start"
		else
			vim.notify("No video player configured", vim.log.levels.ERROR, { title = "rec.nvim" })
			return
		end
	end

	vim.fn.jobstart({ open_cmd, rec.path }, { detach = true })
	vim.notify("Opening: " .. vim.fn.fnamemodify(rec.path, ":t"), vim.log.levels.INFO, { title = "rec.nvim" })
end

local function delete_recording()
	local rec = get_selected()
	if not rec then
		return
	end

	rec.path = normalize_path(rec.path)
	local filename = vim.fn.fnamemodify(rec.path, ":t")

	local choice = vim.fn.confirm(string.format("Delete '%s'?", filename), "&Yes\n&No", 2)
	if choice ~= 1 then
		return
	end

	local success = storage.delete_recording(rec.path)
	if success then
		vim.notify("Deleted: " .. filename, vim.log.levels.INFO, { title = "rec.nvim" })
		refresh()
	else
		vim.notify("Failed to delete: " .. filename, vim.log.levels.ERROR, { title = "rec.nvim" })
	end
end

local function setup_keymaps()
	if not state.buf then
		return
	end

	local opts = { buffer = state.buf, noremap = true, silent = true }

	vim.keymap.set("n", "j", function()
		if state.selected_idx < #state.filtered then
			state.selected_idx = state.selected_idx + 1
			refresh()
		end
	end, opts)

	vim.keymap.set("n", "k", function()
		if state.selected_idx > 1 then
			state.selected_idx = state.selected_idx - 1
			refresh()
		end
	end, opts)

	vim.keymap.set("n", "<Down>", function()
		if state.selected_idx < #state.filtered then
			state.selected_idx = state.selected_idx + 1
			refresh()
		end
	end, opts)

	vim.keymap.set("n", "<Up>", function()
		if state.selected_idx > 1 then
			state.selected_idx = state.selected_idx - 1
			refresh()
		end
	end, opts)

	vim.keymap.set("n", "<CR>", open_recording, opts)
	vim.keymap.set("n", "d", delete_recording, opts)
	vim.keymap.set("n", "/", function()
		local input = vim.fn.input("Search recordings: ", state.search_query or "")
		state.search_query = input or ""
		state.selected_idx = 1
		refresh()
	end, opts)

	vim.keymap.set("n", "q", function()
		M.close()
	end, opts)

	vim.keymap.set("n", "<Esc>", function()
		M.close()
	end, opts)
end

local function setup_highlights()
	vim.api.nvim_set_hl(0, "RecDashboardBorder", { fg = "#334155" })
	vim.api.nvim_set_hl(0, "RecDashboardTitle", { fg = "#e2e8f0", bold = true })
	vim.api.nvim_set_hl(0, "RecDashboardSubtitle", { fg = "#94a3b8" })
	vim.api.nvim_set_hl(0, "RecDashboardSelected", { fg = "#f8fafc", bg = "#0f172a", bold = true })
	vim.api.nvim_set_hl(0, "RecDashboardBadgeWin", { fg = "#22d3ee", bold = true })
	vim.api.nvim_set_hl(0, "RecDashboardBadgeFull", { fg = "#f59e0b", bold = true })
	vim.api.nvim_set_hl(0, "RecDashboardDate", { fg = "#94a3b8" })
	vim.api.nvim_set_hl(0, "RecDashboardPath", { fg = "#64748b" })
end

function M.open()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		M.close()
		return
	end

	setup_highlights()
	state.selected_idx = 1

	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(state.buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(state.buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(state.buf, "swapfile", false)
	vim.api.nvim_buf_set_option(state.buf, "filetype", "rec-dashboard")
	vim.api.nvim_buf_set_option(state.buf, "modifiable", false)

	refresh()

	local width = math.floor(vim.o.columns * 0.7)
	local height = math.floor(vim.o.lines * 0.7)
	if width < 60 then
		width = 60
	end
	if height < 20 then
		height = 20
	end

	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
	})

	vim.api.nvim_win_set_option(state.win, "cursorline", false)
	vim.api.nvim_win_set_option(state.win, "number", false)
	vim.api.nvim_win_set_option(state.win, "relativenumber", false)
	vim.api.nvim_win_set_option(state.win, "wrap", false)

	setup_keymaps()
end

function M.close()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
	end
	state.win = nil
	state.buf = nil
end

function M.toggle()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		M.close()
	else
		M.open()
	end
end

return M
