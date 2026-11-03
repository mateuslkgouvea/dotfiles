local M = {}

local formats = {
  arrow = true,
  avro = true,
  csv = true,
  db = true,
  db3 = true,
  dsv = true,
  fwf = true,
  html = true,
  htm = true,
  json = true,
  jsonl = true,
  logfmt = true,
  md = true,
  markdown = true,
  ndjson = true,
  parquet = true,
  sqlite = true,
  sqlite3 = true,
  tsv = true,
  xls = true,
  xlsx = true,
  xlsm = true,
}

local state
local close, focus_list, focus_preview, toggle_layout
local filter_hint_namespace = vim.api.nvim_create_namespace('tabiew-filter-hint')

local function fuzzy_match(text, query)
  local text_index = 1
  text, query = text:lower(), query:lower()

  for query_index = 1, #query do
    local found = text:find(query:sub(query_index, query_index), text_index, true)
    if not found then return false end
    text_index = found + 1
  end

  return true
end

local function supported_file(path)
  local extension = path:match '%.([^./]+)$'
  return extension ~= nil and formats[extension:lower()] == true
end

local function discard_preview(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local job = vim.b[buf].terminal_job_id
  if job then vim.fn.jobstop(job) end
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

local function active_border(win, active)
  if win and vim.api.nvim_win_is_valid(win) then
    local highlight = active and 'FloatBorder:TabiewActiveBorder' or 'FloatBorder:TabiewInactiveBorder'
    if state and win == state.list_win then
      highlight = highlight .. ',CursorLine:TabiewSelectedLine,Cursor:TabiewSelectedLine'
    end
    vim.wo[win].winhighlight = highlight
  end
end

local function set_active_pane(pane)
  if not state or state.closed then return end
  state.active_pane = pane
  active_border(state.list_win, pane == 'list')
  active_border(state.preview_win, pane == 'preview')
end

local function filtered_files()
  local files = {}
  for _, path in ipairs(state.files) do
    local relative = vim.fs.relpath(state.root, path) or path
    if fuzzy_match(relative, state.query) then
      files[#files + 1] = { path = path, label = relative }
    end
  end
  return files
end

local function selected_row()
  for index, file in ipairs(state.visible) do
    if file.path == state.selected then return index + 1 end
  end
  return 2
end

local function render_items()
  if not state or state.closed then return end
  state.visible = filtered_files()

  local lines = {}
  for _, file in ipairs(state.visible) do
    lines[#lines + 1] = file.label
  end
  if #lines == 0 then lines[1] = 'No matching files' end

  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.list_buf, 1, -1, false, lines)
  vim.bo[state.list_buf].modifiable = state.filtering
  vim.bo[state.list_buf].modified = false
  vim.api.nvim_buf_clear_namespace(state.list_buf, filter_hint_namespace, 0, 1)
  if state.query == '' then
    vim.api.nvim_buf_set_extmark(state.list_buf, filter_hint_namespace, 0, 0, {
      virt_text = { { '/ to filter files', 'TabiewFilterHint' } },
      virt_text_pos = 'eol',
    })
  end

  if not state.visible[1] then
    state.selected = nil
  else
    local selected_is_visible = false
    for _, file in ipairs(state.visible) do
      if file.path == state.selected then
        selected_is_visible = true
        break
      end
    end
    if not selected_is_visible then state.selected = state.visible[1].path end
  end

  local row = selected_row()
  if not state.filtering and state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    vim.api.nvim_win_set_cursor(state.list_win, { row, 0 })
  end

  if state.selected ~= state.preview_path then
    state.preview_path = state.selected
    state.set_preview(state.selected)
  end
end

local function update_filter()
  if not state or state.closed or state.filter_update_pending then return end
  state.filter_update_pending = true
  vim.schedule(function()
    if not state or state.closed then return end
    state.filter_update_pending = false
    local line = vim.api.nvim_buf_get_lines(state.list_buf, 0, 1, false)[1] or ''
    state.query = line
    render_items()
    vim.bo[state.list_buf].modified = false
  end)
end

local function select_offset(offset)
  if not state or state.closed or #state.visible == 0 then return end
  local row = vim.api.nvim_win_get_cursor(state.list_win)[1]
  row = math.max(2, math.min(#state.visible + 1, row + offset))
  vim.api.nvim_win_set_cursor(state.list_win, { row, 0 })

  local file = state.visible[row - 1]
  if file.path ~= state.selected then
    state.selected = file.path
    state.preview_path = file.path
    state.set_preview(file.path)
  end
end

local function exit_filter()
  if not state or state.closed then return end
  state.filtering = false
  vim.cmd.stopinsert()
  vim.schedule(function()
    if not state or state.closed or not vim.api.nvim_win_is_valid(state.list_win) then return end
    vim.bo[state.list_buf].modifiable = false
    vim.bo[state.list_buf].modified = false
    vim.api.nvim_win_set_cursor(state.list_win, { selected_row(), 0 })
    vim.api.nvim_set_current_win(state.list_win)
    set_active_pane('list')
  end)
end

local function enter_filter()
  if not state or state.closed then return end
  state.filtering = true
  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_win_set_cursor(state.list_win, { 1, #state.query })
  vim.cmd 'startinsert'
end

local function escape_preview()
  if not state or state.closed then return end
  vim.cmd.stopinsert()
  vim.schedule(function()
    if not state or state.closed then return end
    if state.fullscreen then toggle_layout() end
    focus_list()
  end)
end

local function terminal_key(action)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true), 'n', false)
  vim.schedule(action)
end

local function install_preview_maps(buf)
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', '<Esc>', escape_preview, opts)
  vim.keymap.set('n', '<Tab>', toggle_layout, opts)
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('t', '<Esc>', function() terminal_key(escape_preview) end, opts)
  vim.keymap.set('t', '<Tab>', function() terminal_key(toggle_layout) end, opts)
  vim.keymap.set('t', 'q', function() terminal_key(close) end, opts)
end

local function show_preview_error(buf, path, exit_code)
  if not state or state.closed or state.preview_buf ~= buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'Tabiew could not open this file.',
    '',
    vim.fs.relpath(state.root, path) or path,
    ('Tabiew exited with status %d.'):format(exit_code),
    '',
    'Press Esc to return to the file list.',
  })
  vim.bo[buf].modifiable = false
end

local function set_preview(path)
  if not state or state.closed or not state.preview_win or not vim.api.nvim_win_is_valid(state.preview_win) then return end

  local previous = state.preview_buf
  local buf = vim.api.nvim_create_buf(false, true)
  state.preview_buf = buf
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_win_set_buf(state.preview_win, buf)
  discard_preview(previous)
  install_preview_maps(buf)

  if not path then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'No compatible files match this filter.' })
    vim.bo[buf].modifiable = false
    return
  end

  local result = vim.api.nvim_buf_call(buf, function()
    return vim.fn.termopen({ state.command, path }, {
      cwd = state.root,
      on_exit = function(_, exit_code)
        if exit_code ~= 0 then
          vim.schedule(function() show_preview_error(buf, path, exit_code) end)
        end
      end,
    })
  end)
  if result <= 0 then
    show_preview_error(buf, path, result)
    vim.notify(('Could not start Tabiew for %s.'):format(path), vim.log.levels.ERROR)
  end
