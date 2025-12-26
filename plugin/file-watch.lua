-- Prevent double-loading
if vim.g.loaded_file_watch then
  return
end
vim.g.loaded_file_watch = true

-- Plugin auto-loads when setup() is called
-- For users without a plugin manager, provide a simple way to get started
vim.api.nvim_create_user_command("FileWatchSetup", function()
  require("file-watch").setup()
end, { desc = "Setup file-watch with default config" })
