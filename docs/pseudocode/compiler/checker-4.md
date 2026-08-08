# 类型检查器（checker）.cr 伪代码（第 4 部分：泛型辅助 + 函数检查 + 实现验证）
> 源文件：src/compiler/类型检查器（checker）.cr 第 828～1284 行
> 功能概要：泛型相关谓词（判断函数/结构体是否为泛型、按名称查找）、调用类型解析（泛型参数→泛型参数类型条目）、类型统一化（泛型参数映射到具体类型）、返回类型替换（泛型映射后的最终实例化）、泛型函数调用推断、函数体检查、接口实现验证、全局声明初始化检查。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 判断函数泛型 | is_func_generic | 判断函数泛型 |
| 查找函数 | find_func | 查找函数 |
| 判断结构体泛型 | is_struct_generic | 判断结构体泛型 |
| 查找结构体按字节名称 | find_struct_by_name | 查找结构体按字节名称 |
| 解析调用类型 | res_call_type | 解析调用类型 |
| 统一类型列表 | unify_types | 统一类型列表 |
| 替换返回类型 | substitute_return_type | 替换返回类型 |
| 类型推断泛型调用 | infer_gen_call | 类型推断泛型调用 |
| 检查函数 | check_func | 检查函数 |
| 检查实现 | check_impl_for | 检查实现 |
| 检查全局声明 | check_global_let | 检查全局声明 |
| 类型推断表达式 | infer_expr | 类型推断泛型调用 |
| 解析类型节点 | res_type_node | 检查函数 |
| 检查接口 | check_iface | 类型推断泛型调用 |
| 查找接口 | find_iface | 类型推断泛型调用 |
| 查找泛型符号 | find_gsym | 解析调用类型 |
| 查找符号 | find_sym | 检查函数 |
| 定义符号 | def_sym | 检查函数 |
| 压入作用域 | push_scope | 检查函数 |
| 弹出作用域 | pop_scope | 检查函数 |
| 分配类型 | alloc_type | 解析调用类型 |
| 获取类型类别 | get_type_kind | 统一类型列表 |
| 获取类型数据 | get_type_data | 统一类型列表 |
| 获取类型额外 | get_type_extra | 替换返回类型 |
| 获取类型名称 | get_type_name | 类型推断泛型调用 |
| 类型相等判断 | type_equal | 替换返回类型 |
| 检查错误 | check_error | 解析调用类型 |
| 扫描让出 | scan_for_yield | 检查函数 |
| 当前检查函数索引 | g_checker_current_fi | 检查函数 |
| 函数数组 | g_funcs | 判断函数泛型 |
| 函数计数 | g_func_count | 判断函数泛型 |
| 结构体数组 | g_structs | 判断结构体泛型 |
| 结构体计数 | g_struct_count | 判断结构体泛型 |
| 泛型映射计数 | g_gen_map_count | 统一类型列表 |
| 泛型映射容量 | g_gen_map_cap | 统一类型列表 |
| 泛型映射名数组 | g_gen_map_names | 统一类型列表 |
| 泛型映射类型数组 | g_gen_map_types | 统一类型列表 |
| 泛型应用数据数组 | g_gen_apply_data | 解析调用类型 |
| 泛型应用数据计数 | g_gen_apply_data_count | 解析调用类型 |
| 泛型约束数组 | g_generic_constr | 类型推断泛型调用 |
| 泛型约束计数 | g_generic_constr_count | 类型推断泛型调用 |
| 泛型参数数组 | g_gen_params | 检查函数 |
| 泛型参数计数 | g_gen_param_count | 检查函数 |
| AST 节点计数 | g_ast_count | 检查函数 |
| 函数信息条目大小 | ESZ_FUNCINFO | 判断函数泛型 |
| 函数信息：泛型名称偏移 | OFF_FI_GENERIC_NAMES | 判断函数泛型 |
| unsafe 块深度 | g_unsafe_depth | 解析调用类型 |
| 接口实现数组 | g_impl_for | 检查实现 |
| 接口实现计数 | g_impl_for_count | 检查实现 |
| 接口数组 | g_ifaces | 检查实现 |
| 接口信息条目大小 | ESZ_IFACEINFO | 检查实现 |
| 接口信息：方法数量偏移 | OFF_IF_METHOD_COUNT | 检查实现 |
| 接口信息：方法列表偏移 | OFF_IF_METHODS | 检查实现 |
| 接口方法条目大小 | ESZ_IFMETHOD | 检查实现 |
| 接口方法：名称偏移 | OFF_IFM_NAME | 检查实现 |
| 接口方法：参数个数偏移 | OFF_IFM_PARAM_COUNT | 检查实现 |
| 接口方法：返回类型偏移 | OFF_IFM_RET_TI | 检查实现 |
| 接口方法：参数类型列表偏移 | OFF_IFM_PARAM_TYPES | 检查实现 |
| 最大泛型参数数 | MAX_GENERICS | 类型推断泛型调用 |
| 读写全局 | r64 / w64 | 多个函数 |
| 驻留字符串获取 | istr_get | 检查函数 |
| 字符串驻留 | str_intern | 检查函数 |
| 字符串长度 | str_len | 检查函数 |
| 字符串切片 | str_sub | 检查函数 |
| 读单字节 | load8 | 检查函数 |
| 整数转字符串 | int_str | 检查实现 |
| 扩展泛型映射数组 | grow_gen_map | 统一类型列表 |
| 扩展泛型应用数据数组 | grow_gen_apply_data | 解析调用类型 |
| 扩展泛型参数数组 | grow_gen_params | 检查函数 |
| AST 访问器系列 | ast_kind / ast_a / ast_b / ast_c / ast_int_val / ast_type_val / ast_data / ast_line / ast_col / ast_set_b / ast_set_int_val | 多函数共用 |
| 函数信息访问器系列 | fi_ast_node / fi_name / fi_return_type / fi_param_count / fi_generic_count / fi_generic_name / fi_param_type / fi_set_name / fi_set_ast_node / fi_set_return_type / fi_set_param_count / fi_set_ispure / fi_set_generic_count | 多函数共用 |
| 结构体信息访问器：泛型计数 | si_generic_count | 判断结构体泛型 |
| 结构体信息访问器：泛型名称 | si_generic_name | 判断结构体泛型 |
| 结构体信息访问器：名称 | si_name | 查找结构体按字节名称 |
| 符号类别 | sym_kind | 解析调用类型 |
| 符号类型 | sym_type | 解析调用类型 |
| 符号节点 | sym_node | 检查函数 |

