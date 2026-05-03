return {
    "nomnivore/ollama.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",   -- ollama.nvim 依赖的必需工具库
        -- 可选：提供更好的选择器UI，比如模糊搜索。如果没有，会回退到默认的输入框
        "stevearc/dressing.nvim",
    },
    cmd = { "Ollama", "OllamaModel", "OllamaServe", "OllamaServeStop" },
    keys = {
        -- 普通模式和可视模式下的快捷键，<leader> 通常为 \ 键
        { "<leader>op", "<cmd>Ollama<cr>", desc = "打开 Ollama 提示菜单" },
        { "<leader>om", "<cmd>OllamaModel<cr>", desc = "切换 Ollama 模型" },
        -- 直接触发一个名为 'Generate_Code' 的预设提示
        { "<leader>oc", "<cmd>lua require('ollama').prompt('Generate_Code')<cr>", desc = "生成代码" },
    },
    config = function()
        require("ollama").setup({
            -- Ollama 服务的地址和端口，默认是本地 11434
            url = "http://127.0.0.1:11434",
            -- 默认使用的模型，请确保已经通过 `ollama pull <模型名>` 下载
            model = "codegemma:7b-instruct",
            -- 可选：配置 Ollama 服务的启动与停止命令
            serve = {
                on_start = false,   -- 是否在 Neovim 启动时自动开启 Ollama 服务
                command = "ollama",
                args = { "serve" },
                stop_command = "pkill",
                stop_args = { "-SIGTERM", "ollama" },
            },
            -- 配置自定义的 Prompt
            prompts = {
                -- 一个用来生成代码的 Prompt，在提示菜单中会显示为 "Generate Code"
                Generate_Code = {
                    prompt = "请根据以下需求生成代码:\n$input",
                    input_label = "请输入代码需求: ",
                    action = "display",   -- 在浮动窗口中显示结果
                    options = {
                        temperature = 0.2, -- 控制生成文本的随机性，值越低结果越确定
                        top_k = 40,
                        top_p = 0.9,
                    },
                },
                -- 一个用来解释代码的 Prompt，在提示菜单中会显示为 "Explain Code"
                Explain_Code = {
                    prompt = "请详细解释以下代码:\n```$ftype\n$sel\n```",
                    input_label = "是否有补充说明? ",
                    action = "display",   -- 在浮动窗口中显示结果
                },
                -- 一个用来优化/重构代码的 Prompt，在提示菜单中会显示为 "Refactor Code"
                Refactor_Code = {
                    prompt = "请重构以下代码，使其更高效、更清晰:\n```$ftype\n$sel\n```",
                    action = "display_replace", -- 显示结果，并替换选中的代码
                },
            },
        })
    end,
}
