# dump.cr 伪代码
> 源文件：src/compiler/dump.cr（334 行）
> 功能概要：IR/CCR 调试转储格式化工具与诊断输出命令。将 IR 变量、指令、类型转为可读字符串，并提供 cir 文本转储与 .cir/.ccr 文件输出命令。

## 标识符对照表
| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| IR 变量转字符串 | ir_var_str | IR 变量转字符串 |
| 类型类别名称 | type_kind_name | 类型类别名称 |
| 二元运算名称 | binop_name | 二元运算名称 |
| 数据流图：操作码名称 | df_opcode_name | IR 指令转字符串 |
| IR 指令转字符串 | ir_instr_str | IR 指令转字符串 |
| 命令：输出 .cir | cmd_cir | 命令：输出 .cir |
| CIR 文本转储 | cir_text_dump | CIR 文本转储 |
| 命令：输出 .ccr | cmd_ir | 命令：输出 .ccr |
| 获取 IR 变量名 | get_ir_var_name | IR 变量转字符串 |
| 获取变量寄存器 | get_reg_for_var | （外部引用，不在本文件定义） |
| 字符串长度 | str_len | IR 变量转字符串 |
| 整数转字符串 | int_str | IR 变量转字符串 |
| 驻留字符串获取 | istr_get | IR 指令转字符串 |
| 读取文件 | read_file | 命令：输出 .cir |
| 取目录名 | dirname | 命令：输出 .cir |
| 分词 | tokenize | 命令：输出 .cir |
| 解析引入 | res_imports | 命令：输出 .cir |
| 解析全部 | parse_all | 命令：输出 .cir |
| 检查全部 | check_all | 命令：输出 .cir |
| 打印诊断信息 | print_diagnostics | 命令：输出 .cir |
| IR 生成全部 | ir_gen_all | 命令：输出 .cir |
| 数据流图：导出 DOT | df_graph_to_dot | 命令：输出 .cir |
| 降为线性 IR | lower_to_ccr | 命令：输出 .ccr |
| 字符串切片 | str_sub | 命令：输出 .cir |
| 字符串相等比较 | str_eq | 命令：输出 .cir |
| 写入文件 | write_file | 命令：输出 .cir |
| 输出字符串 | print | 命令：输出 .cir |
| 输出行 | println | 命令：输出 .cir |
| 源码目录 | g_source_dir | 命令：输出 .cir |
| 当前源码字符串 | g_source | 命令：输出 .cir |
| 字符串常量计数 | g_str_count | 命令：输出 .cir |
| 诊断计数 | g_diag_count | 命令：输出 .cir |
| 数据流节点计数 | g_df_node_count | 命令：输出 .cir |
| 数据流边计数 | g_df_edge_count | CIR 文本转储 |
| IR 函数个数 | g_ir_func_count | CIR 文本转储 |
| IR 函数名索引数组 | g_ir_func_name_idx | CIR 文本转储 |
| IR 函数指令起始索引数组 | g_ir_func_instr_start | CIR 文本转储 |
| IR 函数指令计数数组 | g_ir_func_instr_count | CIR 文本转储 |
| IR 指令总数 | g_ir_instr_count | 命令：输出 .ccr |
| 结构图数组 | g_sgs | CIR 文本转储 |
| 结构图计数 | g_sg_count | CIR 文本转储 |
| IR 指令访问器：操作码 | iri_op | IR 指令转字符串 |
| IR 指令访问器：目标 | iri_dest | IR 指令转字符串 |
| IR 指令访问器：操作数1 | iri_s1 | IR 指令转字符串 |
| IR 指令访问器：操作数2 | iri_s2 | IR 指令转字符串 |
| IR 指令访问器：操作数3 | iri_s3 | IR 指令转字符串 |
| IR 指令访问器：类型类别 | iri_tk | IR 指令转字符串 |

## 全局状态
| 变量 | 含义 |
|------|------|
| g_source（当前源码字符串） | 读取的源码文件内容 |
| g_source_dir（源码目录） | 源码文件所在目录 |
| g_str_count（字符串常量计数） | 字符串驻留表中条目数 |
| g_diag_count（诊断计数） | 编译诊断信息条目数 |
| g_df_node_count（数据流节点计数） | 数据流图节点总数 |
| g_df_edge_count（数据流边计数） | 数据流图边总数 |
| g_ir_func_count（IR 函数个数） | IR 函数总数 |
| g_ir_func_name_idx（IR 函数名索引数组） | 各函数名称的驻留字符串索引 |
| g_ir_func_instr_start（IR 函数指令起始索引数组） | 各函数第一条指令的索引 |
| g_ir_func_instr_count（IR 函数指令计数数组） | 各函数的指令条数 |
| g_ir_instr_count（IR 指令总数） | 线性 IR 指令总数 |
| g_sgs（结构图数组） | 全部子图/region 条目 |
| g_sg_count（结构图计数） | 子图条目数 |

