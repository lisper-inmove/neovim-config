-- ~/.config/nvim/lua/plugins/neotest-cpp.lua
-- 把自写的 C++/GoogleTest 适配器挂到 neotest 上（实现见 lua/neotest_cpp.lua）
--
-- 之前 <leader>tr 在 .cc 文件里总是 "No tests found"：neotest 只注册了
-- neotest-python，它对非 .py 文件直接返回 false（与光标行号无关）。
--
-- 挂上之后：
--   <leader>tr  跑光标所在用例（gtest 全名做 --gtest_filter，跑前先增量编译）
--   <leader>tt  跑整个文件、<leader>tT 跑全部、<leader>ts 摘要面板
--   <leader>td  用 codelldb 调试最近用例（codelldb 适配器见 debug.lua）
--   <leader>tp  对光标所在用例做 perf 采样（实现见 lua/perf_cpp.lua）
--   <leader>tP  从列表选择用例做 perf
--   <leader>to  看输出（编译错误也会出现在这里）
--
-- 二进制路径、构建命令这些「跟项目走」的值不在这个文件里，也不在
-- neotest_cpp.lua 里，而在**项目根目录的 .nvim.yaml**（见 lua/project_config.lua）。
-- 那个文件只需要一行 `target: <名字>`：Debug 构建目录由 CMake 配置（各构建目录里
-- CMakeCache.txt 的 CMAKE_BUILD_TYPE）自动找，二进制再按名字在里头找。
-- 优先级：项目 .nvim.yaml  >  下面 adapters 里传的 opts  >  内置默认（只有
-- auto_build / extensions；target 没有默认值，瞎猜一个只会在别的项目里报错的错）。
-- 注意：OpenCV 用例里有 cv::imshow + waitKey(0)，会开窗口并阻塞；
--       要在图像窗口里按任意键，测试才结束、neotest 才出结果。
return {
  {
    "nvim-neotest/neotest",
    optional = true,
    -- 只新增键位，不改动 LazyVim test extra 已有的 t 组键位。
    -- Lazy 启动时先注册 stub，按下时才加载 neotest 和 lua/perf_cpp.lua。
    keys = {
      {
        "<leader>tp",
        function()
          require("perf_cpp").profile_cursor()
        end,
        desc = "Perf 光标处 gtest 用例",
      },
      {
        "<leader>tP",
        function()
          require("perf_cpp").profile_picker()
        end,
        desc = "Perf 选择 gtest 用例",
      },
    },
    opts = {
      -- 空表 = 什么都不覆盖，一切按项目根的 .nvim.yaml（没有就按内置默认）。
      -- 想全局改（比如关掉自动编译）就写 ["neotest_cpp"] = { auto_build = false }；
      -- 注意 LazyVim 只在配置表非空时才调 adapter.setup()，所以空表等于不调用。
      adapters = {
        ["neotest_cpp"] = {},
      },
    },
  },
}
