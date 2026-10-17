-- ~/.config/nvim/lua/plugins/debug.lua
return {
  -- 调试核心
  {
    "mfussenegger/nvim-dap",
    -- 被 mason-nvim-dap / nvim-dap-ui 依赖，先于它们加载，避免适配器被覆盖
    -- （mason-nvim-dap 只保留了同路径的 executable，不会覆盖下面的 codelldb 适配器）
    config = function()
      local dap = require("dap")

      -- codelldb：由 mason-nvim-dap 安装到 ~/.local/share/nvim/mason/bin/codelldb，
      -- 这里显式写全路径，不依赖 PATH
      dap.adapters.codelldb = {
        type = "server", -- codelldb 支持 DAP server 模式
        port = "${port}", -- 由 nvim-dap 分配随机端口
        executable = {
          command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
          args = { "--port", "${port}" },
        },
      }

      -- 当前文件所属项目的配置（目标名、二进制、构建命令）。
      -- 根从当前缓冲区文件向上找 .nvim.yaml / compile_commands.json / CMakeLists.txt，
      -- 用的就是 neotest 那边同一个 find_root——以前这里取 cwd、那边向上找，
      -- 在子目录里启动 nvim 时两边会对不上。
      -- 每次调用都重新解析，改了 .nvim.yaml 立刻生效（文件读取按 mtime 缓存）。
      local project_config = require("project_config")
      local function cfg()
        return project_config.resolve_for_buffer()
      end

      -- 拿不到二进制就别往下走。c.problem 里已经写好了「为什么没找到 + 下一步做什么」，
      -- 比这里再编一句有用（比如会列出找到的构建目录和各自的 CMAKE_BUILD_TYPE）
      local function ensure_binary()
        local c = cfg()
        if not c.binary or vim.fn.executable(c.binary) ~= 1 then
          local msg = c.problem or ("测试可执行文件不存在：%s"):format(tostring(c.binary))
          if c.build_hint ~= "" then
            msg = msg .. "\n构建命令：" .. c.build_hint
          end
          vim.notify(msg, vim.log.levels.ERROR)
          return nil
        end
        return c.binary
      end

      -- 构造一次 gtest 调试配置。
      -- program/cwd 在「按 <Space>tg 的那一刻」就取好，不传函数——dap 启动时
      -- 当前缓冲区可能已经换成别的（插件面板之类），传函数会让项目根跑偏。
      local function gtest_config(name, args)
        local c = cfg()
        return {
          name = name,
          type = "codelldb",
          request = "launch",
          program = c.binary,
          args = args,
          cwd = c.root,
          stopOnEntry = false,
        }
      end

      -- 列出二进制里所有测试的全名（Suite.TestName），供选择
      local function list_tests()
        local bin = cfg().binary
        local lines = vim.fn.systemlist({ bin, "--gtest_list_tests" })
        local tests, suite = {}, nil
        for _, line in ipairs(lines) do
          if line:match("^%S.*%.$") then
            suite = line:gsub("%.$", "") -- "Tester." → "Tester"
          elseif suite and line:match("^%s+%S") then
            tests[#tests + 1] = suite .. "." .. vim.trim(line)
          end
        end
        return tests
      end

      -- 按过滤器启动调试。gtest 过滤器语义：
      --   完整名精确匹配（Tester.OpenCV_Hist_Match）
      --   或含 * 的通配（*Hist* / Tester.* / *OpenCV*）
      -- 空过滤器 = 跑全部
      local function run_filtered(filter)
        local args, label = {}, "全部"
        if filter ~= nil and filter ~= "" then
          args = { "--gtest_filter=" .. filter }
          label = "gtest_filter=" .. filter
        end
        require("dap").run(gtest_config(("调试 %s (%s)"):format(cfg().name or "gtest", label), args))
      end

      -- 手动输入过滤器（选择器里的兜底项）
      local function prompt_filter()
        vim.ui.input({ prompt = "gtest_filter (如 *Hist* 或 Tester.OpenCV_Hist_Match; 留空=全部): " }, function(input)
          if input == nil then
            return -- 取消
          end
          run_filtered(input)
        end)
      end

      -- 便捷入口：<leader>tg 从测试列表中选择用例后启动调试
      local function debug_tests()
        if not ensure_binary() then
          return
        end
        local tests = list_tests()
        if #tests == 0 then
          vim.notify(
            ("未能从二进制列出测试，请先构建：%s"):format(cfg().build_hint),
            vim.log.levels.WARN
          )
          return
        end
        table.insert(tests, 1, "▶ 运行全部测试")
        table.insert(tests, 2, "⌨ 手动输入过滤器…")
        vim.ui.select(tests, { prompt = "选择要调试的测试:" }, function(choice)
          if choice == nil then
            return -- 取消
          end
          if choice == "▶ 运行全部测试" then
            run_filtered("")
          elseif choice == "⌨ 手动输入过滤器…" then
            prompt_filter()
          else
            run_filtered(choice)
          end
        end)
      end

      -- 供 nvim-dap 配置选择器使用（<leader>tg 走上面的专用入口，
      -- 这里主要给 :lua require("dap").continue() 无会话时的手动选择）。
      -- config.name 只能是字符串（dap 不支持函数），而这张表在插件加载时就固定了，
      -- 所以进 cpp 文件时重建一次——否则在 A 项目里启动会顶着 B 项目的名字。
      local function refresh_cpp_configs()
        local c = cfg()
        -- 二进制都定位不到（没写 target、没配置过 CMake…）就挂空表：
        -- nvim-dap 会老老实实说「没有可用配置」，比塞一条 program=nil 的坏配置报错清楚。
        -- 详细原因走 <leader>tg，那里会把 c.problem 完整通知出来。
        if not c.binary then
          dap.configurations.cpp = {}
          return
        end
        local name = c.name or "gtest"
        dap.configurations.cpp = {
          gtest_config(("调试 %s (全部)"):format(name), {}),
          gtest_config(("调试 %s (gtest_filter)"):format(name), function()
            -- 注意 gtest 匹配规则：写全称 Tester.OpenCV_Hist_Match，或用通配 *Hist*
            return { "--gtest_filter=" .. vim.fn.input("gtest_filter (全称或含 * 通配，回车=全部): ", "*") }
          end),
        }
      end
      refresh_cpp_configs()
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "cpp",
        callback = refresh_cpp_configs,
        desc = "按当前项目刷新 gtest 调试配置名",
      })

      -- 归在 t 组：这是"调试测试"动作，与 <leader>td 调试 pytest 属于同一语义
      vim.keymap.set("n", "<leader>tg", debug_tests, { desc = "Debug gtest (可选 filter)" })
    end,
    keys = {
      { "<leader>dB", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
      { "<leader>dc", function() require("dap").continue() end, desc = "Continue" },
      { "<leader>di", function() require("dap").step_into() end, desc = "Step Into" },
      { "<leader>do", function() require("dap").step_out() end, desc = "Step Out" },
      { "<leader>dn", function() require("dap").step_over() end, desc = "Step Over" },
      { "<leader>dt", function() require("dapui").toggle() end, desc = "Toggle DAP UI" },
    },
  },

  -- Mason 自动安装调试适配器
  {
    "jay-babu/mason-nvim-dap.nvim",
    dependencies = {
      "mason-org/mason.nvim",
      "mfussenegger/nvim-dap",
    },
    opts = {
      ensure_installed = { "codelldb" }, -- 自动安装 codelldb
      automatic_installation = true,
    },
  },

  -- 调试 UI 界面
  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "nvim-neotest/nvim-nio" },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup()
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end
    end,
  },
}