## 函数 IR 变量转字符串（ir_var_str）
### 作用
将 IR 变量索引转为可读字符串。负数索引返回空串；否则尝试获取变量名，若有名称返回名称，若无名返回索引值的十进制字符串。
### 逻辑
    令 var_idx = 参数 0（变量索引）
    如果 var_idx 小于 0，那么：
        返回 ""（空字符串）
    令 n = 获取 IR 变量名（var_idx）
    如果 字符串长度（n）大于 0，那么：
        返回 n
    返回 整数转字符串（var_idx）
### 测试要点
1. var_idx 为负数时返回空串
2. 有名称的变量返回名称字符串
3. 无名变量返回索引数字字符串（如 "3"）

## 函数 类型类别名称（type_kind_name）
### 作用
将类型类别常量（tk）转为可读的字符串缩写。
### 逻辑
    令 tk = 参数 0（类型类别号）
    如果 tk 等于 0，那么：返回 "int"
    如果 tk 等于 1，那么：返回 "float"
    如果 tk 等于 2，那么：返回 "bool"
    如果 tk 等于 3，那么：返回 "str"
    如果 tk 等于 4，那么：返回 "unit"
    如果 tk 等于 5，那么：返回 "never"
    如果 tk 等于 6，那么：返回 "char"
    返回 "?"
### 测试要点
1. 已知类别 0-6 返回各自缩写
2. 未识别类别返回 "?"

## 函数 二元运算名称（binop_name）
### 作用
将二元运算操作码（op）转为符号字符串表示。
### 逻辑
    令 op = 参数 0（操作码）
    如果 op 等于 1，那么：返回 "+"
    如果 op 等于 2，那么：返回 "-"
    如果 op 等于 3，那么：返回 "*"
    如果 op 等于 4，那么：返回 "/"
    如果 op 等于 5，那么：返回 "%"
    如果 op 等于 6，那么：返回 "=="
    如果 op 等于 7，那么：返回 "!="
    如果 op 等于 8，那么：返回 "<"
    如果 op 等于 9，那么：返回 ">"
    如果 op 等于 10，那么：返回 "<="
    如果 op 等于 11，那么：返回 ">="
    如果 op 等于 12，那么：返回 "&&"
    如果 op 等于 13，那么：返回 "||"
    如果 op 等于 17，那么：返回 "+ (ptr)"（指针加法）
    如果 op 等于 18，那么：返回 "- (ptr)"（指针减法）
    如果 op 等于 19，那么：返回 "- (diff)"（指针差）
    返回 "?"
### 测试要点
1. 算术操作码 1-5 返回对应算术符号
2. 比较操作码 6-11 返回对应比较符号
3. 逻辑操作码 12-13 返回逻辑符号
4. 指针操作码 17-19 返回带标注的符号
5. 未识别操作码返回 "?"