end

close = function()
  if not state or state.closed then return end
  local closing = state
  closing.closed = true

  if closing.autocmd then pcall(vim.api.nvim_del_autocmd, closing.autocmd) end
  if closing.list_win and vim.api.nvim_win_is_valid(closing.list_win) then
    pcall(vim.api.nvim_win_close, closing.list_win, true)
  end
  if closing.preview_win and vim.api.nvim_win_is_valid(closing.preview_win) then
    pcall(vim.api.nvim_win_close, closing.preview_win, true)
  end
  discard_preview(closing.preview_buf)
  if vim.api.nvim_buf_is_valid(closing.list_buf) then
    pcall(vim.api.nvim_buf_delete, closing.list_buf, { force = true })
  end
  if closing.origin_win and vim.api.nvim_win_is_valid(closing.origin_win) then
    pcall(vim.api.nvim_set_current_win, closing.origin_win)
  end
  state = nil
end

local function recover_closed_window(win_id)
  if not state or state.closed then return end
  local closing = state
  closing.closed = true
  if closing.autocmd then pcall(vim.api.nvim_del_autocmd, closing.autocmd) end
  for _, win in ipairs { closing.list_win, closing.preview_win } do
    if win and win ~= win_id and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
  end
  discard_preview(closing.preview_buf)
  if vim.api.nvim_buf_is_valid(closing.list_buf) then
    pcall(vim.api.nvim_buf_delete, closing.list_buf, { force = true })
  end
  state = nil
  if closing.origin_win and vim.api.nvim_win_is_valid(closing.origin_win) then
    pcall(vim.api.nvim_set_current_win, closing.origin_win)
  end
