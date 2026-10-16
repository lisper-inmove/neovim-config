-- ~/.config/nvim/lua/plugins/diagnostics.lua
--
-- 为什么长消息总看不全：Neovim 的两处"行内"提示都不能自动折行。
--   · virtual_text  —— 画在行尾，超出窗口右边界就被裁掉；
--   · virtual_lines —— 同样不能折行（:help virt_lines_overflow 只接受
--     "trunc"/"scroll"，没有 "wrap"），而 LazyVim 默认 wrap=false，
--     所以长行也只是被切短，最多能横向滚一下。
-- 唯一能完整显示的地方是浮窗：它按当前窗口宽度折行，并按折行后的高度开窗
-- （vim.lsp.util.open_floating_preview），多长的消息都放得下。
--
-- 于是分工：行内只留符号 + 下划线表示"这行有问题"，读全文交给浮窗，
-- 光标停在有问题的那行就自动弹出来 —— 见 lua/config/autocmds.lua。
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        -- 关掉会被截断的行内消息，避免只看到半句
        virtual_text = false,
        float = {
          -- 多个 LSP 都在报时标出来源，只有一个（比如只有 clangd）就不标
          source = "if_many",
        },
      },
    },
  },
}
