-- 打印某个项目实际解析出来的配置。排查「路径不对 / 找不到二进制 / 配置改了没反应」
-- 时先跑这个，比在 nvim 里逐项猜快。
--
--   nvim --clean -l scripts/probe/show-config.lua
--   PROBE_PROJECT=/path/to/project nvim --clean -l scripts/probe/show-config.lua
--
-- 在真实会话里也可以直接：
--   :lua print(vim.inspect(require("project_config").resolve_for_buffer()))

local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helper.lua")
H.rtp()

local pc = require("project_config")
local root = pc.find_root(H.real_project) or H.real_project
local r = pc.resolve(root)

local config_path = root .. "/" .. pc.CONFIG_FILE
local fd = io.open(config_path, "r")
print(("=== %s ==="):format(config_path))
print(fd and fd:read("*a") or "(不存在)")
if fd then
  fd:close()
end

print("root       = " .. tostring(r.root))
print("target     = " .. tostring(r.target))
print("name       = " .. tostring(r.name))
print("build_dir  = " .. tostring(r.build_dir))
print("binary     = " .. tostring(r.binary))
print("  可执行    = " .. tostring(r.binary ~= nil and vim.fn.executable(r.binary) == 1))
print("build_args = " .. (r.build_args and table.concat(r.build_args, " ") or ""))
print("auto_build = " .. tostring(r.auto_build))
print("extensions = " .. vim.inspect(r.extensions))
print("problem    = " .. tostring(r.problem))
