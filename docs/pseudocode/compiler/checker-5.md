# 类型检查器（checker）.cr 伪代码（第 5 部分：动态类型跟踪、类型推断、主入口）
> 源文件：src/compiler/类型检查器（checker）.cr 第 1286～2405 行
> 功能概要：动态类型集合（增长/设置/查询/合并位图）、动态方法验证、核心类型推断（infer_expr：处理所有 AST 表达式节点的类型推导）、主入口（check_all：编排整个检查管线）。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 扩展动态类型集数组 | grow_dyn_type_sets | 扩展动态类型集数组 |
| 动态设置类型 | dyn_set_type | 动态设置类型 |
| 动态has类型 | dyn_has_type | 动态has类型 |
| 联合位图 | union_bitmaps | 联合位图 |
| 验证动态方法 | validate_dyn_method | 验证动态方法 |
| 类型推断表达式 | infer_expr | 类型推断表达式 |
| 检查全部 | check_all | 检查全部 |
| 动态类型集合数组 | g_dyn_type_sets | 扩展动态类型集数组 |
| 动态类型集合容量 | g_dyn_type_set_cap | 扩展动态类型集数组 |
| 动态类型集合计数 | g_dyn_type_set_count | 动态设置类型 |
| 类型数组 | g_types | 验证动态方法 |
| 类型计数 | g_type_count | 验证动态方法 |
| 符号数组 / 计数 / 容量 | g_syms / g_sym_count / g_sym_cap | 检查全部 |
| 作用域边界数组 / 深度 / 容量 | g_scope_bounds / g_scope_depth / g_scope_bounds_cap | 检查全部 |
| 诊断数组 / 计数 / 容量 | g_diags / g_diag_count / g_diag_cap | 检查全部 |
| 泛型映射 / 计数 / 容量 / 名称 / 类型 | g_gen_map / g_gen_map_count / g_gen_map_cap / g_gen_map_names / g_gen_map_types | 检查全部 |
| 泛型应用数据数组 / 计数 / 容量 | g_gen_apply_data / g_gen_apply_data_count / g_gen_apply_data_cap | 检查全部 |
| 泛型参数数组 / 计数 / 容量 | g_gen_params / g_gen_param_count / g_gen_param_cap | 检查全部 |
| 初始化types | init_types | 检查全部 |
| 初始化内建 | init_builtins | 检查全部 |
| 收集声明 | collect_decls | 检查全部 |
| 检查函数 | check_func | 检查全部 |
| 检查全局声明 | check_global_let | 检查全部 |
| 检查实现 | check_impl_for | 检查全部 |
| 分配 | alloc | 扩展动态类型集数组 |
| 内部：动态拷贝 | _dyncpy | 扩展动态类型集数组 |
| 读写全局 | r64 / w64 | 多个函数 |
| AST 访问器系列 | ast_kind / ast_a / ast_b / ast_c / ast_int_val / ast_type_val / ast_data / ast_line / ast_col | 类型推断表达式 |
| AST 访问器：设置数据 | ast_set_data | 类型推断表达式 |
| AST 访问器：设置类型值 | ast_set_type_val | 类型推断表达式 |
| AST 访问器：设置整数值 | ast_set_int_val | 类型推断表达式 |
| AST 访问器：设置c | ast_set_c | 类型推断表达式 |
| AST 访问器：设置b | ast_set_b | 类型推断表达式 |
| 函数信息访问器系列 | fi_ast_node / fi_name / fi_return_type / fi_param_count / fi_generic_count / fi_generic_name | 类型推断表达式 |
| 结构体信息访问器系列 | si_field_count / si_field_name / si_field_type / si_field_type_node / si_generic_count / si_generic_name | 类型推断表达式 |
| 查找gsym | find_gsym | 类型推断表达式 |
| 查找符号 | find_sym | 类型推断表达式 |
| 查找函数 | find_func | 类型推断表达式 |
| 查找结构体 | find_struct | 类型推断表达式 |
| 查找结构体按字节名称 | find_struct_by_name | 类型推断表达式 |
| 查找接口 | find_iface | 类型推断表达式 |
| 查找借用条目 | find_borrow_entry | 类型推断表达式 |
| 检查借用 | check_borrow | 类型推断表达式 |
| 检查使用 | check_use | 类型推断表达式 |
| 检查错误 | check_error | 类型推断表达式 |
| 定义符号 | def_sym | 类型推断表达式 |
| 压入作用域 / 弹出作用域 | push_scope / pop_scope | 类型推断表达式 |
| 压入借用作用域 / 弹出借用作用域 | push_borrow_scope / pop_borrow_scope | 类型推断表达式 |
| 压入不安全作用域 / 弹出不安全作用域 | push_unsafe_scope / pop_unsafe_scope | 类型推断表达式 |
| 类型推断泛型调用 | infer_gen_call | 类型推断表达式 |
| 类型equal | type_equal | 类型推断表达式 |
| 获取类型类别 | get_type_kind | 类型推断表达式 |
| 获取类型数据 | get_type_data | 类型推断表达式 |
| 获取类型额外 | get_type_extra | 类型推断表达式 |
| 获取类型名称 | get_type_name | 验证动态方法 |
| 类型has方法 | type_has_method | 验证动态方法 |
| 分配类型 | alloc_type | 类型推断表达式 |
| 解析类型节点 | res_type_node | 类型推断表达式 |
| 解析调用类型 | res_call_type | 类型推断表达式 |
| 判断函数泛型 | is_func_generic | 类型推断表达式 |
| 判断结构体泛型 | is_struct_generic | 类型推断表达式 |
| 统一types | unify_types | 类型推断表达式 |
| 替换返回类型 | substitute_return_type | 类型推断表达式 |
| 扫描让出 | scan_for_yield | 类型推断表达式 |
| 借用变量名称 | borrow_var_name | 类型推断表达式 |
| 记录借用持有者 | record_borrow_holder | 类型推断表达式 |
| 扩展类型数组 | grow_types | 分配类型 |
| 扩展符号数组 | grow_syms | 检查全部 |
| 扩展动态类型集数组 | grow_dyn_type_sets | 动态设置类型 |
| 扩展泛型映射数组 | grow_gen_map | 统一types |
| 扩展泛型应用数据数组 | grow_gen_apply_data | 类型推断表达式 |
| 扩展函数数组 | grow_funcs | 检查全部 |
| 驻留字符串获取 | istr_get | 类型推断表达式 |
| 字符串驻留 | str_intern | 类型推断表达式 |
| 字符串长度 | str_len | 类型推断表达式 |
| 字符串相等比较 | str_eq | 类型推断表达式 |
| 字符串转整数 | str_int | 类型推断表达式 |
| 符号类别 | sym_kind | 类型推断表达式 |
| 符号类型 | sym_type | 类型推断表达式 |
| 符号节点 | sym_node | 类型推断表达式 |
| 符号名称 | sym_name | 检查全部 |
| 符号设置名称 / 类别 / 类型 / 节点 | sym_set_name / sym_set_kind / sym_set_type / sym_set_node | 检查全部 |
| unsafe 块深度 | g_unsafe_depth | 类型推断表达式 |
| 当前检查函数索引 | g_checker_current_fi | 类型推断表达式 |
| 模块函数文件 ID 数组 | g_mod_func_fileids | 类型推断表达式 |
| 模块函数名数组 | g_mod_func_names | 类型推断表达式 |
| 模块函数计数 | g_mod_func_count | 类型推断表达式 |
| 模块函数类型索引数组 | g_mod_func_tis | 类型推断表达式 |
| 方法数组 / 计数 | g_methods / g_method_count | 类型推断表达式 |
| 运行时内建函数名数组 / 计数 / 返回类型数组 | g_rt_builtin_names / g_rt_builtin_count / g_rt_builtin_ret_types | 类型推断表达式 |

## 全局状态
（本部分未单独列出全局变量；涉及的全局变量含义见「标识符对照表」）

## 函数 扩展动态类型集数组（grow_dyn_type_sets）
**签名：** `函数（fn） 扩展动态类型集数组（grow_dyn_type_sets）（需求（needed）: 整数（int））`

### 作用
确保动态类型集合数组（g_dyn_type_sets）有足够容量（需求（needed） 个条目）。如果不足则分配新缓冲（当前容量 变量甲（x） 2，最小 64），拷贝旧数据。

### 逻辑
`
如果 所需条目数（needed）小于 动态类型集合容量（g_dyn_type_set_cap），那么：返回

令 新容量（nc）= 动态类型集合容量（g_dyn_type_set_cap） * 2（可变）
如果 新容量（nc）小于 64，那么：令 新容量（名称计数） = 64
如果 新容量（nc）小于 所需条目数（needed），那么：令 新容量（名称计数） = 所需条目数（需求） + 64

令 新缓冲（nb）= 调用 分配（alloc）（新容量（nc） * 8）的字节
调用 内部：动态拷贝（_dyncpy）（动态类型集合数组（g_dyn_type_sets），动态类型集合容量（g_dyn_type_set_cap） * 8，新缓冲（nb））
令 动态类型集合数组（g_dyn_type_sets） = 新缓冲（nb）
令 动态类型集合容量（g_dyn_type_set_cap） = 新容量（nc）
`

### 测试要点
1. 需求量小于当前容量：直接返回
2. 首次扩容从空（容量（cap）=0）开始：名称计数（nc） = 64
3. 已有数据被拷贝保留到新缓冲
4. 需求量远大于当前容量：名称计数（nc） = 需求（needed） + 64

## 函数 动态设置类型（dyn_set_type）
**签名：** `函数（fn） 动态设置类型（dyn_set_type）（var_idx: 整数（int）, ti: 整数）`

### 作用
将类型表索引（ti）添加到指定变量的动态类型集合中（通过位图标记）。用于 动态（dyn） 变量的类型追踪：记录运行时实际可能持有的类型。

### 逻辑
`
调用 扩展动态类型集数组（grow_dyn_type_sets）（变量索引（var_idx） + 1）

令 原位图（old_bits）= 调用 读写全局（r64）（动态类型集合数组（g_dyn_type_sets），变量索引（var_idx） * 8）

（计算 2^ti 以设置位图中的对应 bit）
令 位值（bit）= 1（可变）
如果 类型表索引（ti）大于等于 0 且 类型表索引（ti）小于 64，那么：
    令 位值（bit） = 1
    令 左移计数（shl）= 类型表索引（ti）
    循环（当 左移计数（shl）大于 0 时）：
        如果 左移计数（shl）小于等于 0，那么：跳出循环
        位值（bit） = 位值（bit） * 2
        左移计数（shl） = 左移计数（shl） - 1

调用 读写全局（w64）（动态类型集合数组（g_dyn_type_sets），变量索引（var_idx） * 8，原位图（old_bits） + 位值（bit））
如果 变量索引（var_idx）大于等于 动态类型集合计数（g_dyn_type_set_count），那么：
    令 动态类型集合计数（g_dyn_type_set_count） = 变量索引（var_idx） + 1
`

### 测试要点
1. 设置 类型信息：整数（TI_INT）（0）位：旧位（old_bits） + 1
2. 设置 类型信息：布尔（TI_BOOL）（2）位：旧位（old_bits） + 4
3. 多次设置不同类型：位图累加（OR 语义）
4. 超出当前计数：动态类型集合计数（g_dyn_type_set_count）更新

## 函数 动态具有（has）类型（dyn_has_type）
**签名：** `函数（fn） 动态具有（has）类型（dyn_has_type）（var_idx: 整数（int）, ti: 整数） -> 整数（整数）`

### 作用
检查指定变量是否在动态类型集合（位图）中注册了给定的类型（ti 位为 1）。返回 1 表示是，0 表示否。

### 逻辑
`
如果 变量索引（var_idx）小于 0 或 变量索引（var_idx）大于等于 动态类型集合计数（g_dyn_type_set_count），那么：返回 0

令 位图（set）= 调用 读写全局（r64）（动态类型集合数组（g_dyn_type_sets），变量索引（var_idx） * 8）

（计算 2^ti）
令 位值（bit）= 1（可变）
如果 类型表索引（ti）大于等于 0 且 类型表索引（ti）小于 64，那么：
    令 位值（bit） = 1
    令 左移计数（shl）= 类型表索引（ti）
    循环（当 左移计数（shl）大于 0 时）：
        如果 左移计数（shl）小于等于 0，那么：跳出循环
        位值（bit） = 位值（bit） * 2
        左移计数（shl） = 左移计数（shl） - 1

如果 （位图（set） / 位值（bit）） % 2 不等于 0，那么：返回 1
返回 0
`