## 全局状态

| 全局变量 | 含义 | 初值 |
|---------|------|------|
| 泛型映射计数（g_gen_map_count） | 泛型参数名→具体类型的映射条目数 | 0 |
| 泛型映射容量（g_gen_map_cap） | 泛型映射数组当前容量 | 0 |
| 泛型映射名数组（g_gen_map_names） | 泛型参数名索引列表 | 空 |
| 泛型映射类型数组（g_gen_map_types） | 对应的具体类型表索引列表 | 空 |
| 当前检查函数索引（g_checker_current_fi） | 正在检查的函数在函数数组（g_funcs）中的索引 | 0 |

## 函数 判断函数泛型（is_func_generic）
### 作用
检查指定函数索引（fi）是否存在某个名称索引（name_idx）对应的泛型参数。遍历函数的泛型名称列表，有匹配则返回真，否则返回假。

### 逻辑
`
函数 判断函数泛型（is_func_generic）（函数索引 fi：整数，名称索引 name_idx：整数）-> 布尔
    如果 函数索引（fi）小于 0 或 函数索引（fi）大于等于 函数计数（g_func_count），那么：返回 假

    令 泛型索引（gi）= 0（可变）
    循环：
        如果 泛型索引（gi）大于等于 调用 函数信息访问器系列（fi_generic_count）（fi），那么：返回 假
        如果 调用 读写全局（r64）（函数数组（g_funcs），函数索引（fi） * 函数信息条目大小（ESZ_FUNCINFO） + 函数信息：泛型名称偏移（OFF_FI_GENERIC_NAMES） + 泛型索引（gi） * 8）等于 名称索引（name_idx），那么：返回 真
        令 泛型索引（gi） = 泛型索引（gi） + 1

    返回 假
`

### 测试要点
1. 函数有对应泛型参数：返回 真
2. 函数没有对应泛型参数：返回 假
3. 传入无效函数索引（g_func_count）：返回 假

## 函数 查找函数（find_func）
### 作用
在函数数组（g_funcs）中线性搜索指定名称索引的函数。返回函数数组中的索引，未找到返回 -1。

### 逻辑
`
函数 查找函数（find_func）（名称索引 name_idx：整数）-> 整数
    令 索引（i）= 0（可变）
    循环：
        如果 索引（i）大于等于 函数计数（g_func_count），那么：返回 -1
        如果 调用 函数信息访问器系列（fi_name）（i）等于 名称索引（name_idx），那么：返回 索引（i）
        令 索引（i） = 索引（i） + 1
    返回 -1
`

### 测试要点
1. 找到已注册函数：返回正确索引
2. 找不到：返回 -1

## 函数 判断结构体泛型（is_struct_generic）
### 作用
检查指定结构体索引（si）是否存在某个名称索引（name_idx）对应的泛型参数。

### 逻辑
`
函数 判断结构体泛型（is_struct_generic）（结构体索引 si：整数，名称索引 name_idx：整数）-> 布尔
    如果 结构体索引（si）小于 0 或 结构体索引（si）大于等于 结构体计数（g_struct_count），那么：返回 假

    令 泛型索引（gi）= 0（可变）
    循环：
        如果 泛型索引（gi）大于等于 调用 结构体信息访问器：泛型计数（si_generic_count）（si），那么：返回 假
        如果 调用 结构体信息访问器：泛型名称（si_generic_name）（结构体索引（si），泛型索引（gi））等于 名称索引（name_idx），那么：返回 真
        令 泛型索引（gi） = 泛型索引（gi） + 1

    返回 假
`

### 测试要点
1. 结构体有对应泛型参数：返回 真
2. 结构体没有对应泛型参数：返回 假
3. 传入无效结构体索引：返回 假

## 函数 查找结构体按字节名称（find_struct_by_name）
### 作用
按名称索引在结构体数组中线性搜索匹配的结构体。与查找结构体的区别在于使用结构体信息访问器获取名称。

### 逻辑
`
函数 查找结构体按字节名称（find_struct_by_name）（名称索引 name_idx：整数）-> 整数
    令 索引（i）= 0（可变）
    循环：
        如果 索引（i）大于等于 结构体计数（g_struct_count），那么：返回 -1
        如果 调用 结构体信息访问器：名称（si_name）（i）等于 名称索引（name_idx），那么：返回 索引（i）
        令 索引（i） = 索引（i） + 1
    返回 -1
`

### 测试要点
1. 找到已注册结构体：返回正确索引
2. 找不到：返回 -1

## 函数 解析调用类型（res_call_type）
### 作用
解析用于函数调用类型推断的类型节点。与解析类型节点的差异：对泛型参数名称不再解析为已注册的类型表条目，而直接创建泛型参数类型条目——这样后续统一化才能匹配泛型参数。

