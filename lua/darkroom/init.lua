-- Darkroom - A neovim plugin that simulates a dark room by creating darkened side windows
-- Author: Paulo Diovani <https://github.com/paulodiovani>
-- Maintainer: Paulo Diovani <https://github.com/paulodiovani>

local M = {}
local edgy = require("edgy")

local default_options = {
  darken_percent = 25,         -- percent to darken the bg color in darkroom side windows
  min_columns = 130,           -- minimum number of columns for the main/center window
  left = {                     -- left window options
    filetype = "darkroomleft", -- darkroom window filetype
    additional_filetypes = {   -- additional filetypes to use darkroom

    },
  },
  right = {                     -- left window options
    filetype = "darkroomright", -- darkroom window filetype
    additional_filetypes = {    -- additional filetypes to use darkroom

    },
  },
  --  window options used in darkroom left/right windows
  --- @type vim.wo
  --- @diagnostic disable: missing-fields
  wo = {
    winbar = false,                                                -- do not show winbar
    winhighlight = "Normal:DarkRoomNormal,NormalNC:DarkRoomNormal" -- window highlight used by darkroom
  },
  -- setup edgy.nvim
  -- set as false to configure edgy yourself
  setup_edgy = true
}
local options

-- Local state
local is_initialized = false

-- Helper functions
local function is_active()
  local darkroom_windows = M.get_windows('darkroom')
  return #darkroom_windows >= 2
end

-- check if a window is a darkroom window
local function is_darkroom_window(window)
  window = window or 0 -- 0 for current window

  local winid = vim.fn.win_getid(window)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local ft = vim.api.nvim_get_option_value('filetype', { scope = 'local', buf = bufnr })

  -- Check if the filetype matches any darkroom filetypes
  if ft == options.left.filetype or ft == options.right.filetype then
    return true
  end

  -- Check additional filetypes for left side
  for _, additional_ft in ipairs(options.left.additional_filetypes or {}) do
    if ft == additional_ft then
      return true
    end
  end

  -- Check additional filetypes for right side
  for _, additional_ft in ipairs(options.right.additional_filetypes or {}) do
    if ft == additional_ft then
      return true
    end
  end

  return false
end

-- return a window number for the position
local function get_dest_window(position)
  if position == 'left' then
    return 1
  else -- right
    return vim.fn.winnr('$')
  end
end

-- Return a list of window numbers filtered by type
function M.get_windows(window_type)
  window_type = window_type or 'all'
  local windows = {}
  for i = 1, vim.fn.winnr('$') do
    table.insert(windows, i)
  end

  if window_type == 'darkroom' then
    -- return darkroom windows
    local result = {}
    for _, win in ipairs(windows) do
      if is_darkroom_window(win) then
        table.insert(result, win)
      end
    end
    return result
  elseif window_type == 'nondarkroom' then
    -- return non-darkroom windows
    local result = {}
    for _, win in ipairs(windows) do
      if not is_darkroom_window(win) then
        table.insert(result, win)
      end
    end
    return result
  elseif window_type == 'vertical' then
    -- return vertical split windows
    local result = {}
    for _, win in ipairs(windows) do
      if vim.fn.winwidth(win) ~= vim.o.columns then
        table.insert(result, win)
      end
    end
    return result
  elseif window_type == 'horizontal' then
    -- return horizontal split windows
    local result = {}
    for _, win in ipairs(windows) do
      if vim.fn.winheight(win) ~= vim.o.lines - vim.o.cmdheight - 1 then
        table.insert(result, win)
      end
    end
    return result
  else -- if window_type == 'all'
    -- return all windows
    return windows
  end
end

function M.get_darkroom_width()
  return math.floor((vim.o.columns - options.min_columns) / 2)
end

-- Darken a hex color
function M.darken_color(hex, percent)
  local r = tonumber(string.sub(hex, 2, 3), 16)
  local g = tonumber(string.sub(hex, 4, 5), 16)
  local b = tonumber(string.sub(hex, 6, 7), 16)

  local factor = 1 - (percent / 100.0)
  r = math.max(0, math.floor(r * factor))
  g = math.max(0, math.floor(g * factor))
  b = math.max(0, math.floor(b * factor))

  return string.format("#%02x%02x%02x", r, g, b)
end

function M.get_darker_bg()
  local current_bg = vim.fn.synIDattr(vim.fn.hlID('Normal'), 'bg#')
  return M.darken_color(current_bg, options.darken_percent)
end

-- Set window background
local function set_window_bg()
  vim.api.nvim_set_option_value("winhighlight", options.wo.winhighlight, { scope = 'local' })
end