### 测试要点
1. 已注册类型：返回 1
2. 未注册类型：返回 0
3. 变量索引无效（< 0 或 >= 动态类型集合计数（g_dyn_type_set_count））：返回 0

## 函数 联合位图（union_bitmaps）
**签名：** `函数（fn） 联合位图（union_bitmaps）（变量甲（a）: 整数（int）, 变量乙（b）: 整数） -> 整数（整数）`

### 作用
计算两个 64 位位图（位图 变量甲（a） 与位图 变量乙（b））的按位或（union）。用于合并 如果（if）-否则（else） 两分支的动态类型集合。

### 逻辑
`
令 结果（r）= 0（可变）
令 位索引（pos）= 0（可变）
循环（当 位索引（pos）小于 64 时）：
    如果 位索引（pos）大于等于 64，那么：跳出循环
    令 位值（bit）= 1（可变）
    令 左移计数（shl）= 位索引（pos）
    循环（当 左移计数（shl）大于 0 时）：
        如果 左移计数（shl）小于等于 0，那么：跳出循环
        位值（bit） = 位值（bit） * 2
        左移计数（shl） = 左移计数（shl） - 1
    如果 （位图 变量甲（a）（变量甲） / 位值（bit）） % 2 不等于 0 或 （位图 变量乙（b）（变量乙） / 位值（bit）） % 2 不等于 0，那么：
        结果（r） = 结果（r） + 位值（bit）
    位索引（pos） = 位索引（位置） + 1
返回 结果（r）
`

### 测试要点
1. 位图 变量甲（a） = 1（0b1），位图 变量乙（b） = 2（0b10）：返回 3（0b11）
2. 两个相同位图：返回原位图
3. 零位图：返回另一个位图
4. 遍历全部 64 位

## 函数 验证动态方法（validate_dyn_method）
**签名：** `函数（fn） 验证动态方法（validate_dyn_method）（si: 整数（int）, method_ni: 整数, line: 整数, col: 整数）`

### 作用
对 动态（dyn） 类型变量调用方法时，验证位图中所有可能的实际类型都定义了指定方法。任一类型缺少方法则报告诊断。

### 逻辑
`
如果 符号索引（si）小于 0 或 符号索引（si）大于等于 动态类型集合计数（g_dyn_type_set_count），那么：返回

令 位图（set）= 调用 读写全局（r64）（动态类型集合数组（g_dyn_type_sets），符号索引（si） * 8）
如果 位图（set）等于 0，那么：返回

令 类型索引（ti）= 0（可变）
循环（当 类型索引（ti）小于 类型计数（g_type_count）时）：
    如果 类型索引（ti）大于等于 类型计数（g_type_count），那么：跳出循环
    如果 类型索引（ti）大于等于 64，那么：跳出循环

    （计算 2^ti）
    令 位值（bit）= 1（可变）
    令 左移计数（shl）= 类型索引（ti）
    循环（当 左移计数（shl）大于 0 时）：
        如果 左移计数（shl）小于等于 0，那么：跳出循环
        位值（bit） = 位值（bit） * 2
        左移计数（shl） = 左移计数（shl） - 1

    如果 （位图（set） / 位值（bit）） % 2 不等于 0，那么：
        （这一位被设置——检查该类型是否有方法）
        令 类型名索引（type_ni）= 调用 获取类型名称（get_type_name）（ti）
        如果 类型名索引（type_ni）大于等于 0，那么：
            如果 非 调用 类型具有（has）方法（type_has_method）（类型名索引（type_ni），方法名索引（method_ni）），那么：
                令 类型名字符串（tname）= 调用 驻留字符串获取（istr_get）（type_ni）
                令 方法名字符串（mname）= 调用 驻留字符串获取（istr_get）（method_ni）
                调用 检查错误（check_error）（未定义方法错误码（EC_N_METHOD），"动态（dyn）: 方法 '" + 方法名字符串（mname）+ "' 在类型 '" + 类型名字符串（tname）+ "' 上未找到"，行号（line），列号（col））
    类型索引（ti） = 类型索引（ti） + 1
`

### 测试要点
1. 位图为空（set == 0）：直接返回
2. 所有类型有方法：无诊断
3. 任一类型缺少方法：产生 未定义方法错误码（EC_N_METHOD） 诊断
4. 位图只检查前 64 个类型表索引

## 函数 类型推断表达式（infer_expr）
**签名：** `函数（fn） 类型推断表达式（infer_expr）（节点（node）: 整数（int）） -> 整数（整数）`

### 作用
核心语义分析函数：对 AST 表达式节点进行类型推断，返回类型表索引（TI_*）。同时执行借用规则检查、动态（dyn） 类型追踪、各种语义错误诊断。被 检查函数（check_func）、类型推断泛型调用（infer_gen_call）等递归调用。