### 逻辑
`
函数 解析调用类型（res_call_type）（节点 节点（node）：整数，函数表索引 func_fi：整数）-> 整数
    如果 节点（node）小于 0，那么：返回 类型表预分配：单元（TI_UNIT）

    如果 调用 AST 访问器系列（ast_kind）（node）等于 0，那么：
        令 类型值（tv）= 调用 AST 访问器系列（ast_type_val）（node）
        如果 类型值（tv）等于 整数类型（TY_INT），那么：返回 类型表预分配：整数（TI_INT）
        如果 类型值（tv）等于 浮点数类型（TY_FLOAT），那么：返回 类型表预分配：浮点数（TI_FLOAT）
        如果 类型值（tv）等于 布尔类型（TY_BOOL），那么：返回 类型表预分配：布尔（TI_BOOL）
        如果 类型值（tv）等于 字符串类型（TY_STRING），那么：返回 类型表预分配：字符串（TI_STR）
        如果 类型值（tv）等于 单元类型（TY_UNIT），那么：返回 类型表预分配：单元（TI_UNIT）
        如果 类型值（tv）等于 字符类型（TY_CHAR），那么：返回 类型表预分配：字符（TI_CHAR）
        如果 类型值（tv）等于 类型表预分配：动态（TI_DYN），那么：返回 类型表预分配：动态（类型信息：动态）
        返回 类型表预分配：单元（TI_UNIT）

    如果 调用 AST 访问器系列（ast_kind）（node）等于 标识符表达式（EXPR_IDENT），那么：
        令 名称索引（name_idx）= 调用 AST 访问器系列（ast_int_val）（node）
        如果 调用 判断函数泛型（is_func_generic）（函数表索引（func_fi），名称索引（name_idx）），那么：
            返回 调用 分配类型（alloc_type）（类型条目类别：泛型参数（TYP_GENERIC_PARAM），名称索引（name_idx），0）
        令 符号索引（si）= 调用 查找泛型符号（gsym）（find_gsym）（name_idx）
        如果 符号索引（si）大于等于 0 且 调用 符号类别（sym_kind）（si）等于 符号类别：类型（SYM_TYPE），那么：
            返回 调用 符号类型（sym_type）（si）
        返回 调用 分配类型（alloc_type）（类型条目类别：命名（TYP_NAMED），名称索引（name_idx），0）

    如果 调用 AST 访问器系列（ast_kind）（node）等于 泛型应用表达式（EXPR_GENERIC_APPLY），那么：
        令 名称索引（name_idx）= 调用 AST 访问器系列（ast_a）（node）
        令 首参节点（first_an）= 调用 AST 访问器系列（ast_b）（node）
        令 参数个数（ac）= 调用 AST 访问器系列（ast_c）（node）
        令 符号索引（si）= 调用 查找泛型符号（gsym）（find_gsym）（name_idx）
        如果 符号索引（si）小于 0 或 调用 符号类别（sym_kind）（si）不等于 符号类别：类型（SYM_TYPE），那么：返回 类型表预分配：单元（TI_UNIT）
        令 基础类型表索引（base_ti）= 调用 符号类型（sym_type）（si）

        令 数据段起始（ds）= 泛型应用数据计数（g_gen_apply_data_count）
        调用 扩展泛型应用数据数组（grow_gen_apply_data）（数据段起始（ds） + 1 + 参数个数（ac））
        调用 读写全局（w64）（泛型应用数据数组（g_gen_apply_data），数据段起始（ds） * 8，参数个数（ac））
        令 泛型应用数据计数（g_gen_apply_data_count） = 数据段起始（ds） + 1

        令 参数索引（ai）= 0（可变）
        令 当前参数节点（an）= 首参节点（first_an）（可变）
        循环：
            如果 参数索引（ai）大于等于 参数个数（ac），那么：跳出循环
            令 参数类型表索引（at）= 调用 解析调用类型（res_call_type）（当前参数节点（an），函数表索引（func_fi））
            调用 读写全局（w64）（泛型应用数据数组（g_gen_apply_data），（数据段起始（ds） + 1 + 参数索引（ai）） * 8，参数类型表索引（at））
            令 参数索引（ai） = 参数索引（ai） + 1
            令 当前参数节点（an） = 当前参数节点（an） + 1

        令 泛型应用数据计数（g_gen_apply_data_count） = 数据段起始（ds） + 1 + 参数个数（ac）
        返回 调用 分配类型（alloc_type）（类型条目类别：泛型应用（TYP_GENERIC_APPLY），基础类型表索引（base_ti），数据段起始（ds））

    如果 调用 AST 访问器系列（ast_kind）（node）等于 引用类型表达式（EXPR_REFTYPE），那么：
        令 内部类型表索引（inner）= 调用 解析调用类型（res_call_type）（调用 AST 访问器系列（ast_a）（node），函数表索引（func_fi））
        令 可变标记（mf）= 调用 AST 访问器系列（ast_int_val）（node）
        返回 调用 分配类型（alloc_type）（类型条目类别：引用（TYP_REF），内部类型表索引（inner），可变标记（mf））

    返回 类型表预分配：单元（TI_UNIT）
`

### 测试要点
1. 基础类型 整数类型（int）对应节点 → 返回 类型表预分配：整数（TI_INT）
2. 函数泛型参数名称（T）→ 返回 类型条目类别：泛型参数（TYP_GENERIC_PARAM）条目
3. 常规命名类型 → 正常解析
4. 泛型应用中嵌套泛型参数 → 递归创建 类型条目类别：泛型参数（TYP_GENERIC_PARAM）

## 函数 统一类型列表（unify_types）
### 作用
将模式类型（pattern）与具体类型（concrete）统一化。如果模式是泛型参数，则记录映射关系或检查已有映射的一致性。如果是泛型应用模式，则递归统一化每个泛型参数。

