-- 使用 lazy.nvim 示例
return {
    'junegunn/fzf',
    dependencies = {
        'junegunn/fzf.vim',
    },
    -- 可选：让 fzf 安装其二进制文件
    build = './install --bin',
    config = function()
        -- 在这里可以设置 fzf 的快捷键等
    end
}