-- Split window at the given position
local function split_window(position)
  local width = M.get_darkroom_width()
  local filetype = position == "left" and options.left.filetype or options.right.filetype

  if width <= 0 then
    return
  end

  -- local buf = vim.fn.bufadd(config.bufname)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_open_win(buf, false, { vertical = true, split = position })

  -- Apply buffer/window options
  vim.api.nvim_set_option_value("filetype", filetype, { scope = 'local', buf = buf })
end

-- Toggle darkroom to use a smaller viewport
function M.toggle()
  -- make only window if darkroom is in use
  if is_active() then
    -- let edgy close windows
    edgy.close()
  else
    if not is_darkroom_window(1) then
      split_window('left')
    end

    if not is_darkroom_window(vim.fn.winnr('$')) then
      split_window('right')
    end
  end
end

-- Runs a command on the specified darkroom window
function M.exec(position, command, replace)
  replace = replace or false
  local dest_window = get_dest_window(position)
  local dest_win_id = vim.fn.win_getid(dest_window)

  local range = ""
  local mode = vim.fn.mode() -- editor mode

  -- include range, if in visual mode
  if mode == 'v' or mode == 'V' or mode == '\22' then -- \22 is <C-V>
    range = vim.fn.line("'<") .. ',' .. vim.fn.line("'>")
  end

  local ok, err = pcall(function()
    if replace == true then
      -- close darkroom window first, if exists
      if is_darkroom_window(dest_window) then
        vim.api.nvim_win_close(dest_win_id, false)
      end

      local splitpos = position == 'left' and 'topleft' or 'botright'
      vim.cmd('vert ' .. splitpos .. ' ' .. range .. command)
      -- must refresh winnr because windows have changed
      dest_window = get_dest_window(position)
      dest_win_id = vim.fn.win_getid(dest_window)
    else
      -- make sure we have a window and move to it
      if not is_darkroom_window(dest_window) then
        split_window(position)
        -- must refresh winnr because windows have changed
        dest_window = get_dest_window(position)
        dest_win_id = vim.fn.win_getid(dest_window)
      end

      vim.api.nvim_set_current_win(dest_win_id)
      vim.api.nvim_command(range .. command)
    end

    set_window_bg()
  end)

  if not ok and err then
    vim.notify(err, vim.log.levels.ERROR)
    -- return to main window in case of error
    edgy.goto_main()
  end
end

--  return edgy options used for darkroom windows
--- @return Edgy.Config
function M.edgy_options()
  return {
    animate = { enabled = false },
    left = {
      {
        ft = options.left.filetype,
        size = { width = M.get_darkroom_width },
        wo = options.wo
      },
      -- Add additional filetypes for left side
      unpack(vim.tbl_map(function(ft)
        return {
          ft = ft,
          size = { width = M.get_darkroom_width },
          wo = options.wo
        }
      end, options.left.additional_filetypes or {})),
    },
    right = {
      {
        ft = options.right.filetype,
        size = { width = M.get_darkroom_width },
        wo = options.wo
      },
      -- Add additional filetypes for right side
      unpack(vim.tbl_map(function(ft)
        return {
          ft = ft,
          size = { width = M.get_darkroom_width },
          wo = options.wo
        }
      end, options.right.additional_filetypes or {})),
    },
  }
end

function M.setup(opts)
  -- Merge user config with defaults
  opts = opts or {}
  options = vim.tbl_deep_extend("force", default_options, opts)

  if not is_initialized then
    is_initialized = true
  end

  -- Set up highlight group
  vim.api.nvim_set_hl(0, "DarkRoomNormal", { bg = M.get_darker_bg() })

  -- Create commands
  vim.api.nvim_create_user_command('DarkRoomToggle', function()
    M.toggle()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command('DarkRoomLeft', function(args)
    M.exec('left', args.args, false)
  end, { nargs = '+', range = true })

  vim.api.nvim_create_user_command('DarkRoomRight', function(args)
    M.exec('right', args.args, false)
  end, { nargs = '+', range = true })

  vim.api.nvim_create_user_command('DarkRoomReplaceLeft', function(args)
    M.exec('left', args.args, true)
  end, { nargs = '+', range = true })

  vim.api.nvim_create_user_command('DarkRoomReplaceRight', function(args)
    M.exec('right', args.args, true)
  end, { nargs = '+', range = true })

  -- Create default mapping
  if not vim.fn.hasmapto('<Plug>DarkRoomToggle') then
    vim.api.nvim_set_keymap('n', '<Leader><BS>', ':DarkRoomToggle<CR>', { noremap = false, silent = true })
  end

  -- setup edgy.nvim
  if options.setup_edgy then
    edgy.setup(M.edgy_options())
  end
end

return M
