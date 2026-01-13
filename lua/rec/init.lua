local M = {}

-- 🔧 CHANGE ONLY IF YOU MOVE THE BINARY
local REC_CLI = vim.fn.expand("~/dev/rec.nvim/crates/rec-cli/target/debug/rec-cli")

local state = {
	running = false,
	start_time = nil,
	timer = nil,
	win = nil,
	buf = nil,
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

-- ---------- floating window ----------

local function open_float(text)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		return
	end

	state.buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, text)

	local width = 20
	local height = 3

	state.win = vim.api.nvim_open_win(state.buf, false, {
		relative = "editor",
		anchor = "NE",
		row = 1,
		col = vim.o.columns - 2,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
	})
end

local function update_float()
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return
	end

	local elapsed = os.time() - state.start_time
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
		"🔴 REC",
		format_time(elapsed),
	})
end

local function close_float()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
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

	open_float({ "🔴 REC", "00:00" })

	state.timer = vim.loop.new_timer()
	state.timer:start(0, 1000, vim.schedule_wrap(update_float))

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

	close_float()

	state.running = false
	state.start_time = nil

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
