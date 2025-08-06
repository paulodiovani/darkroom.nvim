-- Darkroom - A neovim plugin that simulates a dark room by creating darkened side windows
-- Author: Paulo Diovani <https://github.com/paulodiovani>
-- Maintainer: Paulo Diovani <https://github.com/paulodiovani>

local M = {}

-- Default configuration
M.config = {
  bufname = '__darkroom__',                                                                                                                                                                    -- buffer name used in darkroom side windows
  highlight = 'DarkRoomNormal',                                                                                                                                                                -- highlight group name used by darkroom
  darken_percent = 25,                                                                                                                                                                         -- percent to darken the bg color in darkroom side windows
  min_columns = 130,                                                                                                                                                                           -- minimum number of columns for the main/center window
  win_params =
  'buftype=nofile filetype=darkroom bufhidden=wipe nomodifiable nobuflisted noswapfile nocursorline nocursorcolumn nonumber norelativenumber noruler nolist noshowmode noshowcmd'              -- window params
}

-- Local state
local is_initialized = false

-- Helper functions
local function is_active()
  local darkroom_windows = M.get_windows('darkroom')
  return #darkroom_windows >= 2
end

local function is_darkroom_window(window)
  window = window or 0 -- 0 for current window
  local buffer = vim.fn.bufname(vim.fn.winbufnr(window))
  local window_width = vim.fn.winwidth(window)
  local darkroom_width = M.get_darkroom_width()

  return string.find(buffer, M.config.bufname) ~= nil or window_width == darkroom_width
end

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

-- Get darkroom windows width
function M.get_darkroom_width()
  return math.floor((vim.o.columns - M.config.min_columns) / 2)
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

-- Get a darker background color
function M.get_darker_bg()
  local current_bg = vim.fn.synIDattr(vim.fn.hlID('Normal'), 'bg#')
  return M.darken_color(current_bg, M.config.darken_percent)
end

-- Set window background
local function set_window_bg()
  vim.cmd('set winhighlight=Normal:' .. M.config.highlight)
end

-- Split window at the given position and set win highlight
local function split_window(position)
  local width = M.get_darkroom_width()

  if width <= 0 then
    return
  end

  local buf = vim.fn.bufadd(M.config.bufname)
  local win = vim.api.nvim_open_win(buf, true, {
    split = position,
    width = width,
  })
  -- Parse win_params and apply them
  for option, value in string.gmatch(M.config.win_params, "(%w+)=(%w+)") do
    vim.api.nvim_win_set_option(win, option, value)
  end

  set_window_bg()
  vim.cmd('wincmd p')
end

-- Toggle darkroom to use a smaller viewport
function M.toggle()
  -- make only window if darkroom is in use
  if is_active() then
    -- focus on first non-darkroom window, if needed
    if is_darkroom_window() then
      local focus_window = M.get_windows('nondarkroom')[1]
      vim.cmd(focus_window .. 'wincmd w')
    end

    -- close darkroom windows (in reverse bc of win numbers)
    local darkroom_windows = M.get_windows('darkroom')
    for i = #darkroom_windows, 1, -1 do
      vim.cmd(darkroom_windows[i] .. ' wincmd c')
    end
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
function M.cmd(position, command, replace)
  replace = replace or false
  local width = M.get_darkroom_width()
  local dest_window = get_dest_window(position)

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
        vim.cmd(dest_window .. ' wincmd c')
      end

      local splitpos = position == 'left' and 'topleft' or 'botright'
      vim.cmd('vert ' .. splitpos .. ' ' .. range .. command)
      -- must refresh winnr because windows may have changed
      dest_window = get_dest_window(position)
      vim.cmd('vert ' .. dest_window .. ' resize ' .. M.get_darkroom_width())
    else
      -- make sure we have a window and move to it
      if not is_darkroom_window(dest_window) then
        split_window(position)
      end

      vim.cmd(dest_window .. ' wincmd w')
      vim.cmd(range .. command)
    end

    set_window_bg()
  end)

  if not ok then
    vim.api.nvim_err_writeln(err)
    -- return to main window in case of error
    vim.cmd('silent wincmd p')
  end
end

-- Set up the highlight group
local function setup_highlight()
  vim.cmd('highlight ' .. M.config.highlight .. ' guibg=' .. M.get_darker_bg())
end

-- Setup function to initialize the plugin with user configuration
function M.setup(opts)
  -- Merge user config with defaults
  if opts then
    for k, v in pairs(opts) do
      M.config[k] = v
    end
  end

  if not is_initialized then
    -- Set up highlight group
    setup_highlight()
    is_initialized = true
  end

  -- Create commands
  vim.api.nvim_create_user_command('DarkRoomToggle', function()
    M.toggle()
  end, { nargs = 0 })

  vim.api.nvim_create_user_command('DarkRoomLeft', function(args)
    M.cmd('left', args.args, false)
  end, { nargs = '+', range = true })

  vim.api.nvim_create_user_command('DarkRoomRight', function(args)
    M.cmd('right', args.args, false)
  end, { nargs = '+', range = true })

  vim.api.nvim_create_user_command('DarkRoomReplaceLeft', function(args)
    M.cmd('left', args.args, true)
  end, { nargs = '+', range = true })

  vim.api.nvim_create_user_command('DarkRoomReplaceRight', function(args)
    M.cmd('right', args.args, true)
  end, { nargs = '+', range = true })

  -- Create default mapping
  if not vim.fn.hasmapto('<Plug>DarkRoomToggle') then
    vim.api.nvim_set_keymap('n', '<Leader><BS>', ':DarkRoomToggle<CR>', { noremap = false, silent = true })
  end
end

return M
