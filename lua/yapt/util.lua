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
function M.find_file_buffer(exclude_buf)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_normal_listed_buffer(buf, exclude_buf)
      and vim.api.nvim_buf_get_name(buf) ~= "" then
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

-- Find a buffer suitable for a window we're "giving back" to the user
-- (e.g. when leaving fullscreen or closing a transient prompt buffer).
--
-- Tries (in order):
--   1. an existing real file buffer
--   2. an existing empty unnamed unmodified buffer
--   3. a freshly created listed buffer (last resort)
--
-- This avoids leaking new `[No Name]` buffers on every fullscreen exit
-- in workspaces where no other file is currently loaded.
function M.find_or_create_restore_buffer(exclude_buf)
  local found = M.find_file_buffer(exclude_buf)
  if found then return found end

  local empty = M.find_empty_unnamed_buffer(exclude_buf)
  if empty then return empty end

  return vim.api.nvim_create_buf(true, false)
end

return M
