local M = {}

-- ABSOLUTE path on purpose (no ~ expansion issues)
local BIN = "/Users/willsantiago/dev/rec.nvim/crates/rec-cli/target/debug/rec-cli"

local function run(args, cb)
	vim.system({ BIN, unpack(args) }, { text = true }, function(res)
		if not res then
			vim.notify("rec.nvim: failed to run backend", vim.log.levels.ERROR)
			return
		end

		local stdout = res.stdout and vim.trim(res.stdout) or ""
		local stderr = res.stderr and vim.trim(res.stderr) or ""

		if stdout == "ERR_PERMISSION_DENIED" then
			vim.notify(
				"Screen Recording permission denied.\n\n"
					.. "Enable it in:\n"
					.. "System Settings → Privacy & Security → Screen Recording\n\n"
					.. "Then restart your terminal.",
				vim.log.levels.ERROR
			)
			return
		end

		if stdout == "ERR_ALREADY_RECORDING" then
			vim.notify("rec.nvim is already recording 🔴", vim.log.levels.WARN)
			return
		end

		if stdout == "ERR_NOT_RECORDING" then
			vim.notify("rec.nvim is not recording", vim.log.levels.WARN)
			return
		end

		if stdout == "ERR_NO_SCREEN_DEVICE" then
			vim.notify("No screen capture device found", vim.log.levels.ERROR)
			return
		end

		if stdout == "ERR_FFMPEG_FAILED" then
			vim.notify("ffmpeg failed to start (is it installed?)", vim.log.levels.ERROR)
			return
		end

		if cb then
			cb(stdout, stderr)
		end
	end)
end

-- =========================
-- Public API
-- =========================

function M.start()
	run({ "start" }, function(out)
		if out == "REC_STARTED" then
			vim.notify("Recording started 🎥", vim.log.levels.INFO)
		else
			vim.notify(out, vim.log.levels.INFO)
		end
	end)
end

function M.stop()
	run({ "stop" }, function(out)
		if out == "REC_STOPPED" then
			vim.notify("Recording stopped ⏹️", vim.log.levels.INFO)
			vim.notify("Saved to /tmp/rec.nvim.mp4", vim.log.levels.INFO)
		else
			vim.notify(out, vim.log.levels.INFO)
		end
	end)
end

function M.status()
	run({ "status" }, function(out)
		if out == "REC_RECORDING" then
			vim.notify("rec.nvim is recording 🔴", vim.log.levels.INFO)
		elseif out == "REC_IDLE" then
			vim.notify("rec.nvim is idle ⚪", vim.log.levels.INFO)
		else
			vim.notify(out, vim.log.levels.INFO)
		end
	end)
end

function M.devices()
	vim.system({ BIN, "devices" }, { text = true }, function(res)
		if res.stderr and res.stderr ~= "" then
			vim.notify(res.stderr, vim.log.levels.INFO)
		else
			vim.notify("No devices output", vim.log.levels.WARN)
		end
	end)
end

return M