### 逻辑
`
如果 节点（node）小于 0，那么：返回 类型表预分配：单元（TI_UNIT）

（── 字面量 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 整数字面量表达式（EXPR_INT），那么：返回 类型表预分配：整数（TI_INT）
如果 调用 AST 访问器系列（ast_kind）（node）等于 空表达式（EXPR_NONE）且 调用 AST 访问器系列（ast_a）（节点（节点））大于等于 0 且 调用 AST 访问器系列（ast_a）（节点（节点））不等于 节点（节点），那么：返回 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（节点（节点）））
如果 调用 AST 访问器系列（ast_kind）（node）等于 浮点数字面量表达式（EXPR_FLOAT），那么：返回 类型表预分配：浮点数（TI_FLOAT）
如果 调用 AST 访问器系列（ast_kind）（node）等于 字符串字面量表达式（EXPR_STRING），那么：返回 类型表预分配：字符串（TI_STR）
如果 调用 AST 访问器系列（ast_kind）（node）等于 布尔字面量表达式（EXPR_BOOL），那么：返回 类型表预分配：布尔（TI_BOOL）
如果 调用 AST 访问器系列（ast_kind）（node）等于 字符字面量表达式（EXPR_CHAR），那么：返回 类型表预分配：字符（TI_CHAR）

（── 标识符 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 标识符表达式（EXPR_IDENT），那么：
    令 名称索引（name_idx）= 调用 AST 访问器系列（ast_int_val）（node）
    （借用检查：变量被借用期间不能使用）
    如果 非 调用 检查使用（check_use）（name_idx），那么：
        令 名字（name）= 调用 驻留字符串获取（istr_get）（name_idx）
        调用 检查错误（check_error）（借用期间使用错误码（EC_B_USE_WHILE_BORROWED），"不能使用 '" + 名字（name）+ "' 在它被借用期间"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
    令 符号索引（si）= 调用 查找符号（find_sym）（name_idx）
    如果 符号索引（si）大于等于 0，那么：返回 调用 符号类型（sym_type）（si）
    令 名字（name）= 调用 驻留字符串获取（istr_get）（name_idx）
    调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"未定义名称 '" + 名字（name）+ "'"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
    返回 类型表预分配：永无（TI_NEVER）

（── 空节点包装 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 空表达式（EXPR_NONE），那么：
    如果 调用 AST 访问器系列（ast_a）（node）大于等于 0 且 调用 AST 访问器系列（ast_a）（节点（节点））不等于 节点（节点），那么：返回 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（节点（节点）））
    返回 类型表预分配：单元（TI_UNIT）

（── 二元运算 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 二元运算表达式（EXPR_BINARY），那么：
    令 左侧（left）= 调用 AST 访问器系列（ast_a）（node）
    令 右侧（right）= 调用 AST 访问器系列（ast_b）（node）
    令 操作码（op）= 调用 AST 访问器系列（ast_c）（node）

    如果 操作码（op）等于 赋值指令（OP_ASSIGN），那么：
        令 左侧类型（lt）= 调用 类型推断表达式（infer_expr）（left）
        令 右侧类型（rt）= 调用 类型推断表达式（infer_expr）（right）
        如果 非 调用 类型相等（equal）（type_equal）（左侧类型（lt），右侧类型（rt）），那么：
            调用 检查错误（check_error）（EC_TA_ASSIGN，"赋值类型不匹配"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
        返回 右侧类型（rt）

    令 左侧类型（lt）= 调用 类型推断表达式（infer_expr）（left）
    令 右侧类型（rt）= 调用 类型推断表达式（infer_expr）（right）

    如果 操作码（op）等于 加法运算指令（OP_ADD）或 操作码（op）等于 减法运算指令（OP_SUB）或 操作码（op）等于 乘法运算指令（OP_MUL）或 操作码（op）等于 除法运算指令（OP_DIV）或 操作码（op）等于 取模运算指令（OP_MOD），那么：
        （字符串拼接：仅 加法运算符（OP_ADD） 适用）
        如果 操作码（op）等于 加法运算指令（OP_ADD）且（左侧类型（lt）等于 类型表预分配：字符串（TI_STR）或 右侧类型（rt）等于 类型表预分配：字符串（类型信息：字符串）），那么：返回 类型表预分配：字符串（类型信息：字符串）
        （指针算术：*泛型参数（T） + 数量（n） 或 *泛型参数 - 数量 → *泛型参数 T）
        如果（操作码（op）等于 加法运算指令（OP_ADD）或 操作码（op）等于 减法运算指令（OP_SUB））且（调用 获取类型类别（get_type_kind）（lt）等于 类型条目类别：指针（TYP_PTR）且 右侧类型（rt）等于 类型表预分配：整数（TI_INT）），那么：返回 左侧类型（lt）
        （指针算术：数量（n） + *泛型参数（T） → *泛型参数 T）
        如果（操作码（op）等于 加法运算指令（OP_ADD）或 操作码（op）等于 减法运算指令（OP_SUB））且（左侧类型（lt）等于 类型表预分配：整数（TI_INT）且 调用 获取类型类别（get_type_kind）（rt）等于 类型条目类别：指针（TYP_PTR）），那么：返回 右侧类型（rt）
        （指针差值：*泛型参数（T） - *泛型参数 → 整数（int））
        如果 操作码（op）等于 减法运算指令（OP_SUB）且 调用 获取类型类别（get_type_kind）（lt）等于 类型条目类别：指针（TYP_PTR）且 调用 获取类型类别（get_type_kind）（rt）等于 类型条目类别：指针（指针类型），那么：返回 类型表预分配：整数（TI_INT）
        （算术操作需整数或浮点数）
        如果 左侧类型（lt）不等于 类型表预分配：整数（TI_INT）且 左侧类型（lt）不等于 类型表预分配：浮点数（TI_FLOAT）且 右侧类型（rt）不等于 类型表预分配：整数（类型信息：整数）且 右侧类型（rt）不等于 类型表预分配：浮点数（类型信息：浮点），那么：
            调用 检查错误（check_error）（加法类型错误码（EC_TB_ADD），"算术操作需要整数或浮点数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
        如果 左侧类型（lt）等于 类型表预分配：浮点数（TI_FLOAT）或 右侧类型（rt）等于 类型表预分配：浮点数（类型信息：浮点），那么：返回 类型表预分配：浮点数（类型信息：浮点）
        返回 类型表预分配：整数（TI_INT）

    （bool）
    如果 操作码（op）等于 等于比较指令（OP_EQ）或 操作码（op）等于 不等于比较指令（OP_NE）或 操作码（op）等于 小于比较指令（OP_LT）或 操作码（op）等于 大于比较指令（OP_GT）或 操作码（op）等于 小于等于比较指令（OP_LE）或 操作码（op）等于 大于等于比较指令（OP_GE），那么：返回 类型表预分配：布尔（TI_BOOL）

    （逻辑运算 && 和 ||）
    如果 操作码（op）等于 逻辑与指令（OP_AND）或 操作码（op）等于 逻辑或指令（OP_OR），那么：
        如果（左侧类型（lt）不等于 类型表预分配：布尔（TI_BOOL）且 左侧类型（lt）不等于 类型表预分配：整数（TI_INT））或（右侧类型（rt）不等于 类型表预分配：布尔（类型信息：布尔）且 右侧类型（rt）不等于 类型表预分配：整数（类型信息：整数）），那么：
            调用 检查错误（check_error）（EC_TC_IF_COND，"逻辑操作符需要布尔或整数操作数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
        返回 类型表预分配：布尔（TI_BOOL）

    返回 类型表预分配：整数（TI_INT）

（── 一元运算 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 一元运算表达式（EXPR_UNARY），那么：
    令 操作码（op）= 调用 AST 访问器系列（ast_c）（node）

    如果 操作码（op）等于 一元取负（UOP_NEG）或 操作码（op）等于 一元逻辑非（UOP_NOT），那么：
        返回 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））

    如果 操作码（op）等于 一元取引用（UOP_REF），那么：
        令 操作数（operand）= 调用 AST 访问器系列（ast_a）（node）
        令 内部类型（inner）= 类型表预分配：单元（TI_UNIT）（可变）
        如果 调用 AST 访问器系列（ast_kind）（operand）等于 标识符表达式（EXPR_IDENT），那么：
            令 变量索引（vi）= 调用 AST 访问器系列（ast_int_val）（operand）
            令 符号索引（si）= 调用 查找符号（find_sym）（vi）
            如果 符号索引（si）大于等于 0，那么：令 内部类型（inner） = 调用 符号类型（sym_type）（si）
        否则：
            令 内部类型（inner） = 调用 类型推断表达式（infer_expr）（operand）
        令 地址空间（asp）= 0（可变）
        如果 非安全（unsafe） 块深度（g_unsafe_depth）大于 0，那么：令 地址空间（asp） = 1
        返回 调用 分配类型（alloc_type）（类型条目类别：指针（TYP_PTR），内部类型（inner），地址空间（asp））

    如果 操作码（op）等于 一元解引用（UOP_DEREF），那么：
        令 被引用类型（inner）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））
        如果 调用 获取类型类别（get_type_kind）（inner）等于 类型条目类别：引用（TYP_REF），那么：
            返回 调用 获取类型数据（get_type_data）（inner）
        如果 调用 获取类型类别（get_type_kind）（inner）等于 类型条目类别：指针（TYP_PTR），那么：
            返回 调用 获取类型数据（get_type_data）（inner）
        如果 调用 获取类型类别（get_type_kind）（inner）等于 类型条目类别：泛型参数（TYP_GENERIC_PARAM），那么：
            返回 被引用类型（inner）
        返回 被引用类型（inner）

    返回 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））

（── 函数调用 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 调用表达式（EXPR_CALL），那么：
    令 被调用节点（func_node）= 调用 AST 访问器系列（ast_a）（node）
    令 首实参（first_arg）= 调用 AST 访问器系列（ast_b）（node）
    令 实参个数（arg_count）= 调用 AST 访问器系列（ast_c）（node）
    令 函数名索引（func_ni）= -1（可变）

    （── 方法调用：obj.方法（method）（args） 或 模块.函数（args） ──）
    如果 调用 AST 访问器系列（ast_kind）（func_node）等于 字段访问表达式（EXPR_FIELD），那么：
        令 对象（obj）= 调用 AST 访问器系列（ast_a）（func_node）
        令 方法名索引（method_ni）= 调用 AST 访问器系列（ast_int_val）（func_node）

        （── 模块限定调用：模块.函数（args） ──）
        令 模块调用完成标记（mod_call_done）= 0（可变）
        令 找到的模块函数索引（mod_found_mfi）= -1（可变）
        如果 调用 AST 访问器系列（ast_kind）（obj）等于 标识符表达式（EXPR_IDENT），那么：
            令 模块名索引（mod_name_ni）= 调用 AST 访问器系列（ast_int_val）（obj）
            令 符号索引（si）= 调用 查找符号（find_sym）（mod_name_ni）
            如果 符号索引（si）大于等于 0 且 调用 符号类别（sym_kind）（si）等于 符号类别：模块（SYM_MODULE），那么：
                令 文件 ID 索引（fileid_ni）= 调用 符号类型（sym_type）（si）
                （在模块函数表中查找（文件标识（fileid），方法）对）
                令 表索引（mfi）= 0（可变）
                循环（当 表索引（mfi）小于 模块函数计数（g_mod_func_count）时）：
                    如果 表索引（mfi）大于等于 模块函数计数（g_mod_func_count），那么：跳出循环
                    如果 调用 读写全局（r64）（模块函数文件 ID 数组（g_mod_func_fileids），表索引（mfi） * 8）等于 文件 ID 索引（fileid_ni）且 调用 读写全局（r64）（模块函数名数组（g_mod_func_names），表索引（mfi） * 8）等于 方法名索引（method_ni），那么：
                        令 函数名索引（func_ni） = 调用 读写全局（r64）（模块函数名数组（g_mod_func_names），表索引（mfi） * 8）
                        调用 AST 访问器：设置数据（ast_set_data）（节点（node），函数名索引（func_ni））
                        调用 AST 访问器：设置类型值（ast_set_type_val）（节点（node），1）  （标记为模块调用）
                        令 模块调用完成标记（mod_call_done） = 1
                        令 找到的模块函数索引（mod_found_mfi） = 表索引（mfi）
                        跳出循环
                    表索引（mfi） = 表索引（mfi） + 1

        如果 模块调用完成标记（mod_call_done）等于 1，那么：
            （推断实参类型）
            令 实参节点（an）= 首实参（first_arg）（可变）
            循环（当 实参节点（an）大于等于 0 时）：
                如果 实参节点（an）小于 0，那么：跳出循环
                调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（an））
                实参节点（an） = 调用 AST 访问器系列（ast_b）（an）
            如果 找到的模块函数索引（mod_found_mfi）大于等于 0，那么：
                返回 调用 读写全局（r64）（模块函数类型索引数组（g_mod_func_tis），找到的模块函数索引（mod_found_mfi） * 8）
            返回 类型表预分配：单元（TI_UNIT）

        （── 常规方法调用 ──）
        令 对象类型表索引（obj_ti）= 调用 类型推断表达式（infer_expr）（obj）

        （── Dyn 方法验证 ──）
        如果 对象类型表索引（obj_ti）等于 类型表预分配：动态（TI_DYN），那么：
            如果 调用 AST 访问器系列（ast_kind）（obj）等于 标识符表达式（EXPR_IDENT），那么：
                令 对象名索引（obj_ni）= 调用 AST 访问器系列（ast_int_val）（obj）
                令 对象符号索引（obj_si）= 调用 查找符号（find_sym）（obj_ni）
                如果 对象符号索引（obj_si）大于等于 0，那么：
                    调用 验证动态方法（validate_dyn_method）（对象符号索引（obj_si），方法名索引（method_ni），调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            （推断实参类型（副作用））
            令 实参节点（an_dyn）= 首实参（first_arg）（可变）
            循环（当 实参节点（an_dyn）大于等于 0 时）：
                如果 实参节点（an_dyn）小于 0，那么：跳出循环
                调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（an_dyn））
                实参节点（an_dyn） = 调用 AST 访问器系列（ast_b）（an_dyn）
            返回 类型表预分配：单元（TI_UNIT）

        （── 展开泛型应用到基础类型，用于方法查找 ──）
        令 查找类型表索引（lookup_ti）= 对象类型表索引（obj_ti）（可变）
        如果 查找类型表索引（lookup_ti）大于等于 0 且 查找类型表索引（lookup_ti）小于 类型计数（g_type_count）且 调用 获取类型类别（get_type_kind）（lookup_ti）等于 类型条目类别：泛型应用（TYP_GENERIC_APPLY），那么：
            令 查找类型表索引（lookup_ti） = 调用 获取类型数据（get_type_data）（lookup_ti）

        （── 在方法表中查找 ──）
        如果 查找类型表索引（lookup_ti）大于等于 0 且 查找类型表索引（lookup_ti）小于 类型计数（g_type_count）且 调用 获取类型类别（get_type_kind）（lookup_ti）等于 类型条目类别：命名（TYP_NAMED），那么：
            令 结构体名索引（struct_ni）= 调用 获取类型数据（get_type_data）（lookup_ti）
            令 方法表索引（mi）= 0（可变）
            循环（当 方法表索引（mi）小于 方法计数（g_method_count）时）：
                如果 方法表索引（mi）大于等于 方法计数（g_method_count），那么：跳出循环
                如果 调用 读写全局（r64）（方法数组（g_methods），方法表索引（mi） * 24）等于 结构体名索引（struct_ni）且 调用 读写全局（r64）（方法数组（g_methods），方法表索引（mi） * 24 + 8）等于 方法名索引（method_ni），那么：
                    令 函数名索引（func_ni） = 调用 读写全局（r64）（方法数组（g_methods），方法表索引（mi） * 24 + 16）
                    调用 AST 访问器：设置数据（ast_set_data）（节点（node），函数名索引（func_ni））
                    跳出循环
                方法表索引（mi） = 方法表索引（mi） + 1

        （── 泛型参数上的方法调用解析：通过接口约束查找 ──）
        如果 函数名索引（func_ni）小于 0 且 调用 获取类型类别（get_type_kind）（lookup_ti）等于 类型条目类别：泛型参数（TYP_GENERIC_PARAM），那么：
            令 泛型参数名索引（gen_ni）= 调用 获取类型数据（get_type_data）（lookup_ti）
            令 泛型个数（gc2）= 调用 函数信息访问器系列（fi_generic_count）（g_checker_current_fi）
            令 约束循环索引（gci2）= 0（可变）
            循环（当 约束循环索引（gci2）小于 泛型个数（gc2）时）：
                如果 约束循环索引（gci2）大于等于 泛型个数（gc2），那么：跳出循环
                令 泛型名索引（gname_idx2）= 调用 读写全局（r64）（函数数组（g_funcs），当前检查函数索引（g_checker_current_fi） * ESZ_FUNCINFO + OFF_FI_GENERIC_NAMES + 约束循环索引（gci2） * 8）
                如果 泛型名索引（gname_idx2）等于 泛型参数名索引（gen_ni），那么：
                    令 约束条目索引（constr_idx2）= 当前检查函数索引（g_checker_current_fi） * 最大泛型参数数（MAX_GENERICS） + 约束循环索引（gci2）
                    如果 约束条目索引（constr_idx2）小于 泛型约束计数（g_generic_constr_count），那么：
                        令 接口名索引（iface_ni2）= 调用 读写全局（r64）（泛型约束数组（g_generic_constr），约束条目索引（constr_idx2） * 8）
                        如果 接口名索引（iface_ni2）大于等于 0，那么：
                            令 接口表索引（ii2）= 调用 查找接口（find_iface）（iface_ni2）
                            如果 接口表索引（ii2）大于等于 0，那么：
                                令 接口方法个数（imc2）= 调用 读写全局（r64）（接口数组（g_ifaces），接口表索引（ii2） * 接口信息大小（ESZ_IFACEINFO） + OFF_IF_METHOD_COUNT）
                                令 接口方法遍历索引（imi2）= 0（可变）
                                循环（当 接口方法遍历索引（imi2）小于 接口方法个数（imc2）时）：
                                    如果 接口方法遍历索引（imi2）大于等于 接口方法个数（imc2），那么：跳出循环
                                    令 接口方法基址（imbase2）= 接口表索引（ii2） * 接口信息大小（ESZ_IFACEINFO） + 接口方法表偏移（OFF_IF_METHODS） + 接口方法遍历索引（imi2） * 接口方法大小（ESZ_IFMETHOD）
                                    如果 调用 读写全局（r64）（接口数组（g_ifaces），接口方法基址（imbase2） + OFF_IFM_NAME）等于 方法名索引（method_ni），那么：
                                        （构造加工名："泛型参数名.方法名"）
                                        令 泛型参数字符串（tname2）= 调用 驻留字符串获取（istr_get）（gen_ni）
                                        令 方法字符串（mname2）= 调用 驻留字符串获取（istr_get）（method_ni）
                                        令 加工名（mangled2）= 泛型参数字符串（tname2） + "." + 方法字符串（mname2）
                                        令 加工名索引（mangled_ni2）= 调用 字符串驻留（str_intern）（mangled2）
                                        调用 AST 访问器：设置数据（ast_set_data）（节点（node），加工名索引（mangled_ni2））
                                        （根据接口方法返回类型返回对应 TI_*）
                                        令 接口返回类型（iface_ret2）= 调用 读写全局（r64）（接口数组（g_ifaces），接口方法基址（imbase2） + OFF_IFM_RET_TI）
                                        如果 接口返回类型（iface_ret2）等于 整数类型（TY_INT），那么：令 函数名索引（func_ni） = 加工名索引（mangled_ni2）；返回 类型表预分配：整数（TI_INT）
                                        如果 接口返回类型（iface_ret2）等于 浮点类型（TY_FLOAT），那么：令 函数名索引（func_ni） = 加工名索引（mangled_ni2）；返回 类型表预分配：浮点数（TI_FLOAT）
                                        如果 接口返回类型（iface_ret2）等于 布尔类型（TY_BOOL），那么：令 函数名索引（func_ni） = 加工名索引（mangled_ni2）；返回 类型表预分配：布尔（TI_BOOL）
                                        如果 接口返回类型（iface_ret2）等于 字符串类型（TY_STRING），那么：令 函数名索引（func_ni） = 加工名索引（mangled_ni2）；返回 类型表预分配：字符串（TI_STR）
                                        如果 接口返回类型（iface_ret2）等于 单元类型（TY_UNIT），那么：令 函数名索引（func_ni） = 加工名索引（mangled_ni2）；返回 类型表预分配：单元（TI_UNIT）
                                        如果 接口返回类型（iface_ret2）等于 字符类型（TY_CHAR），那么：令 函数名索引（func_ni） = 加工名索引（mangled_ni2）；返回 类型表预分配：字符（TI_CHAR）
                                        令 函数名索引（func_ni） = 加工名索引（mangled_ni2）；返回 类型表预分配：单元（TI_UNIT）
                                    接口方法遍历索引（imi2） = 接口方法遍历索引（imi2） + 1
                    跳出循环
                约束循环索引（gci2） = 约束循环索引（gci2） + 1

        （── 推断实参类型（沿 参数表达式（EXPR_ARG） 链表遍历）──）
        令 实参节点（an）= 首实参（first_arg）（可变）
        循环（当 实参节点（an）大于等于 0 时）：
            如果 实参节点（an）小于 0，那么：跳出循环
            调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（an））
            实参节点（an） = 调用 AST 访问器系列（ast_b）（an）

        如果 函数名索引（func_ni）大于等于 0，那么：
            令 符号索引（si）= 调用 查找泛型符号（gsym）（find_gsym）（func_ni）
            如果 符号索引（si）大于等于 0 且 调用 符号类别（sym_kind）（si）等于 符号类别：函数（SYM_FN），那么：
                返回 调用 符号类型（sym_type）（si）
        返回 类型表预分配：单元（TI_UNIT）

    （── 直接函数调用（非方法） ──）
    如果 调用 AST 访问器系列（ast_kind）（func_node）等于 标识符表达式（EXPR_IDENT），那么：
        令 函数名索引（func_ni） = 调用 AST 访问器系列（ast_int_val）（func_node）

    （── @内建（builtin）（args） —— 将参数从 调用表达式（EXPR_CALL） 转移到 属性访问表达式（EXPR_AT） 再委托 ──）
    如果 调用 AST 访问器系列（ast_kind）（func_node）等于 内建注解表达式（EXPR_AT），那么：
        调用 AST 访问器：设置变量乙（b）（ast_set_b）（被调用节点（func_node），首实参（first_arg））
        返回 调用 类型推断表达式（infer_expr）（func_node）

    （── 检查内建函数（只处理 syscall3，操作系统通信，无 .cr 体）──）
    如果 函数名索引（func_ni）大于等于 0，那么：
        令 函数名字符串（s）= 调用 驻留字符串获取（istr_get）（func_ni）
        如果 函数名字符串（s）等于 "syscall3"，那么：返回 类型表预分配：整数（TI_INT）

    （── 检查 符号：动态库函数（SYM_SO_FN）（已注册 .so 扩展）──）
    令 .so 函数符号索引（so_fn_fi）= -1（可变）
    如果 函数名索引（func_ni）大于等于 0，那么：
        令 符号索引（si）= 调用 查找泛型符号（gsym）（find_gsym）（func_ni）
        如果 符号索引（si）大于等于 0 且 调用 符号类别（sym_kind）（si）等于 符号类别：动态库函数（SYM_SO_FN），那么：
            令 .so 函数符号索引（so_fn_fi） = 符号索引（si）
            令 标签标记（tag_flags2）= 调用 符号类型（sym_type）（si）   （存储标签标记）
            令 类型编码值（type_enc2）= 调用 符号节点（sym_node）（si）   （存储类型编码）

            （推断实参类型：沿 参数表达式（EXPR_ARG） 链表遍历）
            令 实参节点（an）= 首实参（first_arg）（可变）
            循环（当 实参节点（an）大于等于 0 时）：
                如果 实参节点（an）小于 0，那么：跳出循环
                调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（an））
                实参节点（an） = 调用 AST 访问器系列（ast_b）（an）

            （解码返回类型：type_enc2 % 100 → TI_*）
            令 返回代码（ret_code2）= 类型编码值（type_enc2） - （类型编码值（type_enc2） / 100） * 100（可变）
            如果 返回代码（ret_code2）等于 0，那么：返回 类型表预分配：整数（TI_INT）
            如果 返回代码（ret_code2）等于 1，那么：返回 类型表预分配：字符串（TI_STR）
            如果 返回代码（ret_code2）等于 2，那么：返回 类型表预分配：单元（TI_UNIT）
            如果 返回代码（ret_code2）等于 3，那么：返回 类型表预分配：浮点数（TI_FLOAT）
            如果 返回代码（ret_code2）等于 4，那么：返回 类型表预分配：布尔（TI_BOOL）
            返回 类型表预分配：单元（TI_UNIT）

    （── 查找普通函数 ──）
    如果 函数名索引（func_ni）大于等于 0 且 .so 函数符号索引（so_fn_fi）小于 0，那么：
        令 符号索引（si）= 调用 查找泛型符号（gsym）（find_gsym）（func_ni）
        如果 符号索引（si）大于等于 0 且 调用 符号类别（sym_kind）（si）等于 符号类别：函数（SYM_FN），那么：
            （检查是否为泛型函数）
            令 函数表索引（fi）= 调用 查找函数（find_func）（func_ni）
            如果 函数表索引（fi）大于等于 0 且 调用 函数信息访问器系列（fi_generic_count）（fi）大于 0，那么：
                返回 调用 类型推断泛型调用（infer_gen_call）（函数表索引（fi），节点（node），首实参（first_arg），实参个数（arg_count））
            返回 调用 符号类型（sym_type）（si）

        （检查运行时内建函数（无 .cr 体，在 rt.状态（s） 中实现））
        令 内建索引（bi）= 0（可变）
        循环（当 内建索引（bi）小于 运行时内建函数计数（g_rt_builtin_count）时）：
            如果 内建索引（bi）大于等于 运行时内建函数计数（g_rt_builtin_count），那么：跳出循环
            如果 调用 读写全局（r64）（运行时内建函数名数组（g_rt_builtin_names），内建索引（bi） * 8）等于 函数名索引（func_ni），那么：
                返回 调用 读写全局（r64）（运行时内建函数返回类型数组（g_rt_builtin_ret_types），内建索引（bi） * 8）
            内建索引（bi） = 内建索引（二元信息） + 1

        （符号表和内建函数中都未找到——报告错误）
        令 名字（name）= 调用 驻留字符串获取（istr_get）（func_ni）
        调用 检查错误（check_error）（EC_N_FUNC，"未定义函数 '" + 名字（name）+ "'"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
        返回 类型表预分配：永无（TI_NEVER）

    （推断实参类型（副作用），外部/未知函数默认返回 整数（int））
    令 实参节点（an）= 首实参（first_arg）（可变）
    循环（当 实参节点（an）大于等于 0 时）：
        如果 实参节点（an）小于 0，那么：跳出循环
        调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（an））
        实参节点（an） = 调用 AST 访问器系列（ast_b）（an）
    返回 类型表预分配：整数（TI_INT）

（── 代码块 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 代码块表达式（EXPR_BLOCK），那么：
    令 语句起始（stmt_start）= 调用 AST 访问器系列（ast_a）（node）
    令 语句计数（stmt_count）= 调用 AST 访问器系列（ast_b）（node）
    令 结果类型（res）= 类型表预分配：单元（TI_UNIT）（可变）
    调用 压入借用作用域（push_borrow_scope）（）
    令 语句索引（i）= 0（可变）
    循环（当 语句索引（i）小于 语句计数（stmt_count）时）：
        如果 语句索引（i）大于等于 语句计数（stmt_count），那么：跳出循环
        令 语句节点（sn）= 调用 读写全局（r64）（代码块语句数组（g_block_stmts），（语句起始（stmt_start） + 语句索引（i）） * 8）
        令 结果类型（res） = 调用 类型推断表达式（infer_expr）（sn）
        语句索引（i） = 语句索引（索引） + 1
    调用 弹出借用作用域（pop_borrow_scope）（）
    返回 结果类型（res）

（── 如果（if） 表达式 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 如果表达式（EXPR_IF），那么：
    令 条件（cond）= 调用 AST 访问器系列（ast_a）（node）
    令 真分支（then_node）= 调用 AST 访问器系列（ast_b）（node）
    令 假分支（else_node）= 调用 AST 访问器系列（ast_c）（node）
    令 条件类型表索引（cond_ti）= 调用 类型推断表达式（infer_expr）（cond）
    （接受整数作为真假判断（不仅限于布尔））
    如果 条件类型表索引（cond_ti）不等于 类型表预分配：布尔（TI_BOOL）且 条件类型表索引（cond_ti）不等于 类型表预分配：整数（TI_INT），那么：
        调用 检查错误（check_error）（EC_TC_IF_COND，"如果条件必须是布尔或整数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））

    （── 动态类型集合合并：保存 如果（if） 之前的状态 ──）
    令 如果（if） 前动态类型集合计数（pre_dyn_count）= 动态类型集合计数（g_dyn_type_set_count）（可变）
    令 如果（if） 前动态类型集合保存缓冲（pre_dyn_save）= ""（可变）
    如果 如果（if） 前动态类型集合计数（pre_dyn_count）大于 0，那么：
        令 如果（if） 前动态类型集合保存缓冲（pre_dyn_save） = 调用 分配（alloc）（如果 前动态类型集合计数（pre_dyn_count） * 8）的字节
        调用 内部：动态拷贝（_dyncpy）（动态类型集合数组（g_dyn_type_sets），如果（if） 前动态类型集合计数（pre_dyn_count） * 8，如果 前动态类型集合保存缓冲（pre_dyn_save））

    （── 处理真分支 ──）
    调用 压入借用作用域（push_borrow_scope）（）
    令 真分支类型表索引（then_ti）= 调用 类型推断表达式（infer_expr）（then_node）
    调用 弹出借用作用域（pop_borrow_scope）（）

    （── 保存真分支的动态类型集合状态 ──）
    令 真分支动态类型集合计数（then_dyn_count）= 动态类型集合计数（g_dyn_type_set_count）（可变）
    令 真分支动态类型集合保存缓冲（then_dyn_save）= ""（可变）
    如果 真分支动态类型集合计数（then_dyn_count）大于 0，那么：
        令 真分支动态类型集合保存缓冲（then_dyn_save） = 调用 分配（alloc）（真分支动态类型集合计数（then_dyn_count） * 8）的字节
        调用 内部：动态拷贝（_dyncpy）（动态类型集合数组（g_dyn_type_sets），真分支动态类型集合计数（then_dyn_count） * 8，真分支动态类型集合保存缓冲（then_dyn_save））

    （── 恢复 如果（if） 之前状态（清零超过 如果 前计数的过期条目）──）
    令 动态类型集合计数（g_dyn_type_set_count） = 如果（if） 前动态类型集合计数（pre_dyn_count）
    如果 如果（if） 前动态类型集合计数（pre_dyn_count）大于 0，那么：
        调用 内部：动态拷贝（_dyncpy）（如果（if） 前动态类型集合保存缓冲（pre_dyn_save），如果 前动态类型集合计数（pre_dyn_count） * 8，动态类型集合数组（g_dyn_type_sets））
    令 清零索引（iz）= 如果（if） 前动态类型集合计数（pre_dyn_count）（可变）
    循环（当 清零索引（iz）小于 真分支动态类型集合计数（then_dyn_count）时）：
        如果 清零索引（iz）大于等于 真分支动态类型集合计数（then_dyn_count），那么：跳出循环
        调用 读写全局（w64）（动态类型集合数组（g_dyn_type_sets），清零索引（iz） * 8，0）
        清零索引（iz） = 清零索引（iz） + 1

    （── 处理假分支（如果存在）──）
    如果 假分支（else_node）大于等于 0，那么：
        调用 压入借用作用域（push_borrow_scope）（）
        令 假分支类型表索引（else_ti）= 调用 类型推断表达式（infer_expr）（else_node）
        调用 弹出借用作用域（pop_borrow_scope）（）

        （── 合并两个分支的动态类型集合 ──）
        令 合并后的计数（merge_count）= 真分支动态类型集合计数（then_dyn_count）（可变）
        如果 动态类型集合计数（g_dyn_type_set_count）大于 合并后的计数（merge_count），那么：令 合并后的计数（merge_count） = 动态类型集合计数（g_dyn_type_set_count）
        调用 扩展动态类型集数组（grow_dyn_type_sets）（merge_count）
        令 动态类型集合计数（g_dyn_type_set_count） = 合并后的计数（merge_count）
        令 合并索引（mi）= 0（可变）
        循环（当 合并索引（mi）小于 合并后的计数（merge_count）时）：
            如果 合并索引（mi）大于等于 合并后的计数（merge_count），那么：跳出循环
            令 真分支位图（then_bits）= 0（可变）
            如果 合并索引（mi）小于 真分支动态类型集合计数（then_dyn_count），那么：令 真分支位图（then_bits） = 调用 读写全局（r64）（真分支动态类型集合保存缓冲（then_dyn_save），合并索引（mi） * 8）
            令 假分支位图（else_bits）= 0（可变）
            如果 合并索引（mi）小于 动态类型集合计数（g_dyn_type_set_count），那么：令 假分支位图（else_bits） = 调用 读写全局（r64）（动态类型集合数组（g_dyn_type_sets），合并索引（mi） * 8）
            令 合并后位图（merged）= 调用 联合位图（union_bitmaps）（真分支位图（then_bits），假分支位图（else_bits））
            调用 读写全局（w64）（动态类型集合数组（g_dyn_type_sets），合并索引（mi） * 8，合并后位图（merged））
            合并索引（mi） = 合并索引（mi） + 1
        令 动态类型集合计数（g_dyn_type_set_count） = 合并后的计数（merge_count）

        如果 非 调用 类型相等（equal）（type_equal）（真分支类型表索引（then_ti），假分支类型表索引（else_ti））且 真分支类型表索引（then_ti）不等于 类型表预分配：永无（TI_NEVER）且 假分支类型表索引（else_ti）不等于 类型表预分配：永无（TI_NEVER），那么：
            调用 检查错误（check_error）（如果分支类型错误码（EC_TC_IF_BRANCH），"如果分支的类型不同"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
        返回 真分支类型表索引（then_ti）

    返回 类型表预分配：单元（TI_UNIT）

（── 协程启动（go） 表达式 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 协程表达式（EXPR_GO），那么：
    （变量甲（a）=-1，变量乙（b）=函数体；变量丙（c）=迭代名索引（>=0 表示范围模式），数据（data）=范围节点）
    令 函数体（body）= 调用 AST 访问器系列（ast_b）（node）
    调用 压入借用作用域（push_borrow_scope）（）
    令 函数体类型表索引（body_ti）= 调用 类型推断表达式（infer_expr）（body）
    调用 弹出借用作用域（pop_borrow_scope）（）
    令 范围节点（rn）= 调用 AST 访问器系列（ast_data）（node）
    如果 范围节点（rn）小于等于 0，那么：
        返回 函数体类型表索引（body_ti）  （单个 协程启动（go）：函数体类型的 future）
    （范围 协程启动（go）：返回数组类型的函数体类型（大小来自 数据（data）=range_node））
    令 范围表达式（range_node）= 调用 AST 访问器系列（ast_data）（node）
    令 范围计数（rng_count）= 调用 AST 访问器系列（ast_b）（range_node） - 调用 AST 访问器系列（ast_a）（range_node）
    返回 调用 分配类型（alloc_type）（类型条目类别：数组（TYP_ARRAY），函数体类型表索引（body_ti），范围计数（rng_count））

（── 让出（yield） 表达式 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 让出表达式（EXPR_YIELD），那么：
    令 值（val）= 调用 AST 访问器系列（ast_a）（node）
    令 值类型表索引（val_ti）= 类型表预分配：单元（TI_UNIT）（可变）
    如果 值（val）大于等于 0，那么：令 值类型表索引（val_ti） = 调用 类型推断表达式（infer_expr）（值（值））
    返回 值类型表索引（val_ti）

（── 等待（await） 表达式 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 等待表达式（EXPR_AWAIT），那么：
    令 值（val）= 调用 AST 访问器系列（ast_a）（node）
    令 值类型表索引（val_ti）= 调用 类型推断表达式（infer_expr）（val）
    （如果等待一个 泛型参数（T） 类型的数组，返回数组元素类型 泛型参数 T）
    （如果等待单个 future，直接返回其类型）
    如果 调用 获取类型类别（get_type_kind）（val_ti）等于 类型条目类别：数组（TYP_ARRAY），那么：
        返回 调用 获取类型数据（get_type_data）（val_ti）
    返回 值类型表索引（val_ti）

（── 循环表达式（loop）──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 循环表达式（EXPR_LOOP），那么：
    调用 压入借用作用域（push_borrow_scope）（）
    调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））
    调用 弹出借用作用域（pop_borrow_scope）（）
    返回 类型表预分配：单元（TI_UNIT）

（── 当（while） 循环 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 当循环表达式（EXPR_WHILE），那么：
    令 条件（cond）= 调用 AST 访问器系列（ast_a）（node）
    令 循环体（body）= 调用 AST 访问器系列（ast_b）（node）
    令 条件类型表索引（cond_ti）= 调用 类型推断表达式（infer_expr）（cond）
    如果 条件类型表索引（cond_ti）不等于 类型表预分配：布尔（TI_BOOL），那么：
        调用 检查错误（check_error）（EC_TC_WHILE_COND，"当循环条件必须是布尔"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
    调用 压入借用作用域（push_borrow_scope）（）
    调用 类型推断表达式（infer_expr）（body）
    调用 弹出借用作用域（pop_borrow_scope）（）
    返回 类型表预分配：单元（TI_UNIT）

（── 遍历（for） 循环 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 遍历表达式（EXPR_FOR），那么：
    令 变量名索引（var_ni）= 调用 AST 访问器系列（ast_a）（node）
    令 迭代源（iter）= 调用 AST 访问器系列（ast_b）（node）
    令 循环体（body）= 调用 AST 访问器系列（ast_c）（node）
    调用 类型推断表达式（infer_expr）（iter）
    调用 压入作用域（push_scope）（）
    调用 压入借用作用域（push_borrow_scope）（）
    调用 定义符号（def_sym）（变量名索引（var_ni），符号类别：局部变量（SYM_LOCAL），类型表预分配：整数（TI_INT），-1）
    调用 类型推断表达式（infer_expr）（body）
    调用 弹出借用作用域（pop_borrow_scope）（）
    调用 弹出作用域（pop_scope）（）
    返回 类型表预分配：单元（TI_UNIT）

（── 范围表达式 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 范围表达式（EXPR_RANGE），那么：
    令 起始类型（st）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））
    令 结束类型（et）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_b）（node））
    如果 起始类型（st）不等于 类型表预分配：整数（TI_INT），那么：
        调用 检查错误（check_error）（加法类型错误码（EC_TB_ADD），"范围起始必须是整数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
    如果 结束类型（et）不等于 类型表预分配：整数（TI_INT），那么：
        调用 检查错误（check_error）（加法类型错误码（EC_TB_ADD），"范围结束必须是整数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
    返回 类型表预分配：整数（TI_INT）

（── 匹配表达式（match）──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 匹配表达式（EXPR_MATCH），那么：
    令 被匹配表达式（match_expr）= 调用 AST 访问器系列（ast_a）（node）
    令 首分支（first_arm）= 调用 AST 访问器系列（ast_b）（node）
    调用 类型推断表达式（infer_expr）（match_expr）
    令 结果类型（res）= 类型表预分配：单元（TI_UNIT）（可变）
    令 分支索引（ai）= 0（可变）
    令 分支节点（an）= 首分支（first_arm）（可变）
    循环（当 分支节点（an）大于等于 0 时）：
        如果 分支节点（an）小于 0，那么：跳出循环
        令 分支模式（arm_pat）= 调用 AST 访问器系列（ast_a）（an）  （EXPR_ARM：变量甲（a） = 模式）
        令 分支体（arm_body）= 调用 AST 访问器系列（ast_b）（an）  （EXPR_ARM：变量乙（b） = 分支体）
        （在新作用域中绑定模式变量）
        调用 压入作用域（push_scope）（）
        如果 分支模式（arm_pat）大于等于 0，那么：
            如果 调用 AST 访问器系列（ast_kind）（arm_pat）等于 枚举模式表达式（EXPR_ENUMPAT），那么：
                （绑定子模式）
                令 子模式（sub_pat）= 调用 AST 访问器系列（ast_b）（arm_pat）
                令 子模式个数（sub_count）= 调用 AST 访问器系列（ast_c）（arm_pat）
                令 子模式索引（spi）= 0（可变）
                令 子模式节点（spn）= 子模式（sub_pat）（可变）
                循环（当 子模式索引（spi）小于 子模式个数（sub_count）时）：
                    如果 子模式索引（spi）大于等于 子模式个数（sub_count），那么：跳出循环
                    如果 子模式节点（spn）大于等于 0，那么：
                        如果 调用 AST 访问器系列（ast_kind）（spn）等于 标识符表达式（EXPR_IDENT），那么：
                            调用 定义符号（def_sym）（调用 AST 访问器系列（ast_int_val）（spn），符号类别：局部变量（SYM_LOCAL），类型表预分配：整数（TI_INT），-1）
                        子模式节点（spn） = 子模式节点（spn） + 1
                    子模式索引（spi） = 子模式索引（spi） + 1
            如果 调用 AST 访问器系列（ast_kind）（arm_pat）等于 标识符表达式（EXPR_IDENT），那么：
                调用 定义符号（def_sym）（调用 AST 访问器系列（ast_int_val）（arm_pat），符号类别：局部变量（SYM_LOCAL），类型表预分配：整数（TI_INT），-1）
        调用 压入借用作用域（push_borrow_scope）（）
        令 分支类型表索引（arm_ti）= 调用 类型推断表达式（infer_expr）（arm_body）
        调用 弹出借用作用域（pop_borrow_scope）（）
        如果 分支索引（ai）等于 0，那么：令 结果类型（res） = 分支类型表索引（arm_ti）
        调用 弹出作用域（pop_scope）（）
        分支节点（an） = 调用 AST 访问器系列（ast_c）（an）  （下一个分支通过链表）
        分支索引（ai） = 分支索引（ai） + 1
    返回 结果类型（res）

（── 声明（let） ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 声明表达式（EXPR_LET），那么：
    令 变量名索引（var_ni）= 调用 AST 访问器系列（ast_a）（node）
    令 类型节点（type_node）= 调用 AST 访问器系列（ast_b）（node）
    令 值节点（val_node）= 调用 AST 访问器系列（ast_c）（node）
    令 值类型表索引（val_ti）= 类型表预分配：单元（TI_UNIT）
    如果 值节点（val_node）大于等于 0，那么：
        令 值类型表索引（val_ti） = 调用 类型推断表达式（infer_expr）（val_node）
        （检查值是否为借用（&变量甲（x） 或 &可变（mut） 变量甲），记录持有者）
        如果 调用 AST 访问器系列（ast_kind）（val_node）等于 一元运算表达式（EXPR_UNARY）且 调用 AST 访问器系列（ast_c）（val_node）等于 一元取引用（UOP_REF），那么：
            令 被借用者名索引（borrowed_ni）= 调用 借用变量名称（borrow_var_name）（调用 AST 访问器系列（ast_a）（val_node））
            如果 被借用者名索引（borrowed_ni）大于等于 0，那么：
                令 可变标记（mut_flag）= 调用 AST 访问器系列（ast_int_val）（val_node）
                调用 记录借用持有者（record_borrow_holder）（变量名索引（var_ni），被借用者名索引（borrowed_ni），可变标记（mut_flag））
    令 类型表索引（ti）= 值类型表索引（val_ti）
    如果 类型节点（type_node）大于等于 0，那么：令 类型表索引（ti） = 调用 解析类型节点（res_type_node）（type_node）
    如果 调用 驻留字符串获取（istr_get）（var_ni）不等于 "下划线（_）"，那么：
        调用 定义符号（def_sym）（变量名索引（var_ni），符号类别：局部变量（SYM_LOCAL），类型表索引（ti），-1）
        如果 类型表索引（ti）等于 类型表预分配：动态（TI_DYN）且 值节点（val_node）大于等于 0，那么：
            调用 扩展动态类型集数组（grow_dyn_type_sets）（g_sym_count）
            调用 读写全局（w64）（动态类型集合数组（g_dyn_type_sets），（符号计数（g_sym_count） - 1） * 8，0）
            调用 动态设置类型（dyn_set_type）（符号计数（g_sym_count） - 1，值类型表索引（val_ti））
    返回 类型表预分配：单元（TI_UNIT）

（── 返回语句 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 返回表达式（EXPR_RETURN），那么：
    如果 调用 AST 访问器系列（ast_a）（node）大于等于 0，那么：
        返回 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））
    返回 类型表预分配：单元（TI_UNIT）

（── 枚举构造器 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 枚举构造器表达式（EXPR_ENUM_CONSTRUCTOR），那么：
    令 名称索引（name_idx）= 调用 AST 访问器系列（ast_a）（node）
    令 首实参（first_arg）= 调用 AST 访问器系列（ast_b）（node）
    令 实参个数（arg_count）= 调用 AST 访问器系列（ast_c）（node）
    令 符号索引（si）= 调用 查找泛型符号（gsym）（find_gsym）（name_idx）
    如果 符号索引（si）大于等于 0 且 调用 符号类别（sym_kind）（si）等于 符号类别：函数（SYM_FN），那么：
        （推断实参类型：沿 参数表达式（EXPR_ARG） 链表遍历）
        令 实参节点（an）= 首实参（first_arg）（可变）
        循环（当 实参节点（an）大于等于 0 时）：
            如果 实参节点（an）小于 0，那么：跳出循环
            调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（an））
            实参节点（an） = 调用 AST 访问器系列（ast_b）（an）
        返回 调用 符号类型（sym_type）（si）  （枚举类型）
    令 名字（name）= 调用 驻留字符串获取（istr_get）（name_idx）
    调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"未定义枚举构造器 '" + 名字（name）+ "'"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
    返回 类型表预分配：单元（TI_UNIT）

（── 字段访问 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 字段访问表达式（EXPR_FIELD），那么：
    令 对象（obj）= 调用 AST 访问器系列（ast_a）（node）
    令 字段名索引（field_ni）= 调用 AST 访问器系列（ast_int_val）（node）
    令 对象类型表索引（obj_ti）= 调用 类型推断表达式（infer_expr）（obj）
    （自动解引用：如果对象是引用类型，展开到内部类型）
    令 实际类型表索引（actual_ti）= 对象类型表索引（obj_ti）（可变）
    如果 实际类型表索引（actual_ti）大于等于 0 且 实际类型表索引（actual_ti）小于 类型计数（g_type_count）且 调用 获取类型类别（get_type_kind）（actual_ti）等于 类型条目类别：引用（TYP_REF），那么：
        令 实际类型表索引（actual_ti） = 调用 获取类型数据（get_type_data）（actual_ti）
    （处理泛型应用：展开到命名基础类型用于结构体查找）
    如果 实际类型表索引（actual_ti）大于等于 0 且 实际类型表索引（actual_ti）小于 类型计数（g_type_count）且 调用 获取类型类别（get_type_kind）（actual_ti）等于 类型条目类别：泛型应用（TYP_GENERIC_APPLY），那么：
        令 实际类型表索引（actual_ti） = 调用 获取类型数据（get_type_data）（actual_ti）
    （命名类型上的字段查找）
    如果 实际类型表索引（actual_ti）大于等于 0 且 实际类型表索引（actual_ti）小于 类型计数（g_type_count）且 调用 获取类型类别（get_type_kind）（actual_ti）等于 类型条目类别：命名（TYP_NAMED），那么：
        令 结构体名索引（struct_ni）= 调用 获取类型数据（get_type_data）（actual_ti）
        令 结构体表索引（si）= 调用 查找结构体（find_struct）（struct_ni）
        如果 结构体表索引（si）大于等于 0，那么：
            令 字段索引（fi）= 0（可变）
            循环（当 字段索引（fi）小于 调用 结构体信息访问器系列（si_field_count）（si）时）：
                如果 字段索引（fi）大于等于 调用 结构体信息访问器系列（si_field_count）（si），那么：跳出循环
                如果 调用 结构体信息访问器系列（si_field_name）（结构体表索引（si），字段索引（fi））等于 字段名索引（field_ni），那么：
                    调用 AST 访问器：设置数据（ast_set_data）（节点（node），字段索引（fi））  （存储字段索引给 ir_gen 用）
                    调用 AST 访问器：设置变量丙（c）（ast_set_c）（节点（node），结构体名索引（struct_ni））  （存储结构体名索引给 ELF 后端）
                    （解析字段类型，必要时替换泛型参数）
                    令 字段类型节点（ft_node）= 调用 结构体信息访问器系列（si_field_type_node）（结构体表索引（si），字段索引（fi））
                    如果 字段类型节点（ft_node）大于等于 0，那么：
                        如果 调用 AST 访问器系列（ast_kind）（ft_node）等于 标识符表达式（EXPR_IDENT），那么：
                            令 字段类型名索引（ft_name_idx）= 调用 AST 访问器系列（ast_int_val）（ft_node）
                            （检查字段类型是否为泛型参数——如果是且有泛型应用则替换）
                            如果 调用 判断结构体泛型（is_struct_generic）（结构体表索引（si），字段类型名索引（ft_name_idx））且 调用 获取类型类别（get_type_kind）（obj_ti）等于 类型条目类别：泛型应用（TYP_GENERIC_APPLY），那么：
                                令 基础类型（base_ti）= 调用 获取类型数据（get_type_data）（obj_ti）
                                令 泛型应用起始（ga_start）= 调用 获取类型额外（get_type_extra）（obj_ti）
                                令 泛型参数个数（ga_count）= 调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），泛型应用起始（ga_start） * 8）
                                （查找泛型参数索引）
                                令 泛型参数查找索引（gpi）= 0（可变）
                                循环（当 泛型参数查找索引（gpi）小于 调用 结构体信息访问器系列（si_generic_count）（si）时）：
                                    如果 泛型参数查找索引（gpi）大于等于 调用 结构体信息访问器系列（si_generic_count）（si），那么：跳出循环
                                    如果 调用 结构体信息访问器系列（si_generic_name）（结构体表索引（si），泛型参数查找索引（gpi））等于 字段类型名索引（ft_name_idx），那么：
                                        如果 泛型参数查找索引（gpi）小于 泛型参数个数（ga_count），那么：
                                            返回 调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），（泛型应用起始（ga_start） + 1 + 泛型参数查找索引（gpi）） * 8）
                                        跳出循环
                                    泛型参数查找索引（gpi） = 泛型参数查找索引（gpi） + 1
                        返回 调用 解析类型节点（res_type_node）（ft_node）
                    返回 调用 结构体信息访问器系列（si_field_type）（结构体表索引（si），字段索引（fi））
                字段索引（fi） = 字段索引（fi） + 1
    （元组字段访问：类型值（t）.0, 类型值.1）
    如果 实际类型表索引（actual_ti）大于等于 0 且 实际类型表索引（actual_ti）小于 类型计数（g_type_count）且 调用 获取类型类别（get_type_kind）（actual_ti）等于 类型条目类别：元组（TYP_TUPLE），那么：
        令 字段名（field_name）= 调用 驻留字符串获取（istr_get）（field_ni）
        令 索引值（idx）= 调用 字符串转整数（str_int）（field_name）
        令 元组元素个数（tc）= 调用 获取类型数据（get_type_data）（actual_ti）
        如果 索引值（idx）大于等于 0 且 索引值（索引）小于 元组元素个数（tc），那么：
            令 数据起始（data_start）= 调用 获取类型额外（get_type_extra）（actual_ti）
            如果 调用 AST 访问器系列（ast_data）（node）不等于 索引值（idx），那么：
                调用 AST 访问器：设置数据（ast_set_data）（节点（node），索引值（idx））
            返回 调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），（数据起始（data_start） + 索引值（idx）） * 8）
    返回 类型表预分配：单元（TI_UNIT）

（── 索引表达式 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 索引访问表达式（EXPR_INDEX），那么：
    令 数组类型表索引（arr_ti）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））
    令 索引类型表索引（idx_ti）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_b）（node））
    令 数组类别（arr_kind）= 调用 获取类型类别（get_type_kind）（arr_ti）
    （范围索引：数组（arr）[low..high] → 切片类型）
    如果 调用 AST 访问器系列（ast_kind）（调用 AST 访问器系列（ast_b）（node））等于 范围表达式（EXPR_RANGE），那么：
        如果 数组类别（arr_kind）等于 类型条目类别：数组（TYP_ARRAY），那么：
            返回 调用 分配类型（alloc_type）（类型条目类别：切片（TYP_SLICE），调用 获取类型数据（get_type_data）（arr_ti），0）
        返回 类型表预分配：单元（TI_UNIT）
    （常规索引：数组（arr）[索引（i）] 或 slice[索引] → 元素类型）
    如果 数组类别（arr_kind）等于 类型条目类别：数组（TYP_ARRAY），那么：
        返回 调用 获取类型数据（get_type_data）（arr_ti）
    如果 数组类别（arr_kind）等于 类型条目类别：切片（TYP_SLICE），那么：
        返回 调用 获取类型数据（get_type_data）（arr_ti）
    如果 数组类型表索引（arr_ti）等于 类型表预分配：字符串（TI_STR），那么：
        返回 类型表预分配：整数（TI_INT）  （字符串[索引（i）] → 字节值）
    调用 检查错误（check_error）（EC_TK_INDEX，"无法索引非数组类型"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
    返回 类型表预分配：整数（TI_INT）

（── 赋值 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 赋值表达式（EXPR_ASSIGN），那么：
    令 目标（target）= 调用 AST 访问器系列（ast_a）（node）
    令 值（val）= 调用 AST 访问器系列（ast_b）（node）
    令 目标类型表索引（tt）= 调用 类型推断表达式（infer_expr）（target）
    令 值类型表索引（vt）= 调用 类型推断表达式（infer_expr）（val）
    如果 目标类型表索引（tt）等于 类型表预分配：动态（TI_DYN），那么：
        （动态赋值：追踪右侧类型，跳过严格类型检查）
        如果 调用 AST 访问器系列（ast_kind）（target）等于 标识符表达式（EXPR_IDENT），那么：
            令 目标名索引（target_ni）= 调用 AST 访问器系列（ast_int_val）（target）
            令 目标符号索引（target_si）= 调用 查找符号（find_sym）（target_ni）
            如果 目标符号索引（target_si）大于等于 0，那么：
                调用 动态设置类型（dyn_set_type）（目标符号索引（target_si），值类型表索引（vt））
    否则如果 非 调用 类型相等（equal）（type_equal）（目标类型表索引（tt），值类型表索引（vt）），那么：
        调用 检查错误（check_error）（EC_TA_ASSIGN，"赋值类型不匹配"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
    返回 值类型表索引（vt）

（── 结构体字面量 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 结构体字面量表达式（EXPR_STRUCT），那么：
    （变量甲（a） = 名字索引，变量乙（b） = 首字段值（包装节点），变量丙（c） = 字段个数）
    令 名称索引（name_ni）= 调用 AST 访问器系列（ast_a）（node）
    （检查结构体是否为泛型）
    令 结构体表索引（si）= 调用 查找结构体按字节名称（find_struct_by_name）（name_ni）
    如果 结构体表索引（si）大于等于 0 且 调用 结构体信息访问器系列（si_generic_count）（si）大于 0，那么：
        （泛型结构体：从字段值推断具体类型）
        令 泛型映射计数（g_gen_map_count） = 0；令 泛型映射容量（g_gen_map_cap） = 0
        令 字段索引（fi）= 0（可变）
        令 字段节点（fn2）= 调用 AST 访问器系列（ast_b）（node）（可变）
        循环（当 字段索引（fi）小于 调用 AST 访问器系列（ast_c）（node）时）：
            如果 字段索引（fi）大于等于 调用 AST 访问器系列（ast_c）（node），那么：跳出循环
            如果 字段索引（fi）小于 调用 结构体信息访问器系列（si_field_count）（si）且 字段节点（fn2）大于等于 0，那么：
                令 字段值类型表索引（field_val_ti）= 调用 类型推断表达式（infer_expr）（fn2）
                令 原始类型节点（orig_type_node）= 调用 结构体信息访问器系列（si_field_type_node）（结构体表索引（si），字段索引（fi））
                如果 原始类型节点（orig_type_node）大于等于 0，那么：
                    如果 调用 AST 访问器系列（ast_kind）（orig_type_node）等于 标识符表达式（EXPR_IDENT），那么：
                        （检查字段类型是否为泛型参数）
                        令 字段名索引（field_name_idx）= 调用 AST 访问器系列（ast_int_val）（orig_type_node）
                        如果 调用 判断结构体泛型（is_struct_generic）（结构体表索引（si），字段名索引（field_name_idx）），那么：
                            调用 扩展泛型映射数组（grow_gen_map）（泛型映射计数（g_gen_map_count） + 1）
                            调用 读写全局（w64）（泛型映射名数组（g_gen_map_names），泛型映射计数（g_gen_map_count） * 8，字段名索引（field_name_idx））
                            调用 读写全局（w64）（泛型映射类型数组（g_gen_map_types），泛型映射计数（g_gen_map_count） * 8，字段值类型表索引（field_val_ti））
                            令 泛型映射计数（g_gen_map_count） = 泛型映射计数（g_gen_map_count） + 1
                字段节点（fn2） = 字段节点（fn2） + 1
            字段索引（fi） = 字段索引（fi） + 1
        （TYP_GENERIC_APPLY）
        令 基础类型表索引（base_ti）= 调用 分配类型（alloc_type）（类型条目类别：命名（TYP_NAMED），名称索引（name_ni），0）
        令 数据起始（ds）= 泛型应用数据计数（g_gen_apply_data_count）
        调用 扩展泛型应用数据数组（grow_gen_apply_data）（数据起始（ds） + 1 + 泛型映射计数（g_gen_map_count））
        调用 读写全局（w64）（泛型应用数据数组（g_gen_apply_data），数据起始（ds） * 8，泛型映射计数（g_gen_map_count））
        令 泛型应用数据计数（g_gen_apply_data_count） = 数据起始（ds） + 1
        令 映射索引（mi）= 0（可变）
        循环（当 映射索引（mi）小于 泛型映射计数（g_gen_map_count）时）：
            如果 映射索引（mi）大于等于 泛型映射计数（g_gen_map_count），那么：跳出循环
            调用 读写全局（w64）（泛型应用数据数组（g_gen_apply_data），（数据起始（ds） + 1 + 映射索引（mi）） * 8，调用 读写全局（r64）（泛型映射类型数组（g_gen_map_types），映射索引（mi） * 8））
            映射索引（mi） = 映射索引（mi） + 1
        令 泛型应用数据计数（g_gen_apply_data_count） = 数据起始（ds） + 1 + 泛型映射计数（g_gen_map_count）
        返回 调用 分配类型（alloc_type）（类型条目类别：泛型应用（TYP_GENERIC_APPLY），基础类型表索引（base_ti），数据起始（ds））

    （非泛型结构体）
    令 类型表索引（ti）= 调用 分配类型（alloc_type）（类型条目类别：命名（TYP_NAMED），名称索引（name_ni），0）
    令 字段索引（fi）= 0（可变）
    令 字段节点（fn2）= 调用 AST 访问器系列（ast_b）（node）（可变）
    循环（当 字段索引（fi）小于 调用 AST 访问器系列（ast_c）（node）时）：
        如果 字段索引（fi）大于等于 调用 AST 访问器系列（ast_c）（node），那么：跳出循环
        如果 字段节点（fn2）大于等于 0，那么：
            调用 类型推断表达式（infer_expr）（fn2）  （包装节点——转发到值）
            字段节点（fn2） = 字段节点（fn2） + 1
        字段索引（fi） = 字段索引（fi） + 1
    返回 类型表索引（ti）

（── 数组字面量 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 数组字面量表达式（EXPR_ARRAY），那么：
    （变量甲（a） = 首元素，变量乙（b） = 元素个数）
    令 元素类型表索引（elem_ti）= 类型表预分配：整数（TI_INT）
    令 元素索引（ei）= 0（可变）
    令 元素节点（en）= 调用 AST 访问器系列（ast_a）（node）（可变）
    循环（当 元素索引（ei）小于 调用 AST 访问器系列（ast_b）（node）时）：
        如果 元素索引（ei）大于等于 调用 AST 访问器系列（ast_b）（node），那么：跳出循环
        如果 元素节点（en）大于等于 0，那么：
            令 元素类型表索引（elem_ti） = 调用 类型推断表达式（infer_expr）（en）
            元素节点（en） = 元素节点（en） + 1
        元素索引（ei） = 元素索引（ei） + 1
    返回 调用 分配类型（alloc_type）（类型条目类别：数组（TYP_ARRAY），元素类型表索引（elem_ti），调用 AST 访问器系列（ast_b）（node））

（── 简单表达式 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 跳出循环表达式（EXPR_BREAK），那么：返回 类型表预分配：单元（TI_UNIT）
如果 调用 AST 访问器系列（ast_kind）（node）等于 继续表达式（EXPR_CONTINUE），那么：返回 类型表预分配：单元（TI_UNIT）
如果 调用 AST 访问器系列（ast_kind）（node）等于 通配表达式（EXPR_WILDCARD），那么：返回 类型表预分配：单元（TI_UNIT）

（── 移动 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 移动表达式（EXPR_MOVE），那么：
    返回 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））

（── 非安全（unsafe） 块 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 不安全块表达式（EXPR_UNSAFE），那么：
    调用 压入不安全作用域（push_unsafe_scope）（）
    令 返回类型（ret）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））
    调用 弹出不安全作用域（pop_unsafe_scope）（）
    返回 返回类型（ret）

（── 尝试（try） 操作符 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 尝试表达式（EXPR_TRY），那么：
    （Try 操作符：展开 可选类型（Option）[泛型参数（T）] → 泛型参数，结果类型（Result）[泛型参数,错误（E）] → 泛型参数 T）
    令 内部类型表索引（inner_ti）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））
    如果 调用 获取类型类别（get_type_kind）（inner_ti）等于 类型条目类别：泛型应用（TYP_GENERIC_APPLY），那么：
        令 基础类型（base_ti）= 调用 获取类型数据（get_type_data）（inner_ti）
        如果 调用 获取类型类别（get_type_kind）（base_ti）等于 类型条目类别：命名（TYP_NAMED），那么：
            令 基础名索引（base_ni）= 调用 获取类型数据（get_type_data）（base_ti）
            令 基础名字符串（base_name）= 调用 驻留字符串获取（istr_get）（base_ni）
            如果 基础名字符串（base_name）等于 "可选类型（Option）" 或 基础名字符串（base_name）等于 "结果类型（Result）"，那么：
                令 泛型应用起始（ga_start）= 调用 获取类型额外（get_type_extra）（inner_ti）
                如果 调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），泛型应用起始（ga_start） * 8）大于等于 1，那么：
                    返回 调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），（泛型应用起始（ga_start） + 1） * 8）  （第一个类型参数）
    返回 内部类型表索引（inner_ti）

（── 结构体模式 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 结构体模式表达式（EXPR_STRUCTPAT），那么：返回 类型表预分配：单元（TI_UNIT）

（── 类型转换（as） 类型转换 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 类型转换表达式（EXPR_AS），那么：
    （表达式（expr） 类型转换（as） 类型（Type）——类型转换）
    令 内部类型表索引（inner_ti）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））
    令 类型节点（type_node）= 调用 AST 访问器系列（ast_b）（node）
    返回 调用 解析类型节点（res_type_node）（type_node）

（── 语句 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 语句表达式（EXPR_STMT），那么：
    调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（node））
    返回 类型表预分配：单元（TI_UNIT）

（── 元组 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 元组字面量表达式（EXPR_TUPLE），那么：
    （创建 TYP_TUPLE 类型，包含元素类型）
    令 元素索引（elem_idx）= 调用 AST 访问器系列（ast_a）（node）
    令 元素个数（ec）= 调用 AST 访问器系列（ast_b）（node）（可变）
    令 数据起始（data_start）= 泛型应用数据计数（g_gen_apply_data_count）
    令 元素计数（e）= 0（可变）
    循环（当 元素计数（e）小于 元素个数（ec）时）：
        如果 元素计数（e）大于等于 元素个数（ec），那么：跳出循环
        令 元素类型（elem_ti）= 调用 类型推断表达式（infer_expr）（元素索引（elem_idx） + 元素计数（e））
        调用 扩展泛型应用数据数组（grow_gen_apply_data）（泛型应用数据计数（g_gen_apply_data_count） + 1）
        调用 读写全局（w64）（泛型应用数据数组（g_gen_apply_data），泛型应用数据计数（g_gen_apply_data_count） * 8，元素类型（elem_ti））
        令 泛型应用数据计数（g_gen_apply_data_count） = 泛型应用数据计数（g_gen_apply_data_count） + 1
        元素计数（e） = 元素计数（e） + 1
    返回 调用 分配类型（alloc_type）（类型条目类别：元组（TYP_TUPLE），元素个数（ec），数据起始（data_start））

（── @ 内建注解 ──）
如果 调用 AST 访问器系列（ast_kind）（node）等于 内建注解表达式（EXPR_AT），那么：
    令 名称索引（name_ni）= 调用 AST 访问器系列（ast_a）（node）
    令 名字（name）= 调用 驻留字符串获取（istr_get）（name_ni）
    令 参数（args）= 调用 AST 访问器系列（ast_b）（node）

    （@大小计算（sizeOf）（T）——一个类型参数）
    如果 调用 字符串相等比较（str_eq）（名字（name），"大小计算（sizeOf）"）不等于 0，那么：
        如果 参数（args）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@大小计算（sizeOf） 需要一个类型参数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            返回 类型表预分配：永无（TI_NEVER）
        令 类型表索引（ti）= 调用 解析类型节点（res_type_node）（args）
        如果 类型表索引（ti）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@大小计算（sizeOf）：未知类型"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            返回 类型表预分配：永无（TI_NEVER）
        返回 类型表预分配：整数（TI_INT）

    （@地址（addr）（fn）——函数地址，类型为 整数（int））
    如果 调用 字符串相等比较（str_eq）（名字（name），"地址（addr）"）不等于 0，那么：
        调用 AST 访问器：设置类型值（ast_set_type_val）（节点（node），类型表预分配：整数（TI_INT））
        返回 类型表预分配：整数（TI_INT）

    （@对齐计算（alignOf）（T）——一个类型参数）
    如果 调用 字符串相等比较（str_eq）（名字（name），"对齐计算（alignOf）"）不等于 0，那么：
        如果 参数（args）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@对齐计算（alignOf） 需要一个类型参数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            返回 类型表预分配：永无（TI_NEVER）
        令 类型表索引（ti）= 调用 解析类型节点（res_type_node）（args）
        如果 类型表索引（ti）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@对齐计算（alignOf）：未知类型"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            返回 类型表预分配：永无（TI_NEVER）
        返回 类型表预分配：整数（TI_INT）

    （@fields（T）——一个类型参数，返回 []字符串（string））
    如果 调用 字符串相等比较（str_eq）（名字（name），"fields"）不等于 0，那么：
        如果 参数（args）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@fields 需要一个类型参数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            返回 类型表预分配：永无（TI_NEVER）
        令 类型表索引（ti）= 调用 解析类型节点（res_type_node）（args）
        返回 类型表预分配：字符串（TI_STR）

    （@字段检查（hasField）（泛型参数 T（T）, name）——类型 + 字符串两个参数）
    如果 调用 字符串相等比较（str_eq）（名字（name），"字段检查（hasField）"）不等于 0，那么：
        如果 参数（args）小于 0 或 调用 AST 访问器系列（ast_b）（args）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@字段检查（hasField） 需要 2 个参数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            返回 类型表预分配：永无（TI_NEVER）
        令 类型表索引（ti）= 调用 解析类型节点（res_type_node）（调用 AST 访问器系列（ast_a）（args））
        返回 类型表预分配：布尔（TI_BOOL）

    （@field（泛型参数 T（T）, name）——类型 + 字符串，返回 FieldInfo）
    如果 调用 字符串相等比较（str_eq）（名字（name），"field"）不等于 0，那么：
        如果 参数（args）小于 0 或 调用 AST 访问器系列（ast_b）（args）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@field 需要 2 个参数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            返回 类型表预分配：永无（TI_NEVER）
        令 类型表索引（ti）= 调用 解析类型节点（res_type_node）（调用 AST 访问器系列（ast_a）（args））
        返回 类型表预分配：整数（TI_INT）

    （@typeInfo（T）——返回 TypeInfo）
    如果 调用 字符串相等比较（str_eq）（名字（name），"typeInfo"）不等于 0，那么：
        如果 参数（args）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@typeInfo 需要一个类型参数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            返回 类型表预分配：永无（TI_NEVER）
        令 类型表索引（ti）= 调用 解析类型节点（res_type_node）（args）
        返回 类型表预分配：整数（TI_INT）  （占位—返回句柄）

    （@comptime（expr）——强制编译时求值）
    如果 调用 字符串相等比较（str_eq）（名字（name），"comptime"）不等于 0，那么：
        如果 参数（args）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@comptime 需要一个表达式"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            返回 类型表预分配：永无（TI_NEVER）
        令 值类型（v）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（args））
        调用 AST 访问器：设置类型值（ast_set_type_val）（节点（node），值类型（v））
        返回 值类型（v）

    （@inline（fn）——内联提示）
    如果 调用 字符串相等比较（str_eq）（名字（name），"inline"）不等于 0，那么：
        如果 参数（args）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@inline 需要一个函数参数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
            返回 类型表预分配：永无（TI_NEVER）
        令 值类型（v）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（args））
        调用 AST 访问器：设置类型值（ast_set_type_val）（节点（node），值类型（v））
        返回 值类型（v）

    （@no_bounds_check——无参数，单元类型）
    如果 调用 字符串相等比较（str_eq）（名字（name），"no_bounds_check"）不等于 0，那么：返回 类型表预分配：单元（TI_UNIT）

    （@fast——无参数，单元类型）
    如果 调用 字符串相等比较（str_eq）（名字（name），"fast"）不等于 0，那么：返回 类型表预分配：单元（TI_UNIT）

    （@unroll（n）——需要整数参数）
    如果 调用 字符串相等比较（str_eq）（名字（name），"unroll"）不等于 0，那么：
        如果 参数（args）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@unroll 需要一个整数参数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
        返回 类型表预分配：单元（TI_UNIT）

    （@section（name）——需要字符串参数）
    如果 调用 字符串相等比较（str_eq）（名字（name），"section"）不等于 0，那么：
        如果 参数（args）小于 0，那么：
            调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"@section 需要一个字符串参数"，调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
        返回 类型表预分配：单元（TI_UNIT）

    （@热补丁（hotpatch）——函数注解，非表达式）
    如果 调用 字符串相等比较（str_eq）（名字（name），"热补丁（hotpatch）"）不等于 0，那么：返回 类型表预分配：单元（TI_UNIT）

    （未知 @ 内建——报告错误）
    调用 检查错误（check_error）（未定义名称错误码（EC_N_UNDEFINED），"未知 @ 内建：" + 名字（name），调用 AST 访问器系列（ast_line）（node），调用 AST 访问器系列（ast_col）（节点（节点）））
    返回 类型表预分配：单元（TI_UNIT）

（── 兜底 ──）
返回 类型表预分配：单元（TI_UNIT）
`

