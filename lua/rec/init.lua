local M = {}

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
		width = 18,
		height = 3,
		style = "minimal",
		border = "rounded",
	})
end

local function open_keys()
	state.keys_buf = vim.api.nvim_create_buf(false, true)

	state.keys_win = vim.api.nvim_open_win(state.keys_buf, false, {
		relative = "editor",
		anchor = "NE",
		row = 5,
		col = vim.o.columns - 2,
		width = 30,
		height = 4,
		style = "minimal",
		border = "rounded",
	})
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
		"🔴 REC",
		format_time(elapsed),
	})
end

-- ---------- keystroke capture ----------

local function redraw_keys()
	if not (state.keys_buf and vim.api.nvim_buf_is_valid(state.keys_buf)) then
		return
	end

	vim.api.nvim_buf_set_lines(state.keys_buf, 0, -1, false, {
		"⌨ Keystrokes",
		table.concat(state.keys, " "),
	})
end

local function on_key(key)
	if not state.running then
		return
	end

	local k = vim.fn.keytrans(key)

	-- filter junk
	if k == "<Ignore>" or k == "" then
		return
	end

	table.insert(state.keys, k)

	-- keep last ~20 keys
	if #state.keys > 20 then
		table.remove(state.keys, 1)
	end

	redraw_keys()
end

-- ---------- rust runner ----------

local function run(args)
	if not ensure_executable() then
		return
	end

	vim.fn.jobstart(vim.list_extend({ REC_CLI }, args), {
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

	notify("REC_STOP_OK")
end

-- ---------- statusline ----------

function M.status()
	return state.running and "🔴 REC" or ""
end

function M.setup()
	vim.api.nvim_create_user_command("RecStart", M.start, {})
	vim.api.nvim_create_user_command("RecStop", M.stop, {})
end

return M
