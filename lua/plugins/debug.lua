-- ~/.config/nvim/lua/plugins/debug.lua
return {
  -- 调试核心
  {
    "mfussenegger/nvim-dap",
    config = function()
      local dap = require("dap")
      -- dap.setup()
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
      ensure_installed = { "codelldb" },  -- 自动安装 codelldb
      automatic_installation = true,
    },
    -- Optional: Add config to ensure Mason DAP setup runs after nvim-dap
    config = function(_, opts)
      require("mason-nvim-dap").setup(opts)
    end,
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
