# ir_gen.cr 伪代码（第 4 部分：表达式 IR 生成（下）与函数级流程/入口）
> 源文件：src/compiler/ir_gen.cr（第 1119–2032 行）
> 功能概要：生成表达式（gen_expr） 的剩余部分（代码块 代码块表达式（EXPR_BLOCK）、如果（if）/循环（loop）/当（while）/遍历（for） 控制流含 SG region 和竞技场管理、匹配（match） 匹配含枚举/整数/布尔/通配符模式与子值绑定、令（let） 绑定含 动态（dyn） 与数组标注、让出（yield）/等待（await）/返回（return）、字段/下标访问含 范围（range） 切片、枚举构造/结构体字面量/数组字面量、范围/跳出（break）/继续（continue）、非安全（unsafe）/类型转换（as）/尝试（try）/move/wildcard/enumpat/structpat/stmt/tuple），以及函数级 IR 生成（ir_gen_func）、全局变量初始值提取与注册（global_init_val/reg_one_global/ir_gen_globals）、AST 修补（ast_patch_node）、单态函数创建（find_or_create_mono_func）、总入口（ir_gen_all）、函数指纹/签名指纹计算。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 生成表达式 | gen_expr | 生成表达式（gen_expr） |
| IR 生成函数 | ir_gen_func | IR 生成函数（ir_gen_func） |
| 全局变量初始值 | global_init_val | 全局变量初始值（global_init_val） |
| 注册单个全局变量 | reg_one_global | 注册单个全局变量（reg_one_global） |
| IR 生成全局变量 | ir_gen_globals | IR 生成全局变量（ir_gen_globals） |
| AST 修补节点 | ast_patch_node | AST 修补节点（ast_patch_node） |
| 查找或创建单态化函数 | find_or_create_mono_func | 查找或创建单态化函数（find_or_create_mono_func） |
| IR 生成全部 | ir_gen_all | IR 生成全部（ir_gen_all） |
| 函数指纹 | func_fingerprint | 函数指纹（func_fingerprint） |
| 签名指纹 | sig_fingerprint | 签名指纹（sig_fingerprint） |
| 代码块语句数组 | g_block_stmts | 生成表达式（gen_expr） |
| 初始化 HDFG | init_df | IR 生成全部（ir_gen_all） |
| HDFG：开始函数 | df_begin_func | IR 生成全部（ir_gen_all） |
| HDFG：结束函数 | df_end_func | IR 生成全部（ir_gen_all） |
| IR 函数名索引数组 | g_ir_func_name_idx | IR 生成函数（ir_gen_func） |
| IR 函数返回类型数组 | g_ir_func_ret_type | IR 生成函数（ir_gen_func） |
| IR 函数指令起始索引数组 | g_ir_func_instr_start | IR 生成函数（ir_gen_func） |
| IR 函数变量起始索引数组 | g_ir_func_var_start | IR 生成函数（ir_gen_func） |
| IR 函数参数计数数组 | g_ir_func_param_count | IR 生成函数（ir_gen_func） |
| IR 函数指令计数数组 | g_ir_func_instr_count | IR 生成函数（ir_gen_func） |
| IR 函数变量计数数组 | g_ir_func_var_count | IR 生成函数（ir_gen_func） |
| 扩展 IR 函数元数据数组 | grow_ir_func_meta | IR 生成函数（ir_gen_func） |
| 扩展 IR 全局变量数组 | grow_ir_globals | 注册单个全局变量（reg_one_global） |
| 压入 SG 分配槽 | sg_alloc_push | 生成表达式（gen_expr） |
| 弹出 SG 分配槽 | sg_alloc_pop | 生成表达式（gen_expr） |
| 压入 IR 作用域 | push_ir_scope | 生成表达式（gen_expr） |
| 弹出 IR 作用域 | pop_ir_scope | 生成表达式（gen_expr） |
| 压入循环标签栈 | push_loop_labels | 生成表达式（gen_expr） |
| 弹出循环标签栈 | pop_loop_labels | 生成表达式（gen_expr） |
| 绑定局部变量 | bind_local | 生成表达式（gen_expr） |
| 获取变体名索引 | get_variant_name_idx | 生成表达式（gen_expr） |
| 数组访问前处理 | pass_before_array_access | 生成表达式（gen_expr） |
| 扩展 SG 分配数组 | grow_sg_alloc | IR 生成函数（ir_gen_func） |
| 扩展 SG 竞技场变量数组 | grow_sg_arena_var | IR 生成函数（ir_gen_func） |
| AST 访问器：行号 | ast_line | 函数指纹（func_fingerprint） |
| AST 访问器：列号 | ast_col | 函数指纹（func_fingerprint） |
| AST 访问器：类型值 | ast_type_val | IR 生成函数（ir_gen_func） |
| AST 访问器：设置数据 | ast_set_data | AST 修补节点（ast_patch_node） |
| AST 访问器：设置整数值 | ast_set_int_val | （全局状态） |
| IR 指令访问器：设置操作数1 | iri_set_s1 | 生成表达式（gen_expr） |
| 分配 AST 节点 | alloc_node | 查找或创建单态化函数（find_or_create_mono_func） |
| 添加函数 | add_func | 查找或创建单态化函数（find_or_create_mono_func） |
| 函数信息访问器：AST 节点 | fi_ast_node | IR 生成函数（ir_gen_func） |
| 函数信息访问器：名称 | fi_name | 查找或创建单态化函数（find_or_create_mono_func） |
| 函数信息访问器：参数类型 | fi_param_type | （全局状态） |
| 函数信息访问器：参数计数 | fi_param_count | （全局状态） |
| 函数信息访问器：设置泛型计数 | fi_set_generic_count | 查找或创建单态化函数（find_or_create_mono_func） |
| 函数信息访问器：泛型名称 | fi_generic_name | 查找或创建单态化函数（find_or_create_mono_func） |
| 函数信息访问器：泛型计数 | fi_generic_count | IR 生成函数（ir_gen_func） |
| 字符串按字节读取 | str_load8 | AST 修补节点（ast_patch_node）中 |
| 字符串长度 | str_len | AST 修补节点（ast_patch_node）中 |
| 字符串切片 | str_sub | AST 修补节点（ast_patch_node）中 |
| 字符串驻留 | str_intern | AST 修补节点（ast_patch_node）中 |
| 驻留字符串获取 | istr_get | 查找或创建单态化函数（find_or_create_mono_func） |
| 强制 如果-那么 块 | force_if_thunk | 生成表达式（gen_expr） |
| 新建 IR 变量 | new_ir_var | 生成表达式（gen_expr） |
| 发射指令 | emit | 生成表达式（gen_expr） |
| 新建标签 | new_label | 生成表达式（gen_expr） |
| 查找函数 | find_func | 查找或创建单态化函数（find_or_create_mono_func） |
| 读 64 位 | r64 | 生成表达式（gen_expr） |
| 写 64 位 | w64 | 生成表达式（gen_expr） |
| 结构图计数 | g_sg_count | 生成表达式（gen_expr） |
| SG 分配槽总数 | g_sg_alloc_total | 生成表达式（gen_expr） |
| SG 竞技场变量数组 | g_sg_arena_var | 生成表达式（gen_expr） |
| IR 局部变量计数 | g_ir_local_count | 生成表达式（gen_expr） |
| IR 循环头标签栈 | g_ir_loop_header | 生成表达式（gen_expr） |
| IR 循环出口标签栈 | g_ir_loop_exit | 生成表达式（gen_expr） |
| IR 循环嵌套深度 | g_ir_loop_depth | 生成表达式（gen_expr） |
| IR 变量总数 | g_ir_var_count | IR 生成函数（ir_gen_func） |
| IR 指令总数 | g_ir_instr_count | IR 生成函数（ir_gen_func） |
| IR 函数个数 | g_ir_func_count | IR 生成函数（ir_gen_func） |
| IR 全局变量计数 | g_ir_global_count | IR 生成函数（ir_gen_func） |
| 下一个标签号 | g_next_label | IR 生成全部（ir_gen_all） |
| 全局声明数组 | g_global_lets | 全局变量初始值（global_init_val） |
| 全局声明计数 | g_global_let_count | 全局变量初始值（global_init_val） |
| AST 节点计数 | g_ast_count | IR 生成函数（ir_gen_func） |
| 函数计数 | g_func_count | IR 生成全部（ir_gen_all） |
| IR 字符串常量计数 | g_ir_str_const_count | IR 生成全部（ir_gen_all） |
| IR 局部变量作用域深度 | g_ir_local_depth | IR 生成全部（ir_gen_all） |

---

## 全局状态
（本部分未单独列出全局变量；涉及的全局变量含义见「标识符对照表」）

## 函数 生成表达式（gen_expr）（续）

（第 4 部分覆盖：代码块、控制流、匹配（match）、令（let）、让出（yield）/等待（await）/返回（return）、字段/下标、枚举（enum）/结构（struct）/array 构造、范围（range）/跳出（break）/继续（continue）、非安全（unsafe）/类型转换（as）/尝试（try）/move/wildcard/enumpat/structpat/stmt/tuple，源文件第 1119–1628 行）

### 逻辑

（—— 代码块：代码块表达式（EXPR_BLOCK） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 代码块表达式（EXPR_BLOCK），那么：
    令 语句起始索引 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 语句数量 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 最后语句结果 = -1
    压入 IR 作用域（push_ir_scope）（）
    令 扫描位置 = 0
    循环：
        如果 扫描位置 大于等于 语句数量，那么：
            跳出循环
        令 当前语句节点 = 从 代码块语句数组（g_block_stmts）偏移（（语句起始索引 + 扫描位置） * 8）处读取 64 位
        令 最后语句结果 = 生成表达式（gen_expr）（当前语句节点）
        令 扫描位置 = 扫描位置 + 1
    弹出 IR 作用域（pop_ir_scope）（）
    返回 最后语句结果

