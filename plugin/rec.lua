if vim.g.loaded_rec_nvim == 1 then
	return
end
vim.g.loaded_rec_nvim = 1

local cli = require("rec.cli")

vim.api.nvim_create_user_command("RecStart", function()
	cli.start()
end, {})

vim.api.nvim_create_user_command("RecStop", function()
	cli.stop()
end, {})

vim.api.nvim_create_user_command("RecDevices", function()
	cli.devices()
end, {})

vim.api.nvim_create_user_command("RecStatus", function()
	cli.status()
end, {})
