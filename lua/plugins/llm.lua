-- DeepSeek via llm.nvim (https://github.com/Kurama622/llm.nvim).
-- Set DEEPSEEK_API_KEY in your shell environment.
return {
  "Kurama622/llm.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
  cmd = {
    "LLMSessionToggle",
    "LLMSelectedTextHandler",
  },
  keys = {
    { "<leader>ac", "<cmd>LLMSessionToggle<cr>", desc = "Toggle AI Chat" },
    -- LLMSelectedTextHandler only makes sense on a selection,
    -- so these are visual mode only. <esc> closes a chat session.
    {
      "<leader>ae",
      "<cmd>LLMSelectedTextHandler 请详细解释一下以下代码<cr>",
      mode = "x",
      desc = "Explain Selected Code",
    },
    {
      "<leader>ao",
      "<cmd>LLMSelectedTextHandler 请按照Google C++规范和C++17标准优化以下代码：<cr>",
      mode = "x",
      desc = "Optimize Code",
    },
    {
      "<leader>ah",
      "<cmd>LLMSelectedTextHandler 根据以下要求，生成代码段<cr>",
      mode = "x",
      desc = "Generate Code",
    },
  },
  config = function()
    if not vim.env.DEEPSEEK_API_KEY then
      vim.notify(
        "DEEPSEEK_API_KEY is not set. llm.nvim requests will fail.",
        vim.log.levels.WARN
      )
    end

    require("llm").setup({
      -- API
      url = "https://api.deepseek.com/v1/chat/completions",
      api_type = "deepseek",
      model = "deepseek-chat",
      fetch_key = function()
        return vim.env.DEEPSEEK_API_KEY
      end,

      -- Request parameters
      timeout = 60,
      max_tokens = 8192,
      temperature = 0.7,
      top_p = 0.95,

      -- Chat window (was: width 0.8, height 0.7)
      chat_ui_opts = {
        size = {
          width = "80%",
          height = "70%",
        },
      },

      -- System prompt (the `prompt` key is sent as the system message)
      prompt = [[
You are a C++ expert, proficient in the C++17 standard.
All code must strictly follow the Google C++ Style Guide.
When providing code examples or explanations, ensure they comply with these standards.
Focus on best practices, modern C++ features (C++17), and maintainable code structures.
]],
    })
  end,
}