（—— If 表达式：条件表达式（EXPR_IF） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 条件表达式（EXPR_IF），那么：
    压入结构图（sg_push）（SG_IF）（条件区域覆盖 [condition, merge）——供区域迭代使用）
    令 条件节点 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 那么（then） 分支节点 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 否则（else） 分支节点 = 第三子节点访问器（ast_c）（ast_c）（节点）
    令 条件结果变量 = 生成表达式（gen_expr）（条件节点）
    令 条件结果变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（条件结果变量）
    令 那么（then） 入口标签 = 新建标签（new_label）（）
    令 否则（else） 入口标签 = 新建标签（new_label）（）
    令 汇合标签 = 新建标签（new_label）（）
    如果 否则（else） 分支节点 大于等于 0，那么：
        发射指令（emit）（IR_BRANCH, -1, 条件结果变量, 那么（then） 入口标签, 否则（else） 入口标签, 0）
    否则：
        发射指令（emit）（IR_BRANCH, -1, 条件结果变量, 那么（then） 入口标签, 汇合标签, 0）
    （那么（then） 分支）
    发射指令（emit）（IR_LABEL, -1, 那么（then） 入口标签, 0, 0, 0）
    生成表达式（gen_expr）（那么（then） 分支节点）
    发射指令（emit）（IR_JUMP, -1, 汇合标签, 0, 0, 0）
    （否则（else） 分支——仅当存在时）
    如果 否则（else） 分支节点 大于等于 0，那么：
        发射指令（emit）（IR_LABEL, -1, 否则（else） 入口标签, 0, 0, 0）
        生成表达式（gen_expr）（否则（else） 分支节点）
        发射指令（emit）（IR_JUMP, -1, 汇合标签, 0, 0, 0）
    发射指令（emit）（IR_LABEL, -1, 汇合标签, 0, 0, 0）
    弹出结构图（sg_pop）（）
    返回 -1

（—— Loop 表达式：无限循环表达式（EXPR_LOOP） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 无限循环表达式（EXPR_LOOP），那么：
    令 循环头部标签 = 新建标签（new_label）（）
    令 循环体入口标签 = 新建标签（new_label）（）
    令 循环出口标签 = 新建标签（new_label）（）
    发射指令（emit）（IR_JUMP, -1, 循环头部标签, 0, 0, 0）
    （SG_LOOP 区域覆盖 [header, exit）——回边跳转到头部时，若解释器在区域边界驱动迭代，则回边落在 region 进入（enter） 上）
    压入 SG 分配槽（sg_alloc_push）（SG_LOOP）
    令 竞技场变量 = 新建 IR 变量（new_ir_var）（"_arena", 类型信息：整数（TI_INT））
    在 SG 竞技场变量数组（g_sg_arena_var）偏移（（结构图计数（g_sg_count） - 1） * 8）处写入 64 位值：竞技场变量
    发射指令（emit）（IR_LABEL, -1, 循环头部标签, 0, 0, 0）
    发射指令（emit）（IR_JUMP, -1, 循环体入口标签, 0, 0, 0）
    发射指令（emit）（IR_LABEL, -1, 循环体入口标签, 0, 0, 0）
    发射指令（emit）（IR_ARENA_NEW, 竞技场变量, 0, 0, 0, 0）
    令 竞技场指令索引 = IR 指令总数（g_ir_instr_count） - 1
    压入 IR 作用域（push_ir_scope）（）
    （post_lbl：继续（continue） 必须跳到 post 标签而非头部——否则 继续 路径上的竞技场重置不会执行）
    令 循环递增标签 = 新建标签（new_label）（）
    压入循环标签列表（looplabels）（push_loop_labels）（循环递增标签, 循环出口标签）
    生成表达式（gen_expr）（第一子节点访问器（ast_a）（节点））
    弹出循环标签列表（looplabels）（pop_loop_labels）（）
    弹出 IR 作用域（pop_ir_scope）（）
    令 累计分配量 = 从 SG 分配槽总数（g_sg_alloc_total）偏移（结构图计数 - 1）处读取 64 位
    如果 累计分配量 大于 0，那么：
        IR 指令访问器：设置操作数1（iri_set_s1）（竞技场指令索引, 累计分配量）
    发射指令（emit）（IR_LABEL, -1, 循环递增标签, 0, 0, 0）
    发射指令（emit）（IR_ARENA_RESET, -1, 竞技场变量, 0, 0, 0）（每迭代复用竞技场）
    发射指令（emit）（IR_JUMP, -1, 循环头部标签, 0, 0, 0）
    发射指令（emit）（IR_LABEL, -1, 循环出口标签, 0, 0, 0）
    弹出结构图（sg_pop）（）（关闭 循环（loop） region——竞技场已在上方重置）
    返回 -1

（—— While 循环：条件循环表达式（EXPR_WHILE） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 条件循环表达式（EXPR_WHILE），那么：
    令 条件节点 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 循环体节点 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 循环头部标签 = 新建标签（new_label）（）
    令 循环体入口标签 = 新建标签（new_label）（）
    令 循环出口标签 = 新建标签（new_label）（）
    发射指令（emit）（IR_LABEL, -1, 循环头部标签, 0, 0, 0）
    令 条件结果变量 = 生成表达式（gen_expr）（条件节点）
    令 条件结果变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（条件结果变量）
    发射指令（emit）（IR_BRANCH, -1, 条件结果变量, 循环体入口标签, 循环出口标签, 0）
    发射指令（emit）（IR_LABEL, -1, 循环体入口标签, 0, 0, 0）
    压入 IR 作用域（push_ir_scope）（）
    压入循环标签列表（looplabels）（push_loop_labels）（循环头部标签, 循环出口标签）
    生成表达式（gen_expr）（循环体节点）
    弹出循环标签列表（looplabels）（pop_loop_labels）（）
    弹出 IR 作用域（pop_ir_scope）（）
    发射指令（emit）（IR_JUMP, -1, 循环头部标签, 0, 0, 0）
    发射指令（emit）（IR_LABEL, -1, 循环出口标签, 0, 0, 0）
    返回 -1

（—— For 循环：遍历循环表达式（EXPR_FOR） ——）
（语法：遍历（for） var in 开始（start）..结束（end） 「 body 」）

如果 AST 访问器：类别（ast_kind）（节点） 等于 遍历循环表达式（EXPR_FOR），那么：
    令 循环变量名索引 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 迭代器节点 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 循环体节点 = 第三子节点访问器（ast_c）（ast_c）（节点）
    令 起始值变量 = -1
    令 结束值变量 = -1
    （范围（range） 迭代器）
    如果 AST 访问器：类别（ast_kind）（迭代器节点） 等于 范围表达式（EXPR_RANGE），那么：
        令 起始值变量 = 生成表达式（gen_expr）（第一子节点访问器（ast_a）（迭代器节点））
        令 起始值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（起始值变量）
        令 结束值变量 = 生成表达式（gen_expr）（第二子节点访问器（ast_b）（迭代器节点））
        令 结束值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（结束值变量）
    否则：
        （非 范围（range） 迭代器：视为 0..iter）
        令 起始常量 = 新建 IR 变量（new_ir_var）（"开始（start）", 类型信息：整数（TI_INT））
        发射指令（emit）（常量指令（IR_CONST）, 起始常量, 0, 0, 0, 类型信息：整数（TI_INT））
        令 起始值变量 = 起始常量
        令 结束值变量 = 生成表达式（gen_expr）（迭代器节点）
        令 结束值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（结束值变量）
    （创建循环变量并初始化为起始值）
    令 循环变量 = 新建 IR 变量（new_ir_var）（"for_i", 类型信息：整数（TI_INT））
    发射指令（emit）（IR_ALLOC, 循环变量, 0, 0, 0, 类型信息：整数（TI_INT））
    发射指令（emit）（存储指令（IR_STORE）, -1, 循环变量, 起始值变量, 0, 0）
    绑定局部变量（bind_local）（循环变量名索引, 循环变量）
    令 循环头部标签 = 新建标签（new_label）（）
    令 循环体入口标签 = 新建标签（new_label）（）
    令 循环出口标签 = 新建标签（new_label）（）
    （SG_FOR 区域覆盖 [header, exit）——回边跳转为 region 进入（enter） 跳转，支持区域迭代）
    压入 SG 分配槽（sg_alloc_push）（SG_FOR）
    令 竞技场变量 = 新建 IR 变量（new_ir_var）（"_arena", 类型信息：整数（TI_INT））
    在 SG 竞技场变量数组 偏移（（结构图计数（g_sg_count） - 1） * 8）处写入 64 位值：竞技场变量
    （头部：检查循环变量 小于 结束值变量，不满足则跳到出口）
    发射指令（emit）（IR_LABEL, -1, 循环头部标签, 0, 0, 0）
    令 条件变量 = 新建 IR 变量（new_ir_var）（"for_cond", 类型信息：整数（TI_INT））
    发射指令（emit）（IR_BINARY, 条件变量, 循环变量, 结束值变量, OP_LT, 0）
    发射指令（emit）（IR_BRANCH, -1, 条件变量, 循环体入口标签, 循环出口标签, 0）
    （体）
    发射指令（emit）（IR_LABEL, -1, 循环体入口标签, 0, 0, 0）
    发射指令（emit）（IR_ARENA_NEW, 竞技场变量, 0, 0, 0, 0）
    令 竞技场指令索引 = IR 指令总数（g_ir_instr_count） - 1
    压入 IR 作用域（push_ir_scope）（）
    （post_lbl：继续（continue） 跳到递增标签而非头部——否则循环变量永不递增导致死循环）
    令 循环递增标签 = 新建标签（new_label）（）
    压入循环标签列表（looplabels）（push_loop_labels）（循环递增标签, 循环出口标签）
    生成表达式（gen_expr）（循环体节点）
    弹出循环标签列表（looplabels）（pop_loop_labels）（）
    弹出 IR 作用域（pop_ir_scope）（）
    令 累计分配量 = 从 SG 分配槽总数 偏移（结构图计数 - 1）处读取 64 位
    如果 累计分配量 大于 0，那么：
        IR 指令访问器：设置操作数1（iri_set_s1）（竞技场指令索引, 累计分配量）
    （递增循环变量并跳回头部——竞技场重置在每条路径（continue）运行，实现每迭代内存复用）
    发射指令（emit）（IR_LABEL, -1, 循环递增标签, 0, 0, 0）
    发射指令（emit）（IR_ARENA_RESET, -1, 竞技场变量, 0, 0, 0）
    令 单位常量 = 新建 IR 变量（new_ir_var）（TI_INT）
    发射指令（emit）（常量指令（IR_CONST）, 单位常量, 1, 0, 0, 类型信息：整数（TI_INT））
    令 递增后变量 = 新建 IR 变量（new_ir_var）（TI_INT）
    发射指令（emit）（IR_BINARY, 递增后变量, 循环变量, 单位常量, 加法运算符（OP_ADD）, 0）
    发射指令（emit）（存储指令（IR_STORE）, -1, 循环变量, 递增后变量, 0, 0）
    发射指令（emit）（IR_JUMP, -1, 循环头部标签, 0, 0, 0）
    （出口）
    发射指令（emit）（IR_LABEL, -1, 循环出口标签, 0, 0, 0）
    弹出结构图（sg_pop）（）
    返回 -1

（—— Match 表达式：匹配表达式（EXPR_MATCH） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 匹配表达式（EXPR_MATCH），那么：
    令 匹配目标表达式 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 第一个分支节点 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 匹配值变量 = 生成表达式（gen_expr）（匹配目标表达式）
    令 匹配值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（匹配值变量）
    （分配 匹配（match） 表达式的结果变量）
    令 结果变量 = 新建 IR 变量（new_ir_var）（"match_res", 类型信息：整数（TI_INT））
    发射指令（emit）（IR_ALLOC, 结果变量, 0, 0, 0, 类型信息：整数（TI_INT））
    令 汇合标签 = 新建标签（new_label）（）
    令 当前分支节点 = 第一个分支节点
    循环：
        如果 当前分支节点 小于 0，那么：
            跳出循环
        令 分支模式节点 = 第一子节点访问器（ast_a）（ast_a）（当前分支节点）
        令 分支体节点 = 第二子节点访问器（ast_b）（ast_b）（当前分支节点）
        令 模式类别 = -1
        如果 分支模式节点 大于等于 0，那么：
            令 模式类别 = AST 访问器：类别（ast_kind）（分支模式节点）
        令 是否为通配符 = 0
        如果 模式类别 等于 通配模式（EXPR_WILDCARD），那么：
            令 是否为通配符 = 1
        令 分支体入口标签 = 新建标签（new_label）（）
        令 分支落点标签 = 汇合标签（默认落点为汇合标签）
        令 有下一分支 = 0
        如果 第三子节点访问器（ast_c）（ast_c）（当前分支节点） 大于等于 0，那么：
            令 有下一分支 = 1

        （通配符分支：无条件跳转到分支体）
        如果 是否为通配符 等于 1，那么：
            发射指令（emit）（IR_JUMP, -1, 分支体入口标签, 0, 0, 0）

        （枚举模式匹配：加载枚举标签并比较变体名索引）
        否则如果 模式类别 等于 枚举模式（EXPR_ENUMPAT），那么：
            令 变体名索引 = 获取变体名索引（get_variant_name_idx）（第一子节点访问器（ast_a）（分支模式节点））
            令 枚举标签变量 = 新建 IR 变量（new_ir_var）（TI_INT）
            发射指令（emit）（IR_LOAD_ENUM_TAG, 枚举标签变量, 匹配值变量, 0, 0, 0）
            令 变体标签常量 = 新建 IR 变量（new_ir_var）（TI_INT）
            发射指令（emit）（常量指令（IR_CONST）, 变体标签常量, 变体名索引, 0, 0, 类型信息：整数（TI_INT））
            令 比较结果变量 = 新建 IR 变量（new_ir_var）（TI_INT）
            发射指令（emit）（IR_BINARY, 比较结果变量, 枚举标签变量, 变体标签常量, 相等运算（OP_EQ）, 0）
            如果 有下一分支 等于 1，那么：
                令 分支落点标签 = 新建标签（new_label）（）（下一分支的比较入口）
            发射指令（emit）（IR_BRANCH, -1, 比较结果变量, 分支体入口标签, 分支落点标签, 0）

        （整数模式匹配）
        否则如果 模式类别 等于 整数字面量表达式（EXPR_INT），那么：
            令 模式值常量 = 新建 IR 变量（new_ir_var）（TI_INT）
            发射指令（emit）（常量指令（IR_CONST）, 模式值常量, AST 访问器：整数值（ast_int_val）（分支模式节点）, 0, 0, 类型信息：整数（TI_INT））
            令 比较结果变量 = 新建 IR 变量（new_ir_var）（TI_INT）
            发射指令（emit）（IR_BINARY, 比较结果变量, 匹配值变量, 模式值常量, 相等运算（OP_EQ）, 0）
            如果 有下一分支 等于 1，那么：
                令 分支落点标签 = 新建标签（new_label）（）
            发射指令（emit）（IR_BRANCH, -1, 比较结果变量, 分支体入口标签, 分支落点标签, 0）

        （布尔模式匹配）
        否则如果 模式类别 等于 布尔字面量表达式（EXPR_BOOL），那么：
            令 模式值常量 = 新建 IR 变量（new_ir_var）（TI_INT）
            令 布尔文本值 = 0
            如果 AST 访问器：整数值（ast_int_val）（分支模式节点） 不等于 0，那么：
                令 布尔文本值 = 1
            发射指令（emit）（常量指令（IR_CONST）, 模式值常量, 布尔文本值, 0, 0, 类型信息：整数（TI_INT））
            令 比较结果变量 = 新建 IR 变量（new_ir_var）（TI_INT）
            发射指令（emit）（IR_BINARY, 比较结果变量, 匹配值变量, 模式值常量, 相等运算（OP_EQ）, 0）
            如果 有下一分支 等于 1，那么：
                令 分支落点标签 = 新建标签（new_label）（）
            发射指令（emit）（IR_BRANCH, -1, 比较结果变量, 分支体入口标签, 分支落点标签, 0）

        （执行分支体）
        发射指令（emit）（IR_LABEL, -1, 分支体入口标签, 0, 0, 0）
        压入 IR 作用域（push_ir_scope）（）
        （枚举模式：将子值绑定为局部变量——从字段 +1 偏移开始读取，跳过标签字段）
        如果 模式类别 等于 枚举模式（EXPR_ENUMPAT），那么：
            令 子值数量 = 第三子节点访问器（ast_c）（ast_c）（分支模式节点）
            令 字段扫描位置 = 0
            循环：
                如果 字段扫描位置 大于等于 子值数量，那么：
                    跳出循环
                令 字段值变量 = 新建 IR 变量（new_ir_var）（TI_INT）
                发射指令（emit）（IR_LOAD_FIELD, 字段值变量, 匹配值变量, 0, 字段扫描位置 + 1, 0）（+1 为跳过标签字段偏移）
                令 子模式节点 = 第二子节点访问器（ast_b）（ast_b）（分支模式节点） + 字段扫描位置
                如果 子模式节点 大于等于 0 且 AST 访问器：类别（ast_kind）（子模式节点） 等于 标识符表达式（EXPR_IDENT），那么：
                    绑定局部变量（bind_local）（AST 访问器：整数值（ast_int_val）（子模式节点）, 字段值变量）
                令 字段扫描位置 = 字段扫描位置 + 1
        令 分支体结果变量 = 生成表达式（gen_expr）（分支体节点）
        令 分支体结果变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（分支体结果变量）
        如果 分支体结果变量 大于等于 0，那么：
            发射指令（emit）（存储指令（IR_STORE）, -1, 结果变量, 分支体结果变量, 0, 0）
        弹出 IR 作用域（pop_ir_scope）（）
        发射指令（emit）（IR_JUMP, -1, 汇合标签, 0, 0, 0）
        （非通配符分支且有下一分支时，在落点标签处发射 LABEL 供下一分支的条件跳转使用）
        如果 是否为通配符 等于 0，那么：
            如果 有下一分支 等于 1，那么：
                发射指令（emit）（IR_LABEL, -1, 分支落点标签, 0, 0, 0）
        令 当前分支节点 = 第三子节点访问器（ast_c）（ast_c）（当前分支节点）
    发射指令（emit）（IR_LABEL, -1, 汇合标签, 0, 0, 0）
    返回 结果变量

（—— Let 绑定：变量声明表达式（EXPR_LET） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 变量声明表达式（EXPR_LET），那么：
    令 变量名索引 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 类型标注节点 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 初始值节点 = 第三子节点访问器（ast_c）（ast_c）（节点）
    （检测动态类型变量：类型标注为 动态（dyn））
    令 是否为动态变量 = 0
    如果 类型标注节点 大于等于 0 且 AST 访问器：类别（ast_kind）（类型标注节点） 等于 0 且 AST 访问器：类型值（ast_type_val）（类型标注节点） 等于 类型信息：动态（TI_DYN），那么：
        令 是否为动态变量 = 1
    令 变量 = 新建 IR 变量（new_ir_var）（驻留字符串获取（istr_get）（变量名索引）, 类型信息：单元（TI_UNIT））
    （数组大小标注：[次数（N）]整数（int） 等——ast_kind 等于 19 表示带大小的数组类型标注，若标注大小且无初始值，预分配数组）
    令 是否为数组分配 = 0
    如果 类型标注节点 大于等于 0 且 初始值节点 小于 0，那么：
        如果 AST 访问器：类别（ast_kind）（类型标注节点） 等于 19，那么：
            令 数组大小 = AST 访问器：整数值（ast_int_val）（类型标注节点）
            如果 数组大小 大于 0，那么：
                发射指令（emit）（IR_ALLOC_ARRAY, 变量, 数组大小, 8, 0, 0）
                令 是否为数组分配 = 1
    （动态变量且有初始值时跳过分配——值在下文通过 动态打包指令（IR_DYN_PACK） 打包）
    如果 是否为动态变量 等于 0 或 初始值节点 小于 0，那么：
        如果 是否为数组分配 等于 0，那么：
            发射指令（emit）（IR_ALLOC, 变量, 0, 0, 0, 类型信息：单元（TI_UNIT））
    （存在初始值）
    如果 初始值节点 大于等于 0，那么：
        令 初始值变量 = 生成表达式（gen_expr）（初始值节点）
        令 初始值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（初始值变量）
        （动态变量：将值与类型标签打包为 动态打包指令（IR_DYN_PACK））
        如果 是否为动态变量 不等于 0，那么：
            令 动态变量 = 新建 IR 变量（new_ir_var）（TI_DYN）
            令 类型标签 = IR 变量访问器：类型（irv_type）（初始值变量）
            如果 类型标签 小于 0，那么：令 类型标签 = 类型信息：整数（TI_INT）
            发射指令（emit）（动态打包指令（IR_DYN_PACK）, 动态变量, 初始值变量, 类型标签, 0, 0）
            绑定局部变量（bind_local）（变量名索引, 动态变量）
            返回 动态变量
        （保留初始值类型，以便后续操作选择类型专用降级（concat））
        IR 变量访问器：设置类型（irv_set_type）（变量, IR 变量访问器：类型（irv_type）（初始值变量））
        发射指令（emit）（存储指令（IR_STORE）, -1, 变量, 初始值变量, 0, 0）
    绑定局部变量（bind_local）（变量名索引, 变量）
    返回 变量

（—— Yield：让出表达式（EXPR_YIELD） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 让出表达式（EXPR_YIELD），那么：
    令 产出值节点 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 产出值变量 = -1
    如果 产出值节点 大于等于 0，那么：
        令 产出值变量 = 生成表达式（gen_expr）（产出值节点）
        令 产出值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（产出值变量）
    发射指令（emit）（让出指令（IR_YIELD）, -1, 产出值变量, 0, 0, 0）
    返回 -1（让出（yield） 挂起执行——调用者无返回值）

（—— Await：等待表达式（EXPR_AWAIT） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 等待表达式（EXPR_AWAIT），那么：
    令 被等待值节点 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 被等待值变量 = 生成表达式（gen_expr）（被等待值节点）
    令 被等待值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（被等待值变量）
    令 等待结果变量 = 新建 IR 变量（new_ir_var）（"等待（await）", 类型信息：单元（TI_UNIT））
    发射指令（emit）（IR_AWAIT, 等待结果变量, 被等待值变量, 0, 0, 0）
    返回 等待结果变量

（—— Return：返回表达式（EXPR_RETURN） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 返回表达式（EXPR_RETURN），那么：
    如果 第一子节点访问器（ast_a）（ast_a）（节点） 大于等于 0，那么：
        令 返回值变量 = 生成表达式（gen_expr）（第一子节点访问器（ast_a）（节点））
        令 返回值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（返回值变量）
        发射指令（emit）（返回指令（IR_RETURN）, -1, 返回值变量, 0, 0, 0）
    否则：
        发射指令（emit）（返回指令（IR_RETURN）, -1, -1, 0, 0, 0）（无返回值）
    返回 -1

（—— 字段访问：字段访问表达式（EXPR_FIELD） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 字段访问表达式（EXPR_FIELD），那么：
    令 对象变量 = 生成表达式（gen_expr）（第一子节点访问器（ast_a）（节点））
    令 对象变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（对象变量）
    令 字段结果变量 = 新建 IR 变量（new_ir_var）（"field", 类型信息：整数（TI_INT））
    令 字段索引值 = AST 访问器：类型值（ast_type_val）（节点）
    如果 字段索引值 大于 0，那么：
        令 字段索引值 = 字段索引值 - 1（数字元组索引——解析器（parser） 存储时加了 1）
    否则：
        令 字段索引值 = AST 访问器：数据（ast_data）（节点）（结构体字段索引——由 类型检查器（checker） 设置）
    发射指令（emit）（IR_LOAD_FIELD, 字段结果变量, 对象变量, 0, 字段索引值, 0）
    返回 字段结果变量

（—— 下标访问：下标访问表达式（EXPR_INDEX） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 下标访问表达式（EXPR_INDEX），那么：
    令 数组变量 = 生成表达式（gen_expr）（第一子节点访问器（ast_a）（节点））
    令 数组变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（数组变量）
    令 下标节点 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 下标节点类别 = AST 访问器：类别（ast_kind）（下标节点）
    （Range 下标：数组（arr）[low..high] -> 切片，指向 数组[low] 的指针）
    如果 下标节点类别 等于 范围表达式（EXPR_RANGE），那么：
        令 低下标节点 = 第一子节点访问器（ast_a）（ast_a）（下标节点）
        令 高下标节点 = 第二子节点访问器（ast_b）（ast_b）（下标节点）
        令 低下标变量 = 生成表达式（gen_expr）（低下标节点）
        令 低下标变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（低下标变量）
        令 高下标变量 = 生成表达式（gen_expr）（高下标节点）
        令 高下标变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（高下标变量）
        令 切片结果变量 = 新建 IR 变量（new_ir_var）（"slice", 类型信息：整数（TI_INT））
        发射指令（emit）（IR_SLICE, 切片结果变量, 数组变量, 低下标变量, 高下标变量, 0）
        返回 切片结果变量
    令 元素结果变量 = 新建 IR 变量（new_ir_var）（TI_INT）
    （常量下标：检查数组访问前处理——若 pass_before_array_access 返回非零则不发射加载指令）
    如果 下标节点类别 等于 整数字面量表达式（EXPR_INT），那么：
        如果 数组访问前处理（pass_before_array_access）（数组变量, -1, AST 访问器：整数值（ast_int_val）（下标节点）, -1） 等于 0，那么：
            发射指令（emit）（IR_LOAD_INDEX, 元素结果变量, 数组变量, 0, AST 访问器：整数值（ast_int_val）（下标节点）, 0）
    （变量下标）
    否则：
        令 下标变量 = 生成表达式（gen_expr）（下标节点）
        令 下标变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（下标变量）
        如果 数组访问前处理（pass_before_array_access）（数组变量, 下标变量, -1, -1） 等于 0，那么：
            发射指令（emit）（IR_LOAD_INDEX_VAR, 元素结果变量, 数组变量, 下标变量, 0, 0）
    返回 元素结果变量

（—— 枚举构造：枚举构造表达式（EXPR_ENUM_CONSTRUCTOR） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 枚举构造表达式（EXPR_ENUM_CONSTRUCTOR），那么：
    令 枚举名索引 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 枚举变量 = 新建 IR 变量（new_ir_var）（"枚举（enum）", 类型信息：单元（TI_UNIT））
    发射指令（emit）（IR_MAKE_ENUM, 枚举变量, 枚举名索引, 第三子节点访问器（ast_c）（节点）, 0, 0）
    令 参数索引 = 0
    令 参数链节点 = 第二子节点访问器（ast_b）（ast_b）（节点）（参数表达式（EXPR_ARG） 链）
    循环：
        如果 参数链节点 小于 0，那么：
            跳出循环
        令 参数值变量 = 生成表达式（gen_expr）（第一子节点访问器（ast_a）（参数链节点））
        令 参数值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（参数值变量）
        发射指令（emit）（IR_STORE_FIELD, -1, 枚举变量, 参数值变量, 参数索引 + 1, 0）（+1 为跳过标签字段偏移）
        令 参数链节点 = 第二子节点访问器（ast_b）（ast_b）（参数链节点）
        令 参数索引 = 参数索引 + 1
    返回 枚举变量

（—— 结构体字面量：结构构造表达式（EXPR_STRUCT） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 结构构造表达式（EXPR_STRUCT），那么：
    令 结构体名索引 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 结构体变量 = 新建 IR 变量（new_ir_var）（"结构（struct）", 类型信息：单元（TI_UNIT））
    发射指令（emit）（IR_ALLOC_STRUCT, 结构体变量, 0, 0, 结构体名索引, 0）
    令 字段索引 = 0
    令 字段节点序列 = 第二子节点访问器（ast_b）（ast_b）（节点）
    循环：
        如果 字段索引 大于等于 第三子节点访问器（ast_c）（ast_c）（节点），那么：
            跳出循环
        如果 字段节点序列 大于等于 0，那么：
            （字段节点为包装节点：ast_kind=0, 变量甲（a）=值表达式）
            令 字段值变量 = 生成表达式（gen_expr）（字段节点序列）
            令 字段值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（字段值变量）
            发射指令（emit）（IR_STORE_FIELD, -1, 结构体变量, 字段值变量, 字段索引, 0）
            令 字段节点序列 = 字段节点序列 + 1
        令 字段索引 = 字段索引 + 1
    返回 结构体变量

（—— 数组字面量：数组表达式（EXPR_ARRAY） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 数组表达式（EXPR_ARRAY），那么：
    令 数组结果变量 = 新建 IR 变量（new_ir_var）（"数组（arr）", 类型信息：单元（TI_UNIT））
    发射指令（emit）（IR_ALLOC_ARRAY, 数组结果变量, 第二子节点访问器（ast_b）（节点）, 0, 0, 0）
    令 元素索引 = 0
    令 元素节点序列 = 第一子节点访问器（ast_a）（ast_a）（节点）
    循环：
        如果 元素索引 大于等于 第二子节点访问器（ast_b）（ast_b）（节点），那么：
            跳出循环
        如果 元素节点序列 大于等于 0，那么：
            令 元素值变量 = 生成表达式（gen_expr）（元素节点序列）
            令 元素值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（元素值变量）
            发射指令（emit）（存储索引指令（IR_STORE_INDEX）, -1, 数组结果变量, 元素值变量, 元素索引, 0）
            令 元素节点序列 = 元素节点序列 + 1
        令 元素索引 = 元素索引 + 1
    返回 数组结果变量

（—— Range 表达式：范围表达式（EXPR_RANGE） ——）
（求值两端，返回结束值变量）

如果 AST 访问器：类别（ast_kind）（节点） 等于 范围表达式（EXPR_RANGE），那么：
    令 起始变量 = 生成表达式（gen_expr）（第一子节点访问器（ast_a）（节点））
    令 起始变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（起始变量）
    令 结束变量 = 生成表达式（gen_expr）（第二子节点访问器（ast_b）（节点））
    令 结束变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（结束变量）
    返回 结束变量

（—— Break / Continue ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 跳出表达式（EXPR_BREAK），那么：
    如果 IR 循环嵌套深度（g_ir_loop_depth） 大于 0，那么：
        令 出口标签 = 从 IR 循环出口标签栈（g_ir_loop_exit）偏移（（IR 循环嵌套深度 - 1） * 8）处读取 64 位
        发射指令（emit）（IR_JUMP, -1, 出口标签, 0, 0, 0）
    返回 -1

如果 AST 访问器：类别（ast_kind）（节点） 等于 继续表达式（EXPR_CONTINUE），那么：
    如果 IR 循环嵌套深度（g_ir_loop_depth） 大于 0，那么：
        令 头部标签 = 从 IR 循环头标签栈（g_ir_loop_header）偏移（（IR 循环嵌套深度 - 1） * 8）处读取 64 位
        发射指令（emit）（IR_JUMP, -1, 头部标签, 0, 0, 0）
    返回 -1

（—— 其他表达式 ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 通配模式（EXPR_WILDCARD），那么：返回 -1
如果 AST 访问器：类别（ast_kind）（节点） 等于 枚举模式（EXPR_ENUMPAT），那么：返回 -1（仅作为模式使用，不单独生成 IR）

如果 AST 访问器：类别（ast_kind）（节点） 等于 移动表达式（EXPR_MOVE），那么：
    返回 生成表达式（gen_expr）（第一子节点访问器（ast_a）（节点））（move 仅转移所有权，不生成额外 IR）

（—— Unsafe 块：非安全块表达式（EXPR_UNSAFE） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 非安全块表达式（EXPR_UNSAFE），那么：
    压入 SG 分配槽（sg_alloc_push）（SG_UNSAFE）
    令 竞技场变量 = 新建 IR 变量（new_ir_var）（"_arena", 类型信息：整数（TI_INT））
    在 SG 竞技场变量数组 偏移（（结构图计数（g_sg_count） - 1） * 8）处写入 64 位值：竞技场变量
    发射指令（emit）（IR_ARENA_NEW, 竞技场变量, 0, 0, 0, 0）
    令 竞技场指令索引 = IR 指令总数（g_ir_instr_count） - 1
    令 内部返回值 = 生成表达式（gen_expr）（第一子节点访问器（ast_a）（节点））
    令 累计分配量 = 从 SG 分配槽总数 偏移（结构图计数 - 1）处读取 64 位
    如果 累计分配量 大于 0，那么：
        IR 指令访问器：设置操作数1（iri_set_s1）（竞技场指令索引, 累计分配量）
    弹出 SG 分配槽（sg_alloc_pop）（）（含 IR_ARENA_RESET）
    返回 内部返回值

（—— As 转换：类型转换表达式（EXPR_AS） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 类型转换表达式（EXPR_AS），那么：
    （类型转换：发射内部表达式，结果类型由 类型检查器（checker） 处理）
    返回 生成表达式（gen_expr）（第一子节点访问器（ast_a）（节点））

（—— Try：尝试表达式（EXPR_TRY） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 尝试表达式（EXPR_TRY），那么：
    （Try：解包 结果类型（Result）/可选类型（Option），暂时直接发射内部表达式）
    返回 生成表达式（gen_expr）（第一子节点访问器（ast_a）（节点））

如果 AST 访问器：类别（ast_kind）（节点） 等于 结构模式（EXPR_STRUCTPAT），那么：返回 -1

（—— 语句表达式：语句表达式（EXPR_STMT） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 语句表达式（EXPR_STMT），那么：
    生成表达式（gen_expr）（第一子节点访问器（ast_a）（节点））
    返回 -1

（—— 元组：元组表达式（EXPR_TUPLE） ——）

如果 AST 访问器：类别（ast_kind）（节点） 等于 元组表达式（EXPR_TUPLE），那么：
    令 首个元素AST索引 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 元素个数 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 元组结果变量 = 新建 IR 变量（new_ir_var）（"tuple", 类型信息：整数（TI_INT））
    发射指令（emit）（IR_ALLOC_ARRAY, 元组结果变量, 元素个数, 0, 8, 0）（分配 次数（N） * 8 字节，元素大小 8 字节）
    （按偏移量存储每个元素）
    令 元素位置 = 0
    循环：
        如果 元素位置 大于等于 元素个数，那么：
            跳出循环
        令 元素值变量 = 生成表达式（gen_expr）（首个元素AST索引 + 元素位置）
        令 元素值变量 = 强制 如果（if）-那么（then） 块（force_if_thunk）（元素值变量）
        发射指令（emit）（IR_STORE_FIELD, -1, 元组结果变量, 元素值变量, 元素位置, 0）
        令 元素位置 = 元素位置 + 1
    返回 元组结果变量

（—— 所有其他未匹配的 AST 类别 ——）
返回 -1

---

## 函数 IR 生成函数（ir_gen_func）

### 作用
为单个函数生成完整的 IR 指令序列：跳过泛型函数（将在调用处单态化），记录函数元数据（名字、返回类型、指令起始位置、变量起始位置、参数数量），创建参数 IR 变量并按 参数表达式（EXPR_PARAM） 节点遍历绑定，跳过中间类型节点，初始化函数级竞技场，生成函数体 IR，修补竞技场大小并添加末尾返回指令，写回函数指令数和变量数统计信息。

### 逻辑
接收 函数索引（fi）：整数
（跳过泛型函数——将在调用处单态化）
如果 函数信息访问器：泛型计数（fi_generic_count）（函数索引） 大于 0，那么：
    返回

令 函数AST节点 = 函数信息访问器：AST 数组（ast）节点（fi_ast_node）（函数索引）
令 函数名索引 = 第一子节点访问器（ast_a）（ast_a）（函数AST节点）
令 第一个参数节点 = 第二子节点访问器（ast_b）（ast_b）（函数AST节点）
令 参数总数 = 第三子节点访问器（ast_c）（ast_c）（函数AST节点）
令 返回类型IR索引 = AST 访问器：类型值（ast_type_val）（函数AST节点）
令 函数体节点 = AST 访问器：数据（ast_data）（函数AST节点）

（记录函数元数据）
令 函数元数据索引 = IR 函数个数（g_ir_func_count）
扩展 IR 函数元数据数组（grow_ir_func_meta）（函数元数据索引 + 1）
在 IR 函数名索引数组（g_ir_func_name_idx）偏移（函数元数据索引 * 8）处写入 64 位值：函数名索引
在 IR 函数返回类型数组（g_ir_func_ret_type）偏移（函数元数据索引 * 8）处写入 64 位值：返回类型IR索引
在 IR 函数指令起始索引数组（g_ir_func_instr_start）偏移（函数元数据索引 * 8）处写入 64 位值：IR 指令总数（g_ir_instr_count）
在 IR 函数变量起始索引数组（g_ir_func_var_start）偏移（函数元数据索引 * 8）处写入 64 位值：IR 变量总数（g_ir_var_count）
在 IR 函数参数计数数组（g_ir_func_param_count）偏移（函数元数据索引 * 8）处写入 64 位值：参数总数

（为参数创建 IR 变量）
令 参数索引 = 0
令 当前参数节点 = 第一个参数节点
循环：
    如果 参数索引 大于等于 参数总数，那么：
        跳出循环
    如果 当前参数节点 小于 0，那么：
        跳出循环
    令 参数名索引 = 第一子节点访问器（ast_a）（ast_a）（当前参数节点）
    令 参数名字符串 = 驻留字符串获取（istr_get）（参数名索引）
    令 参数IR类型 = AST 访问器：类型值（ast_type_val）（当前参数节点）
    如果 参数IR类型 小于 0，那么：令 参数IR类型 = 类型信息：整数（TI_INT）
    令 参数IR变量 = 新建 IR 变量（new_ir_var）（参数名字符串, 参数IR类型）
    （绑定参数名到局部变量表）
    绑定局部变量（bind_local）（参数名索引, 参数IR变量）
    令 参数索引 = 参数索引 + 1
    （扫描跳过类型节点，定位到下一个 参数表达式（EXPR_PARAM））
    令 当前参数节点 = 当前参数节点 + 1
    循环：
        如果 当前参数节点 大于等于 AST 节点计数（g_ast_count），那么：
            跳出循环
        如果 AST 访问器：类别（ast_kind）（当前参数节点） 等于 参数表达式（EXPR_PARAM），那么：
            跳出循环
        令 当前参数节点 = 当前参数节点 + 1

（函数级竞技场——HDFG：开始函数（df_begin_func） 已压入 SG_FUNC）
扩展 SG 分配数组（grow_sg_alloc）（结构图计数（g_sg_count） + 1）
扩展 SG 竞技场变量数组（grow_sg_arena_var）（结构图计数 + 1）
在 SG 分配槽总数（g_sg_alloc_total）偏移（（结构图计数 - 1） * 8）处写入 64 位值：0
令 函数竞技场变量 = 新建 IR 变量（new_ir_var）（"_arena", 类型信息：整数（TI_INT））
在 SG 竞技场变量数组 偏移（（结构图计数 - 1） * 8）处写入 64 位值：函数竞技场变量
发射指令（emit）（IR_ARENA_NEW, 函数竞技场变量, 0, 0, 0, 0）
令 竞技场指令索引 = IR 指令总数 - 1

（生成函数体）
如果 函数体节点 大于等于 0，那么：
    生成表达式（gen_expr）（函数体节点）

（修补竞技场大小并在返回前重置）
令 函数累计分配量 = 从 SG 分配槽总数 偏移（（结构图计数 - 1） * 8）处读取 64 位
如果 函数累计分配量 大于 0，那么：
    IR 指令访问器：设置操作数1（iri_set_s1）（竞技场指令索引, 函数累计分配量）
发射指令（emit）（IR_ARENA_RESET, -1, 函数竞技场变量, 0, 0, 0）

（return）
发射指令（emit）（返回指令（IR_RETURN）, -1, -1, 0, 0, 0）

（写回函数统计信息）
在 IR 函数指令计数数组（g_ir_func_instr_count）偏移（函数元数据索引 * 8）处写入 64 位值：IR 指令总数 - 从 IR 函数指令起始索引数组 偏移（函数元数据索引 * 8）处读取的 64 位值
在 IR 函数变量计数数组（g_ir_func_var_count）偏移（函数元数据索引 * 8）处写入 64 位值：IR 变量总数 - 从 IR 函数变量起始索引数组 偏移（函数元数据索引 * 8）处读取的 64 位值
令 IR 函数个数 = 函数元数据索引 + 1

### 测试要点
1. 泛型函数（泛型参数数大于 0）跳过 IR 生成
2. 参数变量按 参数表达式（EXPR_PARAM） 节点遍历并绑定，跳过中间的类型节点（ast_kind 不等于 参数表达式 的节点）
3. 函数级竞技场在函数体开始前初始化（IR_ARENA_NEW），结束后重置（IR_ARENA_RESET）
4. 函数体为空（body 小于 0）时跳过生成，但仍发射末尾 返回指令（IR_RETURN）
5. 末尾始终添加 返回指令（IR_RETURN） 指令（return）
6. 函数指令数和变量数正确地写回元数据（使用差值计算）

---

## 函数 全局变量初始值（global_init_val）

### 作用
提取文件级 令（let） 声明的编译时常量初始值。仅处理整数（EXPR_INT）、布尔（EXPR_BOOL）及负号一元运算（UOP_NEG）折叠，返回整数值。0 表示无常量初始值（BSS 零初始化）。应用于可变和不可变 令（启动时均需写入初始值），与 查找全局常量节点（find_global_const_node）不同——后者仅折叠不可变常量。

### 逻辑
接收 名字索引（name_idx）：整数
令 扫描位置 = 全局声明计数（g_global_let_count） - 1
循环：
    如果 扫描位置 小于 0，那么：
        跳出循环
    令 当前声明节点 = 从 全局声明数组（g_global_lets）偏移（扫描位置 * 8）处读取 64 位
    如果 第一子节点访问器（ast_a）（ast_a）（当前声明节点） 等于 名字索引，那么：
        令 值节点 = 第三子节点访问器（ast_c）（ast_c）（当前声明节点）
        如果 值节点 大于等于 0，那么：
            令 值类别 = AST 访问器：类别（ast_kind）（值节点）
            如果 值类别 等于 整数字面量表达式（EXPR_INT） 或 值类别 等于 布尔字面量表达式（EXPR_BOOL），那么：
                返回 AST 访问器：整数值（ast_int_val）（值节点）
            如果 值类别 等于 一元运算表达式（EXPR_UNARY） 且 第三子节点访问器（ast_c）（ast_c）（值节点） 等于 取负运算（UOP_NEG），那么：
                令 内部节点 = 第一子节点访问器（ast_a）（ast_a）（值节点）
                如果 AST 访问器：类别（ast_kind）（内部节点） 等于 整数字面量表达式（EXPR_INT） 或 等于 布尔字面量表达式（EXPR_BOOL），那么：
                    返回 0 - AST 访问器：整数值（ast_int_val）（内部节点）
    令 扫描位置 = 扫描位置 - 1
返回 0

### 测试要点
1. 找到整数/布尔初始值时返回对应整数值
2. 负号一元运算折叠为负数值（0 - 内部值）
3. 未找到或值不是编译时常量时返回 0（BSS 零初始化）
4. 应用于可变和不可变 令（let）（与 find_global_const_node 的区分：后者仅处理不可变常量）

---

## 函数 注册单个全局变量（reg_one_global）

### 作用
按名字索引注册一个 IR 全局变量，去重：若已存在则跳过，否则创建新 IR 变量并记录到全局变量表（g_ir_globals）（名字索引、变量索引、常量初始值三项，每条记录 24 字节）。常量初始值由 ELF 后端的 初始化全局变量（_init_globals） 发射。

### 逻辑
接收 名字索引（name_idx）：整数
（去重检查）
令 是否已存在 = 0
令 扫描位置 = 0
循环：
    如果 扫描位置 大于等于 IR 全局变量计数（g_ir_global_count），那么：
        跳出循环
    如果 从 全局变量表（g_ir_globals）偏移（扫描位置 * 24）处读取的 64 位值 等于 名字索引，那么：
        令 是否已存在 = 1
        跳出循环
    令 扫描位置 = 扫描位置 + 1

（不存在则创建）
如果 是否已存在 等于 0，那么：
    令 变量名字符串 = 驻留字符串获取（istr_get）（名字索引）
    令 新全局变量 = 新建 IR 变量（new_ir_var）（TI_INT）
    扩展 IR 全局变量数组（grow_ir_globals）（IR 全局变量计数 + 1）
    在 全局变量表 偏移（IR 全局变量计数 * 24）处写入 64 位值：名字索引
    在 全局变量表 偏移（IR 全局变量计数 * 24 + 8）处写入 64 位值：新全局变量
    （常量初始值——由 ELF 后端的 初始化全局变量（_init_globals） 发射）
    在 全局变量表 偏移（IR 全局变量计数 * 24 + 16）处写入 64 位值：全局变量初始值（global_init_val）（名字索引）
    令 IR 全局变量计数 = IR 全局变量计数 + 1

### 测试要点
1. 同名字索引多次调用只注册一次（去重）
2. 每条全局记录占 24 字节（名字索引 + 变量索引 + 初始值）
3. 初始值由 全局变量初始值（global_init_val） 提供，未找到常量时写入 0

---

## 函数 IR 生成全局变量（ir_gen_globals）

### 作用
将 解析器（parser） 收集的所有文件级 令（let） 声明（存储在 全局声明数组（g_global_lets）中）注册为 IR 全局变量，同时手动补充 解析器 未自动检测到的编译器自身全局变量（如 SG 竞技场跟踪、HDFG（CIR） 写缓冲、运行时堆/arena 全局等），确保 ELF 后端 BSS 段中有对应空间。

### 逻辑
（遍历 解析器（parser） 收集的文件级声明——仅 全局声明数组 中的记录，不扫描 变量声明表达式（EXPR_LET））
令 扫描位置 = 0
循环：
    如果 扫描位置 大于等于 全局声明计数（g_global_let_count），那么：
        跳出循环
    令 当前声明节点 = 从 全局声明数组 偏移（扫描位置 * 8）处读取 64 位
    注册单个全局变量（reg_one_global）（第一子节点访问器（ast_a）（当前声明节点））
    令 扫描位置 = 扫描位置 + 1

（手动注册 ir_gen.cr 自身的全局变量——解析器（parser） 的文件级声明自动检测已知遗漏部分，详见 CLAUDE.md Known Issues）
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_sg_alloc_total"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_sg_alloc_cap"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_sg_arena_var"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_sg_arena_var_cap"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_ir_source_hash"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_ir_source_hash_ready"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_cir_write_buf"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_cir_write_pos"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_cir_write_cap"））
（运行时全局变量——emit_alloc_body 和 emit_start 需要，每个程序 BSS 中必须存在，即使不含 rt.cr）
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_heap_ptr"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_heap_end"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_current_arena"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_arena_cursors"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_arena_sizes"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_arena_parents"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_arena_max_size"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_arena_count"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_arena_cap"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_arena_pool_data"））
注册单个全局变量（reg_one_global）（字符串驻留（str_intern）（"g_arena_free_list"））

### 测试要点
1. 文件级声明的全局变量通过 全局声明数组 遍历注册
2. 手动补充的全局变量列表涵盖了 SG/HDFG（CIR）/运行时核心变量
3. 重复注册（如已在 全局声明数组 中 + 手动）被 注册单个全局变量 的去重逻辑处理
4. 运行时全局变量确保每个可执行文件都有 BSS 空间

---

## 函数 AST 修补节点（ast_patch_node）

### 作用
递归遍历 AST，将方法调用（调用表达式（EXPR_CALL） 中的 字段访问表达式（EXPR_FIELD））名中匹配指定前缀（subst_from）的部分替换为新的前缀（subst_to）。用于单态化（monomorphization）时，将泛型参数名替换为具体类型名，生成新的具体函数体 AST。匹配规则：前缀完全相等，或前缀后紧跟点号 '.'（ASCII 46）。

### 逻辑
接收 节点（node）：整数，替换源前缀（subst_from）：字符串，替换目标前缀（subst_to）：字符串
如果 节点 小于 0，那么：返回

令 节点类别 = AST 访问器：类别（ast_kind）（节点）

（处理 调用表达式（EXPR_CALL） 中 字段访问表达式（EXPR_FIELD） 的方法调用名替换）
如果 节点类别 等于 调用表达式（EXPR_CALL），那么：
    令 被调用函数节点 = 第一子节点访问器（ast_a）（ast_a）（节点）
    如果 AST 访问器：类别（ast_kind）（被调用函数节点） 等于 字段访问表达式（EXPR_FIELD），那么：
        令 方法名驻留索引 = AST 访问器：数据（ast_data）（节点）
        如果 方法名驻留索引 大于等于 0，那么：
            令 方法名字符串 = 驻留字符串获取（istr_get）（方法名驻留索引）
            令 方法名长度 = 字符串长度（str_len）（方法名字符串）
            令 源前缀长度 = 字符串长度（str_len）（替换源前缀）
            如果 方法名长度 大于等于 源前缀长度，那么：
                令 前缀匹配 = 1
                令 字符扫描位置 = 0
                循环：
                    如果 字符扫描位置 大于等于 源前缀长度，那么：
                        跳出循环
                    如果 字符串按字节读取（str_load8）（方法名字符串, 字符扫描位置） 不等于 字符串按字节读取（str_load8）（替换源前缀, 字符扫描位置），那么：
                        令 前缀匹配 = 0
                        跳出循环
                    令 字符扫描位置 = 字符扫描位置 + 1
                如果 前缀匹配 不等于 0 且（方法名长度 等于 源前缀长度 或 字符串按字节读取（str_load8）（方法名字符串, 源前缀长度） 等于 46——即 '.' 的 ASCII 码），那么：
                    令 剩余部分 = 字符串切片（str_sub）（方法名字符串, 源前缀长度, 方法名长度 - 源前缀长度）
                    令 新方法名 = 替换目标前缀 + 剩余部分
                    AST 访问器：设置数据（ast_set_data）（节点, 字符串驻留（str_intern）（新方法名））

（根据节点类别递归处理子节点——以下按源码分支逐项覆盖）

（代码块表达式（EXPR_BLOCK）：遍历 g_block_stmts 中的语句）
如果 节点类别 等于 代码块表达式（EXPR_BLOCK），那么：
    令 语句起始位置 = 第一子节点访问器（ast_a）（ast_a）（节点）
    令 语句数量 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 语句扫描位置 = 0
    循环：
        如果 语句扫描位置 大于等于 语句数量，那么：
            跳出循环
        令 语句节点 = 从 代码块语句数组（g_block_stmts）偏移（（语句起始位置 + 语句扫描位置） * 8）处读取 64 位
        AST 修补节点（ast_patch_node）（语句节点, 替换源前缀, 替换目标前缀）
        令 语句扫描位置 = 语句扫描位置 + 1

（条件表达式（EXPR_IF）/无限循环表达式（EXPR_LOOP）/条件循环表达式（EXPR_WHILE）/非安全块表达式（EXPR_UNSAFE）：递归处理条件、那么（then）、否则（else））
否则如果 节点类别 等于 条件表达式（EXPR_IF） 或 等于 无限循环表达式（EXPR_LOOP） 或 等于 条件循环表达式（EXPR_WHILE） 或 等于 非安全块表达式（EXPR_UNSAFE），那么：
    如果 第一子节点访问器（ast_a）（ast_a）（节点） 大于等于 0，那么：
        AST 修补节点（ast_patch_node）（第一子节点访问器（ast_a）（节点）, 替换源前缀, 替换目标前缀）
    如果 节点类别 等于 条件表达式（EXPR_IF），那么：
        如果 第二子节点访问器（ast_b）（ast_b）（节点） 大于等于 0，那么：
            AST 修补节点（ast_patch_node）（第二子节点访问器（ast_b）（节点）, 替换源前缀, 替换目标前缀）
        如果 第三子节点访问器（ast_c）（ast_c）（节点） 大于等于 0，那么：
            AST 修补节点（ast_patch_node）（第三子节点访问器（ast_c）（节点）, 替换源前缀, 替换目标前缀）

（二元运算表达式（EXPR_BINARY）/赋值表达式（EXPR_ASSIGN）/范围表达式（EXPR_RANGE）/类型转换表达式（EXPR_AS）：递归处理左右操作数）
否则如果 节点类别 等于 二元运算表达式（EXPR_BINARY） 或 等于 赋值表达式（EXPR_ASSIGN） 或 等于 范围表达式（EXPR_RANGE） 或 等于 类型转换表达式（EXPR_AS），那么：
    如果 第一子节点访问器（ast_a）（ast_a）（节点） 大于等于 0，那么：
        AST 修补节点（ast_patch_node）（第一子节点访问器（ast_a）（节点）, 替换源前缀, 替换目标前缀）
    如果 第二子节点访问器（ast_b）（ast_b）（节点） 大于等于 0，那么：
        AST 修补节点（ast_patch_node）（第二子节点访问器（ast_b）（节点）, 替换源前缀, 替换目标前缀）

（调用表达式（EXPR_CALL）/枚举构造表达式（EXPR_ENUM_CONSTRUCTOR）：递归处理函数节点和参数链）
否则如果 节点类别 等于 调用表达式（EXPR_CALL） 或 等于 枚举构造表达式（EXPR_ENUM_CONSTRUCTOR），那么：
    如果 第一子节点访问器（ast_a）（ast_a）（节点） 大于等于 0，那么：
        AST 修补节点（ast_patch_node）（第一子节点访问器（ast_a）（节点）, 替换源前缀, 替换目标前缀）
    令 参数链 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 参数个数 = 第三子节点访问器（ast_c）（ast_c）（节点）
    令 参数扫描位置 = 0
    循环：
        如果 参数扫描位置 大于等于 参数个数，那么：
            跳出循环
        如果 参数链 大于等于 0，那么：
            AST 修补节点（ast_patch_node）（参数链, 替换源前缀, 替换目标前缀）
            令 参数链 = 参数链 + 1
        令 参数扫描位置 = 参数扫描位置 + 1

（匹配表达式（EXPR_MATCH）：递归处理匹配目标和各分支的模式/体）
否则如果 节点类别 等于 匹配表达式（EXPR_MATCH），那么：
    如果 第一子节点访问器（ast_a）（ast_a）（节点） 大于等于 0，那么：
        AST 修补节点（ast_patch_node）（第一子节点访问器（ast_a）（节点）, 替换源前缀, 替换目标前缀）
    令 分支链 = 第二子节点访问器（ast_b）（ast_b）（节点）
    循环：
        如果 分支链 小于 0，那么：
            跳出循环
        如果 第一子节点访问器（ast_a）（ast_a）（分支链） 大于等于 0，那么：
            AST 修补节点（ast_patch_node）（第一子节点访问器（ast_a）（分支链）, 替换源前缀, 替换目标前缀）
        如果 第二子节点访问器（ast_b）（ast_b）（分支链） 大于等于 0，那么：
            AST 修补节点（ast_patch_node）（第二子节点访问器（ast_b）（分支链）, 替换源前缀, 替换目标前缀）
        令 分支链 = 第三子节点访问器（ast_c）（ast_c）（分支链）

（遍历循环表达式（EXPR_FOR）：递归处理迭代器和循环体）
否则如果 节点类别 等于 遍历循环表达式（EXPR_FOR），那么：
    如果 第二子节点访问器（ast_b）（ast_b）（节点） 大于等于 0，那么：
        AST 修补节点（ast_patch_node）（第二子节点访问器（ast_b）（节点）, 替换源前缀, 替换目标前缀）
    如果 第三子节点访问器（ast_c）（ast_c）（节点） 大于等于 0，那么：
        AST 修补节点（ast_patch_node）（第三子节点访问器（ast_c）（节点）, 替换源前缀, 替换目标前缀）

（变量声明表达式（EXPR_LET）：递归处理初始值）
否则如果 节点类别 等于 变量声明表达式（EXPR_LET），那么：
    如果 第三子节点访问器（ast_c）（ast_c）（节点） 大于等于 0，那么：
        AST 修补节点（ast_patch_node）（第三子节点访问器（ast_c）（节点）, 替换源前缀, 替换目标前缀）

（语句表达式（EXPR_STMT）：递归处理语句）
否则如果 节点类别 等于 语句表达式（EXPR_STMT），那么：
    如果 第一子节点访问器（ast_a）（ast_a）（节点） 大于等于 0，那么：
        AST 修补节点（ast_patch_node）（第一子节点访问器（ast_a）（节点）, 替换源前缀, 替换目标前缀）

（结构构造表达式（EXPR_STRUCT）：递归处理字段值）
否则如果 节点类别 等于 结构构造表达式（EXPR_STRUCT），那么：
    令 字段链 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 字段个数 = 第三子节点访问器（ast_c）（ast_c）（节点）
    令 字段扫描位置 = 0
    循环：
        如果 字段扫描位置 大于等于 字段个数，那么：
            跳出循环
        如果 字段链 大于等于 0，那么：
            AST 修补节点（ast_patch_node）（字段链, 替换源前缀, 替换目标前缀）
            令 字段链 = 字段链 + 1
        令 字段扫描位置 = 字段扫描位置 + 1

（数组表达式（EXPR_ARRAY）/元组表达式（EXPR_TUPLE）：递归处理元素）
否则如果 节点类别 等于 数组表达式（EXPR_ARRAY） 或 等于 元组表达式（EXPR_TUPLE），那么：
    令 元素链 = 第二子节点访问器（ast_b）（ast_b）（节点）
    令 元素个数 = 第三子节点访问器（ast_c）（ast_c）（节点）
    令 元素扫描位置 = 0
    循环：
        如果 元素扫描位置 大于等于 元素个数，那么：
            跳出循环
        如果 元素链 大于等于 0，那么：
            AST 修补节点（ast_patch_node）（元素链, 替换源前缀, 替换目标前缀）
            令 元素链 = 元素链 + 1
        令 元素扫描位置 = 元素扫描位置 + 1

（字段访问表达式（EXPR_FIELD）/下标访问表达式（EXPR_INDEX）/一元运算表达式（EXPR_UNARY）/返回表达式（EXPR_RETURN）/尝试表达式（EXPR_TRY）/移动表达式（EXPR_MOVE）：递归处理第一个子节点）
否则如果 节点类别 等于 字段访问表达式（EXPR_FIELD） 或 等于 下标访问表达式（EXPR_INDEX） 或 等于 一元运算表达式（EXPR_UNARY） 或 等于 返回表达式（EXPR_RETURN） 或 等于 尝试表达式（EXPR_TRY） 或 等于 移动表达式（EXPR_MOVE），那么：
    如果 第一子节点访问器（ast_a）（ast_a）（节点） 大于等于 0，那么：
        AST 修补节点（ast_patch_node）（第一子节点访问器（ast_a）（节点）, 替换源前缀, 替换目标前缀）

### 测试要点
1. 方法调用名中前缀匹配时替换为新前缀，后缀部分保留
2. 点号（.）作为前缀分隔符：完全相等或后跟点号时触发替换
3. 递归遍历覆盖所有 AST 节点类别（共 12 个 否则（else）-如果（if） 分支）
4. 无效节点（小于 0）立即返回
5. 各节点类别的子节点遍历策略正确——不影响未使用的槽位

---

## 函数 查找或创建单态化函数（find_or_create_mono_func）

### 作用
为泛型函数在给定调用点创建单态化（具体类型实例化）版本。拼装混淆名（funcname$GenericName.ConcreteType），复制 参数表达式（EXPR_PARAM） 节点（将泛型参数类型引用替换为具体类型），通过 AST 修补节点（ast_patch_node）修补函数体中泛型参数名到具体类型名的引用，注册新函数并设泛型计数为 0。若已存在则直接返回已有的函数信息索引。

### 逻辑
接收 泛型函数索引（fi）：整数，调用节点（call_node）：整数
（创建单态化版本的函数信息条目——IR 生成在 ir_gen_all 的第二遍中完成）

令 函数AST节点 = 函数信息访问器：AST 数组（ast）节点（fi_ast_node）（泛型函数索引）
令 函数体节点 = AST 访问器：数据（ast_data）（函数AST节点）
令 第一个参数节点 = 第二子节点访问器（ast_b）（ast_b）（函数AST节点）
令 参数总数 = 第三子节点访问器（ast_c）（ast_c）（函数AST节点）
令 原始返回类型编码 = AST 访问器：整数值（ast_int_val）（函数AST节点）
令 原始返回类型节点索引 = AST 访问器：类型值（ast_type_val）（函数AST节点）

令 泛型名驻留索引 = 函数信息访问器：泛型名称（fi_generic_name）（泛型函数索引, 0）
令 泛型名字符串 = 驻留字符串获取（istr_get）（泛型名驻留索引）

（从调用节点获取具体类型名——由 类型检查器（checker） 存储）
令 具体类型名驻留索引 = AST 访问器：整数值（ast_int_val）（调用节点）
令 具体类型名字符串 = 驻留字符串获取（istr_get）（具体类型名驻留索引）

（创建混淆名："原函数名$泛型参数名.具体类型名"）
令 原始函数名字符串 = 驻留字符串获取（istr_get）（函数信息访问器：名称（fi_name）（泛型函数索引））
令 混淆名字符串 = 原始函数名字符串 + "$"
令 混淆名字符串 = 混淆名字符串 + 泛型名字符串 + "." + 具体类型名字符串
令 混淆名驻留索引 = 字符串驻留（str_intern）（混淆名字符串）

（查是否已存在——若已单态化则直接返回）
令 已有函数索引 = 查找函数（find_func）（混淆名驻留索引）
如果 已有函数索引 大于等于 0，那么：
    返回 已有函数索引

（创建新 参数表达式（EXPR_PARAM） 节点——使用具体参数类型）
令 新首个参数节点 = -1
令 参数迭代索引 = 0
令 当前参数节点 = 第一个参数节点
循环：
    如果 参数迭代索引 大于等于 参数总数，那么：
        跳出循环
    如果 当前参数节点 小于 0，那么：
        跳出循环
    令 参数名驻留索引 = 第一子节点访问器（ast_a）（ast_a）（当前参数节点）
    令 自身模式标记 = AST 访问器：整数值（ast_int_val）（当前参数节点）
    令 原始参数类型值 = AST 访问器：类型值（ast_type_val）（当前参数节点）
    令 原始参数类型节点 = AST 访问器：数据（ast_data）（当前参数节点）

    （若类型节点引用泛型参数名，替换为具体类型名的 标识符表达式（EXPR_IDENT） 节点）
    令 新参数类型节点 = 原始参数类型节点
    如果 原始参数类型节点 大于等于 0 且 AST 访问器：类别（ast_kind）（原始参数类型节点） 等于 标识符表达式（EXPR_IDENT） 且 AST 访问器：整数值（ast_int_val）（原始参数类型节点） 等于 泛型名驻留索引，那么：
        （创建新类型节点，引用具体类型名）
        令 新参数类型节点 = 分配 AST 节点（alloc_node）（标识符表达式（EXPR_IDENT）, 0, 0, 0, 具体类型名驻留索引, 0, 0, 0, 0）

    令 新参数节点 = 分配 AST 节点（alloc_node）（参数表达式（EXPR_PARAM）, 参数名驻留索引, 0, 0, 自身模式标记, 原始参数类型值, 新参数类型节点, 0, 0）
    如果 参数迭代索引 等于 0，那么：
        令 新首个参数节点 = 新参数节点
    令 参数迭代索引 = 参数迭代索引 + 1
    （扫描跳过类型节点，定位到下一个 参数表达式（EXPR_PARAM））
    令 当前参数节点 = 当前参数节点 + 1
    循环：
        如果 当前参数节点 大于等于 AST 节点计数（g_ast_count），那么：
            跳出循环
        如果 AST 访问器：类别（ast_kind）（当前参数节点） 等于 参数表达式（EXPR_PARAM），那么：
            跳出循环
        令 当前参数节点 = 当前参数节点 + 1

（创建新 函数定义表达式（EXPR_FN） 节点）
令 新函数AST节点 = 分配 AST 节点（alloc_node）（函数定义表达式（EXPR_FN）, 混淆名驻留索引, 新首个参数节点, 参数总数, 原始返回类型编码, 原始返回类型节点索引, 函数体节点, 0, 0）

（修补函数体：将 "泛型参数名.方法（method）" 替换为 "具体类型名.方法"）
如果 函数体节点 大于等于 0，那么：
    AST 修补节点（ast_patch_node）（函数体节点, 泛型名字符串, 具体类型名字符串）

（注册新函数）
令 新函数索引 = 添加函数（add_func）（混淆名字符串, 参数总数, 原始返回类型编码, 新函数AST节点）
如果 新函数索引 大于等于 0，那么：
    （拷贝泛型约束信息——不再是泛型但保留引用）
    函数信息访问器：设置泛型计数（fi_set_generic_count）（新函数索引, 0）

返回 新函数索引

### 测试要点
1. 已存在的单态化版本直接返回，不重复创建
2. 泛型参数节点中的类型引用被替换为具体类型名的 标识符表达式（EXPR_IDENT） 节点
3. 函数体中泛型参数名作为方法调用前缀的部分被 AST 修补节点（ast_patch_node） 替换
4. 新函数注册后泛型计数设为 0（不再视为泛型函数）
5. 混淆名为 "原函数名$泛型参数名.具体类型名" 格式

---

## 函数 IR 生成全部（ir_gen_all）

### 作用
主入口函数：重置所有 IR 全局计数器、初始化 HDFG、注册全局变量，然后遍历所有函数（非泛型函数在 IR 生成函数（ir_gen_func）内部跳过），每个函数包裹在 HDFG：开始函数（df_begin_func）/HDFG：结束函数（df_end_func） 调用中以生成函数级 SG 区域。

### 逻辑
（重置全局计数器）
令 IR 变量总数（g_ir_var_count） = 0
令 IR 指令总数（g_ir_instr_count） = 0
令 IR 函数个数（g_ir_func_count） = 0
令 IR 局部变量计数（g_ir_local_count） = 0
令 IR 局部变量作用域深度（g_ir_local_depth） = 0
令 IR 全局变量计数（g_ir_global_count） = 0
令 下一个标签号（g_next_label） = 1
令 IR 循环嵌套深度（g_ir_loop_depth） = 0
令 IR 字符串常量计数（g_ir_str_const_count） = 0

（初始化 HDFG）
初始化 HDFG（init_df）（）

（初始化全局变量）
IR 生成全局变量（ir_gen_globals）（）

（遍历所有函数生成 IR）
令 函数扫描位置 = 0
循环：
    如果 函数扫描位置 大于等于 函数计数（g_func_count），那么：
        跳出循环
    HDFG：开始函数（df_begin_func）（函数扫描位置）
    IR 生成函数（ir_gen_func）（函数扫描位置）
    HDFG：结束函数（df_end_func）（函数扫描位置）
    令 函数扫描位置 = 函数扫描位置 + 1

### 测试要点
1. 每次调用重置所有全局计数器（9 个全局变量归零/归 1）
2. 先初始化 HDFG和全局变量，再遍历函数
3. 每个函数包裹在 HDFG：开始函数（df_begin_func）/HDFG：结束函数（df_end_func） 中
4. 泛型函数在 IR 生成函数（ir_gen_func） 内部跳过（fi_generic_count > 0 时直接返回）

---

## 函数 函数指纹（func_fingerprint）

### 作用
计算函数体的哈希指纹，用于缓存命中检测。若函数体未变化，则可从缓存恢复输出 IR。首次调用时计算并缓存完整源码哈希（FNV 哈希（FNV）-1a 算法：初始值 2166136261，乘数 16777619），之后每个函数叠加其 AST 节点的类别和关键字段（函数名索引、参数数量、函数体节点类别）。

### 逻辑
接收 函数AST节点（func_node）：整数（EXPR_FUNC 节点）
令 函数体节点 = AST 访问器：数据（ast_data）（函数AST节点）
如果 函数体节点 小于 0，那么：
    返回 0

（首次调用时计算完整源码哈希并缓存）
如果 IR 源哈希就绪标记（g_ir_source_hash_ready） 等于 0，那么：
    令 源码哈希 = 2166136261
    令 源码扫描位置 = 0
    令 源码字节长度 = 字符串长度（str_len）（g_source）
    循环：
        如果 源码扫描位置 大于等于 源码字节长度，那么：
            跳出循环
        令 源码哈希 = 源码哈希 * 16777619 + 字符串按字节读取（str_load8）（源代码全文, 源码扫描位置）
        令 源码扫描位置 = 源码扫描位置 + 1
    令 IR 源哈希（g_ir_source_hash） = 源码哈希
    令 IR 源哈希就绪标记 = 1

（在源码哈希基础上叠加函数特征）
令 哈希 = IR 源哈希（g_ir_source_hash）
令 开始行号 = AST 访问器：行号（ast_line）（函数AST节点）
令 开始列号 = AST 访问器：列号（ast_col）（函数AST节点）
（使用函数名索引 + 参数数量 + 函数体节点类别 进行哈希叠加）
令 哈希 = 哈希 * 16777619 + （AST 访问器：类别（ast_kind）（函数AST节点） 取模 256）
令 哈希 = 哈希 * 16777619 + （第一子节点访问器（ast_a）（函数AST节点） 取模 256）（函数名驻留索引）
令 哈希 = 哈希 * 16777619 + （第三子节点访问器（ast_c）（函数AST节点） 取模 256）（参数数量）
如果 函数体节点 大于等于 0，那么：
    令 哈希 = 哈希 * 16777619 + （AST 访问器：类别（ast_kind）（函数体节点） 取模 256）
返回 哈希

### 测试要点
1. 无函数体返回 0
2. 首次调用计算并缓存源码全文哈希（FNV 哈希（FNV）-1a：初始 2166136261，乘数 16777619）
3. 后续调用直接用缓存值，避免重复哈希全文
4. 函数名、参数数、函数体节点类别影响哈希
5. 源码全文哈希改变时所有函数指纹均改变

---

## 函数 签名指纹（sig_fingerprint）

### 作用
计算函数签名哈希（名字 + 参数类型 + 返回类型），用于检测调用者何时需重新编译。签名相同但实现不同的函数指纹不同（用于缓存检测）。

### 逻辑
接收 函数AST节点（func_node）：整数（EXPR_FUNC 节点）
令 哈希 = 2166136261

（名字——逐个字符哈希）
令 函数名驻留索引 = 第一子节点访问器（ast_a）（ast_a）（函数AST节点）
令 函数名字符串 = 驻留字符串获取（istr_get）（函数名驻留索引）
令 字符扫描位置 = 0
循环：
    如果 字符扫描位置 大于等于 字符串长度（str_len）（函数名字符串），那么：
        跳出循环
    令 哈希 = 哈希 * 16777619 + （字符串按字节读取（str_load8）（函数名字符串, 字符扫描位置） 取模 256）
    令 字符扫描位置 = 字符扫描位置 + 1

（参数类型——逐个参数的类型值取模后叠加）
令 参数节点 = 第二子节点访问器（ast_b）（ast_b）（函数AST节点）
令 参数总数 = 第三子节点访问器（ast_c）（ast_c）（函数AST节点）
令 参数扫描位置 = 0
循环：
    如果 参数扫描位置 大于等于 参数总数，那么：
        跳出循环
    令 参数类型值 = AST 访问器：类型值（ast_type_val）（参数节点）
    令 哈希 = 哈希 * 16777619 + （参数类型值 取模 256）
    令 参数扫描位置 = 参数扫描位置 + 1
    令 参数节点 = 参数节点 + 1

（返回类型）
令 返回类型值 = AST 访问器：类型值（ast_type_val）（函数AST节点）
令 哈希 = 哈希 * 16777619 + （返回类型值 取模 256）
返回 哈希

### 测试要点
1. 函数名任意字符变更导致不同指纹
2. 参数类型变更（增删或类型变化）导致不同指纹
3. 返回类型变更导致不同指纹
4. 使用 FNV-1a 哈希算法（初始 2166136261，乘数 16777619）
5. 签名相同但实现不同的函数指纹不同（func_fingerprint 另有独立哈希用于缓存检测）

