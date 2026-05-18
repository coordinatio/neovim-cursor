-- Shared utility helpers for yapt.nvim plugin
--
-- Centralizes small helpers that several modules need (mostly buffer
-- discovery for "what should I show after I stole this window?" logic).
local M = {}

-- True for buffers that look like normal user-facing buffers
-- (listed, valid, and a regular file/empty buftype).
local function is_normal_listed_buffer(buf, exclude_buf)
  return buf ~= exclude_buf
    and vim.api.nvim_buf_is_valid(buf)
    and vim.fn.buflisted(buf) == 1
    and vim.bo[buf].buftype == ""
end

-- Find an existing listed file buffer (with a name) to display.
-- Returns nil if none exists.
-- Optional `should_skip(buf) -> bool` lets callers exclude certain buffers.
function M.find_file_buffer(exclude_buf, should_skip)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_normal_listed_buffer(buf, exclude_buf)
      and vim.api.nvim_buf_get_name(buf) ~= ""
      and (should_skip == nil or not should_skip(buf))
    then
      return buf
    end
  end
  return nil
end

-- Find an existing empty unnamed unmodified buffer suitable to display.
-- Returns nil if none exists.
function M.find_empty_unnamed_buffer(exclude_buf)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_normal_listed_buffer(buf, exclude_buf)
      and vim.api.nvim_buf_get_name(buf) == ""
      and not vim.bo[buf].modified then
      return buf
    end
  end
  return nil
end

-- Return the most recently used normal listed buffer, walking backwards
-- through the buffer MRU list.  Terminal buffers (buftype "terminal") are
-- always excluded by the `is_normal_listed_buffer` guard.
-- Optional `should_skip(buf) -> bool` lets callers exclude additional
-- buffers (e.g. prompt-file buffers).
function M.find_previous_buffer(exclude_buf, should_skip)
  local best = nil
  for _, info in ipairs(vim.fn.getbufinfo()) do
    local buf = info.bufnr
    if info.lastused > 0
      and is_normal_listed_buffer(buf, exclude_buf)
      and (should_skip == nil or not should_skip(buf))
      and (not best or info.lastused > best.lastused)
    then
      best = info
    end
  end
  return best and best.bufnr or nil
end

-- Find a buffer suitable for a window we're "giving back" to the user
-- (e.g. when leaving fullscreen or closing a transient prompt buffer).
--
-- Tries (in order):
--   1. the most recently used buffer (skipping terminals and, optionally,
--      anything `should_skip` rejects)
--   2. an existing real file buffer
--   3. an existing empty unnamed unmodified buffer
--   4. a freshly created listed buffer (last resort)
--
-- This avoids leaking new `[No Name]` buffers on every fullscreen exit
-- in workspaces where no other file is currently loaded.
function M.find_or_create_restore_buffer(exclude_buf, should_skip)
  local prev = M.find_previous_buffer(exclude_buf, should_skip)
  if prev then return prev end

  local found = M.find_file_buffer(exclude_buf, should_skip)
  if found then return found end

  local empty = M.find_empty_unnamed_buffer(exclude_buf)
  if empty then return empty end

  return vim.api.nvim_create_buf(true, false)
end

return M