### 逻辑
`
函数 统一类型列表（unify_types）（模式类型表索引 pattern：整数，具体类型表索引 concrete：整数）-> 布尔
    如果 模式类型表索引（pattern）等于 具体类型表索引（concrete），那么：返回 真

    令 模式类别（pk）= 调用 获取类型类别（get_type_kind）（pattern）
    令 具体类别（ck）= 调用 获取类型类别（get_type_kind）（concrete）
    如果 模式类别（pk）小于 0 或 具体类别（ck）小于 0，那么：返回 假

    如果 模式类别（pk）等于 类型条目类别：泛型参数（TYP_GENERIC_PARAM），那么：
        令 名称索引（name_idx）= 调用 获取类型数据（get_type_data）（pattern）

        令 映射索引（mi）= 0（可变）
        循环：
            如果 映射索引（mi）大于等于 泛型映射计数（g_gen_map_count），那么：跳出循环
            如果 调用 读写全局（r64）（泛型映射名数组（g_gen_map_names），映射索引（mi） * 8）等于 名称索引（name_idx），那么：
                返回 调用 类型相等（equal）（type_equal）（调用 读写全局（r64）（泛型映射类型数组（g_gen_map_types），映射索引（mi） * 8），具体类型表索引（concrete））
            令 映射索引（mi） = 映射索引（mi） + 1

        调用 扩展泛型映射数组（grow_gen_map）（泛型映射计数（g_gen_map_count） + 1）
        调用 读写全局（w64）（泛型映射名数组（g_gen_map_names），泛型映射计数（g_gen_map_count） * 8，名称索引（name_idx））
        调用 读写全局（w64）（泛型映射类型数组（g_gen_map_types），泛型映射计数（g_gen_map_count） * 8，具体类型表索引（concrete））
        令 泛型映射计数（g_gen_map_count） = 泛型映射计数（g_gen_map_count） + 1
        返回 真

    如果 模式类别（pk）等于 类型条目类别：泛型应用（TYP_GENERIC_APPLY）且 具体类别（ck）等于 类型条目类别：泛型应用（泛型应用类型），那么：
        如果 非 调用 类型相等（equal）（type_equal）（调用 获取类型数据（get_type_data）（pattern），调用 获取类型数据（get_type_data）（concrete）），那么：返回 假

        令 模式数据起始（ps）= 调用 获取类型额外（get_type_extra）（pattern）
        令 具体数据起始（cs）= 调用 获取类型额外（get_type_extra）（concrete）
        令 模式参数个数（pc）= 调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），模式数据起始（ps） * 8）
        令 具体参数个数（cc）= 调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），具体数据起始（cs） * 8）
        如果 模式参数个数（pc）不等于 具体参数个数（cc），那么：返回 假

        令 参数索引（ai）= 0（可变）
        循环：
            如果 参数索引（ai）大于等于 模式参数个数（pc），那么：跳出循环
            如果 非 调用 统一类型列表（unify_types）（调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），（模式数据起始（ps） + 1 + 参数索引（ai）） * 8），调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），（具体数据起始（cs） + 1 + 参数索引（ai）） * 8）），那么：返回 假
            令 参数索引（ai） = 参数索引（ai） + 1
        返回 真

    返回 调用 类型相等（equal）（type_equal）（模式类型表索引（pattern），具体类型表索引（concrete））
`

### 测试要点
1. 相同模式与具体类型（TI_INT）：返回 真
2. 泛型参数首次映射到具体类型 整数类型（int）：返回 真且建立映射
3. 已映射泛型参数，新的具体类型与之前映射一致：返回 真
4. 已映射泛型参数，新的具体类型与之前映射不一致：返回 假
5. 基础类型不同（整数类型（int）与 布尔类型（bool））：返回 假
6. 泛型应用模式与泛型应用具体类型（参数个数相同且每个参数可递归统一）：返回 真

## 函数 替换返回类型（substitute_return_type）
### 作用
将类型表索引中的泛型参数替换为泛型映射（g_gen_map）中的具体类型。用于泛型函数调用后产出最终实例化返回类型。如果没有映射条目，直接返回原类型。

### 逻辑
`
函数 替换返回类型（substitute_return_type）（类型表索引 ti：整数）-> 整数
    如果 泛型映射计数（g_gen_map_count）等于 0，那么：返回 类型表索引（ti）

    令 类别（k）= 调用 获取类型类别（get_type_kind）（ti）

    如果 类别（k）等于 类型条目类别：泛型参数（TYP_GENERIC_PARAM），那么：
        令 名称索引（name_idx）= 调用 获取类型数据（get_type_data）（ti）
        令 映射索引（mi）= 0（可变）
        循环：
            如果 映射索引（mi）大于等于 泛型映射计数（g_gen_map_count），那么：跳出循环
            如果 调用 读写全局（r64）（泛型映射名数组（g_gen_map_names），映射索引（mi） * 8）等于 名称索引（name_idx），那么：返回 调用 读写全局（r64）（泛型映射类型数组（g_gen_map_types），映射索引（mi） * 8）
            令 映射索引（mi） = 映射索引（mi） + 1
        返回 类型表索引（ti）

    如果 类别（k）等于 类型条目类别：泛型应用（TYP_GENERIC_APPLY），那么：
        令 基础类型（base）= 调用 获取类型数据（get_type_data）（ti）
        令 原数据起始（start）= 调用 获取类型额外（get_type_extra）（ti）
        令 类型参数个数（count）= 调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），原数据起始（start） * 8）

        令 新数据起始（new_start）= 泛型应用数据计数（g_gen_apply_data_count）
        调用 扩展泛型应用数据数组（grow_gen_apply_data）（新数据起始（new_start） + 1 + 类型参数个数（count））
        调用 读写全局（w64）（泛型应用数据数组（g_gen_apply_data），新数据起始（new_start） * 8，类型参数个数（count））
        令 泛型应用数据计数（g_gen_apply_data_count） = 新数据起始（new_start） + 1

        令 参数索引（ai）= 0（可变）
        循环：
            如果 参数索引（ai）大于等于 类型参数个数（count），那么：跳出循环
            令 替换后的子类型（sub）= 调用 替换返回类型（substitute_return_type）（调用 读写全局（r64）（泛型应用数据数组（g_gen_apply_data），（原数据起始（start） + 1 + 参数索引（ai）） * 8））
            调用 读写全局（w64）（泛型应用数据数组（g_gen_apply_data），（新数据起始（new_start） + 1 + 参数索引（ai）） * 8，替换后的子类型（sub））
            令 参数索引（ai） = 参数索引（ai） + 1

        令 泛型应用数据计数（g_gen_apply_data_count） = 新数据起始（new_start） + 1 + 类型参数个数（count）
        返回 调用 分配类型（alloc_type）（类型条目类别：泛型应用（TYP_GENERIC_APPLY），基础类型（base），新数据起始（new_start））

    返回 类型表索引（ti）
`

### 测试要点
1. 无映射时（泛型映射计数（g_gen_map_count）等于 0）：返回原类型不变
2. 泛型参数映射到具体类型 整数类型（int）：返回 类型表预分配：整数（TI_INT）
3. 泛型应用中的泛型参数被替换为具体类型：返回新的 类型条目类别：泛型应用（TYP_GENERIC_APPLY）条目
4. 嵌套泛型应用（所有层级的泛型参数均被替换为具体类型）：所有层级都被替换
5. 泛型参数未在映射中找到：保留原值

## 函数 类型推断泛型调用（infer_gen_call）
### 作用
对泛型函数调用进行类型推断。收集调用点实参的具体类型，通过统一化建立泛型参数到具体类型的映射，最后用映射替换返回类型得到最终调用点返回类型。还会验证泛型约束是否被满足（通过检查接口进行）。

