-- 探针的公共设置。用 dofile 加载：
--   这些是脚本，不是插件模块，不该靠 runtimepath 的 require 去找。
--
-- 所有路径都从脚本自身位置推出来，所以仓库放在哪都能跑：
--   <repo>/scripts/probe/xxx.lua → <repo>
--
-- 真实 C++ 项目默认是 LearnCPP，想测别的项目用环境变量覆盖：
--   PROBE_PROJECT=/path/to/project nvim --clean -l ...

local H = {}

-- `nvim -l probe.lua` 传相对路径时 debug.getinfo 的 source 也是相对的，
-- 所以用 fnamemodify(":p") 转成绝对路径再推仓库根。
local source = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
H.probe_dir = vim.fs.dirname(source)
H.repo = vim.fs.dirname(vim.fs.dirname(H.probe_dir))
H.data = vim.fn.stdpath("data")
H.tmp = (vim.uv.os_tmpdir() or "/tmp") .. "/nvim-config-probe"
H.real_project = os.getenv("PROBE_PROJECT") or "/home/inmove/code/LearnCPP"

-- 把仓库和指定插件挂到 runtimepath 上。
-- 注意：nvim -l 下 package.path 不会跟着 rtp 变，但 require 走 Neovim
-- 自己的 loader，所以只加 rtp 就够了（见 docs/testing.md）。
---@param ... string 插件目录名（~/.local/share/nvim/lazy/ 下的子目录）
function H.rtp(...)
  vim.opt.rtp:append(H.repo)
  for _, name in ipairs({ ... }) do
    vim.opt.rtp:append(H.data .. "/lazy/" .. name)
  end
end

---@param path string
---@return string
function H.read(path)
  local fd = assert(io.open(path, "r"))
  local content = fd:read("*a")
  fd:close()
  return content
end

return H
