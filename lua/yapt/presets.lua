-- Preset prompt libraries for yapt.nvim
--
-- Reusable markdown files from:
-- - Global: Neovim config (stdpath("config")/yapt/prompts)
-- - Project: ${CWD}/.nvim-yapt/prompts
--
-- Selecting a preset clones it into a new prompt-history file so the
-- library file stays pristine. Telescope extra actions: send now, insert.
local history = require("yapt.history")
local util = require("yapt.util")

local M = {}

local function has_telescope()
  return pcall(require, "telescope")
end

local function trim_slash(path)
  return path:gsub("/$", "")
end

local function global_dir(config)
  local dir = config.prompts and config.prompts.dir
  if not dir or dir == "" then
    return nil
  end
  return trim_slash(dir)
end

local function project_dir(config)
  local dir = config.prompts and config.prompts.project_dir
  if not dir or dir == "" then
    return nil
  end
  dir = vim.fn.expand(dir)
  if vim.fn.isabsolutepath(dir) == 0 then
    dir = vim.fs.joinpath(vim.fn.getcwd(), dir)
  end
  return trim_slash(vim.fs.abspath(dir))
end

-- Unique picker label when `full` is not under `root` (symlink target
-- outside the library). Prefer a `..` form so two outside files with the
-- same basename stay distinct; fall back to the absolute path.
local function outside_display(root, full)
  root = vim.fs.normalize(vim.fs.abspath(root))
  full = vim.fs.normalize(vim.fs.abspath(full))
  local root_parts = vim.split(root, "/", { plain = true, trimempty = true })
  local full_parts = vim.split(full, "/", { plain = true, trimempty = true })
  local n = 0
  local limit = math.min(#root_parts, #full_parts)
  while n < limit and root_parts[n + 1] == full_parts[n + 1] do
    n = n + 1
  end
  if n == 0 then
    return full
  end
  local parts = {}
  for _ = n + 1, #root_parts do
    table.insert(parts, "..")
  end
  for i = n + 1, #full_parts do
    table.insert(parts, full_parts[i])
  end
  if #parts == 0 then
    return full
  end
  return table.concat(parts, "/")
end

local function relpath(root, full)
  local rel = vim.fs.relpath(root, full)
  if rel and rel ~= "" and rel ~= "." then
    return rel
  end
  if rel == "." then
    return vim.fn.fnamemodify(full, ":t")
  end
  return outside_display(root, full)
end

local function has_dot_component(rel)
  for part in rel:gmatch("[^/]+") do
    if part:match("^%.") then
      return true
    end
  end
  return false
end

-- Recursively list .md files under dir. Follows symlinks to regular files
-- and into symlink directories, but skips a directory whose device+inode
-- was already seen (so a cycle `prompts/loop -> prompts/` cannot hang).
-- Caps both files and directories visited so a link to a huge tree cannot
-- freeze the UI; either cap notifies. The inner scandir loop is also
-- bounded by the remaining file/dir budget (a single node_modules cannot
-- run unbounded). Hidden names (dot-prefixed files and directories) are
-- skipped, so a project_dir of "." does not walk .git.
-- Returns { { path, relpath }, ... }.
local function list_md_under(dir)
  if not dir or vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end

  local root = trim_slash(vim.fn.fnamemodify(dir, ":p"))
  local out = {}
  local visited = {}
  local max_files = 10000
  local max_dirs = 1000
  local dirs_seen = 0
  -- Scandir entries not enqueued as directories (md or not, hidden or
  -- not, plus overflow dirs once the dir cap is hit) so a huge
  -- node_modules still hits the file cap inside one scandir.
  local files_seen = 0
  local truncated = nil -- "files" | "directories"

  local function inode_key(path)
    -- Follow so a symlink to an already-walked directory is recognized.
    local st = vim.uv.fs_stat(path) or vim.uv.fs_lstat(path)
    if not st or st.dev == nil or st.ino == nil then
      return path
    end
    return tostring(st.dev) .. ":" .. tostring(st.ino)
  end

  local function add_md(full)
    -- Hidden-name filter is library-relative only. A `..` / absolute
    -- display for an outside symlink target can contain `.config` or `..`
    -- and must not be dropped (the walk already skipped `^%.` names).
    local under = vim.fs.relpath(root, full)
    if under and under ~= "" and under ~= "." and has_dot_component(under) then
      return
    end
    table.insert(out, { path = full, relpath = relpath(root, full) })
  end

  local stack = { root }
  while #stack > 0 do
    if #out >= max_files or files_seen >= max_files then
      truncated = "files"
      break
    end
    if dirs_seen >= max_dirs then
      truncated = "directories"
      break
    end
    local path = table.remove(stack)
    local key = inode_key(path)
    if not visited[key] then
      visited[key] = true
      dirs_seen = dirs_seen + 1
      local fd = vim.uv.fs_scandir(path)
      if fd then
        while true do
          -- Remaining file budget gates scandir_next (every non-enqueued
          -- name counts). Remaining dir slots only gate enqueue: do not
          -- break when dirs_left is 0, or subdirectory .md files are skipped.
          if #out >= max_files or files_seen >= max_files then
            truncated = "files"
            break
          end
          local dirs_left = max_dirs - dirs_seen - #stack
          local name, ftype = vim.uv.fs_scandir_next(fd)
          if not name then
            break
          end
          -- Hidden: skip the file and do not descend into the directory.
          -- Still counts toward the file cap so a huge hidden listing
          -- cannot run this loop unbounded.
          if name:match("^%.") then
            files_seen = files_seen + 1
          else
            local full = path .. "/" .. name
            if not ftype then
              local lst = vim.uv.fs_lstat(full)
              ftype = lst and lst.type
            end
            if ftype == "directory" then
              if dirs_left > 0 then
                table.insert(stack, full)
              else
                truncated = "directories"
                files_seen = files_seen + 1
              end
            elseif ftype == "link" then
              local st = vim.uv.fs_stat(full)
              if st and st.type == "directory" then
                if dirs_left > 0 then
                  table.insert(stack, full)
                else
                  truncated = "directories"
                  files_seen = files_seen + 1
                end
              else
                files_seen = files_seen + 1
                if st and st.type == "file" and name:match("%.md$") then
                  add_md(full)
                end
              end
            else
              files_seen = files_seen + 1
              if ftype == "file" and name:match("%.md$") then
                add_md(full)
              end
            end
          end
        end
      end
    end
  end

  if truncated then
    local limit = truncated == "files" and max_files or max_dirs
    util.notify(
      string.format("Preset scan truncated under %s (limit: %d %s)", root, limit, truncated),
      vim.log.levels.WARN
    )
  end
  return out
end

local function collect_from(dir, source, entries)
  if not dir then
    return
  end
  for _, f in ipairs(list_md_under(dir)) do
    table.insert(entries, {
      path = f.path,
      relpath = f.relpath,
      source = source,
    })
  end
end

-- List merged preset entries (project first, then global; alphabetical
-- within each source). Duplicate filenames in both libraries are two rows.
-- @return entries, searched_dirs
function M.list_presets(config)
  config = config or {}
  local entries = {}
  local searched = {}

  local proj = project_dir(config)
  local glob = global_dir(config)
  if proj then
    table.insert(searched, proj)
    collect_from(proj, "project", entries)
  end
  if glob then
    table.insert(searched, glob)
    collect_from(glob, "global", entries)
  end

  table.sort(entries, function(a, b)
    if a.source ~= b.source then
      return a.source == "project"
    end
    if a.relpath ~= b.relpath then
      return a.relpath < b.relpath
    end
    return a.path < b.path
  end)

  return entries, searched
end

local function read_preset_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    util.notify("Failed to read preset: " .. path, vim.log.levels.ERROR)
    return nil
  end
  return lines
end

local function clone_into_history(config, entry, loc, open_cmd, must_split)
  local lines = read_preset_lines(entry.path)
  if not lines then
    return nil
  end
  return history.create_prompt_file(config, {
    lines = lines,
    location = loc,
    open_cmd = open_cmd,
    must_split = must_split,
  })
end

local function send_preset(config, entry)
  local lines = read_preset_lines(entry.path)
  if not lines then
    return
  end
  if vim.trim(table.concat(lines, "\n")) == "" then
    util.notify("Preset is empty — nothing to send", vim.log.levels.WARN)
    return
  end
  local text = table.concat(lines, "\n")
  history.send_text_to_terminal(config, text, {
    success_message = "Sent preset prompt to terminal",
    on_success = function()
      local path = history.write_prompt_file(config, lines)
      if not path then
        -- Send already succeeded; write_prompt_file notified the archive
        -- failure. Keep the send success message (do not return false).
        return "but failed to save history"
      end
      return path
    end,
  })
end

-- Insert into the Source file buffer (not an mtw Reader/Float view).
-- loc/cursor/winid are captured when the picker opens. cursor is already
-- Source line/column — do not rematch against a view that may be gone.
-- @param winid integer|nil originating window (preferred for cursor restore)
local function insert_preset_at_cursor(entry, loc, cursor, winid)
  loc = loc or util.resolve_file_location()
  local source_buf = loc.source_bufnr
  local view_buf = loc.view_bufnr

  if not source_buf or not vim.api.nvim_buf_is_valid(source_buf) then
    util.notify("Cannot insert: original buffer is gone", vim.log.levels.WARN)
    return
  end
  if vim.bo[source_buf].buftype ~= "" then
    util.notify("Cannot insert into a non-file buffer", vim.log.levels.WARN)
    return
  end
  if not vim.bo[source_buf].modifiable then
    util.notify("Cannot insert: buffer is not modifiable", vim.log.levels.WARN)
    return
  end

  local lines = read_preset_lines(entry.path)
  if not lines then
    return
  end
  if vim.trim(table.concat(lines, "\n")) == "" then
    util.notify("Preset is empty — nothing to insert", vim.log.levels.WARN)
    return
  end

  local row, col
  if cursor then
    row, col = cursor[1], cursor[2]
  else
    local last = vim.api.nvim_buf_line_count(source_buf)
    local last_line = vim.api.nvim_buf_get_lines(source_buf, last - 1, last, false)[1] or ""
    row, col = last, #last_line
  end

  local last = vim.api.nvim_buf_line_count(source_buf)
  row = math.max(1, math.min(row, last))
  local line = vim.api.nvim_buf_get_lines(source_buf, row - 1, row, false)[1] or ""
  col = util.clamp_col_to_char_boundary(line, col)

  -- Insert into Source first while the view is still intact. Closing the
  -- Float / swapping Reader before set_text would leave no rollback if it fails.
  local ok, err = pcall(vim.api.nvim_buf_set_text, source_buf, row - 1, col, row - 1, col, lines)
  if not ok then
    util.notify("Failed to insert preset: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  -- Close an mtw Float like clone, then put Source in the originating window
  -- (e.g. Reader) so the insert is visible instead of happening off-screen.
  if view_buf then
    util.close_float_view_if_needed(view_buf)
  end

  local origin = winid
  if origin
    and util.win_in_current_tab(origin)
    and util.is_non_terminal_window(origin)
    and vim.api.nvim_win_get_buf(origin) ~= source_buf
  then
    pcall(vim.api.nvim_win_set_buf, origin, source_buf)
  end

  local last_line = lines[#lines] or ""
  local new_row, new_col
  if #lines == 1 then
    new_row = row
    new_col = col + #last_line
  else
    new_row = row + #lines - 1
    new_col = #last_line
  end

  local win
  if origin
    and util.win_in_current_tab(origin)
    and vim.api.nvim_win_get_buf(origin) == source_buf
  then
    win = origin
  else
    win = util.window_showing_buffer(source_buf)
  end
  if win then
    pcall(vim.api.nvim_set_current_win, win)
    pcall(vim.api.nvim_win_set_cursor, win, { new_row, new_col })
  end
end

local function notify_empty(searched)
  local paths = searched
  if not paths or #paths == 0 then
    paths = { "(no preset directories configured)" }
  end
  util.notify(
    "No preset prompts found. Add .md files to:\n  " .. table.concat(paths, "\n  "),
    vim.log.levels.WARN
  )
end

local function pick_with_telescope(config, entries, loc, cursor, winid, must_split)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  local entry_display = require("telescope.pickers.entry_display")

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 8 },
      { remaining = true },
    },
  })

  local preset_previewer = previewers.new_buffer_previewer({
    title = "Prompt preview",
    define_preview = function(self, entry, _status)
      local path = entry.value and entry.value.path
      if not path or path == "" then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "No file to preview" })
        return
      end
      previewers.buffer_previewer_maker(path, self.state.bufnr, { winid = self.state.winid })
      util.apply_wrap(self.state.winid)
    end,
  })

  local function selected_entry(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    actions.close(prompt_bufnr)
    return selection and selection.value or nil
  end

  pickers.new({}, {
    prompt_title = "Preset prompts (Enter: clone & open, C-s: send, C-y: insert)",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        -- Omit `path` so leftover Telescope actions (quickfix, etc.) cannot
        -- open/overwrite the library file via entry.path.
        return {
          value = entry,
          ordinal = entry.relpath .. " " .. entry.source,
          display = function(e)
            local item = e.value or entry
            return displayer({
              { item.source, "TelescopeResultsComment" },
              { item.relpath },
            })
          end,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    -- Empty prompt scores every row equally; default tiebreak is shorter
    -- ordinal, which would scramble the project-then-global sort.
    tiebreak = function()
      return false
    end,
    previewer = preset_previewer,
    attach_mappings = function(prompt_bufnr, map)
      -- Clone into a history file, never :edit entry.path (the library).
      -- open_cmd is a Telescope-style edit command for the clone ("new",
      -- "vnew", "tabedit"); nil uses the normal mount-window path. Split/tab
      -- go through the same hide-fullscreen / mount logic as Enter.
      -- must_split is the origin-window snapshot from picker-open, not
      -- the window current after Telescope closes.
      local function clone_selected(open_cmd)
        local entry = selected_entry(prompt_bufnr)
        if not entry then
          return
        end
        vim.schedule(function()
          clone_into_history(config, entry, loc, open_cmd, must_split)
        end)
      end

      actions.select_default:replace(function()
        clone_selected()
      end)
      actions.select_horizontal:replace(function()
        clone_selected("new")
      end)
      actions.select_vertical:replace(function()
        clone_selected("vnew")
      end)
      actions.select_tab:replace(function()
        clone_selected("tabedit")
      end)
      -- :drop would replace the current window (including a YAPT terminal).
      if actions.select_drop then
        actions.select_drop:replace(function()
          clone_selected()
        end)
      end
      if actions.select_tab_drop then
        actions.select_tab_drop:replace(function()
          clone_selected("tabedit")
        end)
      end

      -- <C-q> / <M-q> send to quickfix using entry.path; disable those too.
      for _, name in ipairs({
        "send_to_qflist",
        "add_to_qflist",
        "send_selected_to_qflist",
        "add_selected_to_qflist",
        "smart_send_to_qflist",
        "smart_add_to_qflist",
      }) do
        if actions[name] then
          actions[name]:replace(function() end)
        end
      end
      map("i", "<C-q>", actions.nop)
      map("n", "<C-q>", actions.nop)
      map("i", "<M-q>", actions.nop)
      map("n", "<M-q>", actions.nop)

      local function send_selected()
        local entry = selected_entry(prompt_bufnr)
        if not entry then
          return
        end
        vim.schedule(function()
          send_preset(config, entry)
        end)
      end

      local function insert_selected()
        local entry = selected_entry(prompt_bufnr)
        if not entry then
          return
        end
        vim.schedule(function()
          insert_preset_at_cursor(entry, loc, cursor, winid)
        end)
      end

      map("i", "<C-s>", send_selected)
      map("n", "<C-s>", send_selected)
      map("i", "<C-y>", insert_selected)
      map("n", "<C-y>", insert_selected)
      return true
    end,
  }):find()
end

local function pick_with_ui_select(config, entries, loc, must_split)
  local labels = {}
  for _, e in ipairs(entries) do
    table.insert(labels, e.relpath .. " (" .. e.source .. ")")
  end

  vim.ui.select(labels, {
    prompt = "Preset prompts:",
  }, function(item, idx)
    -- UI replacements may call on_choice(item) only; resolve from the
    -- chosen label and fall back to idx (default vim.ui.select).
    local entry
    if item ~= nil then
      for i, label in ipairs(labels) do
        if label == item then
          entry = entries[i]
          break
        end
      end
    end
    if not entry and idx then
      entry = entries[idx]
    end
    if entry then
      clone_into_history(config, entry, loc, nil, must_split)
    end
  end)
end

-- Open the preset-prompt picker. Telescope when available (Enter / C-s / C-y);
-- otherwise vim.ui.select with Enter-only.
function M.open_presets_picker(config)
  config = config or {}
  local entries, searched = M.list_presets(config)
  if #entries == 0 then
    notify_empty(searched)
    return
  end

  -- Capture Source (not mtw Reader/Float view) and the originating window
  -- before the picker takes over. Snapshot Source line/column while the
  -- view is still live: Telescope closing an mtw Float (or focus loss)
  -- can clear float_rendered, after which rematching uses the raw view
  -- line and lands at column 0 on the wrong Source line.
  -- Snapshot protected/fullscreen status from that same origin window:
  -- picker teardown can dismiss an mtw Float, after which Source looks
  -- like an in-place mount and Enter would replace the user's file.
  local loc = util.resolve_file_location()
  local winid = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local must_split = history.must_split_from_window(winid)
  local view_buf = loc.view_bufnr
  if view_buf and view_buf ~= loc.source_bufnr then
    local mapped = util.map_view_cursor_to_source(view_buf, winid)
    if mapped then
      cursor = { mapped.lnum, mapped.col }
    else
      cursor = { util.map_line_to_source(view_buf, cursor[1]) or cursor[1], 0 }
    end
  end

  if has_telescope() then
    pick_with_telescope(config, entries, loc, cursor, winid, must_split)
    return
  end

  pick_with_ui_select(config, entries, loc, must_split)
end

return M