### 逻辑
`
函数 类型推断泛型调用（infer_gen_call）（函数表索引 fi：整数，调用节点 call_node：整数，首实参 first_arg：整数，实参个数 arg_count：整数）-> 整数
    令 函数节点（fn_node）= 调用 函数信息访问器系列（fi_ast_node）（fi）
    令 首参节点（first_param）= 调用 AST 访问器系列（ast_b）（fn_node）
    令 形参个数（param_count）= 调用 AST 访问器系列（ast_c）（fn_node）
    令 返回类型节点（ret_type_node）= 调用 AST 访问器系列（ast_type_val）（fn_node）

    令 泛型映射计数（g_gen_map_count） = 0
    令 泛型映射容量（g_gen_map_cap） = 0

    令 形参索引（pi）= 0（可变）
    令 当前形参节点（pn）= 首参节点（first_param）（可变）
    令 当前实参节点（an）= 首实参（first_arg）（可变）
    循环：
        如果 形参索引（pi）大于等于 形参个数（param_count）或 形参索引（pi）大于等于 实参个数（arg_count），那么：跳出循环
        如果 当前形参节点（pn）小于 0 或 当前实参节点（an）小于 0，那么：跳出循环

        令 原始类型节点（orig_type_node）= 调用 AST 访问器系列（ast_data）（pn）

        如果 原始类型节点（orig_type_node）大于等于 0，那么：
            令 模式类型（pattern_ti）= 调用 解析调用类型（res_call_type）（原始类型节点（orig_type_node），函数表索引（fi））
            令 具体类型（concrete_ti）= 调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（an））
            调用 统一类型列表（unify_types）（模式类型（pattern_ti），具体类型（concrete_ti））
        否则：
            调用 类型推断表达式（infer_expr）（调用 AST 访问器系列（ast_a）（an））

        令 形参索引（pi） = 形参索引（pi） + 1
        令 当前形参节点（pn） = 当前形参节点（pn） + 1
        令 当前实参节点（an） = 调用 AST 访问器系列（ast_b）（an）

    令 泛型参数个数（gc）= 调用 函数信息访问器系列（fi_generic_count）（fi）
    如果 泛型参数个数（gc）大于 0，那么：
        令 约束索引（gci）= 0（可变）
        循环：
            如果 约束索引（gci）大于等于 泛型参数个数（gc），那么：跳出循环
            令 约束条目索引（constr_idx）= 函数表索引（fi） * 最大泛型参数数（MAX_GENERICS） + 约束索引（gci）
            如果 约束条目索引（constr_idx）小于 泛型约束计数（g_generic_constr_count），那么：
                令 接口名索引（iface_ni）= 调用 读写全局（r64）（泛型约束数组（g_generic_constr），约束条目索引（constr_idx） * 8）
                如果 接口名索引（iface_ni）大于等于 0，那么：
                    令 泛型参数名索引（pname_ni）= 调用 函数信息访问器系列（fi_generic_name）（函数表索引（fi），约束索引（gci））
                    令 对应的具体类型（concrete_ti）= -1（可变）
                    令 映射查找索引（hmi）= 0（可变）
                    循环：
                        如果 映射查找索引（hmi）大于等于 泛型映射计数（g_gen_map_count），那么：跳出循环
                        如果 调用 读写全局（r64）（泛型映射名数组（g_gen_map_names），映射查找索引（hmi） * 8）等于 泛型参数名索引（pname_ni），那么：
                            令 对应的具体类型（concrete_ti） = 调用 读写全局（r64）（泛型映射类型数组（g_gen_map_types），映射查找索引（hmi） * 8）
                            跳出循环
                        令 映射查找索引（hmi） = 映射查找索引（hmi） + 1

                    如果 对应的具体类型（concrete_ti）大于等于 0，那么：
                        令 类型名索引（type_ni）= 调用 获取类型名称（get_type_name）（concrete_ti）
                        如果 类型名索引（type_ni）大于等于 0，那么：
                            令 接口表索引（ii）= 调用 查找接口（find_iface）（iface_ni）
                            如果 接口表索引（ii）大于等于 0，那么：
                                如果 非 调用 检查接口（check_iface）（类型名索引（type_ni），接口表索引（ii）），那么：
                                    调用 检查错误（check_error）（类型泛型错误：泛型约束不满足（EC_TG_BOUND），"类型 '" + 调用 驻留字符串获取（istr_get）（type_ni）+ "' 不满足接口 '" + 调用 驻留字符串获取（istr_get）（iface_ni）+ "'"，调用 AST 访问器系列（ast_line）（call_node），调用 AST 访问器系列（ast_col）（call_node））
            令 约束索引（gci） = 约束索引（gci） + 1

    如果 泛型映射计数（g_gen_map_count）大于 0，那么：
        令 首个映射的具体类型（conc_type_ni）= 调用 读写全局（r64）（泛型映射类型数组（g_gen_map_types），0）
        令 具体类型名索引（conc_name_ni）= 调用 获取类型名称（get_type_name）（conc_type_ni）
        如果 具体类型名索引（conc_name_ni）大于等于 0，那么：
            调用 AST 访问器：设置整数值（ast_set_int_val）（调用节点（call_node），具体类型名索引（conc_name_ni））

    如果 泛型映射计数（g_gen_map_count）大于 0 且 返回类型节点（ret_type_node）大于等于 0，那么：
        令 解析后的返回类型（resolved_ret）= 调用 解析调用类型（res_call_type）（返回类型节点（ret_type_node），函数表索引（fi））
        返回 调用 替换返回类型（substitute_return_type）（resolved_ret）

    令 函数名索引（func_ni）= 调用 AST 访问器系列（ast_a）（fn_node）（可变）
    令 符号索引（si）= 调用 查找泛型符号（gsym）（find_gsym）（func_ni）
    如果 符号索引（si）大于等于 0 且 调用 符号类别（sym_kind）（si）等于 符号类别：函数（SYM_FN），那么：
        返回 调用 符号类型（sym_type）（si）
    返回 类型表预分配：单元（TI_UNIT）
`

