-- 够用就好的 YAML 子集解析器
--
-- 为什么自己写：本机完全没有 YAML 解析器可用——yq 没有、ruby 没有、
-- Python 的 PyYAML 没装（python3 -c "import yaml" 直接 ModuleNotFoundError）、
-- node 也没有 yaml 模块、lazy 目录下没有任何 yaml 插件。而 Neovim 自身
-- 不内置 YAML 解析。为了读一个两行的配置文件去装 apt 包或引入要编译的插件，
-- 代价比这 100 行还大。
--
-- 支持（够描述本项目配置的全部）：
--   key: value              扁平映射，无嵌套
--   # 注释 / 行尾注释 / 空行
--   "带引号" / '带引号' / 裸字符串
--   true / false / 整数 / 小数 / null(~)
--   key:\n  - a\n  - b       块列表（缩进有无都认）
--   key: [a, b]             行内列表
--
-- 不支持（碰到会明确报错，不猜）：
--   嵌套映射、锚点/别名、多行字符串(| >)、多文档(---)、流式映射({})
--   —— 这个 schema 用不到，写错了宁可报错也别静默解析成别的东西。

local M = {}

-- 去掉注释部分。只有 # 前面是行首或空白才算注释，
-- 所以 "a#b" 和引号里的 # 都原样保留。
---@param line string
---@return string
local function strip_comment(line)
  local in_single, in_double = false, false
  for i = 1, #line do
    local c = line:sub(i, i)
    if c == "'" and not in_double then
      in_single = not in_single
    elseif c == '"' and not in_single then
      in_double = not in_double
    elseif c == "#" and not in_single and not in_double then
      if i == 1 or line:sub(i - 1, i - 1):match("%s") then
        return line:sub(1, i - 1)
      end
    end
  end
  return line
end

-- 引号包裹时去引号；'' 是单引号里的转义，\" 是双引号里的
---@param v string
---@return string
local function unquote(v)
  if #v >= 2 and v:sub(1, 1) == '"' and v:sub(-1) == '"' then
    return (v:sub(2, -2):gsub('\\"', '"'))
  end
  return v
end

---@param v string
---@return boolean
local function is_quoted(v)
  return #v >= 2 and ((v:sub(1, 1) == '"' and v:sub(-1) == '"') or (v:sub(1, 1) == "'" and v:sub(-1) == "'"))
end

---@param v string
---@return string
local function strip_quotes(v)
  if v:sub(1, 1) == '"' then
    return unquote(v)
  end
  if is_quoted(v) then
    return (v:sub(2, -2):gsub("''", "'"))
  end
  return v
end

---@param item string 已 trim 的单项
---@return any
local function parse_item(item)
  local v = strip_quotes(item)
  if is_quoted(item) then
    return v
  end
  if v == "true" then
    return true
  end
  if v == "false" then
    return false
  end
  return tonumber(v) or v
end

-- 行内列表 [a, b, "c"]。返回 nil + 错误信息表示不是行内列表。
---@param v string
---@return table|nil, string|nil
local function parse_inline_list(v)
  local inner = v:sub(2, -2)
  local items = {}
  for piece in (inner .. ","):gmatch("(.-),") do
    local item = vim.trim(piece)
    if item ~= "" then
      items[#items + 1] = parse_item(item)
    end
  end
  return items
end

-- 单个值。返回 (值, 错误信息)。第二个返回值非 nil 表示这一行有问题。
---@param raw string 已去注释的 "key: " 之后的部分
---@param lineno integer
---@return any, string|nil
local function parse_value(raw, lineno)
  local v = vim.trim(raw)
  if v == "" then
    return nil, ("第 %d 行：冒号后面没有值。只支持扁平映射，不支持嵌套"):format(lineno)
  end
  if v:sub(1, 1) == "{" then
    return nil, ("第 %d 行：不支持流式映射 {}，请写成 key: value"):format(lineno)
  end
  if v:sub(1, 1) == "[" then
    if v:sub(-1) ~= "]" then
      return nil, ("第 %d 行：行内列表没有闭合的 ]"):format(lineno)
    end
    return parse_inline_list(v)
  end
  if v:sub(1, 1) == "|" or v:sub(1, 1) == ">" then
    return nil, ("第 %d 行：不支持多行字符串（| 或 >）"):format(lineno)
  end
  if is_quoted(v) then
    return strip_quotes(v)
  end
  if v == "null" or v == "~" then
    return vim.NIL -- 交给调用方当「没写」处理
  end
  if v == "true" then
    return true
  end
  if v == "false" then
    return false
  end
  return tonumber(v) or v
end

-- 解析整份文本。
---@param text string
---@return table|nil data, string|nil err
function M.parse(text)
  local data = {}
  local seen = {} -- 单独记「出现过哪些 key」：值为 null 的 key 不进 data，但重复仍要报错
  local lines = vim.split(text, "\n", { plain = true })
  local i = 1
  while i <= #lines do
    local lineno = i
    local line = vim.trim(strip_comment(lines[i]))
    i = i + 1

    if line ~= "" then -- 空行/纯注释直接跳过
      if line:sub(1, 1) == "-" then
        return nil, ("第 %d 行：列表项没有归属的 key（上一行应该是个空的 `key:`）"):format(lineno)
      end
      if line == "---" then
        return nil, ("第 %d 行：不支持多文档（---）"):format(lineno)
      end

      -- 只切第一个冒号，所以值里可以带冒号（Windows 盘符、URL 之类）
      local key, rest = line:match("^([%w_%-.]+)%s*:%s*(.*)$")
      if not key then
        return nil, ("第 %d 行看不懂，期望 `key: value`：%s"):format(lineno, line)
      end
      if seen[key] then
        return nil, ("第 %d 行：重复的 key `%s`"):format(lineno, key)
      end
      seen[key] = true

      if rest ~= "" then
        local value, err = parse_value(rest, lineno)
        if err then
          return nil, err
        end
        -- null 当作「没写这个键」，让调用方自然落到默认值上
        if value ~= vim.NIL then
          data[key] = value
        end
      else
        -- 值是空的：后面要么跟着块列表，要么就是写错了
        local items = {}
        while i <= #lines do
          local next_line = vim.trim(strip_comment(lines[i]))
          if next_line == "" then
            break
          end
          local item = next_line:match("^%-%s*(.*)$")
          if not item then
            break
          end
          if item == "" then
            return nil, ("第 %d 行：列表项是空的"):format(i)
          end
          items[#items + 1] = parse_item(item)
          i = i + 1
        end
        if #items == 0 then
          return nil,
            ("第 %d 行：`%s:` 后面没有值。只支持扁平映射，不支持嵌套"):format(lineno, key)
        end
        data[key] = items
      end
    end
  end
  return data
end

return M
