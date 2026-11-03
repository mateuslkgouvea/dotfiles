local M = {}

local state
local close, focus_list, focus_query, focus_preview, toggle_layout, render_selection

local function sql_file(path)
  return path:match('%.([^./]+)$') and path:match('%.([^./]+)$'):lower() == 'sql'
end

local function explorer_root()
  if vim.bo.filetype ~= 'NvimTree' then return nil end

  local ok, node = pcall(function() return require('nvim-tree.api').tree.get_node_under_cursor() end)
  if not ok or not node or not node.absolute_path then return nil end

  local stat = vim.uv.fs_stat(node.absolute_path)
  if stat and stat.type == 'directory' then return node.absolute_path end
  return vim.fs.dirname(node.absolute_path)
end

local function query_files(root, current_path)
  local files, seen = {}, {}
  for _, pattern in ipairs { '*.sql', '**/*.sql' } do
    for _, path in ipairs(vim.fn.globpath(root, pattern, false, true)) do
      path = vim.fs.normalize(path)
      if not seen[path] then
        seen[path] = true
        files[#files + 1] = path
      end
    end
  end

  if current_path and sql_file(current_path) then
    current_path = vim.fs.normalize(current_path)
    if not seen[current_path] then files[#files + 1] = current_path end
  end

  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  return files
end

local function query_text(path)
  local buf = vim.fn.bufnr(path)
  local query
  if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
    query = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  else
    local file, err = io.open(path, 'rb')
    if not file then return nil, err end
    local read_error
    query, read_error = file:read('*a')
    file:close()
    if not query then return nil, read_error end
  end
  query = query:gsub('\r\n', '\n'):gsub('\n+$', '')
  return query
end

local function cache_path(query, project)
  local hash = vim.fn.sha256(project .. '\0' .. query)
  return hash, state.cache_dir .. '/' .. hash .. '.csv'
end

local function make_entries()
  local entries = {}
  for _, path in ipairs(state.files) do
    local query, query_error = query_text(path)
    local hash, result_path, cached
    if query then
      hash, result_path = cache_path(query, state.project or 'bq-default')
      local stat = vim.uv.fs_stat(result_path)
      cached = stat ~= nil and stat.type == 'file'
    end
    entries[#entries + 1] = {
      path = path,
      query = query,
      query_error = query_error,
      hash = hash,
      result_path = result_path,
      cached = cached,
      fetching = hash ~= nil and state.fetching[hash] == true,
    }
  end
  return entries
end

local function selected_entry()
  if not state or not state.selected then return nil end
  for _, entry in ipairs(state.entries) do
    if entry.path == state.selected then return entry end
  end
end

local function set_active(pane)
  if not state or state.closed then return end
  state.active_pane = pane
  local windows = {
    list = state.list_win,
    query = state.query_win,
    preview = state.preview_win,
  }
  local active = windows[pane]
  if active and vim.api.nvim_win_is_valid(active) then
    local highlights = 'FloatBorder:DiagnosticInfo'
    if pane == 'list' then highlights = highlights .. ',CursorLine:TabiewSelectedLine,Cursor:TabiewSelectedLine' end
    vim.wo[active].winhighlight = highlights
  end
  for other_pane, win in pairs(windows) do
    if other_pane ~= pane and win and vim.api.nvim_win_is_valid(win) then
      vim.wo[win].winhighlight = 'FloatBorder:FloatBorder'
    end
  end
end

local function discard_preview(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local job = vim.b[buf].terminal_job_id
  if job then vim.fn.jobstop(job) end
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

local function terminal_key(action)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true), 'n', false)
  vim.schedule(action)
end

local function install_preview_maps(buf)
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', '<Esc>', focus_list, opts)
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', 'e', function() M.edit_selected() end, opts)
  vim.keymap.set('n', '<Tab>', toggle_layout, opts)
  vim.keymap.set('t', '<Esc>', function() terminal_key(focus_list) end, opts)
  vim.keymap.set('t', 'q', function() terminal_key(close) end, opts)
  vim.keymap.set('t', '<Tab>', function() terminal_key(toggle_layout) end, opts)
end

local function render_query(entry)
  if not state or not vim.api.nvim_buf_is_valid(state.query_buf) then return end
  local lines
  if not entry then
    lines = { 'No .sql files found in this directory.' }
  elseif entry.query_error then
    lines = { 'Could not read SQL file:', entry.query_error }
  else
    lines = vim.split(entry.query, '\n', { plain = true })
  end

  vim.bo[state.query_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.query_buf, 0, -1, false, lines)
  vim.bo[state.query_buf].modifiable = false
  vim.bo[state.query_buf].modified = false
  if state.query_win and vim.api.nvim_win_is_valid(state.query_win) then
    vim.api.nvim_win_set_cursor(state.query_win, { 1, 0 })
  end
end

local function render_separator()
  if not state or not vim.api.nvim_buf_is_valid(state.separator_buf) then return end
  local width = state.preview_config.width
  local label = ' Query preview  ·  Tabiew results '
  local remaining = math.max(0, width - vim.fn.strdisplaywidth(label))
  local left = string.rep('─', math.floor(remaining / 2))
  local right = string.rep('─', remaining - #left)
  vim.bo[state.separator_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.separator_buf, 0, -1, false, { left .. label .. right })
  vim.bo[state.separator_buf].modifiable = false
end

local function show_message(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function clean_tabiew_stderr(stderr)
  stderr = stderr:gsub('\27%[[%d;]*m', '')
  stderr = stderr:gsub(
    '%[W%]%s*"Config::global_config%(%)"%s*|%s*No config file was loaded, a config with default values will be used%.?',
    ''
  )
  return vim.trim(stderr)
end

local function open_tabiew(buf, entry)
  local stderr_path = vim.fn.tempname()
  local command = {
    '/bin/sh',
    '-c',
    'exec "$1" "$2" 2>"$3"',
    'tabiew',
    state.tw,
    entry.result_path,
    stderr_path,
  }
  local job = vim.api.nvim_buf_call(buf, function()
    return vim.fn.termopen(command, {
      cwd = state.root,
      on_exit = function(_, exit_code)
        vim.schedule(function()
          local stderr = ''
          if vim.fn.filereadable(stderr_path) == 1 then
            stderr = table.concat(vim.fn.readfile(stderr_path), '\n')
            vim.fn.delete(stderr_path)
          end
          stderr = clean_tabiew_stderr(stderr)
          if stderr ~= '' then
            vim.notify('Tabiew reported:\n' .. stderr, vim.log.levels.WARN)
          elseif exit_code ~= 0 then
            vim.notify(('Tabiew exited with status %d.'):format(exit_code), vim.log.levels.ERROR)
          end
        end)
      end,
    })
  end)

  if job <= 0 then
    vim.fn.delete(stderr_path)
    show_message(buf, { 'Could not start Tabiew for the cached BigQuery result.' })
    vim.notify('Could not start Tabiew for the cached BigQuery result.', vim.log.levels.ERROR)
  end
end

render_selection = function()
  if not state or state.closed or not state.preview_win or not vim.api.nvim_win_is_valid(state.preview_win) then return end

  local previous = state.preview_buf
  local buf = vim.api.nvim_create_buf(false, true)
  state.preview_buf = buf
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_win_set_buf(state.preview_win, buf)
  discard_preview(previous)
  install_preview_maps(buf)

  local entry = selected_entry()
  render_query(entry)
  render_separator()
  if not entry then
    show_message(buf, { 'No .sql files found in this directory.' })
    return
  end
  if entry.query_error then
    show_message(buf, { 'Could not read this SQL file:', '', entry.query_error })
    return
  end
  if entry.query == '' then
    show_message(buf, { 'The selected SQL file is empty.' })
    return
  end
  if entry.cached then
    open_tabiew(buf, entry)
    return
  end

  show_message(buf, {
    'No cached result for this query.',
    '',
    'Query hash: ' .. entry.hash,
    'Press f to fetch, or r to run it fresh.',
  })
end

local function render_list()
  if not state or state.closed then return end
  state.entries = make_entries()

  local lines = { 'j/k navigate · Enter result · p query · e edit · f fetch · r refresh · Tab fullscreen' }
  for _, entry in ipairs(state.entries) do
    local relative = vim.fs.relpath(state.root, entry.path) or entry.path
    local status = entry.fetching and '…' or (entry.cached and '✓' or '○')
    local hash = entry.hash and entry.hash:sub(1, 8) or 'unreadable'
    lines[#lines + 1] = ('%s %s · %s'):format(status, relative, hash)
  end
  if #state.entries == 0 then lines[#lines + 1] = 'No .sql files found' end

  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
  vim.bo[state.list_buf].modifiable = false
  vim.bo[state.list_buf].modified = false

  local row = 2
  for index, entry in ipairs(state.entries) do
    if entry.path == state.selected then
      row = index + 1
      break
    end
  end
  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    vim.api.nvim_win_set_cursor(state.list_win, { row, 0 })
  end
end

local function select_offset(offset)
  if not state or state.closed or #state.entries == 0 then return end
  local row = vim.api.nvim_win_get_cursor(state.list_win)[1]
  row = math.max(2, math.min(#state.entries + 1, row + offset))
  vim.api.nvim_win_set_cursor(state.list_win, { row, 0 })
  local entry = state.entries[row - 1]
  if entry and entry.path ~= state.selected then
    state.selected = entry.path
    render_selection()
  end
end

local function editing_window(origin_win)
  if not origin_win or not vim.api.nvim_win_is_valid(origin_win) then return nil end
  if vim.bo[vim.api.nvim_win_get_buf(origin_win)].filetype ~= 'NvimTree' then return origin_win end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local config = vim.api.nvim_win_get_config(win)
    if win ~= origin_win and config.relative == ''
      and vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= 'NvimTree'
    then
      return win
    end
  end
end

function M.edit_selected()
  if not state or state.closed then return end
  local entry = selected_entry()
  if not entry then
    vim.notify('Select a .sql file before opening it.', vim.log.levels.WARN)
    return
  end

  local path = entry.path
  local target_win = state.edit_win
  close()
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  else
    vim.cmd.tabnew()
  end

  local ok, err = pcall(vim.api.nvim_cmd, { cmd = 'edit', args = { path } }, {})
  if not ok then
    vim.notify(('Could not open %s: %s'):format(path, err), vim.log.levels.ERROR)
  end
end

local function write_cache(path, output)
  local temp_path = ('%s.tmp-%d-%d'):format(path, vim.uv.os_getpid(), vim.uv.hrtime())
  local fd, open_error = vim.uv.fs_open(temp_path, 'w', 384)
  if not fd then return nil, open_error end

  local bytes, write_error = vim.uv.fs_write(fd, output, -1)
  local _, close_error = vim.uv.fs_close(fd)
  if not bytes or bytes ~= #output then
    vim.uv.fs_unlink(temp_path)
    return nil, write_error or close_error or 'incomplete write'
  end

  local renamed, rename_error = vim.uv.fs_rename(temp_path, path)
  if not renamed then
    vim.uv.fs_unlink(temp_path)
    return nil, rename_error
  end
  return true
end

local function fetch_selected(fresh)
  if not state or state.closed then return end
  local entry = selected_entry()
  if not entry then
    vim.notify('Select a .sql file before fetching a result.', vim.log.levels.WARN)
    return
  end
  if entry.query_error then
    vim.notify(('Could not read %s: %s'):format(entry.path, entry.query_error), vim.log.levels.ERROR)
    return
  end
  if entry.query == '' then
    vim.notify('The selected SQL file is empty.', vim.log.levels.WARN)
    return
  end
  if entry.fetching then
    vim.notify('This query is already running.', vim.log.levels.INFO)
    return
  end
  if entry.cached and not fresh then
    vim.notify('A cached result is already available; press r to refresh it.', vim.log.levels.INFO)
    return
  end
  if vim.fn.executable 'bq' ~= 1 then
    vim.notify('BigQuery CLI `bq` was not found in PATH.', vim.log.levels.ERROR)
    return
  end

  local mkdir_result = vim.fn.mkdir(state.cache_dir, 'p', 448)
  if mkdir_result == 0 and vim.fn.isdirectory(state.cache_dir) ~= 1 then
    vim.notify('Could not create BigQuery cache directory: ' .. state.cache_dir, vim.log.levels.ERROR)
    return
  end

  local command = { 'bq' }
  if state.project then command[#command + 1] = '--project_id=' .. state.project end
  command[#command + 1] = '--quiet'
  command[#command + 1] = '--format=csv'
  command[#command + 1] = 'query'
  command[#command + 1] = '--use_legacy_sql=false'
  if fresh then command[#command + 1] = '--nouse_cache' end

  state.fetching[entry.hash] = true
  render_list()
  if state.selected == entry.path and not entry.cached then
    show_message(state.preview_buf, { 'Running BigQuery query...', '', vim.fs.relpath(state.root, entry.path) or entry.path })
  end

  local query, result_path = entry.query, entry.result_path
  local current_state = state
  local ok, process = pcall(vim.system, command, { stdin = query, text = true }, function(result)
    vim.schedule(function()
      local saved, save_error
      if result.code == 0 then
        saved, save_error = write_cache(result_path, result.stdout or '')
      end

      if state == current_state and not state.closed then
        state.fetching[entry.hash] = nil
        if result.code ~= 0 then
          local stderr = vim.trim(result.stderr or '')
          local stdout = vim.trim(result.stdout or '')
          local status = ('bq exited with status %s%s'):format(
            result.code or 'unknown',
            result.signal and result.signal ~= 0 and (' (signal ' .. result.signal .. ')') or ''
          )
          local details = {
            status,
            'Command: ' .. table.concat(command, ' '),
            stderr,
            stdout,
          }
          local detail = table.concat(vim.tbl_filter(function(text) return text ~= '' end, details), '\n')
          vim.notify('BigQuery query failed:\n' .. detail, vim.log.levels.ERROR)
          if state.selected == entry.path and not entry.cached then
            local lines = { 'BigQuery query failed.', '' }
            vim.list_extend(lines, vim.split(detail, '\n', { plain = true }))
            show_message(state.preview_buf, lines)
          end
        elseif not saved then
          vim.notify('Could not cache BigQuery results: ' .. tostring(save_error), vim.log.levels.ERROR)
        else
          vim.notify(fresh and 'BigQuery query refreshed.' or 'BigQuery query fetched and cached.', vim.log.levels.INFO)
        end
        render_list()
        local selected = selected_entry()
        if saved and selected and selected.hash == entry.hash then render_selection() end
      elseif result.code == 0 and not saved then
        vim.notify('Could not cache BigQuery results: ' .. tostring(save_error), vim.log.levels.ERROR)
      end
    end)
  end)

  if not ok then
    state.fetching[entry.hash] = nil
    render_list()
    vim.notify('Could not start bq: ' .. tostring(process), vim.log.levels.ERROR)
  end
end

local function resolve_project()
  for _, name in ipairs { 'CLOUDSDK_CORE_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'GCLOUD_PROJECT' } do
    local project = vim.env[name]
    if project and project ~= '' then return project end
  end
  if vim.fn.executable 'gcloud' ~= 1 then return nil end

  local result = vim.system({ 'gcloud', 'config', 'get-value', 'project', '--quiet' }, { text = true }):wait()
  if result.code ~= 0 then return nil end
  local project = vim.trim(result.stdout or '')
  if project == '' or project == '(unset)' then return nil end
  return project
end

local function configure_list(buf)
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', 'j', function() select_offset(1) end, opts)
  vim.keymap.set('n', 'k', function() select_offset(-1) end, opts)
  vim.keymap.set('n', '<Down>', function() select_offset(1) end, opts)
  vim.keymap.set('n', '<Up>', function() select_offset(-1) end, opts)
  vim.keymap.set('n', '<CR>', focus_preview, opts)
  vim.keymap.set('n', 'p', focus_query, opts)
  vim.keymap.set('n', 'e', M.edit_selected, opts)
  vim.keymap.set('n', 'f', function() fetch_selected(false) end, opts)
  vim.keymap.set('n', 'r', function() fetch_selected(true) end, opts)
  vim.keymap.set('n', '<Tab>', toggle_layout, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
  vim.keymap.set('n', 'q', close, opts)
end

close = function()
  if not state or state.closed then return end
  local closing = state
  closing.closed = true
  if closing.autocmd then pcall(vim.api.nvim_del_autocmd, closing.autocmd) end
  for _, win in pairs { closing.list_win, closing.query_win, closing.separator_win, closing.preview_win } do
    if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
  end
  discard_preview(closing.preview_buf)
  for _, buf in pairs { closing.query_buf, closing.separator_buf } do
    if buf and vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
  end
  if vim.api.nvim_buf_is_valid(closing.list_buf) then
    pcall(vim.api.nvim_buf_delete, closing.list_buf, { force = true })
  end
  if closing.origin_win and vim.api.nvim_win_is_valid(closing.origin_win) then
    pcall(vim.api.nvim_set_current_win, closing.origin_win)
  end
  state = nil
end

focus_query = function()
  if not state or state.closed or not state.query_win or not vim.api.nvim_win_is_valid(state.query_win) then return end
  vim.api.nvim_set_current_win(state.query_win)
  set_active('query')
end

focus_list = function()
  if not state or state.closed or not state.list_win or not vim.api.nvim_win_is_valid(state.list_win) then return end
  vim.api.nvim_set_current_win(state.list_win)
  set_active('list')
end

focus_preview = function()
  if not state or state.closed or not state.preview_win or not vim.api.nvim_win_is_valid(state.preview_win) then return end
  vim.api.nvim_set_current_win(state.preview_win)
  set_active('preview')
  if vim.b[state.preview_buf].terminal_job_id then vim.cmd 'startinsert' end
end

toggle_layout = function()
  if not state or state.closed then return end

  if not state.fullscreen then
    state.restore_pane = state.active_pane or 'list'
    if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
      state.list_cursor = vim.api.nvim_win_get_cursor(state.list_win)
    end
    state.fullscreen = true
    for _, win in pairs { state.list_win, state.query_win, state.separator_win } do
      if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end
    state.list_win = nil
    state.query_win = nil
    state.separator_win = nil
    vim.api.nvim_win_set_config(state.preview_win, state.full_preview_config)
    vim.api.nvim_set_current_win(state.preview_win)
    set_active('preview')
    if vim.b[state.preview_buf].terminal_job_id then vim.cmd 'startinsert' end
    return
  end

  state.fullscreen = false
  vim.api.nvim_win_set_config(state.preview_win, state.preview_config)
  state.list_win = vim.api.nvim_open_win(state.list_buf, false, state.list_config)
  vim.wo[state.list_win].cursorline = true
  state.query_win = vim.api.nvim_open_win(state.query_buf, false, state.query_config)
  vim.wo[state.query_win].wrap = true
  state.separator_win = vim.api.nvim_open_win(state.separator_buf, false, state.separator_config)
  vim.wo[state.separator_win].winhighlight = 'Normal:Comment'
  vim.api.nvim_win_set_cursor(state.list_win, state.list_cursor or { 1, 0 })

  local pane = state.restore_pane or 'list'
  if pane == 'list' then
    vim.api.nvim_set_current_win(state.list_win)
    set_active('list')
  elseif pane == 'query' then
    vim.api.nvim_set_current_win(state.query_win)
    set_active('query')
  else
    vim.api.nvim_set_current_win(state.preview_win)
    set_active('preview')
    if vim.b[state.preview_buf].terminal_job_id then vim.cmd 'startinsert' end
  end
end

function M.open()
  if state and not state.closed then
    focus_list()
    return
  end

  local cache_dir = vim.env.BQ_RESULTS_DIR
  if not cache_dir or cache_dir == '' then
    vim.notify('Set BQ_RESULTS_DIR in your shell before opening the BigQuery explorer.', vim.log.levels.ERROR)
    return
  end
  local tw = vim.fn.executable 'tw' == 1 and 'tw' or 'tabiew'
  if vim.fn.executable(tw) ~= 1 then
    vim.notify('Tabiew was not found (expected the `tw` or `tabiew` executable).', vim.log.levels.ERROR)
    return
  end

  local current_path = vim.api.nvim_buf_get_name(0)
  local root = explorer_root() or vim.fn.getcwd()
  cache_dir = vim.fn.fnamemodify(vim.fn.expand(cache_dir), ':p')
  local project = resolve_project()
  if not project then
    vim.notify('No active Google Cloud project detected; results will use the bq default project.', vim.log.levels.WARN)
  end

  local files = query_files(root, current_path ~= '' and current_path or nil)
  local selected = current_path ~= '' and vim.fs.normalize(current_path) or files[1]
  local found = false
  for _, path in ipairs(files) do
    if path == selected then found = true; break end
  end
  if not found then selected = files[1] end

  local columns, lines = vim.o.columns, vim.o.lines
  local total_width = math.max(30, math.floor(columns * 0.9))
  local total_height = math.max(8, math.floor(lines * 0.8))
  local list_width = math.floor(total_width * 0.4)
  local preview_width = total_width - list_width - 1
  local query_height = math.min(total_height - 4, math.max(4, math.floor(total_height * 0.45)))
  local result_height = total_height - query_height - 1
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
    title = ' BigQuery SQL · f fetch · r refresh · Tab fullscreen · q quit ',
    title_pos = 'center',
  }
  local preview_config = {
    relative = 'editor',
    width = preview_width,
    height = result_height,
    row = row + query_height + 1,
    col = col + list_width + 1,
    style = 'minimal',
    border = 'rounded',
    title = ' Result · Enter interact · e edit · Tab fullscreen ',
    title_pos = 'center',
  }
  local query_config = {
    relative = 'editor',
    width = preview_width,
    height = query_height,
    row = row,
    col = col + list_width + 1,
    style = 'minimal',
    border = 'rounded',
    title = ' Query · scroll · e edit · Tab fullscreen ',
    title_pos = 'center',
  }
  local separator_config = {
    relative = 'editor',
    width = preview_width,
    height = 1,
    row = row + query_height,
    col = col + list_width + 1,
    style = 'minimal',
    border = 'none',
    zindex = 51,
  }
  local full_preview_config = vim.deepcopy(preview_config)
  full_preview_config.width = math.max(1, columns - 4)
  full_preview_config.height = math.max(1, lines - 6)
  full_preview_config.row = 1
  full_preview_config.col = 1

  local origin_win = vim.api.nvim_get_current_win()
  local list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[list_buf].buftype = 'nofile'
  vim.bo[list_buf].bufhidden = 'hide'
  vim.bo[list_buf].modifiable = false
  local list_win = vim.api.nvim_open_win(list_buf, true, list_config)
  vim.wo[list_win].cursorline = true
  vim.wo[list_win].winhighlight = 'CursorLine:TabiewSelectedLine,Cursor:TabiewSelectedLine'
  local query_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[query_buf].buftype = 'nofile'
  vim.bo[query_buf].bufhidden = 'hide'
  vim.bo[query_buf].filetype = 'sql'
  vim.bo[query_buf].swapfile = false
  local query_win = vim.api.nvim_open_win(query_buf, false, query_config)
  vim.wo[query_win].wrap = true
  local separator_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[separator_buf].buftype = 'nofile'
  vim.bo[separator_buf].bufhidden = 'hide'
  vim.bo[separator_buf].modifiable = false
  local separator_win = vim.api.nvim_open_win(separator_buf, false, separator_config)
  vim.wo[separator_win].winhighlight = 'Normal:Comment'
  local preview_buf = vim.api.nvim_create_buf(false, true)
  local preview_win = vim.api.nvim_open_win(preview_buf, false, preview_config)

  state = {
    cache_dir = cache_dir,
    entries = {},
    fetching = {},
    files = files,
    list_buf = list_buf,
    list_win = list_win,
    origin_win = origin_win,
    preview_buf = preview_buf,
    preview_win = preview_win,
    query_buf = query_buf,
    query_win = query_win,
    separator_buf = separator_buf,
    separator_win = separator_win,
    list_config = list_config,
    query_config = query_config,
    separator_config = separator_config,
    preview_config = preview_config,
    full_preview_config = full_preview_config,
    edit_win = editing_window(origin_win),
    project = project,
    root = root,
    selected = selected,
    tw = tw,
  }

  vim.api.nvim_set_hl(0, 'TabiewSelectedLine', { link = 'Visual', default = true })
  configure_list(list_buf)
  local query_opts = { buffer = query_buf, nowait = true, silent = true }
  vim.keymap.set('n', '<Esc>', focus_list, query_opts)
  vim.keymap.set('n', 'q', close, query_opts)
  vim.keymap.set('n', 'e', M.edit_selected, query_opts)
  vim.keymap.set('n', '<Tab>', toggle_layout, query_opts)
  state.autocmd = vim.api.nvim_create_autocmd('WinClosed', {
    callback = function(event)
      local win = tonumber(event.match)
      if state and not state.closed and not state.fullscreen
        and (win == state.list_win or win == state.query_win or win == state.separator_win or win == state.preview_win)
      then
        vim.schedule(close)
      end
    end,
  })
  render_list()
  render_selection()
  vim.api.nvim_set_current_win(list_win)
  set_active('list')
end

vim.keymap.set('n', '<leader>db', M.open, { desc = 'BigQuery SQL explorer' })

return M