### 测试要点
1. 泛型函数调用（如 `id[整数（int）]（42）` 或类型推断 `id（42）`）：正确推断泛型参数并返回实例化类型
2. 泛型约束不满足（如泛型参数需满足某接口但传入 整数类型（int））：产生 类型泛型错误：泛型约束不满足（EC_TG_BOUND）诊断
3. 多个泛型参数：全部被推断
4. 嵌套泛型应用：递归统一
5. 调用节点上存储了具体类型名称用于后端单态化

## 函数 检查函数（check_func）
### 作用
第二遍类型检查：对单个函数执行语义分析。包括：注册泛型参数、注册形式参数（含 自身（self） 模式处理：直接传值、&自身 不可变引用、&可变（mut） 自身 可变引用）、调用类型推断表达式检查函数体、验证返回类型与函数体类型是否一致。

### 逻辑
`
函数 检查函数（check_func）（函数表索引 fi：整数）
    令 当前检查函数索引（g_checker_current_fi） = 函数表索引（fi）

    令 借用条目计数（g_borrow_count） = 0；令 借用数组容量（g_borrow_cap） = 0
    令 持有者计数（g_holder_count） = 0；令 持有者容量（g_holder_cap） = 0
    令 借用作用域深度（g_borrow_scope_depth） = 0；令 借用作用域标记容量（g_borrow_scope_markers_cap） = 0

    令 函数节点（fn_node）= 调用 函数信息访问器系列（fi_ast_node）（fi）

    如果 调用 AST 访问器系列（ast_kind）（fn_node）等于 外部函数表达式（EXPR_EXTERN），那么：返回

    令 名称索引（name_idx）= 调用 AST 访问器系列（ast_a）（fn_node）
    令 首参节点（first_param）= 调用 AST 访问器系列（ast_b）（fn_node）
    令 形参个数（param_count）= 调用 AST 访问器系列（ast_c）（fn_node）
    令 返回类型（return_type）= 调用 函数信息访问器系列（fi_return_type）（fi）
    令 函数体节点（body）= 调用 AST 访问器系列（ast_data）（fn_node）

    调用 压入作用域（push_scope）（）

    如果 调用 函数信息访问器系列（fi_generic_count）（fi）大于 0，那么：
        令 泛型索引（gi）= 0（可变）
        循环：
            如果 泛型索引（gi）大于等于 调用 函数信息访问器系列（fi_generic_count）（fi），那么：跳出循环
            令 泛型名索引（gname_idx）= 调用 读写全局（r64）（函数数组（g_funcs），函数表索引（fi） * 函数信息条目大小（ESZ_FUNCINFO） + 函数信息：泛型名称偏移（OFF_FI_GENERIC_NAMES） + 泛型索引（gi） * 8）
            令 泛型类型表条目（g_ti）= 调用 分配类型（alloc_type）（类型条目类别：泛型参数（TYP_GENERIC_PARAM），泛型名索引（gname_idx），0）
            调用 定义符号（def_sym）（泛型名索引（gname_idx），符号类别：类型（SYM_TYPE），泛型类型表条目（g_ti），-1）
            令 泛型索引（gi） = 泛型索引（gi） + 1

    令 形参索引（pi）= 0（可变）
    令 当前形参节点（pn）= 首参节点（first_param）（可变）
    循环：
        如果 形参索引（pi）大于等于 形参个数（param_count），那么：跳出循环
        如果 当前形参节点（pn）小于 0，那么：跳出循环
        令 形参名索引（pname_idx）= 调用 AST 访问器系列（ast_a）（pn）
        令 自身模式（self_mode）= 调用 AST 访问器系列（ast_int_val）（pn）

        如果 自身模式（self_mode）等于 -1，那么：
            令 形参索引（pi） = 形参索引（pi） + 1
            令 当前形参节点（pn） = 当前形参节点（pn） + 1
            继续下一次循环

        令 形参类型表索引（ti）= 类型表预分配：单元（TI_UNIT）（可变）

        如果 自身模式（self_mode）等于 0，那么：
            令 原始类型节点（orig_type_node）= 调用 AST 访问器系列（ast_data）（pn）
            如果 原始类型节点（orig_type_node）大于等于 0 且 调用 AST 访问器系列（ast_kind）（orig_type_node）不等于 0，那么：
                令 形参类型表索引（ti） = 调用 解析类型节点（res_type_node）（orig_type_node）
            否则：
                令 参数类型标记（ptype）= 调用 AST 访问器系列（ast_type_val）（pn）
                如果 参数类型标记（ptype）等于 整数类型（TY_INT），那么：令 形参类型表索引（ti） = 类型表预分配：整数（TI_INT）
                否则如果 参数类型标记（ptype）等于 浮点数类型（TY_FLOAT），那么：令 形参类型表索引（ti） = 类型表预分配：浮点数（TI_FLOAT）
                否则如果 参数类型标记（ptype）等于 布尔类型（TY_BOOL），那么：令 形参类型表索引（ti） = 类型表预分配：布尔（TI_BOOL）
                否则如果 参数类型标记（ptype）等于 字符串类型（TY_STRING），那么：令 形参类型表索引（ti） = 类型表预分配：字符串（TI_STR）
                否则如果 参数类型标记（ptype）等于 字符类型（TY_CHAR），那么：令 形参类型表索引（ti） = 类型表预分配：字符（TI_CHAR）
        否则：
            令 函数名字符串（fn_name）= 调用 驻留字符串获取（istr_get）（调用 函数信息访问器系列（fi_name）（fi））
            令 函数名长度（fn_len）= 调用 字符串长度（str_len）（fn_name）
            令 点号位置（dot_pos）= -1（可变）
            令 字符扫描索引（di）= 0（可变）
            循环：
                如果 字符扫描索引（di）大于等于 函数名长度（fn_len），那么：跳出循环
                如果 调用 读单字节（load8）（函数名字符串（fn_name），字符扫描索引（di））等于 46，那么：令 点号位置（dot_pos） = 字符扫描索引（di）；跳出循环
                令 字符扫描索引（di） = 字符扫描索引（di） + 1

            如果 点号位置（dot_pos）大于 0，那么：
                令 结构体名字符串（struct_name）= 调用 字符串切片（str_sub）（函数名字符串（fn_name），0，点号位置（dot_pos））
                令 结构体名索引（struct_ni）= 调用 字符串驻留（str_intern）（struct_name）
                令 符号索引（si）= 调用 查找泛型符号（gsym）（find_gsym）（struct_ni）
                如果 符号索引（si）大于等于 0 且 调用 符号类别（sym_kind）（si）等于 符号类别：类型（SYM_TYPE），那么：
                    令 结构体类型表条目（struct_ti）= 调用 符号类型（sym_type）（si）
                    如果 自身模式（self_mode）等于 1，那么：
                        令 形参类型表索引（ti） = 结构体类型表条目（struct_ti）
                    否则：
                        令 可变标记（mut_flag）= 0
                        如果 自身模式（self_mode）等于 3，那么：令 可变标记（mut_flag） = 1
                        令 形参类型表索引（ti） = 调用 分配类型（alloc_type）（类型条目类别：引用（TYP_REF），结构体类型表条目（struct_ti），可变标记（mut_flag））

        调用 定义符号（def_sym）（形参名索引（pname_idx），符号类别：参数（SYM_PARAM），形参类型表索引（ti），-1）
        令 形参索引（pi） = 形参索引（pi） + 1

        令 当前形参节点（pn） = 当前形参节点（pn） + 1
        循环：
            如果 当前形参节点（pn）大于等于 语法树节点计数（g_ast_count），那么：跳出循环
            如果 调用 AST 访问器系列（ast_kind）（pn）等于 参数表达式（EXPR_PARAM），那么：跳出循环
            令 当前形参节点（pn） = 当前形参节点（pn） + 1

    如果 函数体节点（body）大于等于 0，那么：
        令 函数体推断类型（body_ti）= 调用 类型推断表达式（infer_expr）（body）
        令 期望返回类型（ret_ti）= 类型表预分配：单元（TI_UNIT）（可变）

        令 类型节点（type_node）= 调用 AST 访问器系列（ast_type_val）（fn_node）
        如果 类型节点（type_node）大于 0 且 调用 AST 访问器系列（ast_kind）（type_node）不等于 0，那么：
            令 期望返回类型（ret_ti） = 调用 解析类型节点（res_type_node）（type_node）
        否则如果 返回类型（return_type）等于 整数类型（TY_INT），那么：令 期望返回类型（ret_ti） = 类型表预分配：整数（TI_INT）
        否则如果 返回类型（return_type）等于 浮点数类型（TY_FLOAT），那么：令 期望返回类型（ret_ti） = 类型表预分配：浮点数（TI_FLOAT）
        否则如果 返回类型（return_type）等于 布尔类型（TY_BOOL），那么：令 期望返回类型（ret_ti） = 类型表预分配：布尔（TI_BOOL）
        否则如果 返回类型（return_type）等于 字符串类型（TY_STRING），那么：令 期望返回类型（ret_ti） = 类型表预分配：字符串（TI_STR）
        否则如果 返回类型（return_type）等于 单元类型（TY_UNIT），那么：令 期望返回类型（ret_ti） = 类型表预分配：单元（TI_UNIT）
        否则如果 返回类型（return_type）等于 字符类型（TY_CHAR），那么：令 期望返回类型（ret_ti） = 类型表预分配：字符（TI_CHAR）
        否则如果 返回类型（return_type）等于 永无类型（TY_NEVER），那么：令 期望返回类型（ret_ti） = 类型表预分配：永无（TI_NEVER）

        如果 非 调用 类型相等（equal）（type_equal）（函数体推断类型（body_ti），期望返回类型（ret_ti））且 函数体推断类型（body_ti）不等于 类型表预分配：永无（TI_NEVER），那么：
            令 是否为数据流函数（is_flow_fn）= 0（可变）
            如果 函数体节点（body）大于等于 0 且 调用 扫描让出（scan_for_yield）（body）不等于 0，那么：令 是否为数据流函数（is_flow_fn） = 1
            如果 是否为数据流函数（is_flow_fn）为假 且 调用 获取类型类别（get_type_kind）（ret_ti）不等于 类型条目类别：泛型参数（TYP_GENERIC_PARAM），那么：
                调用 检查错误（check_error）（返回类型不匹配错误码（EC_TF_RETURN），"函数返回类型不匹配"，调用 AST 访问器系列（ast_line）（fn_node），调用 AST 访问器系列（ast_col）（fn_node））

    调用 弹出作用域（pop_scope）（）
`

