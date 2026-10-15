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
--   <leader>to  看输出（编译错误也会出现在这里）
-- 注意：OpenCV 用例里有 cv::imshow + waitKey(0)，会开窗口并阻塞；
--       要在图像窗口里按任意键，测试才结束、neotest 才出结果。
return {
  {
    "nvim-neotest/neotest",
    optional = true,
    opts = {
      -- 空表 = 用 lua/neotest_cpp.lua 的默认配置；
      -- 想改（比如关掉自动编译）就写 ["neotest_cpp"] = { auto_build = false }
      adapters = {
        ["neotest_cpp"] = {},
      },
    },
  },
}