### 测试要点
1. 整数字面量 42：返回 类型信息：整数（TI_INT）
2. 标识符引用已定义变量（TI_INT）：返回 类型信息：整数（类型信息：整数）
3. 被借用的变量被使用：产生 借用期间使用错误码（EC_B_USE_WHILE_BORROWED） 诊断
4. 未定义变量：产生 未定义名称错误码（EC_N_UNDEFINED） 诊断
5. 二元加法 整数（int）+整数：返回 类型信息：整数（TI_INT）；整数+字符串（string）：返回 类型信息：字符串（TI_STR）；自定义类型+整数：产生 加法类型错误码（EC_TB_ADD）
6. &变量甲（x） 取引用（非 非安全（unsafe） 块内）：返回 指针类型（TYP_PTR）（inner, asp=0）
7. &变量甲（x） 取引用（非安全（unsafe） 块内）：返回 指针类型（TYP_PTR）（inner, asp=1）
8. *变量甲（x） 解引用 引用类型（TYP_REF）/指针类型（TYP_PTR）：返回内部类型
9. 泛型函数调用：触发 类型推断泛型调用（infer_gen_call） 进行类型推断
10. 符号：动态库函数（SYM_SO_FN） 调用通过类型编码解码返回类型
11. 模块限定调用（模块.函数）通过模块函数表查找
12. 如果（if）-否则（else） 两分支：动态类型集合合并（union_bitmaps），类型不同产生 如果分支类型错误码（EC_TC_IF_BRANCH）
13. 动态（dyn） 类型上方法调用：通过 验证动态方法（validate_dyn_method） 验证所有可能类型
14. 结构体字面量泛型推断：通过字段类型映射泛型参数创建 泛型应用类型（TYP_GENERIC_APPLY）
15. 尝试（try）? 操作符：对 可选类型（Option）[泛型参数 泛型参数（T）（泛型参数 T）] 或 结果类型（Result）[泛型参数 泛型参数,错误（E）] 提取第一类型参数