### 测试要点
1. 正常函数：参数和函数体类型全部匹配
2. 返回类型不匹配：产生 返回类型不匹配错误码（EC_TF_RETURN）诊断
3. 泛型函数的返回类型是泛型参数：跳过声明时的返回类型检查
4. 数据流函数（流程（flow） 函数）（yield）：跳过返回类型检查
5. 自身（self）参数模式 1（按值）/2（&自身）/3（&可变（mut） 自身）：正确派生结构体类型和引用类型
6. 函数体永无返回（EXPR_NEVER）：不触发返回类型不匹配检查
7. 外部函数（EXPR_EXTERN）：直接返回不检查

## 函数 检查实现（check_impl_for）
### 作用
验证所有 "实现接口（实现（impl） Interface）为类型（遍历（for） 类型（Type））" 关系：检查实现类型是否提供了接口要求的全部方法、参数个数是否匹配、参数类型是否匹配、返回类型是否匹配。

### 逻辑
`
函数 检查实现（check_impl_for）（）
    令 实现条目索引（pi）= 0（可变）
    循环：
        如果 实现条目索引（pi）大于等于 接口实现计数（g_impl_for_count），那么：跳出循环
        令 接口名索引（iface_ni）= 调用 读写全局（r64）（接口实现数组（g_impl_for），实现条目索引（pi） * 16）
        令 实现类型名索引（type_ni）= 调用 读写全局（r64）（接口实现数组（g_impl_for），实现条目索引（pi） * 16 + 8）

        令 接口表索引（ii）= 调用 查找接口（find_iface）（iface_ni）
        如果 接口表索引（ii）小于 0，那么：
            令 接口名字符串（iface_name）= 调用 驻留字符串获取（istr_get）（iface_ni）
            调用 检查错误（check_error）（名称解析错误：未定义名称（EC_N_UNDEFINED），"未定义接口 '" + 接口名字符串（iface_name）+ "'"，0，0）
            令 实现条目索引（pi） = 实现条目索引（pi） + 1
            继续下一次循环

        令 接口方法数量（method_count）= 调用 读写全局（r64）（接口数组（g_ifaces），接口表索引（ii） * 接口信息条目大小（ESZ_IFACEINFO） + 接口信息：方法数量偏移（OFF_IF_METHOD_COUNT））

        令 方法索引（mi）= 0（可变）
        循环：
            如果 方法索引（mi）大于等于 接口方法数量（method_count），那么：跳出循环
            令 方法数据基址（mbase）= 接口表索引（ii） * 接口信息条目大小（ESZ_IFACEINFO） + 接口信息：方法列表偏移（OFF_IF_METHODS） + 方法索引（mi） * 接口方法条目大小（ESZ_IFMETHOD）
            令 方法名索引（method_ni）= 调用 读写全局（r64）（接口数组（g_ifaces），方法数据基址（mbase） + 接口方法：名称偏移（OFF_IFM_NAME））
            令 期望参数个数（method_pc）= 调用 读写全局（r64）（接口数组（g_ifaces），方法数据基址（mbase） + 接口方法：参数个数偏移（OFF_IFM_PARAM_COUNT））
            令 期望返回类型（method_rt）= 调用 读写全局（r64）（接口数组（g_ifaces），方法数据基址（mbase） + 接口方法：返回类型偏移（OFF_IFM_RET_TI））

            令 类型名字符串（type_name）= 调用 驻留字符串获取（istr_get）（type_ni）
            令 方法名字符串（method_name）= 调用 驻留字符串获取（istr_get）（method_ni）
            令 加工名（mangled）= 类型名字符串（type_name） + "." + 方法名字符串（method_name）
            令 加工名索引（mangled_ni）= 调用 字符串驻留（str_intern）（mangled）

            令 函数表索引（fi）= 调用 查找函数（find_func）（mangled_ni）
            如果 函数表索引（fi）小于 0，那么：
                调用 检查错误（check_error）（方法未找到错误码（EC_TF_METHOD_NOT_FOUND），"实现缺少方法 '" + 方法名字符串（method_name）+ "' 对于接口 '" + 调用 驻留字符串获取（istr_get）（iface_ni）+ "'"，0，0）
                令 方法索引（mi） = 方法索引（mi） + 1
                继续下一次循环

            令 实际参数个数（actual_pc）= 调用 函数信息访问器系列（fi_param_count）（fi）
            如果 实际参数个数（actual_pc）不等于 期望参数个数（method_pc），那么：
                调用 检查错误（check_error）（方法实参个数不匹配错误码（EC_TF_METHOD_ARG_CNT），"参数个数不匹配 对于方法 '" + 方法名字符串（method_name）+ "': 期望 " + 调用 整数转字符串（int_str）（method_pc）+ " 得到 " + 调用 整数转字符串（int_str）（actual_pc），0，0）

            令 参数类型索引（pti）= 0（可变）
            循环：
                如果 参数类型索引（pti）大于等于 期望参数个数（method_pc）或 参数类型索引（pti）大于等于 8，那么：跳出循环
                令 期望参数类型（expected_pt）= 调用 读写全局（r64）（接口数组（g_ifaces），方法数据基址（mbase） + 接口方法：参数类型列表偏移（OFF_IFM_PARAM_TYPES） + 参数类型索引（pti） * 8）
                令 实际参数类型（actual_pt）= 调用 函数信息访问器系列（fi_param_type）（函数表索引（fi），参数类型索引（pti））
                如果 期望参数类型（expected_pt）不等于 实际参数类型（actual_pt），那么：
                    令 参数序号文本（pnum_str）= 调用 整数转字符串（int_str）（参数类型索引（pti） + 1）
                    调用 检查错误（check_error）（方法实参类型不匹配错误码（EC_TF_METHOD_ARG_TYP），"参数 " + 参数序号文本（pnum_str）+ " 类型不匹配 对于方法 '" + 方法名字符串（method_name）+ "' 在接口 '" + 调用 驻留字符串获取（istr_get）（iface_ni）+ "'"，0，0）
                令 参数类型索引（pti） = 参数类型索引（pti） + 1

            令 实际返回类型（actual_rt）= 调用 函数信息访问器系列（fi_return_type）（fi）
            如果 实际返回类型（actual_rt）不等于 期望返回类型（method_rt），那么：
                调用 检查错误（check_error）（返回类型不匹配错误码（EC_TF_RETURN），"返回类型不匹配 对于方法 '" + 方法名字符串（method_name）+ "' 在接口 '" + 调用 驻留字符串获取（istr_get）（iface_ni）+ "'"，0，0）

            令 方法索引（mi） = 方法索引（mi） + 1

        令 实现条目索引（pi） = 实现条目索引（pi） + 1
`

