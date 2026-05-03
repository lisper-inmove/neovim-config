return {
    "Kurama622/llm.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
    },
    cmd = {
        "LLMSessionToggle",
        "LLMSelectedTextHandler",
        "LLMAppHandler",
        "LLMSessionClose",
    },
    keys = {
        { "<leader>ac", "<cmd>LLMSessionToggle<cr>", desc = "Toggle AI Chat" },
        { "<leader>ae", "<cmd>LLMSelectedTextHandler 请详细解释一下以下代码<cr>", desc = "Explain Selected Code", mode = {"v", "n"}},
        { "<leader>aq", "<cmd>LLMSessionClose<cr>", desc = "Close AI Chat" },
    	{ "<leader>ao", "<cmd>LLMSelectedTextHandler 请按照Google C++规范和C++17标准优化以下代码：<cr>", mode = { "v", "n" }, desc = "Optimize Code" },
        { "<leader>ah", "<cmd>LLMSelectedTextHandler 根据以下要求，生成代码段<cr>", desc = "Generate Code", mode = {"v"}},
    },
    config = function()
        -- 从环境变量获取 API Key
        local api_key = os.getenv("DEEPSEEK_API_KEY")
        
        if not api_key then
            vim.notify("DeepSeek API Key not found! Please set DEEPSEEK_API_KEY environment variable.", 
                vim.log.levels.ERROR)
            return
        end
        
        require("llm").setup({
            -- API 配置
            url = "https://api.deepseek.com/v1/chat/completions",
            api_type = "openai",
            api_key = api_key,
            model = "deepseek-chat",  -- 或 "deepseek-coder"
            
            -- 请求参数
            timeout = 60,
            max_tokens = 8192,
            temperature = 0.7,
            top_p = 0.95,
            frequency_penalty = 0,
            presence_penalty = 0,
            
            -- 界面配置
            ui = {
                chat_window = {
                    width = 0.8,
                    height = 0.7,
                    border = "rounded",
                },
                popup_position = "center",
            },
            
            -- 系统提示词（已按要求修改）
            system_prompt = [[
You are a C++ expert, proficient in the C++17 standard.
All code must strictly follow the Google C++ Style Guide.
When providing code examples or explanations, ensure they comply with these standards.
Focus on best practices, modern C++ features (C++17), and maintainable code structures.
]],
            
            -- 内置应用配置
            apps = {
                explain = {
                    prompt = "Please explain the following C++ code in detail:\n\n{{code}}",
                },
                optimize = {
                    prompt = "Please optimize the following C++ code following Google C++ Style Guide and C++17 standards:\n\n{{code}}",
                },
                test = {
                    prompt = "Please generate unit tests for the following C++ code:\n\n{{code}}",
                },
                doc = {
                    prompt = "Please generate documentation following Google C++ Style Guide for the following code:\n\n{{code}}",
                },
                translate = {
                    prompt = "Please translate the following text to English:\n\n{{text}}",
                },
            },
        })
    end,
}