end

focus_list = function()
  if not state or state.closed then return end
  if state.fullscreen then toggle_layout() end
  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    vim.api.nvim_set_current_win(state.list_win)
    set_active_pane('list')
  end
end

focus_preview = function()
  if not state or state.closed or not state.selected then return end
  vim.api.nvim_set_current_win(state.preview_win)
  set_active_pane('preview')
  vim.cmd 'startinsert'
end

toggle_layout = function()
  if not state or state.closed then return end
  if state.fullscreen then
    vim.api.nvim_win_set_config(state.preview_win, state.preview_config)
    state.fullscreen = false
    if not state.list_win or not vim.api.nvim_win_is_valid(state.list_win) then
      state.list_win = vim.api.nvim_open_win(state.list_buf, false, state.list_config)
    end
    focus_list()
  else
    local list_win = state.list_win
    state.list_config = vim.api.nvim_win_get_config(list_win)
    state.list_win = nil
    vim.api.nvim_win_close(list_win, true)
    vim.api.nvim_win_set_config(state.preview_win, state.full_preview_config)
    state.fullscreen = true
    vim.api.nvim_set_current_win(state.preview_win)
    set_active_pane('preview')
    vim.cmd 'startinsert'
  end
end

local function find_files(root)
  local files = {}
  for _, path in ipairs(vim.fn.globpath(root, '**/*', false, true)) do
    if supported_file(path) then files[#files + 1] = path end
  end
  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  return files
end

local function explorer_root()
  if vim.bo.filetype ~= 'NvimTree' then return nil end

  local ok, node = pcall(function() return require('nvim-tree.api').tree.get_node_under_cursor() end)
  if not ok or not node or not node.absolute_path then return nil end

  local stat = vim.uv.fs_stat(node.absolute_path)
  if stat and stat.type == 'directory' then return node.absolute_path end
  return vim.fs.dirname(node.absolute_path)
end

local function picker_root()
  return explorer_root() or vim.fn.getcwd()
end

local function configure_filter_buffer(buf)
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed_buf, _, first_line)
      if changed_buf == buf and first_line == 0 then update_filter() end
    end,
  })

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', 'j', function() select_offset(1) end, opts)
  vim.keymap.set('n', 'k', function() select_offset(-1) end, opts)
  vim.keymap.set('n', 'h', '<Nop>', opts)
  vim.keymap.set('n', 'l', '<Nop>', opts)
  vim.keymap.set('n', '/', enter_filter, opts)
  vim.keymap.set('n', '<CR>', focus_preview, opts)
  vim.keymap.set('n', '<Tab>', toggle_layout, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
  vim.keymap.set('n', 'q', close, opts)
  for _, key in ipairs { 'i', 'a', 'A', 'o', 'O', 'c', 's', 'R' } do
    vim.keymap.set('n', key, enter_filter, opts)
  end
  vim.keymap.set('i', '<Esc>', exit_filter, opts)
  vim.keymap.set('i', '<CR>', exit_filter, opts)
  vim.keymap.set('i', '<Down>', exit_filter, opts)
  vim.keymap.set('i', '<Up>', '<C-o>gg', opts)
end

function M.open()
  if state and not state.closed then
    if (state.list_win and vim.api.nvim_win_is_valid(state.list_win))
      or (state.preview_win and vim.api.nvim_win_is_valid(state.preview_win))
    then
      focus_list()
      return
    end
    close()
  end

  local command = vim.fn.executable 'tw' == 1 and 'tw' or 'tabiew'
  if vim.fn.executable(command) ~= 1 then
    vim.notify('Tabiew was not found (expected the `tw` or `tabiew` executable).', vim.log.levels.ERROR)
    return
  end

  local root = picker_root()
  local files = find_files(root)
  if #files == 0 then
    vim.notify('No Tabiew-compatible files found under ' .. root, vim.log.levels.INFO)
    return
  end

  vim.api.nvim_set_hl(0, 'TabiewActiveBorder', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'TabiewInactiveBorder', { fg = '#858b98' })
  vim.api.nvim_set_hl(0, 'TabiewFilterHint', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'TabiewSelectedLine', { link = 'Visual', default = true })

  local columns, lines = vim.o.columns, vim.o.lines
  local total_width = math.max(30, math.floor(columns * 0.9))
  local total_height = math.max(8, math.floor(lines * 0.8))
  local list_width = math.floor(total_width * 0.36)
  local preview_width = total_width - list_width - 1
  local row = math.max(0, math.floor((lines - total_height) / 2) - 1)
  local col = math.max(0, math.floor((columns - total_width) / 2))
  local list_config = {
    relative = 'editor',
    width = list_width,
    height = total_height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' enter select · j/k navigate · q quit ',
    title_pos = 'center',
  }
  local preview_config = {
    relative = 'editor',
    width = preview_width,
    height = total_height,
    row = row,
    col = col + list_width + 1,
    style = 'minimal',
    border = 'rounded',
    title = ' esc back to navigation · Tab toggle fullscreen ',
    title_pos = 'center',
  }
  local full_preview_config = vim.deepcopy(preview_config)
  full_preview_config.width = total_width
  full_preview_config.col = col

  local origin_win = vim.api.nvim_get_current_win()
  local list_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, { '' })
  vim.bo[list_buf].buftype = 'nofile'
  vim.bo[list_buf].bufhidden = 'hide'
  vim.bo[list_buf].modifiable = false
  local list_win = vim.api.nvim_open_win(list_buf, true, list_config)
  vim.wo[list_win].cursorline = true
  vim.wo[list_win].cursorlineopt = 'line'
  vim.wo[list_win].winhighlight = 'CursorLine:TabiewSelectedLine,Cursor:TabiewSelectedLine'
  local preview_buf = vim.api.nvim_create_buf(false, true)
  local preview_win = vim.api.nvim_open_win(preview_buf, false, preview_config)

  state = {
    active_pane = 'list',
    command = command,
    files = files,
    filter_update_pending = false,
    filtering = false,
    full_preview_config = full_preview_config,
    fullscreen = false,
    list_buf = list_buf,
    list_config = list_config,
    list_win = list_win,
    origin_win = origin_win,
    preview_buf = preview_buf,
    preview_config = preview_config,
    preview_path = nil,
    preview_win = preview_win,
    query = '',
    root = root,
    selected = files[1],
    set_preview = set_preview,
    visible = {},
  }

  configure_filter_buffer(list_buf)
  state.insert_guard = vim.api.nvim_create_autocmd('InsertCharPre', {
    buffer = list_buf,
    callback = function()
      if state and state.filtering and vim.api.nvim_get_current_win() == state.list_win then
        local cursor = vim.api.nvim_win_get_cursor(state.list_win)
        if cursor[1] ~= 1 then
          vim.api.nvim_win_set_cursor(state.list_win, { 1, #state.query })
        end
      end
    end,
  })
  state.autocmd = vim.api.nvim_create_autocmd('WinClosed', {
    callback = function(event)
      local closed_win = tonumber(event.match)
      if closed_win == state.list_win or closed_win == state.preview_win then
        recover_closed_window(closed_win)
      end
    end,
  })

  active_border(list_win, true)
  active_border(preview_win, false)
  render_items()
  vim.api.nvim_set_current_win(list_win)
  set_active_pane('list')
end

vim.keymap.set('n', '<leader>d', '<Nop>', { desc = '[D]ata' })
vim.keymap.set('n', '<leader>dd', M.open, { desc = 'Data files with Tabiew' })

return M
