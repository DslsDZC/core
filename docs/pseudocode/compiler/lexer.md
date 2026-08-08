# lexer.cr 伪代码
> 源文件：src/compiler/lexer.cr（393 行）
> 功能概要：将 Core 语言源码字符串切分为词法单元（Token）序列。逐字符扫描源码，识别标识符、关键字、数字字面量（含进制前缀与类型后缀）、字符串字面量（含转义与插值跳过）、字符字面量、单字符运算符、多字符复合运算符、注释（行注释与块注释），跳过空白字符，记录行号列号，最终追加文件结束标记。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 分词 | tokenize | 分词（tokenize） |
| 查关键字表 | lookup_keyword | 查关键字表（lookup_keyword） |
| 跳过空白 | skip_ws | 跳过空白（skip_ws） |
| 当前字符 | cur_char | 当前字符（cur_char） |
| 预读字符 | peek | 预读字符（peek） |
| 当前字符（指定偏移） | cur_char_at | 当前字符（指定偏移）（cur_char_at） |
| 预读字符（指定偏移） | peek_at | 预读字符（指定偏移）（peek_at） |
| 判断数字 | is_digit | 判断数字（is_digit） |
| 判断字母 | is_alpha | 判断字母（is_alpha） |
| 判断标识符字符 | is_ident_char | 判断标识符字符（is_ident_char） |
| 添加错误 | add_error | 添加错误（add_error） |
| 添加词法单元 | add_tok | 添加词法单元（add_tok） |
| 添加整数词法单元 | add_tok_int | 添加整数词法单元（add_tok_int） |
| 添加字符串词法单元 | add_tok_str | 添加字符串词法单元（add_tok_str） |
| 源码字符串 | g_source | （全局） |
| 源码长度 | g_source_len | （全局） |
| 字符位置 | g_pos | （全局） |
| 行号 | g_line | （全局） |
| 列号 | g_col | （全局） |
| 词法单元数组 | g_tokens | （全局） |
| 词法单元计数 | g_token_count | （全局） |
| 错误数组 | g_errors | （全局） |
| 错误计数 | g_error_count | （全局） |
| 字符常量：空格 | C_SP | （全局常量） |
| 字符常量：水平制表 | C_TB | （全局常量） |
| 字符常量：换行 | C_LF | （全局常量） |
| 字符常量：回车 | C_CR | （全局常量） |
| 字符常量：换行（归一化） | C_NL | （全局常量） |
| 字符常量：左斜杠 | C_SLASH | （全局常量） |
| 字符常量：星号 | C_STAR | （全局常量） |
| 字符常量：反斜杠 | C_BSLASH | （全局常量） |
| 字符常量：单引号 | C_SQUOTE | （全局常量） |
| 字符常量：双引号 | C_DQUOTE | （全局常量） |
| 源位置 | _pos | 分词（tokenize） |
| 源码长度（局部） | _slen | 分词（tokenize） |
| 起始行 | start_line | 分词（tokenize） |
| 起始列 | start_col | 分词（tokenize） |
| 词素索引 | ident | 分词（tokenize） |
| 数字字符串 | num_str | 分词（tokenize） |
| 后缀 | suffix | 分词（tokenize） |
| 字符串值 | str_val | 分词（tokenize） |
| 当前字符值 | c, cc, c0, c2, esc, esc2 等 | 各函数 |

## 全局状态

- **源码字符串（g_source）**：待分词的源码完整文本；由外部调用者在调用分词前设置（可变）。
- **源码长度（g_source_len）**：分词结束时写入 `str_len(g_source)` 的缓存值（可变）。
- **字符位置（g_pos）**：当前词法单元已处理到的字符索引；跳过空白后更新为该位置（可变）。
- **行号（g_line）**：当前行号，从 1 开始计数；每遇换行递增，重置列号为 1（可变）。
- **列号（g_col）**：当前列号，从 1 开始计数；每遇非换行字符递增（可变）。
- **词法单元数组（g_tokens）**：扁平字节数组，每个词法单元占 ESZ_TOKEN 字节；由 grow_tokens 动态扩展。
- **词法单元计数（g_token_count）**：已产生的词法单元总数（索引）。
- **错误数组（g_errors）**：扁平字节数组，每个错误占 8 字节（驻留字符串索引）。
- **错误计数（g_error_count）**：已收集的错误总数（索引）。

