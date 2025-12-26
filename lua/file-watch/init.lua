local M = {}

---@class FileWatchConfig
---@field debounce_ms number Debounce delay in milliseconds (default: 100)
---@field notify boolean Show notification when file is reloaded (default: true)
---@field notify_level number Notification level (default: vim.log.levels.INFO)
---@field ignore_patterns string[] Patterns to ignore (default: { "%.git/", "%.swp$", "~$" })
---@field auto_enable boolean Automatically watch files on BufReadPost (default: true)

---@type FileWatchConfig
local default_config = {
  debounce_ms = 100,
  notify = true,
  notify_level = vim.log.levels.INFO,
  ignore_patterns = { "%.git/", "%.swp$", "~$", "4913$" },
  auto_enable = true,
}

---@type FileWatchConfig
local config = vim.deepcopy(default_config)

---@type table<number, uv_fs_event_t>
local watchers = {}

---@type table<number, uv_timer_t|nil>
local debounce_timers = {}

---@type boolean
local enabled = false

---@type number|nil
local autocmd_group = nil

---Check if a filepath matches any ignore pattern
---@param filepath string
---@return boolean
local function should_ignore(filepath)
  for _, pattern in ipairs(config.ignore_patterns) do
    if filepath:match(pattern) then
      return true
    end
  end
  return false
end

---Check if a buffer is watchable (has a real file path)
---@param bufnr number
---@return boolean, string|nil filepath
local function is_watchable(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, nil
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    return false, nil
  end

  -- Skip remote files (netrw, fugitive, etc.)
  if filepath:match("^%w+://") then
    return false, nil
  end

  -- Skip if file doesn't exist
  local stat = vim.uv.fs_stat(filepath)
  if not stat or stat.type ~= "file" then
    return false, nil
  end

  if should_ignore(filepath) then
    return false, nil
  end

  return true, filepath
end

---Stop watching a buffer
---@param bufnr number
local function unwatch_buffer(bufnr)
  local timer = debounce_timers[bufnr]
  if timer then
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    debounce_timers[bufnr] = nil
  end

  local handle = watchers[bufnr]
  if handle then
    if not handle:is_closing() then
      handle:stop()
      handle:close()
    end
    watchers[bufnr] = nil
  end
end

-- Forward declaration for mutual recursion
local watch_buffer

---Start watching a buffer's file
---@param bufnr number
watch_buffer = function(bufnr)
  -- Clean up any existing watcher first
  unwatch_buffer(bufnr)

  local watchable, filepath = is_watchable(bufnr)
  if not watchable or not filepath then
    return
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  watchers[bufnr] = handle

  local ok, _ = handle:start(filepath, {}, function(err_watch, _, events)
    if err_watch then
      vim.schedule(function()
        unwatch_buffer(bufnr)
      end)
      return
    end

    -- Handle both change and rename events
    -- Many editors do atomic writes (write to temp file, then rename)
    if not events or (not events.change and not events.rename) then
      return
    end

    -- Cancel existing debounce timer
    local existing_timer = debounce_timers[bufnr]
    if existing_timer and not existing_timer:is_closing() then
      existing_timer:stop()
      existing_timer:close()
      debounce_timers[bufnr] = nil
    end

    -- Create new debounce timer
    local timer = vim.uv.new_timer()
    if not timer then
      return
    end
    debounce_timers[bufnr] = timer

    timer:start(config.debounce_ms, 0, function()
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
      debounce_timers[bufnr] = nil

      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          unwatch_buffer(bufnr)
          return
        end

        -- Check if file still exists
        local stat = vim.uv.fs_stat(filepath)
        if not stat then
          if config.notify then
            vim.notify("File deleted: " .. vim.fn.fnamemodify(filepath, ":~:."), vim.log.levels.WARN)
          end
          unwatch_buffer(bufnr)
          return
        end

        -- Store changedtick before checktime so we can verify actual reload
        vim.b[bufnr].file_watch_changedtick = vim.api.nvim_buf_get_var(bufnr, "changedtick")

        -- Use checktime to handle the reload
        -- This respects autoread and shows conflict dialog if buffer is modified
        -- Notification is handled by FileChangedShellPost autocmd
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("checktime")
        end)

        -- Re-establish the watch after a short delay
        -- (gives FileChangedShellPost time to read file_watch_changedtick first)
        vim.defer_fn(function()
          if enabled and vim.api.nvim_buf_is_valid(bufnr) then
            watch_buffer(bufnr)
          end
        end, 50)
      end)
    end)
  end)

  if not ok then
    handle:close()
    watchers[bufnr] = nil
  end