## 函数 检查全部（check_all）
**签名：** `函数（fn） 检查全部（check_all）（）`

### 作用
整个检查管线的主入口。按顺序：初始化类型表 → 保存 符号：动态库函数（SYM_SO_FN） 条目 → 清空符号表/诊断/泛型状态 → 第一遍收集声明（collect_decls）→ 注册内建函数 → 恢复 符号：动态库函数 条目 → 注册运行时内建函数 → 第二遍检查每个函数体（check_func）→ 检查全局声明初始化 → 验证 实现（impl）-遍历（for） 关系。

### 逻辑
`
调用 初始化类型列表（types）（init_types）（）

（在 g_sym_count 重置之前保存 符号：动态库函数（SYM_SO_FN） 条目）
令 .so 函数个数（so_count）= 0（可变）
令 .so 函数名保存数组（so_names）= 调用 分配（alloc）（128 * 8）的字节（可变）
令 .so 函数类型保存数组（so_types）= 调用 分配（alloc）（128 * 8）的字节（可变）
令 .so 函数节点保存数组（so_nodes）= 调用 分配（alloc）（128 * 8）的字节（可变）

令 扫描索引（si_scan）= 0（可变）
循环（当 扫描索引（si_scan）小于 符号计数（g_sym_count）时）：
    如果 扫描索引（si_scan）大于等于 符号计数（g_sym_count），那么：跳出循环
    如果 调用 符号类别（sym_kind）（si_scan）等于 符号类别：动态库函数（SYM_SO_FN），那么：
        调用 读写全局（w64）（.so 函数名保存数组（so_names），.so 函数个数（so_count） * 8，调用 符号名称（sym_name）（si_scan））
        调用 读写全局（w64）（.so 函数类型保存数组（so_types），.so 函数个数（so_count） * 8，调用 符号类型（sym_type）（si_scan））
        调用 读写全局（w64）（.so 函数节点保存数组（so_nodes），.so 函数个数（so_count） * 8，调用 符号节点（sym_node）（si_scan））
        令 .so 函数个数（so_count） = .so 函数个数（so_count） + 1
    扫描索引（si_scan） = 扫描索引（si_scan） + 1

（重置符号表和全局检查状态）
令 符号计数（g_sym_count） = 0
令 作用域深度（g_scope_depth） = 0；令 作用域边界容量（g_scope_bounds_cap） = 0
令 诊断计数（g_diag_count） = 0；令 诊断容量（g_diag_cap） = 0
令 泛型映射计数（g_gen_map_count） = 0；令 泛型映射容量（g_gen_map_cap） = 0
令 泛型应用数据计数（g_gen_apply_data_count） = 0；令 泛型应用数据容量（g_gen_apply_data_cap） = 0
令 泛型参数计数（g_gen_param_count） = 0；令 泛型参数容量（g_gen_param_cap） = 0
令 动态类型集合计数（g_dyn_type_set_count） = 0；令 动态类型集合容量（g_dyn_type_set_cap） = 0；令 动态类型集合数组（g_dyn_type_sets） = ""

（第一遍：收集声明）
调用 收集声明（collect_decls）（）
调用 初始化内建（init_builtins）（）

（恢复在 g_sym_count 重置中丢失的 符号：动态库函数（SYM_SO_FN） 条目）
令 恢复索引（ri）= 0（可变）
循环（当 恢复索引（ri）小于 .so 函数个数（so_count）时）：
    如果 恢复索引（ri）大于等于 .so 函数个数（so_count），那么：跳出循环
    令 符号插入位置（si）= 符号计数（g_sym_count）
    调用 扩展符号数组（grow_syms）（符号插入位置（si） + 1）
    调用 符号设置名称（sym_set_name）（符号插入位置（si），调用 读写全局（r64）（.so 函数名保存数组（so_names），恢复索引（ri） * 8））
    调用 符号设置类别（sym_set_kind）（符号插入位置（si），符号类别：动态库函数（SYM_SO_FN））
    调用 符号设置类型（sym_set_type）（符号插入位置（si），调用 读写全局（r64）（.so 函数类型保存数组（so_types），恢复索引（ri） * 8））
    调用 符号设置节点（sym_set_node）（符号插入位置（si），调用 读写全局（r64）（.so 函数节点保存数组（so_nodes），恢复索引（ri） * 8））
    令 符号计数（g_sym_count） = 符号插入位置（si） + 1
    恢复索引（ri） = 恢复索引（ri） + 1

（将运行时内建函数注册为正式 符号：函数（SYM_FN）（无 .cr 体，在 rt.状态（s） 中实现））
（必须在 collect_decls 之后注册，以让用户自定义函数优先）
令 内建注册索引（ri2）= 0（可变）
循环（当 内建注册索引（ri2）小于 运行时内建函数计数（g_rt_builtin_count）时）：
    如果 内建注册索引（ri2）大于等于 运行时内建函数计数（g_rt_builtin_count），那么：跳出循环
    令 内建名索引（ni2）= 调用 读写全局（r64）（运行时内建函数名数组（g_rt_builtin_names），内建注册索引（ri2） * 8）
    令 内建类型索引（ti2）= 调用 读写全局（r64）（运行时内建函数返回类型数组（g_rt_builtin_ret_types），内建注册索引（ri2） * 8）
    如果 调用 查找泛型符号（gsym）（find_gsym）（ni2）小于 0，那么：  （如果用户已定义则跳过）
        令 符号插入位置（si2）= 符号计数（g_sym_count）
        调用 扩展符号数组（grow_syms）（符号插入位置（si2） + 1）
        调用 符号设置名称（sym_set_name）（符号插入位置（si2），内建名索引（ni2））
        调用 符号设置类别（sym_set_kind）（符号插入位置（si2），符号类别：函数（SYM_FN））
        调用 符号设置类型（sym_set_type）（符号插入位置（si2），内建类型索引（ti2））
        调用 符号设置节点（sym_set_node）（符号插入位置（si2），-1）
        令 符号计数（g_sym_count） = 符号插入位置（si2） + 1
    内建注册索引（ri2） = 内建注册索引（ri2） + 1

（第二遍：检查函数体）
令 函数遍历索引（i）= 0（可变）
循环（当 函数遍历索引（i）小于 函数计数（g_func_count）时）：
    如果 函数遍历索引（i）大于等于 函数计数（g_func_count），那么：跳出循环
    调用 检查函数（check_func）（i）
    函数遍历索引（i） = 函数遍历索引（索引） + 1

（检查全局 令（let） 初始化器）
令 全局声明遍历索引（i）= 0
循环（当 全局声明遍历索引（i）小于 全局声明计数（g_global_let_count）时）：
    如果 全局声明遍历索引（i）大于等于 全局声明计数（g_global_let_count），那么：跳出循环
    调用 检查全局声明（check_global_let）（调用 读写全局（r64）（全局声明数组（g_global_lets），全局声明遍历索引（i） * 8））
    全局声明遍历索引（i） = 全局声明遍历索引（索引） + 1

（检查 实现（impl）-遍历（for） 关系）
调用 检查实现（check_impl_for）（）
`

### 测试要点
1. 正常调用后：所有函数体的类型检查完成，错误数存入诊断数组（g_diags）
2. 符号：动态库函数（SYM_SO_FN） 条目在 重置（reset） 前后保持一致（先保存后恢复）
3. 运行时内建函数在用户自定义函数之后注册（用户定义优先）
4. 全局 令（let） 初始化器被推断：非法初始化产生诊断
5. 实现（impl）-遍历（for） 所有关系被验证
6. 多次调用检查全部重新初始化整个检查管线
7. @热补丁（hotpatch） 函数签名不匹配在收集声明阶段被捕获
8. 泛型函数的类型检查推迟到调用点（泛型参数按 泛型参数类型（TYP_GENERIC_PARAM） 处理）