## 函数 判断数字（is_digit）
### 作用
判断给定 ASCII 字符码是否属于十进制数字范围（'0'~'9'，对应码值 48~57）。返回 1（真）或 0（假）；不产生副作用，也不依赖全局状态。
### 逻辑
```
函数 is_digit(字符码 c) -> 整数
    如果 c 不小于等于 48 且 c 不大于等于 57，那么：
        返回 1
    返回 0
```
### 测试要点
1. 输入 48（'0'）应返回 1；输入 57（'9'）应返回 1
2. 输入 47（'/'）应返回 0；输入 58（':'）应返回 0
3. 输入 0、-1、255 等边界值应返回 0

## 函数 判断字母（is_alpha）
### 作用
判断给定 ASCII 字符码是否属于标识符首字符合法集：大写字母（65~90）、小写字母（97~122）、下划线（95）。返回 1 或 0。
### 逻辑
```
函数 is_alpha(字符码 c) -> 整数
    如果 (c 不小于等于 65 且 c 不大于等于 90) 或 (c 不小于等于 97 且 c 不大于等于 122) 或 c 等于 95，那么：
        返回 1
    返回 0
```
### 测试要点
1. 大写字母 'A'（65）、'Z'（90）返回 1
2. 小写字母 'a'（97）、'z'（122）返回 1
3. 下划线 '_'（95）返回 1
4. 数字 '0'（48）返回 0；符号 '+'（43）返回 0

## 函数 判断标识符字符（is_ident_char）
### 作用
判断给定 ASCII 字符码是否为标识符后续字符（首字符之后可出现的字符）：即字母（含下划线）或数字。
### 逻辑
```
函数 is_ident_char(字符码 c) -> 整数
    如果 is_alpha(c) 不等于 0 或 is_digit(c) 不等于 0，那么：
        返回 1
    返回 0
```
### 测试要点
1. 字母 'a' 返回 1；数字 '5' 返回 1；下划线 '_' 返回 1
2. 空格 ' ' 返回 0；运算符 '+' 返回 0

## 函数 添加错误（add_error）
### 作用
将一条错误消息（字符串）记录到全局错误数组。消息经字符串驻留后以 8 字节整数索引存入，错误计数递增。
### 逻辑
```
函数 add_error(消息 msg)
    令 消息索引 = 字符串驻留（str_intern）(msg)
    扩展错误数组（grow_errors）(g_error_count + 1)
    写 64 位（w64）(g_errors, g_error_count * 8, 消息索引)
    g_error_count = g_error_count + 1
```
### 测试要点
1. 调用后 g_error_count 正确递增 1
2. 空字符串消息正常驻留并记录
3. 多次调用后错误数组按序排列

## 函数 当前字符（cur_char）
### 作用
返回源码字符串 g_source 在当前位置 g_pos 处的字节（ASCII 码值）。若已超出源码末尾则返回 0（EOF）。内部使用 `str_len(g_source)` 而非 g_source_len 来绕过自举 ELF 后端的全局变量修补 bug。
### 逻辑
```
函数 cur_char() -> 整数
    令 src_len = 字符串长度（str_len）(g_source)
    如果 g_pos 不小于等于 src_len，那么：
        返回 0
    返回 按字节读取（load8）(g_source, g_pos)
```
### 测试要点
1. 初始位置 g_pos=0 且源码非空时返回首字符码值
2. g_pos 等于源码长度时返回 0（EOF）
3. g_pos 超过源码长度时返回 0

## 函数 预读字符（peek）
### 作用
返回 g_pos+1 位置的下一字符码值，不移动 g_pos。用于探测复合运算符、注释起止等向前看一个字符的场景。
### 逻辑
```
函数 peek() -> 整数
    令 src_len = 字符串长度（str_len）(g_source)
    如果 g_pos + 1 不小于等于 src_len，那么：
        返回 0
    返回 按字节读取（load8）(g_source, g_pos + 1)
```
### 测试要点
1. g_pos+1 在源码范围内时返回下一字符
2. g_pos 在倒数第一位时返回 0（EOF）

## 函数 当前字符（指定偏移）（cur_char_at）
### 作用
从指定字符串 src 的位置 pos 读取一个字节，若 pos >= max_len 则返回 0。用于分词循环内不依赖 g_pos 的局部字符访问。
### 逻辑
```
函数 cur_char_at(源码 src, 位置 pos, 最大长度 max_len) -> 整数
    如果 pos 不小于等于 max_len，那么：
        返回 0
    返回 按字节读取（load8）(src, pos)
```
### 测试要点
1. pos 在有效范围返回正确字符
2. pos 等于 max_len 返回 0；pos 大于 max_len 返回 0

