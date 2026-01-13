local M = {}

-- Configuration
local config = {
	max_repeat_count = 3, -- Show "jjj" then collapse to "j×5"
	ignore_navigation = true,
	ignore_mouse = true,
}

-- Keycode to symbol mapping
local KEY_SYMBOLS = {
	["<Cmd>"] = "⌘",
	["<CR>"] = "⏎",
	["<Return>"] = "⏎",
	["<Enter>"] = "⏎",
	["<Esc>"] = "⎋",
	["<Tab>"] = "⇥",
	["<Space>"] = "␣",
	["<BS>"] = "⌫",
	["<Backspace>"] = "⌫",
	["<Del>"] = "⌦",
	["<Delete>"] = "⌦",
	["<Up>"] = "↑",
	["<Down>"] = "↓",
	["<Left>"] = "←",
	["<Right>"] = "→",
	["<Home>"] = "⇱",
	["<End>"] = "⇲",
	["<PageUp>"] = "⇞",
	["<PageDown>"] = "⇟",
}

-- Modifier prefixes
local MODIFIERS = {
	["<S%-"] = "⇧",
	["<Shift%-"] = "⇧",
	["<C%-"] = "⌃",
	["<Ctrl%-"] = "⌃",
	["<Control%-"] = "⌃",
	["<M%-"] = "⌥",
	["<A%-"] = "⌥",
	["<Alt%-"] = "⌥",
	["<D%-"] = "⌘", -- Some systems use D- for command
}

-- Navigation keys to collapse when repeated
local NAV_KEYS = {
	h = true,
	j = true,
	k = true,
	l = true,
	w = true,
	b = true,
	e = true,
	["0"] = true,
	["$"] = true,
}

-- Keys to completely ignore
local IGNORE_KEYS = {
	["<Ignore>"] = true,
	["<MouseMove>"] = true,
	["<ScrollWheelUp>"] = true,
	["<ScrollWheelDown>"] = true,
	["<LeftMouse>"] = true,
	["<RightMouse>"] = true,
	["<MiddleMouse>"] = true,
	["<LeftDrag>"] = true,
	["<LeftRelease>"] = true,
	["<RightDrag>"] = true,
	["<RightRelease>"] = true,
	[""] = true,
}

---Normalize a raw Vim keycode into human-readable format
---@param raw_key string The raw key from vim.fn.keytrans()
---@return string|nil Normalized key or nil if should be ignored
local function normalize_key(raw_key)
	-- Check if should be ignored
	if IGNORE_KEYS[raw_key] then
		return nil
	end

	-- Ignore mouse events
	if config.ignore_mouse and raw_key:match("^<.*Mouse.*>$") then
		return nil
	end

	local key = raw_key

	-- Replace special keys first
	for pattern, symbol in pairs(KEY_SYMBOLS) do
		key = key:gsub(vim.pesc(pattern), symbol)
	end

	-- Extract and combine modifiers
	local modifiers = {}
	for pattern, symbol in pairs(MODIFIERS) do
		if key:match(pattern) then
			table.insert(modifiers, symbol)
			key = key:gsub(pattern, "")
		end
	end

	-- Clean up remaining angle brackets
	key = key:gsub(">", ""):gsub("<", "")

	-- If we have modifiers, combine them with the key (no spaces)
	if #modifiers > 0 then
		-- Sort modifiers for consistency: ⌘ ⌥ ⇧ ⌃
		local order = { ["⌘"] = 1, ["⌥"] = 2, ["⇧"] = 3, ["⌃"] = 4 }
		table.sort(modifiers, function(a, b)
			return (order[a] or 99) < (order[b] or 99)
		end)

		return table.concat(modifiers, "") .. key
	end

	return key
end

---State for tracking key sequences
local state = {
	last_key = nil,
	repeat_count = 1,
}

---Process a raw key and return formatted output
---Handles key repetition and collapsing
---@param raw_key string Raw key from Vim
---@return string|nil Formatted key(s) to display, or nil if filtered
function M.process(raw_key)
	local key = normalize_key(raw_key)

	if not key then
		return nil
	end

	-- Handle key repetition
	if key == state.last_key then
		state.repeat_count = state.repeat_count + 1

		-- Collapse navigation keys
		if config.ignore_navigation and NAV_KEYS[key] then
			if state.repeat_count > config.max_repeat_count then
				return nil -- Filter out, will show in finalize
			end
			return key
		end

		-- Show first N occurrences, then start collapsing
		if state.repeat_count > config.max_repeat_count then
			return nil -- Filter out until sequence ends
		end

		return key
	else
		-- Key changed, finalize previous sequence if needed
		local result = M.finalize()
		state.last_key = key
		state.repeat_count = 1
		return result or key
	end
end

---Finalize a key sequence (called when key changes)
---Returns collapsed representation if needed
---@return string|nil Collapsed key representation
function M.finalize()
	if state.repeat_count > config.max_repeat_count then
		local collapsed = string.format("%s×%d", state.last_key, state.repeat_count)
		state.repeat_count = 1
		return collapsed
	end
	return nil
end

---Reset the processor state
function M.reset()
	state.last_key = nil
	state.repeat_count = 1
end

---Configure the keymap processor
---@param opts table Configuration options
function M.configure(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

---Get the current configuration
---@return table Current config
function M.get_config()
	return vim.deepcopy(config)
end

return M