### 测试要点
1. 实现类型提供所有方法且签名匹配：无诊断（静默通过）
2. 缺少方法：产生 方法未找到错误码（EC_TF_METHOD_NOT_FOUND）诊断
3. 参数个数不匹配：产生 方法实参个数不匹配错误码（EC_TF_METHOD_ARG_CNT）诊断
4. 参数类型不匹配：产生 方法实参类型不匹配错误码（EC_TF_METHOD_ARG_TYP）诊断
5. 返回类型不匹配：产生 返回类型不匹配错误码（EC_TF_RETURN）诊断
6. 接口不存在：产生 名称解析错误：未定义名称（EC_N_UNDEFINED）诊断
7. 接口实现计数（g_impl_for_count）为 0：无操作

## 函数 检查全局声明（check_global_let）
### 作用
对全局声明中的值表达式进行类型推断。用于第二遍检查中验证全局变量初始化表达式的类型。

### 逻辑
`
函数 检查全局声明（check_global_let）（节点 节点（node）：整数）
    令 值表达式节点（val_node）= 调用 AST 访问器系列（ast_c）（node）
    如果 值表达式节点（val_node）大于等于 0，那么：
        调用 类型推断表达式（infer_expr）（val_node）
`

### 测试要点
1. 有初始化表达式的全局声明（let）：值表达式被类型推断
2. 无初始化表达式（值表达式节点（val_node）为 -1）：跳过不处理
3. 初始化表达式非法类型：在 类型推断表达式（infer_expr）中产生诊断
