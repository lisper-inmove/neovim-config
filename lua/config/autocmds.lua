-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- 光标在有诊断的行上停留（LazyVim 把 updatetime 设成了 200ms）时，自动弹出完整
-- 消息的浮窗：浮窗会按窗口宽度折行、并按折行后的高度开窗，所以 clang-tidy 那种
-- 上百字符的消息也能一次看全（行内提示做不到，见 lua/plugins/diagnostics.lua）。
-- 移动光标 / 进入插入模式 / 切走 buffer 时自动关掉。
vim.api.nvim_create_autocmd("CursorHold", {
  group = vim.api.nvim_create_augroup("user_diagnostic_float", { clear = true }),
  callback = function()
    -- 特殊 buffer（neo-tree、trouble、终端等）不弹
    if vim.bo.buftype ~= "" then
      return
    end
    local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
    if vim.tbl_isempty(vim.diagnostic.get(0, { lnum = lnum })) then
      return
    end
    vim.diagnostic.open_float({
      scope = "line",
      -- 浮窗默认 focusable=true，且同 focus_id 的浮窗已存在时 open_float 会把焦点
      -- 切进去。第一次 CursorHold 弹出浮窗后，按 Esc 会让 CursorHold 再次触发，
      -- 焦点就被送进浮窗。两个都关掉，保证永远不进入这个临时窗。
      focus = false,
      focusable = false,
      close_events = { "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave" },
    })
  end,
})
