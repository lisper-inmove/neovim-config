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

      -- 项目根目录（nvim 启动时 cwd 即项目根）
      local function project_root()
        return vim.fn.getcwd()
      end

      -- gtest 可执行文件路径：Debug 构建产物
      local function test_binary()
        return project_root() .. "/build-Debug/bin/LearnCPP_Test"
      end

      -- 找不到二进制时提示先构建
      local function ensure_binary()
        local bin = test_binary()
        if vim.fn.executable(bin) ~= 1 then
          vim.notify(
            ("找不到测试可执行文件：%s\n请先构建：cmake --build build-Debug -j"):format(bin),
            vim.log.levels.ERROR
          )
          return nil
        end
        return bin
      end

      -- 构造一次 gtest 调试配置。program/cwd 传函数，dap 启动时求值
      local function gtest_config(name, args)
        return {
          name = name,
          type = "codelldb",
          request = "launch",
          program = test_binary,
          args = args,
          cwd = project_root,
          stopOnEntry = false,
        }
      end

      -- 列出二进制里所有测试的全名（Suite.TestName），供选择
      local function list_tests()
        local bin = test_binary()
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
        require("dap").run(gtest_config("调试 LearnCPP_Test (" .. label .. ")", args))
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

      -- 便捷入口：<leader>dg 从测试列表中选择用例后启动调试
      local function debug_tests()
        if not ensure_binary() then
          return
        end
        local tests = list_tests()
        if #tests == 0 then
          vim.notify("未能从二进制列出测试，请先构建：cmake --build build-Debug -j", vim.log.levels.WARN)
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

      -- 供 nvim-dap 配置选择器使用（<leader>dg 走上面的专用入口，
      -- 这里主要给 :lua require("dap").continue() 无会话时的手动选择）
      dap.configurations.cpp = {
        gtest_config("调试 LearnCPP_Test (全部)", {}),
        gtest_config("调试 LearnCPP_Test (gtest_filter)", function()
          -- 注意 gtest 匹配规则：写全称 Tester.OpenCV_Hist_Match，或用通配 *Hist*
          return { "--gtest_filter=" .. vim.fn.input("gtest_filter (全称或含 * 通配，回车=全部): ", "*") }
        end),
      }

      vim.keymap.set("n", "<leader>dg", debug_tests, { desc = "Debug gtest (可选 filter)" })
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
