local M = {}

M.dap = {
  n = {
    -- 打断点
    ["<leader>db"] = {
      "<cmd> DapToggleBreakpoint <CR>",
      "Toggle breakpoint"
    },
    -- 开始debug
    ["<leader>dr"] = {
      "<cmd> RustDebuggables <CR>",
      "Start Debug"
    },
    -- 下一步
    ["<leader>di"] = {
      "<cmd> DapStepInto <CR>",
      "StepInto"
    },
    -- over
    ["<leader>dov"] = {
      "<cmd> DapStepOver <CR>",
      "StepOver"
    },
    -- out
    ["<leader>dou"] = {
      "<cmd> DapStepOut <CR>",
      "StepOut"
    },
    -- 打开面板
    ["<leader>dus"] = {
      function ()
        local widgets = require("dap.ui.widgets");
        local sidebar = widgets.sidebar(widgets.scopes);
        sidebar.open();
      end,
      "Open debug sidebar"
    }
  }
}

M.crates = {
  n = {
    ["<leader>rcu"] = {
      function ()
        require("crates").upgrade_all_crates()
      end,
      "update crates"
    }
  }
}

-- M.toggleterm = {
--   n = {
--     ["<leader>tt"] = {
--       "<cmd> ToggleTerm direction=float <CR>",
--       "toggle term"
--     },
-- 
--     ["<leader>tu"] = {
--       "<cmd> ToggleTerm direction=horizontal <CR>",
--       "toggle term"
--     }
--   }
-- }

return M