## 函数 IR 指令转字符串（ir_instr_str）
### 作用
将单条 IR 指令（按索引）格式化为可读的单行字符串，包含操作码名称、目标变量、源操作数，针对不同操作码有专用的格式化输出。
### 逻辑
    令 instr_idx = 参数 0（指令索引）
    令 opname = 数据流图：操作码名称（IR 指令访问器：操作码（instr_idx）, IR 指令访问器：操作数3（instr_idx））（操作码名）
    令 s = "  "（初始缩进）
    令 s = s 拼接 opname
    令 pa = 字符串长度（opname）（当前列位置）
    循环（当 pa 小于 18 时）：
        令 s = s 拼接 " "（空格填充至列宽18）
        令 pa = pa + 1

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_CONST，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = " + 整数转字符串（IR 指令访问器：操作数1（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_BINARY，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = " + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ " " + 二元运算名称（IR 指令访问器：操作数3（instr_idx））+ " " + IR 变量转字符串（IR 指令访问器：操作数2（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_UNARY，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = unary(" + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ ")"
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_CALL，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = call " + 驻留字符串获取（IR 指令访问器：操作数3（instr_idx））+ "("
        令 ai = 0（参数索引）
        令 a_first = 1（是否第一个参数标记）
        循环（当 ai 小于 IR 指令访问器：操作数2（instr_idx）时）：
            如果 a_first 等于 0，那么：令 s = s 拼接 ", "
            令 s = s 拼接 IR 变量转字符串（IR 指令访问器：操作数1（instr_idx）+ ai）
            令 a_first = 0
            令 ai = ai + 1
        令 s = s 拼接 ")"
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_RETURN，那么：
        如果 IR 指令访问器：操作数1（instr_idx）不小于 0，那么：令 s = s 拼接 IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））
        否则：令 s = s 拼接 "void"
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_ALLOC，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " : " + 类型类别名称（IR 指令访问器：类型类别（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_ALLOC_STRUCT，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " : struct " + 驻留字符串获取（IR 指令访问器：操作数3（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_ALLOC_ARRAY，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ "[" + 整数转字符串（IR 指令访问器：操作数1（instr_idx））+ "]"
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_STORE，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ " <- " + IR 变量转字符串（IR 指令访问器：操作数2（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_LOAD，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = " + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_LOAD_FIELD，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = " + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ "." + 整数转字符串（IR 指令访问器：操作数3（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_STORE_FIELD，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ "." + 整数转字符串（IR 指令访问器：操作数3（instr_idx））+ " <- " + IR 变量转字符串（IR 指令访问器：操作数2（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_LOAD_INDEX，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = " + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ "[" + 整数转字符串（IR 指令访问器：操作数3（instr_idx））+ "]"
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_STORE_INDEX，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ "[" + 整数转字符串（IR 指令访问器：操作数3（instr_idx））+ "] <- " + IR 变量转字符串（IR 指令访问器：操作数2（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_LOAD_INDEX_VAR，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = " + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ "[" + IR 变量转字符串（IR 指令访问器：操作数2（instr_idx））+ "]"
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_STORE_INDEX_VAR，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ "[" + IR 变量转字符串（IR 指令访问器：操作数2（instr_idx））+ "] <- " + IR 变量转字符串（IR 指令访问器：目标（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_MAKE_ENUM，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = make_enum(" + 驻留字符串获取（IR 指令访问器：操作数1（instr_idx））+ ")"
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_REF，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = ref " + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_DEREF，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = deref " + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_STORE_PTR，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ " := " + IR 变量转字符串（IR 指令访问器：操作数2（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_BRANCH，那么：
        令 s = s 拼接 "if " + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ " goto label" + 整数转字符串（IR 指令访问器：操作数2（instr_idx））+ " else label" + 整数转字符串（IR 指令访问器：操作数3（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_JUMP，那么：
        令 s = s 拼接 "goto label" + 整数转字符串（IR 指令访问器：操作数1（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_LABEL，那么：
        令 s = s 拼接 "label" + 整数转字符串（IR 指令访问器：操作数1（instr_idx））+ ":"
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_PHI，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = phi("
        令 pi = 0（参数索引）
        令 p_first = 1（是否首个标记）
        循环（当 pi 小于 IR 指令访问器：操作数2（instr_idx）时）：
            如果 p_first 等于 0，那么：令 s = s 拼接 ", "
            令 s = s 拼接 IR 变量转字符串（IR 指令访问器：操作数1（instr_idx）+ pi）
            令 p_first = 0
            令 pi = pi + 1
        令 s = s 拼接 ")"
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_LOAD_ENUM_TAG，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = tag " + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））
        返回 s

    如果 IR 指令访问器：操作码（instr_idx）等于 IR_SLICE，那么：
        令 s = s 拼接 IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " = slice " + IR 变量转字符串（IR 指令访问器：操作数1（instr_idx））+ "[" + IR 变量转字符串（IR 指令访问器：操作数2（instr_idx））+ ":" + IR 变量转字符串（IR 指令访问器：操作数3（instr_idx））+ "]"
        返回 s

    （未匹配的操作码，回退格式：）
    令 s = s 拼接 "dest=" + IR 变量转字符串（IR 指令访问器：目标（instr_idx））+ " s1=" + 整数转字符串（IR 指令访问器：操作数1（instr_idx））+ " s2=" + 整数转字符串（IR 指令访问器：操作数2（instr_idx））+ " s3=" + 整数转字符串（IR 指令访问器：操作数3（instr_idx））
    返回 s
### 测试要点
1. IR_CONST 指令输出 "var = 数值" 格式
2. IR_BINARY 指令输出 "var = left 运算符 right" 格式
3. IR_CALL 指令输出函数名和逗号分隔的参数列表
4. IR_RETURN 指令无返回值时输出 "void"
5. IR_BRANCH 指令输出条件和两个跳转目标
6. IR_PHI 指令输出逗号分隔的 phi 操作数列表
7. 未识别操作码回退到通用 "dest=... s1=... s2=... s3=..." 格式

## 函数 命令：输出 .cir（cmd_cir）
### 作用
读取 .cr 源文件，完成完整前端管线（分词、解析引入、解析、类型检查、IR 生成），将数据流图的 DOT 格式输出写入 .cir 文件。返回 0 表示成功，1 表示错误。
### 逻辑
    令 src_path = 参数 0（源文件路径）
    令 g_source（当前源码字符串）= 读取文件（src_path）
    如果 字符串长度（g_source（当前源码字符串））等于 0，那么：
        输出字符串（"error: cannot read "）
        输出行（src_path）
        返回 1
    令 g_source_dir（源码目录）= 取目录名（src_path）
    分词（g_source（当前源码字符串））
    令 g_str_count（字符串常量计数）= 0
    解析引入（）
    解析全部（）
    检查全部（）
    如果 g_diag_count（诊断计数）大于 0，那么：
        打印诊断信息（）
        返回 1
    IR 生成全部（）
    令 dot = 数据流图：导出 DOT（）

    令 cir_path = src_path（输出路径，默认同源文件路径）
    令 slen = 字符串长度（src_path）
    如果 slen 大于 3，那么：
        令 ext = 字符串切片（src_path, slen - 3, 3）
        如果 字符串相等比较（ext, ".cr"）不等于 0，那么：
            令 cir_path = 字符串切片（src_path, 0, slen - 3）+ ".cir"

    令 written = 写入文件（cir_path, dot）
    如果 written 小于 0，那么：
        输出字符串（"error: could not write "）
        输出行（cir_path）
        返回 1
    输出字符串（" -> "）
    输出字符串（cir_path）
    输出字符串（" ("）
    输出字符串（整数转字符串（g_df_node_count（数据流节点计数）））
    输出字符串（" nodes, "）
    输出字符串（整数转字符串（g_df_edge_count（数据流边计数）））
    输出行（" edges)"）
    返回 0
### 测试要点
1. 源文件无法读取时打印错误返回 1
2. 类型检查有诊断错误时打印诊断返回 1
3. 输出文件写入失败时打印错误返回 1
4. 成功时输出 ".cir 路径 (节点数, 边数)" 信息
5. 自动将 .cr 后缀替换为 .cir 后缀

## 函数 CIR 文本转储（cir_text_dump）
### 作用
生成线性 CFG 的文本表示：按函数分组，列出每个函数内的 region 信息（SG_IF/SG_LOOP/SG_FOR/SG_FLOW/SG_UNSAFE）和指令块（Block: labelN），最后附上状态边（state edges）列表。返回拼接好的完整字符串。
### 逻辑
    令 ccr = ""（结果字符串）
    令 fi = 0（函数索引）
    循环（当 fi 小于 g_ir_func_count（IR 函数个数）时）：
        令 name_ni = r64（g_ir_func_name_idx（IR 函数名索引数组）, fi * 8）
        令 ccr = ccr 拼接 "Function: " + 驻留字符串获取（name_ni）+ "\n"
        令 start = r64（g_ir_func_instr_start（IR 函数指令起始索引数组）, fi * 8）
        令 count = r64（g_ir_func_instr_count（IR 函数指令计数数组）, fi * 8）
        （输出该函数的 region 列表——仅输出 DFNode 起始索引落在本函数指令范围内的 region）
        令 ri = 0（region 索引）
        循环（当 ri 小于 g_sg_count（结构图计数）时）：
            令 rkind = r64（g_sgs（结构图数组）, ri * ESZ_SG + OFF_SG_KIND）
            令 rstart = r64（g_sgs（结构图数组）, ri * ESZ_SG + OFF_SG_NSTART）
            令 rend = r64（g_sgs（结构图数组）, ri * ESZ_SG + OFF_SG_EXIT）
            如果 rstart 不小于 start 且 rstart 小于 start + count，那么：
                如果 rend 不小于 0（跳过未闭合的 region，即 EXIT < 0），那么：
                    令 rname = "?"（region 名称，默认为未知）
                    如果 rkind 等于 SG_FUNC，那么：令 rname = "func"
                    如果 rkind 等于 SG_IF，那么：令 rname = "if"
                    如果 rkind 等于 SG_LOOP，那么：令 rname = "loop"
                    如果 rkind 等于 SG_FOR，那么：令 rname = "for"
                    如果 rkind 等于 SG_FLOW，那么：令 rname = "flow"
                    如果 rkind 等于 SG_UNSAFE，那么：令 rname = "unsafe"
                    令 ccr = ccr 拼接 "  Region: " + rname + " nodes " + 整数转字符串（rstart）+ ".." + 整数转字符串（rend）+ "\n"
            令 ri = ri + 1

        （输出指令块：以 IR_LABEL 为界分组）
        令 in_block = 0（是否处于块内标记）
        令 ii = 0（指令索引）
        循环（当 ii 小于 count 时）：
            如果 IR 指令访问器：操作码（start + ii）等于 IR_LABEL，那么：
                如果 in_block 不等于 0，那么：令 ccr = ccr 拼接 "\n"（块间空行）
                令 ccr = ccr 拼接 "  Block: label" + 整数转字符串（IR 指令访问器：操作数1（start + ii））+ "\n"
                令 in_block = 1
            否则：
                令 ccr = ccr 拼接 "    " + IR 指令转字符串（start + ii）+ "\n"
            令 ii = ii + 1

        令 ccr = ccr 拼接 "\n"
        令 fi = fi + 1

    （输出状态边：副作用链与循环终止依赖）
    令 ccr = ccr 拼接 "State edges:\n"
    令 ei = 0（边索引）
    循环（当 ei 小于 g_df_edge_count（数据流边计数）时）：
        如果 r64（g_df_edges（数据流边数组）, ei * ESZ_DFEDGE + OFF_DFE_KIND）不等于 0，那么：
            令 e_from = r64（g_df_edges（数据流边数组）, ei * ESZ_DFEDGE + OFF_DFE_FROM）
            令 e_to = r64（g_df_edges（数据流边数组）, ei * ESZ_DFEDGE + OFF_DFE_TO）
            令 ccr = ccr 拼接 "  state: n" + 整数转字符串（e_from）+ " -> n" + 整数转字符串（e_to）+ "\n"
        令 ei = ei + 1

    返回 ccr
### 测试要点
1. 空图（无函数）输出仅含 "State edges:\n"
2. 每个函数输出 "Function: 名称" 头
3. region 的 DFNode 起始索引不在当前函数范围内时不输出
4. 未闭合 region（EXIT < 0）被跳过不输出
5. IR_LABEL 指令标记新 Block 的开始，块间有空行分隔
6. 状态边仅输出 KIND 非 0 的边（即 state 边，非 data 边）

## 函数 命令：输出 .ccr（cmd_ir）
### 作用
读取 .cr 源文件，完成完整前端管线（分词、解析引入、解析、类型检查、IR 生成、降为线性 IR），调用 CIR 文本转储（cir_text_dump）生成文本格式，写入 .ccr 文件。返回 0 成功，1 错误。
### 逻辑
    令 src_path = 参数 0（源文件路径）
    令 g_source（当前源码字符串）= 读取文件（src_path）
    如果 字符串长度（g_source（当前源码字符串））等于 0，那么：
        输出字符串（"error: cannot read "）
        输出行（src_path）
        返回 1
    令 g_source_dir（源码目录）= 取目录名（src_path）
    分词（g_source（当前源码字符串））
    令 g_str_count（字符串常量计数）= 0
    解析引入（）
    解析全部（）
    检查全部（）
    如果 g_diag_count（诊断计数）大于 0，那么：
        打印诊断信息（）
        返回 1
    IR 生成全部（）
    降为线性 IR（）

    令 ccr = CIR 文本转储（）

    令 ccr_path = src_path（输出路径）
    令 slen = 字符串长度（src_path）
    如果 slen 大于 3，那么：
        令 ext = 字符串切片（src_path, slen - 3, 3）
        如果 字符串相等比较（ext, ".cr"）不等于 0，那么：
            令 ccr_path = 字符串切片（src_path, 0, slen - 3）+ ".ccr"

    令 written = 写入文件（ccr_path, ccr）
    如果 written 小于 0，那么：
        输出字符串（"error: could not write "）
        输出行（ccr_path）
        返回 1
    输出字符串（" -> "）
    输出字符串（ccr_path）
    输出字符串（" ("）
    输出字符串（整数转字符串（g_ir_func_count（IR 函数个数）））
    输出字符串（" functions, "）
    输出字符串（整数转字符串（g_ir_instr_count（IR 指令总数）））
    输出行（" instrs)"）
    返回 0
### 测试要点
1. 与 cmd_cir 相同的错误处理路径（文件不可读、诊断错误、写入失败均返回 1）
2. 额外调用 降为线性 IR（lower_to_ccr）将数据流图转为线性 IR
3. 成功时输出 ".ccr 路径 (函数数, 指令数)" 信息
4. 自动将 .cr 后缀替换为 .ccr 后缀
