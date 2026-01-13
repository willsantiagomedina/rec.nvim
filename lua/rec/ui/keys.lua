local width = 24
local height = 3

local row = vim.o.lines - height - 2
local col = vim.o.columns - width - 2

state.keys_win = vim.api.nvim_open_win(state.keys_buf, false, {
	relative = "editor",
	anchor = "NW",
	row = row,
	col = col,
	width = width,
	height = height,
	style = "minimal",
	border = "rounded",
	zindex = 50,
})