## 函数 预读字符（指定偏移）（peek_at）
### 作用
从指定字符串 src 的位置 pos+1 读取一个字节，若 pos+1 >= max_len 则返回 0。用于分词循环内不依赖 g_pos 的局部向前看。
### 逻辑
```
函数 peek_at(源码 src, 位置 pos, 最大长度 max_len) -> 整数
    如果 pos + 1 不小于等于 max_len，那么：
        返回 0
    返回 按字节读取（load8）(src, pos + 1)
```
### 测试要点
1. pos+1 在有效范围返回正确字符
2. pos+1 等于或超出 max_len 返回 0

## 函数 查关键字表（lookup_keyword）
### 作用
将标识符字符串与所有 Core 语言保留关键字逐一比较，匹配则返回对应的词法单元类别标记（T_FN、T_MUT 等），无一匹配则返回 T_IDENT（普通标识符）。
### 逻辑
```
函数 lookup_keyword(字符串 s) -> 整数
    如果 s 等于 "fn"，那么：返回 T_FN
    如果 s 等于 "mut"，那么：返回 T_MUT
    如果 s 等于 "return"，那么：返回 T_RETURN
    如果 s 等于 "if"，那么：返回 T_IF
    如果 s 等于 "else"，那么：返回 T_ELSE
    如果 s 等于 "loop"，那么：返回 T_LOOP
    如果 s 等于 "while"，那么：返回 T_WHILE
    如果 s 等于 "for"，那么：返回 T_FOR
    如果 s 等于 "break"，那么：返回 T_BREAK
    如果 s 等于 "continue"，那么：返回 T_CONTINUE
    如果 s 等于 "true"，那么：返回 T_TRUE
    如果 s 等于 "false"，那么：返回 T_FALSE
    如果 s 等于 "struct"，那么：返回 T_STRUCT
    如果 s 等于 "enum"，那么：返回 T_ENUM
    如果 s 等于 "extern"，那么：返回 T_EXTERN
    如果 s 等于 "impl"，那么：返回 T_IMPL
    如果 s 等于 "match"，那么：返回 T_MATCH
    如果 s 等于 "import"，那么：返回 T_IMPORT
    如果 s 等于 "pub"，那么：返回 T_PUB
    如果 s 等于 "go"，那么：返回 T_GO
    如果 s 等于 "await"，那么：返回 T_AWAIT
    如果 s 等于 "unsafe"，那么：返回 T_UNSAFE
    如果 s 等于 "flow"，那么：返回 T_FLOW
    如果 s 等于 "yield"，那么：返回 T_YIELD
    如果 s 等于 "interface"，那么：返回 T_INTERFACE
    如果 s 等于 "type"，那么：返回 T_TYPE
    如果 s 等于 "mod"，那么：返回 T_MOD
    如果 s 等于 "as"，那么：返回 T_AS
    如果 s 等于 "auto"，那么：返回 T_AUTO
    如果 s 等于 "fileid"，那么：返回 T_FILEID
    如果 s 等于 "move"，那么：返回 T_MOVE
    如果 s 等于 "in"，那么：返回 T_IN
    如果 s 等于 "None"，那么：返回 T_NONE
    如果 s 等于 "Some"，那么：返回 T_SOME
    如果 s 等于 "unit"，那么：返回 T_UNIT
    返回 T_IDENT
```
### 测试要点
1. 输入 "fn" 返回 T_FN；输入 "hello" 返回 T_IDENT
2. 输入 ""（空串）返回 T_IDENT（不等于任何关键字）
3. 所有 35 个关键字逐一匹配正确