end

---Setup autocommands for watching
local function setup_autocmds()
  if autocmd_group then
    return
  end

  autocmd_group = vim.api.nvim_create_augroup("FileWatch", { clear = true })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = autocmd_group,
    pattern = "*",
    callback = function(args)
      if enabled and config.auto_enable then
        watch_buffer(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = autocmd_group,
    pattern = "*",
    callback = function(args)
      unwatch_buffer(args.buf)
    end,
  })

  -- Re-watch on file rename/save-as
  vim.api.nvim_create_autocmd("BufFilePost", {
    group = autocmd_group,
    pattern = "*",
    callback = function(args)
      if enabled then
        unwatch_buffer(args.buf)
        watch_buffer(args.buf)
      end
    end,
  })

  -- Notify when file is actually reloaded
  vim.api.nvim_create_autocmd("FileChangedShellPost", {
    group = autocmd_group,
    pattern = "*",
    callback = function(args)
      -- Redraw first to show the updated buffer
      vim.cmd("redraw")

      if not config.notify then
        return
      end

      -- Only notify if buffer content actually changed
      local prev_tick = vim.b[args.buf].file_watch_changedtick
      local curr_tick = vim.api.nvim_buf_get_var(args.buf, "changedtick")
      vim.b[args.buf].file_watch_changedtick = nil

      if prev_tick and curr_tick == prev_tick then
        -- Content didn't change, user kept their buffer
        return
      end

      local time = os.date("%H:%M:%S")
      local name = vim.fn.fnamemodify(args.file, ":~:.")
      vim.notify("Reloaded: " .. name .. " at " .. time, config.notify_level)
    end,
  })
end

---Clear all autocommands
local function clear_autocmds()
  if autocmd_group then
    vim.api.nvim_del_augroup_by_id(autocmd_group)
    autocmd_group = nil
  end
end

---Enable file watching globally
function M.enable()
  if enabled then
    return
  end

  enabled = true
  vim.o.autoread = true

  setup_autocmds()

  -- Watch all existing buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      watch_buffer(bufnr)
    end
  end

  if config.notify then
    vim.notify("File watching enabled", config.notify_level)
  end
end

---Disable file watching globally
function M.disable()
  if not enabled then
    return
  end

  enabled = false

  -- Stop all watchers
  for bufnr, _ in pairs(watchers) do
    unwatch_buffer(bufnr)
  end

  clear_autocmds()

  if config.notify then
    vim.notify("File watching disabled", config.notify_level)
  end
end

---Toggle file watching
function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

---Get status of file watching
---@return table
function M.status()
  local watched_files = {}
  for bufnr, _ in pairs(watchers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      table.insert(watched_files, {
        bufnr = bufnr,
        file = vim.fn.fnamemodify(name, ":~:."),
      })
    end
  end

  return {
    enabled = enabled,
    watched_count = #watched_files,
    watched_files = watched_files,
  }
end

---Print status to messages
function M.print_status()
  local status = M.status()
  local lines = {
    "File Watch: " .. (status.enabled and "enabled" or "disabled"),
    "Watching " .. status.watched_count .. " file(s):",
  }
  for _, file in ipairs(status.watched_files) do
    table.insert(lines, "  [" .. file.bufnr .. "] " .. file.file)
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

---Setup the plugin with user config
---@param opts FileWatchConfig|nil
function M.setup(opts)
  config = vim.tbl_deep_extend("force", default_config, opts or {})

  -- Create user commands
  vim.api.nvim_create_user_command("FileWatchEnable", function()
    M.enable()
  end, { desc = "Enable file watching" })

  vim.api.nvim_create_user_command("FileWatchDisable", function()
    M.disable()
  end, { desc = "Disable file watching" })

  vim.api.nvim_create_user_command("FileWatchToggle", function()
    M.toggle()
  end, { desc = "Toggle file watching" })

  vim.api.nvim_create_user_command("FileWatchStatus", function()
    M.print_status()
  end, { desc = "Show file watching status" })

  -- Auto-enable if configured
  if config.auto_enable then
    M.enable()
  end
end

return M