## 函数 添加词法单元（add_tok）
### 作用
向全局词法单元数组追加一个无词素/整数值的词法单元（如运算符、分隔符、关键字、EOF）。写入类别、词素（-1）、整数值（0）、行号、列号，计数递增。
### 逻辑
```
函数 add_tok(类别 kind, 词素 lex, 起始行 start_line, 起始列 start_col)
    扩展词法单元数组（grow_tokens）(g_token_count + 1)
    令 偏移 = g_token_count * ESZ_TOKEN
    写 64 位（g_tokens, 偏移 + OFF_TK_KIND, kind)
    写 64 位（g_tokens, 偏移 + OFF_TK_LEXEME, lex)
    写 64 位（g_tokens, 偏移 + OFF_TK_INTVAL, 0)
    写 64 位（g_tokens, 偏移 + OFF_TK_LINE, start_line)
    写 64 位（g_tokens, 偏移 + OFF_TK_COL, start_col)
    g_token_count = g_token_count + 1
```
### 测试要点
1. 调用后 g_token_count 递增 1
2. 写入各字段可正确读出
3. 词素传 -1 正确写入

## 函数 添加整数词法单元（add_tok_int）
### 作用
向全局词法单元数组追加一个含整数值的词法单元（数字字面量）。词素设为 -1（无字符串词素），整数字段写入解析后的数值。
### 逻辑
```
函数 add_tok_int(类别 kind, 整数值 ival, 起始行 start_line, 起始列 start_col)
    扩展词法单元数组（grow_tokens）(g_token_count + 1)
    令 偏移 = g_token_count * ESZ_TOKEN
    写 64 位（g_tokens, 偏移 + OFF_TK_KIND, kind)
    写 64 位（g_tokens, 偏移 + OFF_TK_LEXEME, -1)
    写 64 位（g_tokens, 偏移 + OFF_TK_INTVAL, ival)
    写 64 位（g_tokens, 偏移 + OFF_TK_LINE, start_line)
    写 64 位（g_tokens, 偏移 + OFF_TK_COL, start_col)
    g_token_count = g_token_count + 1
```
### 测试要点
1. ival=42 时整数字段写入 42
2. 词素字段为 -1
3. 行号列号正确记录

## 函数 添加字符串词法单元（add_tok_str）
### 作用
向全局词法单元数组追加一个含字符串词素的词法单元（标识符、字符串字面量、字符字面量）。字符串经驻留后以索引存储。
### 逻辑
```
函数 add_tok_str(类别 kind, 字符串 s, 起始行 start_line, 起始列 start_col)
    扩展词法单元数组（grow_tokens）(g_token_count + 1)
    令 偏移 = g_token_count * ESZ_TOKEN
    写 64 位（g_tokens, 偏移 + OFF_TK_KIND, kind)
    令 字符串索引 = 字符串驻留（str_intern）(s)
    写 64 位（g_tokens, 偏移 + OFF_TK_LEXEME, 字符串索引)
    写 64 位（g_tokens, 偏移 + OFF_TK_INTVAL, 0)
    写 64 位（g_tokens, 偏移 + OFF_TK_LINE, start_line)
    写 64 位（g_tokens, 偏移 + OFF_TK_COL, start_col)
    g_token_count = g_token_count + 1
```
### 测试要点
1. 标识符 "hello" 驻留后可正确通过词素索引取回
2. 空字符串正常驻留
3. 整数字段为 0

## 函数 跳过空白（skip_ws）
### 作用
在产生一个词法单元后，同步行号列号状态：先消费自上次 g_pos 以来遗漏的字符（更新行列号），再跳过当前位置起的所有空白字符（空格、水平制表、回车、换行）。最后将 g_pos 更新到跳白后的位置。
### 逻辑
```
函数 skip_ws(源码 src, 位置 pos, 最大长度 max_len) -> 整数
    令 追踪位置 tracked = g_pos（可变）
    循环（当 真 时）：
        如果 tracked 不小于等于 pos，那么：跳出循环
        令 c0 = cur_char_at(src, tracked, max_len)
        如果 c0 等于 10，那么：g_line = g_line + 1; g_col = 1
        否则：g_col = g_col + 1
        tracked = tracked + 1
    循环（当 真 时）：
        令 c = cur_char_at(src, pos, max_len)
        如果 c 等于 32 或 c 等于 9 或 c 等于 13 或 c 等于 10，那么：
            如果 c 等于 10，那么：g_line = g_line + 1; g_col = 1
            否则：g_col = g_col + 1
            pos = pos + 1
        否则：跳出循环
    g_pos = pos
    返回 pos
```
### 测试要点
1. 连续空格跳过且 g_col 正确递增
2. 换行符使 g_line 递增且 g_col 重置为 1
3. 非空白字符处停止且返回值指向该字符位置
4. 反复调用时 tracked 追赶逻辑正确（不重复计数）

## 函数 分词（tokenize）
### 作用
将输入源码字符串 _src 切分为词法单元序列，存入全局词法单元数组 g_tokens。这是分词模块的主入口函数。重置全局计数后逐字符扫描：处理注释（行注释 `//`、块注释 `/* */`）、标识符与关键字、数字字面量（十进制、十六进制 0x/0X、八进制 0o/0O、二进制 0b/0B，含 `.` 小数部分、类型后缀如 u8/i32/f64，以及 `..` 范围运算符与浮点 `.` 的歧义消解）、字符串字面量（转义序列 `\n \t \r \0 \' \" \\ \xHH`，插值 `${}` 跳过）、字符字面量（`'` 单引号包围单字符或转义序列）、多字符复合运算符（`== != <= >= && || -> => := :: .. ...`）、复合赋值运算符（`+= -= *= /=`）、单字符运算符和分隔符。遇未知字符时静默跳过。末尾追加 T_EOF 标记，同步全局状态 g_pos 和 g_source_len。
### 逻辑
```
函数 tokenize(_src)
    g_token_count = 0
    g_error_count = 0
    令 _pos = 0（可变）
    g_pos = 0
    g_line = 1
    g_col = 1
    令 _slen = 字符串长度（str_len）(_src)（可变）
    _pos = skip_ws(_src, _pos, _slen)

    循环（当 真 时）：
        如果 _pos 不小于等于 _slen，那么：跳出循环
        令 c = cur_char_at(_src, _pos, _slen)
        令 start_line = g_line（可变）
        令 start_col = g_col（可变）

        -- 行注释：//
        如果 c 等于 47 且 peek_at(_src, _pos, _slen) 等于 47，那么：
            _pos = _pos + 2
            循环（当 真 时）：
                如果 _pos 不小于等于 _slen，那么：跳出循环
                如果 cur_char_at(_src, _pos, _slen) 等于 10，那么：_pos = _pos + 1; 跳出循环
                _pos = _pos + 1
            _pos = skip_ws(_src, _pos, _slen)
            继续下一次循环

        -- 块注释：/* */
        如果 c 等于 47 且 peek_at(_src, _pos, _slen) 等于 42，那么：
            _pos = _pos + 2
            循环（当 真 时）：
                如果 _pos 不小于等于 _slen，那么：跳出循环
                如果 cur_char_at(_src, _pos, _slen) 等于 42 且 peek_at(_src, _pos, _slen) 等于 47，那么：_pos = _pos + 2; 跳出循环
                _pos = _pos + 1
            _pos = skip_ws(_src, _pos, _slen)
            继续下一次循环

        -- 标识符与关键字
        如果 is_alpha(c) 不等于 0，那么：
            令 start = _pos
            _pos = _pos + 1
            循环（当 真 时）：
                令 c2 = cur_char_at(_src, _pos, _slen)
                如果 is_ident_char(c2) 不等于 0，那么：_pos = _pos + 1
                否则：跳出循环
            令 ident = 字符串切片（str_sub）(_src, start, _pos - start)
            令 kind = lookup_keyword(ident)
            add_tok_str(kind, ident, start_line, start_col)
            _pos = skip_ws(_src, _pos, _slen)
            继续下一次循环

        -- 数字字面量
        如果 is_digit(c) 不等于 0 或 (c 等于 46 且 is_digit(peek_at(_src, _pos, _slen)) 不等于 0)，那么：
            令 start = _pos
            如果 c 等于 46，那么：_pos = _pos + 1; c = cur_char_at(_src, _pos, _slen)
            循环（当 真 时）：
                如果 is_digit(cur_char_at(_src, _pos, _slen)) 不等于 0，那么：_pos = _pos + 1
                否则：跳出循环
            -- 十六进制/八进制/二进制前缀处理
            如果 c 等于 48 且 _pos - start 等于 1，那么：
                令 nx = cur_char_at(_src, _pos, _slen)
                如果 nx 等于 120 或 nx 等于 88，那么：
                    _pos = _pos + 1
                    循环（当 真 时）：
                        令 hc = cur_char_at(_src, _pos, _slen)
                        如果 is_digit(hc) 不等于 0 或 (hc 不小于等于 65 且 hc 不大于等于 70) 或 (hc 不小于等于 97 且 hc 不大于等于 102)，那么：_pos = _pos + 1
                        否则：跳出循环
                否则如果 nx 等于 111 或 nx 等于 79，那么：
                    _pos = _pos + 1
                    循环（当 真 时）：
                        令 oc = cur_char_at(_src, _pos, _slen)
                        如果 oc 不小于等于 48 且 oc 不大于等于 55，那么：_pos = _pos + 1
                        否则：跳出循环
                否则如果 nx 等于 98 或 nx 等于 66，那么：
                    _pos = _pos + 1
                    循环（当 真 时）：
                        令 bc = cur_char_at(_src, _pos, _slen)
                        如果 bc 等于 48 或 bc 等于 49，那么：_pos = _pos + 1
                        否则：跳出循环
            -- 浮点数：只有当 `..`（范围运算符）时才不消费 `.`
            如果 cur_char_at(_src, _pos, _slen) 等于 46 且 peek_at(_src, _pos, _slen) 不等于 46，那么：
                _pos = _pos + 1
                循环（当 真 时）：
                    如果 is_digit(cur_char_at(_src, _pos, _slen)) 不等于 0，那么：_pos = _pos + 1
                    否则：跳出循环
            -- 类型后缀
            令 suffix = ""（可变）
            令 sx = cur_char_at(_src, _pos, _slen)
            如果 is_alpha(sx) 不等于 0，那么：
                令 ss = _pos
                循环（当 真 时）：
                    如果 is_alpha(cur_char_at(_src, _pos, _slen)) 不等于 0，那么：_pos = _pos + 1
                    否则：跳出循环
                suffix = 字符串切片（str_sub）(_src, ss, _pos - ss)
            令 num_str = 字符串切片（str_sub）(_src, start, _pos - start - 字符串长度（str_len）(suffix))
            令 ival = 字符串转整数（str_int）(num_str)（可变）
            如果 suffix 等于 "u8" 或 suffix 等于 "u16" 或 suffix 等于 "u32" 或 suffix 等于 "u64"，那么：不做特殊处理（仅识别）
            否则如果 suffix 等于 "i8" 或 suffix 等于 "i16" 或 suffix 等于 "i32" 或 suffix 等于 "i64"，那么：不做特殊处理（仅识别）
            否则如果 suffix 等于 "f32" 或 suffix 等于 "f64"，那么：不做特殊处理（仅识别）
            否则如果 字符串长度（str_len）(suffix) 大于 0，那么：不做特殊处理（未知后缀）
            如果 字符串长度（str_len）(suffix) 大于 0，那么：add_tok(T_INT, -1, start_line, start_col)
            否则：add_tok_int(T_INT, ival, start_line, start_col)
            _pos = skip_ws(_src, _pos, _slen)
            继续下一次循环

        -- 字符串字面量
        如果 c 等于 34，那么：
            _pos = _pos + 1
            令 str_val = ""（可变）
            循环（当 真 时）：
                令 cc = cur_char_at(_src, _pos, _slen)
                如果 cc 等于 0 或 cc 等于 10，那么：跳出循环
                如果 cc 等于 34，那么：_pos = _pos + 1; 跳出循环
                如果 cc 等于 92，那么： -- 反斜杠转义
                    _pos = _pos + 1
                    令 esc = cur_char_at(_src, _pos, _slen)
                    如果 esc 等于 110，那么：str_val = str_val + 字符构造（chr）(10)
                    否则如果 esc 等于 116，那么：str_val = str_val + 字符构造（chr）(9)
                    否则如果 esc 等于 114，那么：str_val = str_val + 字符构造（chr）(13)
                    否则如果 esc 等于 48，那么：str_val = str_val + 字符构造（chr）(0)
                    否则如果 esc 等于 39，那么：str_val = str_val + "'"
                    否则如果 esc 等于 92，那么：str_val = str_val + 字符构造（chr）(92)
                    否则如果 esc 等于 34，那么：str_val = str_val + 字符构造（chr）(34)
                    否则如果 esc 等于 120，那么：
                        _pos = _pos + 1
                        令 hi = cur_char_at(_src, _pos, _slen)
                        _pos = _pos + 1
                        令 lo = cur_char_at(_src, _pos, _slen)
                        令 hex_str = 字符构造（chr）(hi) + 字符构造（chr）(lo)
                        如果 hex_str 等于 "00"，那么：str_val = str_val + 字符构造（chr）(0)
                        否则如果 hex_str 等于 "0a" 或 hex_str 等于 "0A"，那么：str_val = str_val + 字符构造（chr）(10)
                        否则：str_val = str_val + "?"
                    否则：str_val = str_val + 字符构造（chr）(esc)
                否则如果 cc 等于 36 且 peek_at(_src, _pos, _slen) 等于 123，那么： -- 字符串插值 ${...}
                    _pos = _pos + 2
                    循环（当 真 时）：
                        如果 cur_char_at(_src, _pos, _slen) 等于 125，那么：_pos = _pos + 1; 跳出循环
                        _pos = _pos + 1
                否则：
                    str_val = str_val + 字符构造（chr）(cc)
                _pos = _pos + 1
            add_tok_str(T_STRING, str_val, start_line, start_col)
            _pos = skip_ws(_src, _pos, _slen)
            继续下一次循环

        -- 字符字面量
        如果 c 等于 39，那么：
            _pos = _pos + 1
            令 ch = 字符构造（chr）(0)（可变）
            如果 cur_char_at(_src, _pos, _slen) 等于 92，那么：
                _pos = _pos + 1
                令 esc2 = cur_char_at(_src, _pos, _slen)
                如果 esc2 等于 110，那么：ch = 字符构造（chr）(10)
                否则如果 esc2 等于 116，那么：ch = 字符构造（chr）(9)
                否则如果 esc2 等于 114，那么：ch = 字符构造（chr）(13)
                否则如果 esc2 等于 48，那么：ch = 字符构造（chr）(0)
                否则如果 esc2 等于 39，那么：ch = "'"
                否则如果 esc2 等于 92，那么：ch = 字符构造（chr）(92)
                否则如果 esc2 等于 34，那么：ch = 字符构造（chr）(34)
                否则如果 esc2 等于 120，那么：
                    _pos = _pos + 1
                    令 hi2 = cur_char_at(_src, _pos, _slen)
                    _pos = _pos + 1
                    令 lo2 = cur_char_at(_src, _pos, _slen)
                    如果 字符构造（chr）(hi2) + 字符构造（chr）(lo2) 等于 "00"，那么：ch = 字符构造（chr）(0)
                    否则：ch = "?"
                否则：ch = 字符构造（chr）(esc2)
                _pos = _pos + 1
            否则：
                ch = 字符构造（chr）(cur_char_at(_src, _pos, _slen))
                _pos = _pos + 1
            如果 cur_char_at(_src, _pos, _slen) 等于 39，那么：_pos = _pos + 1
            add_tok_str(T_CHAR, ch, start_line, start_col)
            _pos = skip_ws(_src, _pos, _slen)
            继续下一次循环

        -- 多字符复合运算符
        如果 c 等于 61  且 peek_at 等于 61，那么：_pos = _pos + 2; add_tok(T_EQEQ, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 33 且 peek_at 等于 61，那么：_pos = _pos + 2; add_tok(T_BANGEQ, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 60  且 peek_at 等于 61，那么：_pos = _pos + 2; add_tok(T_LTEQ, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 62  且 peek_at 等于 61，那么：_pos = _pos + 2; add_tok(T_GTEQ, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 38 且 peek_at 等于 38，那么：_pos = _pos + 2; add_tok(T_ANDAND, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 124 且 peek_at 等于 124，那么：_pos = _pos + 2; add_tok(T_PIPEPIPE, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 45 且 peek_at 等于 62，那么：_pos = _pos + 2; add_tok(T_ARROW, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 61  且 peek_at 等于 62，那么：_pos = _pos + 2; add_tok(T_FATARROW, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 58 且 peek_at 等于 61，那么：_pos = _pos + 2; add_tok(T_COLON_EQ, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 58 且 peek_at 等于 58，那么：_pos = _pos + 2; add_tok(T_PATHSEP, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 46  且 peek_at 等于 46，那么：
            _pos = _pos + 2
            如果 cur_char_at(_src, _pos, _slen) 等于 46，那么：_pos = _pos + 1; add_tok(T_DOTDOTDOT, -1, start_line, start_col)
            否则：add_tok(T_DOTDOT, -1, start_line, start_col)
            _pos = skip_ws(_src, _pos, _slen); 继续下一次循环

        -- 复合赋值运算符
        如果 c 等于 43 且 peek_at 等于 61，那么：_pos = _pos + 2; add_tok(T_PLUS_EQ, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 45 且 peek_at 等于 61，那么：_pos = _pos + 2; add_tok(T_MINUS_EQ, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 42 且 peek_at 等于 61，那么：_pos = _pos + 2; add_tok(T_STAR_EQ, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 47 且 peek_at 等于 61，那么：_pos = _pos + 2; add_tok(T_SLASH_EQ, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环

        -- 单字符词法单元
        如果 c 等于 40，那么：_pos = _pos + 1; add_tok(T_LPAREN, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 41，那么：_pos = _pos + 1; add_tok(T_RPAREN, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 123，那么：_pos = _pos + 1; add_tok(T_LBRACE, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 125，那么：_pos = _pos + 1; add_tok(T_RBRACE, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 91，那么：_pos = _pos + 1; add_tok(T_LBRACKET, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 93，那么：_pos = _pos + 1; add_tok(T_RBRACKET, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 44，那么：_pos = _pos + 1; add_tok(T_COMMA, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 59，那么：_pos = _pos + 1; add_tok(T_SEMI, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 58，那么：_pos = _pos + 1; add_tok(T_COLON, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 46，那么：_pos = _pos + 1; add_tok(T_DOT, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 61，那么：_pos = _pos + 1; add_tok(T_EQ, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 33，那么：_pos = _pos + 1; add_tok(T_BANG, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 60，那么：_pos = _pos + 1; add_tok(T_LT, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 62，那么：_pos = _pos + 1; add_tok(T_GT, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 43，那么：_pos = _pos + 1; add_tok(T_PLUS, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 45，那么：_pos = _pos + 1; add_tok(T_MINUS, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 42，那么：_pos = _pos + 1; add_tok(T_STAR, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 47，那么：_pos = _pos + 1; add_tok(T_SLASH, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 37，那么：_pos = _pos + 1; add_tok(T_PERCENT, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 38，那么：_pos = _pos + 1; add_tok(T_AMPERSAND, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 95，那么：_pos = _pos + 1; add_tok(T_UNDERSCORE, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 64，那么：_pos = _pos + 1; add_tok(T_AT, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环
        如果 c 等于 63，那么：_pos = _pos + 1; add_tok(T_QUESTION, -1, start_line, start_col); _pos = skip_ws(_src, _pos, _slen); 继续下一次循环

        -- 未知字符：静默跳过
        _pos = _pos + 1
        _pos = skip_ws(_src, _pos, _slen)

    -- 末尾追加文件结束标记
    add_tok(T_EOF, -1, g_line, g_col)
    -- 同步全局状态
    g_pos = _pos
    g_source_len = _slen
```
### 测试要点
1. 空字符串输入：产生仅含 T_EOF 的词法单元序列；g_line=1, g_col=1
2. 标识符 "hello"：产生 T_IDENT + T_EOF
3. 关键字 "fn"：产生 T_FN + T_EOF（通过 lookup_keyword 匹配）
4. 数字 "42"：产生 T_INT(ival=42) + T_EOF
5. 浮点数 "3.14"：产生 T_INT(ival 为转换后的整数值) + T_EOF；"0..4"（范围）不误识别为浮点数
6. 十六进制 "0xFF"：识别前缀，产生正确的数字词法单元
7. 带后缀 "100u32"：产生 T_INT（ival=-1，由后缀触发标识符处理）+ T_EOF
8. 字符串 '"hello\nworld"'：转义序列 \n 正确转换为换行（ASCII 10）
9. 字符串插值 '"x${y}z"'：插值部分 `{y}` 被跳过，结果为 "xz"
10. 字符字面量 "'a'"、"'\\n'"：分别产生 T_CHAR 含 'a' 和换行符
11. 复合运算符 "=="、"!="、"<="、">="、"&&"、"||"、"->"、"=>"、":="、"::"、".."、"..."：各自产生正确的词法单元类别
12. 复合赋值 "+="、"-="、"*="、"/="：各自产生正确的词法单元类别
13. 行注释 "// comment\n"：注释内容被跳过，\n 导致换行计数递增
14. 块注释 "/* multi\nline */"：包含换行的块注释正确处理行号
15. 修复后的浮点 vs 范围歧义："0..4" 正确拆分为 T_INT(0)、T_DOTDOT、T_INT(4)，不误判为 "0." + ".4"
16. 未知字符（如 '$' 未用于插值时）：静默跳过不崩溃
17. 词法单元计数在末尾为实际词法单元数（含 T_EOF），g_source_len 与输入一致
