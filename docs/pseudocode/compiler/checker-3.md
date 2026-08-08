# 类型检查器（checker）.cr 伪代码（第 3 部分：类型解析与声明收集）
> 源文件：src/compiler/类型检查器（checker）.cr 第 361～826 行
> 功能概要：将 AST 类型节点解析为类型表索引（处理基础/命名/数组/引用/指针/泛型应用类型）、结构体/枚举/接口的按名称查找、方法存在性检查、接口实现验证，以及第一遍声明收集（collect_decls）。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 解析类型节点 | res_type_node | 解析类型节点 |
| 查找结构体 | find_struct | 查找结构体 |
| 查找枚举 | find_enum | 查找枚举 |
| 查找接口 | find_iface | 查找接口 |
| 获取类型名称 | get_type_name | 获取类型名称 |
| 类型has方法 | type_has_method | 类型has方法 |
| 检查接口 | check_iface | 检查接口 |
| 收集声明 | collect_decls | 收集声明 |
| 结构体数组 | g_structs | 解析类型节点 |
| 结构体计数 | g_struct_count | 解析类型节点 |
| 枚举数组 | g_enums | 查找枚举 |
| 枚举计数 | g_enum_count | 查找枚举 |
| 接口数组 | g_ifaces | 查找接口 |
| 接口计数 | g_iface_count | 查找接口 |
| 函数数组 | g_funcs | 收集声明 |
| 函数计数 | g_func_count | 收集声明 |
| 全局声明数组 | g_global_lets | 收集声明 |
| 全局声明计数 | g_global_let_count | 收集声明 |
| 类型别名数组 | g_type_aliases | 收集声明 |
| 类型别名计数 | g_type_alias_count | 收集声明 |
| AST 节点计数 | g_ast_count | 收集声明 |
| 模块数组 | g_mods | 收集声明 |
| 模块计数 | g_mod_count | 收集声明 |
| 模块路径名数组 | g_mod_path_names | 收集声明 |
| 模块路径计数 | g_mod_path_count | 收集声明 |
| 模块函数名数组 | g_mod_func_names | 收集声明 |
| 模块函数文件 ID 数组 | g_mod_func_fileids | 收集声明 |
| 模块函数类型索引数组 | g_mod_func_tis | 收集声明 |
| 模块函数计数 | g_mod_func_count | 收集声明 |
| 模块函数容量 | g_mod_func_cap | 收集声明 |
| 文件数组 | g_files | 收集声明 |
| 文件计数 | g_file_count | 收集声明 |
| 行文件 ID 数组 | g_line_fileid | 收集声明 |
| 行计数 | g_line_count | 收集声明 |
| 泛型参数数组 | g_gen_params | 收集声明 |
| 泛型参数计数 | g_gen_param_count | 收集声明 |
| 泛型应用数据数组 | g_gen_apply_data | 解析类型节点 |
| 泛型应用数据计数 | g_gen_apply_data_count | 解析类型节点 |
| unsafe 块深度 | g_unsafe_depth | 解析类型节点 |
| 查找函数 | find_func | 类型has方法 |
| 查找符号 | find_sym | 收集声明 |
| 分配类型 | alloc_type | 解析类型节点 |
| 获取类型类别 | get_type_kind | 获取类型名称 |
| 获取类型数据 | get_type_data | 获取类型名称 |
| 类型equal | type_equal | 收集声明 |
| 检查错误 | check_error | 解析类型节点 |
| 定义符号 | def_sym | 收集声明 |
| 查找gsym | find_gsym | 解析类型节点 |
| 读写全局 | r64 / w64 | 多个函数 |
| 驻留字符串获取 | istr_get | 类型has方法 |
| 字符串驻留 | str_intern | 类型has方法 |
| 整数转字符串 | int_str | 收集声明 |
| 扩展泛型参数数组 | grow_gen_params | 收集声明 |
| 扩展泛型应用数据数组 | grow_gen_apply_data | 解析类型节点 |
| 扩展函数数组 | grow_funcs | 收集声明 |
| 扩展模块函数数组 | grow_mod_funcs | 收集声明 |
| 结构体信息访问器：名称 | si_name | 收集声明 |
| 结构体信息访问器：字段计数 | si_field_count | 收集声明 |
| 结构体信息访问器：泛型计数 | si_generic_count | 收集声明 |
| 结构体信息访问器：泛型名称 | si_generic_name | 收集声明 |
| 枚举信息访问器：名称 | ei_name | 收集声明 |
| 枚举信息访问器：变体计数 | ei_variant_count | 收集声明 |
| 枚举信息访问器：变体名称 | ei_variant_name | 收集声明 |
| 枚举信息访问器：泛型计数 | ei_generic_count | 收集声明 |
| 枚举信息访问器：泛型名称 | ei_generic_name | 收集声明 |
| 函数信息访问器：名称 | fi_name | 收集声明 |
| 函数信息访问器：ast节点 | fi_ast_node | 收集声明 |
| 函数信息访问器：返回类型 | fi_return_type | 收集声明 |
| 函数信息访问器：参数计数 | fi_param_count | 收集声明 |
| 函数信息访问器：泛型计数 | fi_generic_count | 收集声明 |
| 函数信息访问器：泛型名称 | fi_generic_name | 收集声明 |
| 函数信息访问器：设置是否纯净 | fi_set_ispure | 收集声明 |
| 函数信息访问器：设置名称 | fi_set_name | 收集声明 |
| 函数信息访问器：设置参数计数 | fi_set_param_count | 收集声明 |
| 函数信息访问器：设置返回类型 | fi_set_return_type | 收集声明 |
| 函数信息访问器：设置ast节点 | fi_set_ast_node | 收集声明 |
| 函数信息访问器：设置泛型计数 | fi_set_generic_count | 收集声明 |
| 符号类别 | sym_kind | 查找gsym |
| 符号类型 | sym_type | 查找gsym |
| 符号节点 | sym_node | 收集声明 |
| AST 访问器系列 | ast_kind / ast_a / ast_b / ast_c / ast_int_val / ast_type_val / ast_line / ast_col | 多函数共用 |
| 标识符表达式 | EXPR_IDENT | 解析类型节点 |
| 数组字面量表达式 | EXPR_ARRAY | 解析类型节点 |
| 引用类型表达式 | EXPR_REFTYPE | 解析类型节点 |
| 指针类型表达式 | EXPR_PTRTYPE | 解析类型节点 |
| 泛型应用表达式 | EXPR_GENERIC_APPLY | 解析类型节点 |
| 函数定义表达式 | EXPR_FN | 收集声明 |
| 外部函数表达式 | EXPR_EXTERN | 收集声明 |
| 声明表达式 | EXPR_LET | 收集声明 |

## 全局状态
（本部分未单独列出全局变量；涉及的全局变量含义见「标识符对照表」）

## 函数 解析类型节点（res_type_node）
函数 解析类型节点（res_type_node）（节点（node）：整数（int））-> 整数（整数）

### 作用
将 AST 类型节点（可能是基础类型/命名类型/数组类型/引用类型/指针类型/泛型应用）解析为类型表索引（TI_*）。类型节点可能为 0 类别（基础类型，type_val 域存 TY_*）或表达式类别（命名/数组/引用等）。

### 逻辑
`
如果 节点（node）小于 0，那么：返回 类型表预分配：单元（TI_UNIT）

如果 调用 AST 访问器：类别（ast_kind）（node）等于 0，那么：
    （基础类型节点：type_val = TY_*）
    令 类型值（tv） = 调用 AST 访问器：类型值（ast_type_val）（node）
    如果 类型值（tv）等于 整数（TY_INT），那么：返回 类型表预分配：整数（TI_INT）
    如果 类型值（tv）等于 浮点数（TY_FLOAT），那么：返回 类型表预分配：浮点数（TI_FLOAT）
    如果 类型值（tv）等于 布尔（TY_BOOL），那么：返回 类型表预分配：布尔（TI_BOOL）
    如果 类型值（tv）等于 字符串（TY_STRING），那么：返回 类型表预分配：字符串（TI_STR）
    如果 类型值（tv）等于 单元（TY_UNIT），那么：返回 类型表预分配：单元（TI_UNIT）
    如果 类型值（tv）等于 永无（TY_NEVER），那么：返回 类型表预分配：永无（TI_NEVER）
    如果 类型值（tv）等于 字符（TY_CHAR），那么：返回 类型表预分配：字符（TI_CHAR）
    如果 类型值（tv）等于 类型表预分配：动态（TI_DYN），那么：返回 类型表预分配：动态（类型信息：动态）
    返回 类型表预分配：单元（TI_UNIT）

如果 调用 AST 访问器：类别（ast_kind）（node）等于 标识符表达式（EXPR_IDENT），那么：
    （命名类型：int_val = 名称字符串索引）
    令 名称索引（name_idx） = 调用 AST 访问器：整数值（ast_int_val）（node）
    令 符号索引（si） = 调用 查找泛型符号（gsym）（find_gsym）（name_idx）
    如果 符号索引（si）大于等于 0 且 调用 符号类别（sym_kind）（si）等于 符号类别：类型（SYM_TYPE），那么：
        返回 调用 符号类型（sym_type）（si）
    （未找到已有符号，创建新的命名类型条目）
    返回 调用 分配类型（alloc_type）（类型条目类别：命名（TYP_NAMED），名称索引（name_idx），0）

如果 调用 AST 访问器：类别（ast_kind）（node）等于 数组字面量表达式（EXPR_ARRAY），那么：
    （数组类型 [泛型参数（T）； 次数（N）] 或切片类型 [泛型参数]（size 为 0 时））
    令 元素类型（elem） = 调用 解析类型节点（res_type_node）（调用 第一子节点访问器（ast_a）（node））
    令 大小（sz） = 调用 AST 访问器：整数值（ast_int_val）（node）
    如果 大小（sz）等于 0，那么：
        返回 调用 分配类型（alloc_type）（类型条目类别：切片（TYP_SLICE），元素类型（elem），0）
    返回 调用 分配类型（alloc_type）（类型条目类别：数组（TYP_ARRAY），元素类型（elem），大小（sz））

如果 调用 AST 访问器：类别（ast_kind）（node）等于 引用类型表达式（EXPR_REFTYPE），那么：
    （引用类型 &泛型参数（T） 或 &可变（mut） 泛型参数 T）
    令 内部类型（inner） = 调用 解析类型节点（res_type_node）（调用 第一子节点访问器（ast_a）（node））
    令 可变标记（mut_flag） = 调用 AST 访问器：整数值（ast_int_val）（node）
    返回 调用 分配类型（alloc_type）（类型条目类别：引用（TYP_REF），内部类型（inner），可变标记（mut_flag））

如果 调用 AST 访问器：类别（ast_kind）（node）等于 指针类型表达式（EXPR_PTRTYPE），那么：
    （T）
    令 内部类型（inner） = 调用 解析类型节点（res_type_node）（调用 第一子节点访问器（ast_a）（node））
    令 地址空间（asp） ：可推导类型，可变 = 0
    如果 非安全（unsafe） 块深度（g_unsafe_depth）大于 0，那么：令 地址空间（asp） = 1   （非安全 块内 → 外部地址空间）
    返回 调用 分配类型（alloc_type）（类型条目类别：指针（TYP_PTR），内部类型（inner），地址空间（asp））

如果 调用 AST 访问器：类别（ast_kind）（node）等于 泛型应用表达式（EXPR_GENERIC_APPLY），那么：
    （泛型应用：例如 Box[整数（int）]）
    令 名称索引（name_idx） = 调用 AST 访问器：变量甲（a）（ast_a）（node）
    令 首参节点（first_arg_node） = 调用 AST 访问器：变量乙（b）（ast_b）（node）
    令 参数个数（arg_count） = 调用 AST 访问器：变量丙（c）（ast_c）（node）

    令 符号索引（si） = 调用 查找泛型符号（gsym）（find_gsym）（name_idx）
    如果 符号索引（si）小于 0 或 调用 符号类别（sym_kind）（si）不等于 符号类别：类型（SYM_TYPE），那么：
        调用 检查错误（check_error）（EC_N_GENERIC_TYPE，"泛型应用中的未定义类型"，调用 AST 访问器：行号（ast_line）（node），调用 AST 访问器：列号（ast_col）（节点（节点）））
        返回 类型表预分配：单元（TI_UNIT）

    令 基础类型表索引（base_ti） = 调用 符号类型（sym_type）（si）

    （将参数存入泛型应用数据数组（g_gen_apply_data）：格式为 [参数个数，参1，参2，...]）
    令 数据起始索引（data_start） = 泛型应用数据计数（g_gen_apply_data_count）
    调用 扩展泛型应用数据数组（grow_gen_apply_data）（数据起始索引（data_start） + 1 + 参数个数（arg_count））
    调用 读写字：写 64 位（w64）（泛型应用数据数组（g_gen_apply_data），数据起始索引（data_start） * 8，参数个数（arg_count））
    令 泛型应用数据计数（g_gen_apply_data_count） = 数据起始索引（data_start） + 1

    令 参数索引（ai） ：可推导类型，可变 = 0
    令 参数节点（an） ：可推导类型，可变 = 首参节点（first_arg_node）
    循环：
        如果 参数索引（ai）大于等于 参数个数（arg_count），那么：跳出循环
        令 参数类型表索引（arg_ti） = 调用 解析类型节点（res_type_node）（an）
        调用 读写字：写 64 位（w64）（泛型应用数据数组（g_gen_apply_data），（数据起始索引（data_start） + 1 + 参数索引（ai）） * 8，参数类型表索引（arg_ti））
        参数索引（ai） = 参数索引（ai） + 1
        参数节点（an） = 参数节点（an） + 1

    令 泛型应用数据计数（g_gen_apply_data_count） = 数据起始索引（data_start） + 1 + 参数个数（arg_count）
    返回 调用 分配类型（alloc_type）（类型条目类别：泛型应用（TYP_GENERIC_APPLY），基础类型表索引（base_ti），数据起始索引（data_start））

返回 类型表预分配：单元（TI_UNIT）
`

### 测试要点
1. 基础类型 整数（int） -> 返回 类型信息：整数（TI_INT）
2. 命名类型 示例结构（MyStruct）（已通过 collect_decls 注册）-> 返回对应的类型表索引
3. 数组类型 [整数（int）； 10] -> 返回 数组类型（TYP_ARRAY）（elem=类型信息：整数（TI_INT）, size=10）
4. 切片类型 [整数（int）]（size=0）-> 返回 切片类型（TYP_SLICE）（TI_INT）
5. 引用类型 &整数（int） -> 返回 引用类型（TYP_REF）（inner=类型信息：整数（TI_INT）, mut_flag=0）
6. 引用类型 &可变（mut） 整数（int） -> 返回 引用类型（TYP_REF）（inner=类型信息：整数（TI_INT）, mut_flag=1）
7. 指针类型 *泛型参数 泛型参数（T）（泛型参数 T）（非 非安全（unsafe） 块内）-> 指针类型（TYP_PTR）（inner, asp=0）
8. 指针类型 *泛型参数 泛型参数（T）（泛型参数 T）（非安全（unsafe） 块内）-> 指针类型（TYP_PTR）（inner, asp=1）
9. 泛型应用 向量类型（Vec）[整数（int）] -> 泛型应用类型（TYP_GENERIC_APPLY），泛型应用数据数组（g_gen_apply_data）正确存储参数个数和参数类型
10. 泛型应用的参数类型节点为嵌套命名类型时递归解析

## 函数 查找结构体（find_struct）
函数 查找结构体（find_struct）（名称索引（name_idx）：整数（int））-> 整数（整数）

### 作用
在结构体数组（g_structs）中线性搜索指定名称索引的结构体。返回结构体数组中的索引，未找到返回 -1。

### 逻辑
`
令 索引（i） ：可推导类型，可变 = 0
循环：
    如果 索引（i）大于等于 结构体计数（g_struct_count），那么：返回 -1
    如果 调用 结构体信息访问器：名称（si_name）（i）等于 名称索引（name_idx），那么：返回 索引（索引）
    索引（i） = 索引（索引） + 1
返回 -1
`

### 测试要点
1. 找到已注册结构体：返回正确索引
2. 找不到：返回 -1
3. 结构体计数（g_struct_count）为 0：返回 -1

## 函数 查找枚举（find_enum）
函数 查找枚举（find_enum）（名称索引（name_idx）：整数（int））-> 整数（整数）

### 作用
在枚举数组（g_enums）中线性搜索指定名称索引的枚举。返回枚举数组中的索引，未找到返回 -1。

### 逻辑
`
令 索引（i） ：可推导类型，可变 = 0
循环：
    如果 索引（i）大于等于 枚举计数（g_enum_count），那么：返回 -1
    如果 调用 枚举信息访问器：名称（ei_name）（i）等于 名称索引（name_idx），那么：返回 索引（索引）
    索引（i） = 索引（索引） + 1
返回 -1
`

### 测试要点
1. 找到已注册枚举：返回正确索引
2. 找不到：返回 -1

## 函数 查找接口（find_iface）
函数 查找接口（find_iface）（名称索引（name_ni）：整数（int））-> 整数（整数）

### 作用
在接口数组（g_ifaces）中线性搜索指定名称索引的接口。返回接口数组中的索引，未找到返回 -1。

### 逻辑
`
令 索引（i） ：可推导类型，可变 = 0
循环：
    如果 索引（i）大于等于 接口计数（g_iface_count），那么：返回 -1
    如果 调用 读写字：读 64 位（r64）（接口数组（g_ifaces），索引（i） * 接口信息大小（ESZ_IFACEINFO） + OFF_IF_NAME）等于 名称索引（name_ni），那么：返回 索引（索引）
    索引（i） = 索引（索引） + 1
返回 -1
`

### 测试要点
1. 找到已注册接口：返回正确索引
2. 找不到：返回 -1

## 函数 获取类型名称（get_type_name）
函数 获取类型名称（get_type_name）（类型表索引（ti）：整数（int））-> 整数（整数）

### 作用
从类型表索引（ti）提取可读的类型名称（字符串驻留索引）。基础类型返回 "整数（int）"/"浮点（float）"/"布尔（bool）"/"字符串（string）"/"单元类型（unit）"/"字符（char）" 的驻留索引；命名类型返回其名称字符串索引；泛型应用的命名基础类型返回其基础类型的名称；其他返回 -1。

### 逻辑
`
令 类别（k） = 调用 获取类型类别（get_type_kind）（ti）

如果 类别（k）等于 类型条目类别：命名（TYP_NAMED），那么：
    返回 调用 获取类型数据（get_type_data）（ti）

如果 类别（k）等于 类型条目类别：基础（TYP_BASE），那么：
    令 数据（d） = 调用 获取类型数据（get_type_data）（ti）
    如果 数据（d）等于 整数（TY_INT），那么：返回 调用 字符串驻留（str_intern）（"整数（int）"）
    如果 数据（d）等于 浮点数（TY_FLOAT），那么：返回 调用 字符串驻留（str_intern）（"浮点（float）"）
    如果 数据（d）等于 布尔（TY_BOOL），那么：返回 调用 字符串驻留（str_intern）（"布尔（bool）"）
    如果 数据（d）等于 字符串（TY_STRING），那么：返回 调用 字符串驻留（str_intern）（"字符串（string）"）
    如果 数据（d）等于 单元（TY_UNIT），那么：返回 调用 字符串驻留（str_intern）（"单元类型（unit）"）
    如果 数据（d）等于 字符（TY_CHAR），那么：返回 调用 字符串驻留（str_intern）（"字符（char）"）

如果 类别（k）等于 类型条目类别：泛型应用（TYP_GENERIC_APPLY），那么：
    令 基础类型（base） = 调用 获取类型数据（get_type_data）（ti）
    如果 调用 获取类型类别（get_type_kind）（base）等于 类型条目类别：命名（TYP_NAMED），那么：
        返回 调用 获取类型数据（get_type_data）（base）

返回 -1
`

### 测试要点
1. 类型信息：整数（TI_INT） -> 返回 "整数（int）" 的驻留索引
2. 命名类型 示例结构（MyStruct） -> 返回 "示例结构" 的驻留索引
3. 向量类型（Vec）[整数（int）]（泛型应用）-> 返回 "向量类型" 的驻留索引
4. 指针类型（TYP_PTR）、引用类型（TYP_REF） 类型 -> 返回 -1

## 函数 类型具有（has）方法（type_has_method）
函数 类型具有（has）方法（type_has_method）（类型名称索引（type_ni）：整数（int），方法名称索引（method_ni）：整数）-> 布尔（bool）

### 作用
检查指定类型是否有指定名称的方法。通过拼接 "类型名.方法名" 的加工名称（mangled name），查找是否存在对应的函数定义。

### 逻辑
`
令 类型名（tname） = 调用 驻留字符串获取（istr_get）（type_ni）
令 方法名（mname） = 调用 驻留字符串获取（istr_get）（method_ni）
令 加工名（mangled） = 类型名（tname） + "." + 方法名（mname）
令 加工名索引（mangled_ni） = 调用 字符串驻留（str_intern）（mangled）
返回 调用 查找函数（find_func）（mangled_ni）大于等于 0
`

### 测试要点
1. 类型有对应方法（如定义了 `示例结构（MyStruct）.方法（method）` 函数）：返回 真
2. 类型无对应方法：返回 假
3. 加工名称的格式正确（类型名.方法名）

## 函数 检查接口（check_iface）
函数 检查接口（check_iface）（类型名称索引（type_ni）：整数（int），接口索引（iface_ii）：整数）-> 布尔（bool）

### 作用
检查指定类型是否满足接口的全部方法需求。遍历接口中声明的每个方法，逐一验证类型定义了同名方法，且参数个数和返回类型均匹配。

### 逻辑
`
令 方法个数（method_count） = 调用 读写字：读 64 位（r64）（接口数组（g_ifaces），接口索引（iface_ii） * 接口信息大小（ESZ_IFACEINFO） + OFF_IF_METHOD_COUNT）

令 方法索引（mi） ：可推导类型，可变 = 0
循环：
    如果 方法索引（mi）大于等于 方法个数（method_count），那么：返回 真

    令 方法基址（mbase2） = 接口索引（iface_ii） * 接口信息大小（ESZ_IFACEINFO） + 接口方法表偏移（OFF_IF_METHODS） + 方法索引（mi） * 接口方法大小（ESZ_IFMETHOD）
    令 方法名索引（method_ni） = 调用 读写字：读 64 位（r64）（接口数组（g_ifaces），方法基址（mbase2） + OFF_IFM_NAME）

    如果 非 调用 类型具有（has）方法（type_has_method）（类型名称索引（type_ni），方法名索引（method_ni）），那么：
        返回 假

    （同时验证参数个数和返回类型是否匹配）
    令 类型名（tname2） = 调用 驻留字符串获取（istr_get）（type_ni）
    令 方法名（mname2） = 调用 驻留字符串获取（istr_get）（method_ni）
    令 加工名（mangled2） = 类型名（tname2） + "." + 方法名（mname2）
    令 加工名索引（mangled_ni2） = 调用 字符串驻留（str_intern）（mangled2）
    令 函数索引（fi2） = 调用 查找函数（find_func）（mangled_ni2）

    如果 函数索引（fi2）大于等于 0，那么：
        令 接口参数个数（iface_pc） = 调用 读写字：读 64 位（r64）（接口数组（g_ifaces），方法基址（mbase2） + OFF_IFM_PARAM_COUNT）
        如果 调用 函数信息访问器：参数计数（fi_param_count）（fi2）不等于 接口参数个数（iface_pc），那么：返回 假
        令 接口返回类型（iface_rt） = 调用 读写字：读 64 位（r64）（接口数组（g_ifaces），方法基址（mbase2） + OFF_IFM_RET_TI）
        如果 调用 函数信息访问器：返回类型（fi_return_type）（fi2）不等于 接口返回类型（iface_rt），那么：返回 假

    方法索引（mi） = 方法索引（mi） + 1

返回 真
`

### 测试要点
1. 类型完全满足接口的所有方法需求：返回 真
2. 缺少某个方法：返回 假
3. 有方法但参数个数不匹配：返回 假
4. 有方法但返回类型不匹配：返回 假

## 函数 收集声明（collect_decls）
函数 收集声明（collect_decls）（）-> 空类型（void）

### 作用
编译器语义分析的第一遍：遍历编译单元中的所有顶层声明（结构体/枚举/接口/函数/全局变量/模块别名/外部函数），在符号表中注册名称并按需解析类型。为后续第二遍（类型检查函数体）准备上下文。

### 逻辑
`
令 索引（i） ：可推导类型，可变 = 0

（第一步：注册所有结构体类型）
循环：
    如果 索引（i）大于等于 结构体计数（g_struct_count），那么：跳出循环
    令 名称索引（name_idx） = 调用 结构体信息访问器：名称（si_name）（i）
    令 类型索引（type_idx） = 调用 分配类型（alloc_type）（类型条目类别：命名（TYP_NAMED），名称索引（name_idx），0）
    调用 定义符号（def_sym）（名称索引（name_idx），符号类别：类型（SYM_TYPE），类型索引（type_idx），-1）
    索引（i） = 索引（索引） + 1

（第二步：解析结构体字段类型（目前字段类型以 整数（int） 形式存储，暂不在此解析））
令 索引（i） = 0
循环：
    如果 索引（i）大于等于 结构体计数（g_struct_count），那么：跳出循环
    令 字段索引（j） ：可推导类型，可变 = 0
    循环：
        如果 字段索引（j）大于等于 调用 结构体信息访问器：字段计数（si_field_count）（i），那么：跳出循环
        （字段类型由解析器通过 解包类型（unpack_type）（） 结果（TY_* 或 0）存储。
          此处需要解析它们——但它们以整数而非节点的形式存储。
          目前保持不变，字段在类型推断期间解析。）
        字段索引（j） = 字段索引（j） + 1
    索引（i） = 索引（索引） + 1

（第三步：注册结构体泛型参数以用于类型解析）
令 索引（i） = 0
循环：
    如果 索引（i）大于等于 结构体计数（g_struct_count），那么：跳出循环
    令 泛型个数（gc） = 调用 结构体信息访问器：泛型计数（si_generic_count）（i）
    如果 泛型个数（gc）大于 0，那么：
        令 泛型索引（gj） ：可推导类型，可变 = 0
        循环：
            如果 泛型索引（gj）大于等于 泛型个数（gc），那么：跳出循环
            令 泛型名索引（gname_ni） = 调用 结构体信息访问器：泛型名称（si_generic_name）（索引（i），泛型索引（gj））
            令 泛型类型表索引（g_ti） = 调用 分配类型（alloc_type）（类型条目类别：泛型参数（TYP_GENERIC_PARAM），泛型名索引（gname_ni），0）
            调用 扩展泛型参数数组（grow_gen_params）（泛型参数计数（g_gen_param_count） + 2）
            调用 读写字：写 64 位（w64）（泛型参数数组（g_gen_params），泛型参数计数（g_gen_param_count） * 8，泛型名索引（gname_ni））
            调用 读写字：写 64 位（w64）（泛型参数数组（g_gen_params），（泛型参数计数（g_gen_param_count） + 1） * 8，泛型类型表索引（g_ti））
            令 泛型参数计数（g_gen_param_count） = 泛型参数计数（g_gen_param_count） + 2
            调用 定义符号（def_sym）（泛型名索引（gname_ni），符号类别：类型（SYM_TYPE），泛型类型表索引（g_ti），-1）
            泛型索引（gj） = 泛型索引（gj） + 1
    索引（i） = 索引（索引） + 1

（第四步：注册所有接口类型）
令 索引（i） = 0
循环：
    如果 索引（i）大于等于 接口计数（g_iface_count），那么：跳出循环
    令 名称索引（name_idx） = 调用 读写字：读 64 位（r64）（接口数组（g_ifaces），索引（i） * 接口信息大小（ESZ_IFACEINFO） + OFF_IF_NAME）
    令 类型索引（type_idx） = 调用 分配类型（alloc_type）（类型条目类别：命名（TYP_NAMED），名称索引（name_idx），0）
    调用 定义符号（def_sym）（名称索引（name_idx），符号类别：类型（SYM_TYPE），类型索引（type_idx），-1）
    索引（i） = 索引（索引） + 1

（第五步：注册内建 可选类型（Option） 类型（用于 泛型参数（T）? 语法糖的脱糖））
令 是否找到选项（option_found） ：可推导类型，可变 = 0
令 索引（i） = 0
循环：
    如果 索引（i）大于等于 枚举计数（g_enum_count），那么：跳出循环
    如果 调用 枚举信息访问器：名称（ei_name）（i）等于 调用 字符串驻留（str_intern）（"可选类型（Option）"），那么：
        令 是否找到选项（option_found） = 1
    索引（i） = 索引（索引） + 1

如果 是否找到选项（option_found）等于 0，那么：
    （自动将 可选类型（Option） 注册为一个泛型内建类型）
    令 选项名索引（option_name_idx） = 调用 字符串驻留（str_intern）（"可选类型（Option）"）
    令 选项类型表索引（option_ti） = 调用 分配类型（alloc_type）（类型条目类别：命名（TYP_NAMED），选项名索引（option_name_idx），0）
    调用 定义符号（def_sym）（选项名索引（option_name_idx），符号类别：类型（SYM_TYPE），选项类型表索引（option_ti），-1）

（第六步：注册所有枚举类型及其变体构造器）
令 索引（i） = 0
循环：
    如果 索引（i）大于等于 枚举计数（g_enum_count），那么：跳出循环
    令 名称索引（name_idx） = 调用 枚举信息访问器：名称（ei_name）（i）
    令 类型索引（type_idx） = 调用 分配类型（alloc_type）（类型条目类别：命名（TYP_NAMED），名称索引（name_idx），0）
    调用 定义符号（def_sym）（名称索引（name_idx），符号类别：类型（SYM_TYPE），类型索引（type_idx），-1）

    （将每个变体注册为一个返回该枚举类型的函数）
    令 变体索引（vi） ：可推导类型，可变 = 0
    循环：
        如果 变体索引（vi）大于等于 调用 枚举信息访问器：变体计数（ei_variant_count）（i），那么：跳出循环
        令 变体名索引（vname_idx） = 调用 枚举信息访问器：变体名称（ei_variant_name）（索引（i），变体索引（vi））
        调用 定义符号（def_sym）（变体名索引（vname_idx），符号类别：函数（SYM_FN），类型索引（type_idx），-1）
        变体索引（vi） = 变体索引（vi） + 1
    索引（i） = 索引（索引） + 1

（第七步：注册枚举泛型参数以用于类型解析）
令 索引（i） = 0
循环：
    如果 索引（i）大于等于 枚举计数（g_enum_count），那么：跳出循环
    令 泛型个数（gc） = 调用 枚举信息访问器：泛型计数（ei_generic_count）（i）
    如果 泛型个数（gc）大于 0，那么：
        令 泛型索引（gj） ：可推导类型，可变 = 0
        循环：
            如果 泛型索引（gj）大于等于 泛型个数（gc），那么：跳出循环
            令 泛型名索引（gname_ni） = 调用 枚举信息访问器：泛型名称（ei_generic_name）（索引（i），泛型索引（gj））
            令 泛型类型表索引（g_ti） = 调用 分配类型（alloc_type）（类型条目类别：泛型参数（TYP_GENERIC_PARAM），泛型名索引（gname_ni），0）
            调用 扩展泛型参数数组（grow_gen_params）（泛型参数计数（g_gen_param_count） + 2）
            调用 读写字：写 64 位（w64）（泛型参数数组（g_gen_params），泛型参数计数（g_gen_param_count） * 8，泛型名索引（gname_ni））
            调用 读写字：写 64 位（w64）（泛型参数数组（g_gen_params），（泛型参数计数（g_gen_param_count） + 1） * 8，泛型类型表索引（g_ti））
            令 泛型参数计数（g_gen_param_count） = 泛型参数计数（g_gen_param_count） + 2
            调用 定义符号（def_sym）（泛型名索引（gname_ni），符号类别：类型（SYM_TYPE），泛型类型表索引（g_ti），-1）
            泛型索引（gj） = 泛型索引（gj） + 1
    索引（i） = 索引（索引） + 1

（第八步：注册类型别名）
令 索引（i） = 0
循环：
    如果 索引（i）大于等于 类型别名计数（g_type_alias_count），那么：跳出循环
    令 名称索引（name_idx） = 调用 读写字：读 64 位（r64）（类型别名数组（g_type_aliases），索引（i） * 16）
    令 类型节点（type_node） = 调用 读写字：读 64 位（r64）（类型别名数组（g_type_aliases），索引（i） * 16 + 8）
    令 类型表索引（ti） = 调用 解析类型节点（res_type_node）（type_node）
    调用 定义符号（def_sym）（名称索引（name_idx），符号类别：类型（SYM_TYPE），类型表索引（ti），-1）
    索引（i） = 索引（索引） + 1

（第九步：注册所有函数）
令 索引（i） = 0
循环：
    如果 索引（i）大于等于 函数计数（g_func_count），那么：跳出循环

    令 名称索引（name_idx） = 调用 函数信息访问器：名称（fi_name）（i）
    令 函数节点（fn_node） = 调用 函数信息访问器：AST 数组（ast）节点（fi_ast_node）（i）
    令 热补丁版本号（hotpatch_ver） = 调用 AST 访问器：整数值（ast_int_val）（fn_node） / 256
    令 返回类型（rt） = 调用 函数信息访问器：返回类型（fi_return_type）（i）
    令 返回类型表索引（rt_ti） ：可推导类型，可变 = 类型表预分配：单元（TI_UNIT）

    （对于泛型函数，跳过返回类型解析（取决于调用点））
    如果 调用 函数信息访问器：泛型计数（fi_generic_count）（i）大于 0，那么：
        令 返回类型表索引（rt_ti） = 类型表预分配：单元（TI_UNIT）
        （注册函数泛型参数以用于类型解析）
        令 泛型索引（gj） ：可推导类型，可变 = 0
        循环：
            如果 泛型索引（gj）大于等于 调用 函数信息访问器：泛型计数（fi_generic_count）（i），那么：跳出循环
            令 泛型名索引（gname_ni） = 调用 函数信息访问器：泛型名称（fi_generic_name）（索引（i），泛型索引（gj））
            令 泛型类型表索引（g_ti） = 调用 分配类型（alloc_type）（类型条目类别：泛型参数（TYP_GENERIC_PARAM），泛型名索引（gname_ni），0）
            调用 扩展泛型参数数组（grow_gen_params）（泛型参数计数（g_gen_param_count） + 2）
            调用 读写字：写 64 位（w64）（泛型参数数组（g_gen_params），泛型参数计数（g_gen_param_count） * 8，泛型名索引（gname_ni））
            调用 读写字：写 64 位（w64）（泛型参数数组（g_gen_params），（泛型参数计数（g_gen_param_count） + 1） * 8，泛型类型表索引（g_ti））
            令 泛型参数计数（g_gen_param_count） = 泛型参数计数（g_gen_param_count） + 2
            调用 定义符号（def_sym）（泛型名索引（gname_ni），符号类别：类型（SYM_TYPE），泛型类型表索引（g_ti），-1）
            泛型索引（gj） = 泛型索引（gj） + 1
    否则：
        （非泛型函数：解析返回类型）
        令 类型节点（type_node） = 调用 AST 访问器：类型值（ast_type_val）（fn_node）
        如果 类型节点（type_node）大于 0 且 调用 AST 访问器：类别（ast_kind）（type_node）不等于 0，那么：
            令 返回类型表索引（rt_ti） = 调用 解析类型节点（res_type_node）（type_node）
        否则如果 返回类型（rt）等于 整数（TY_INT），那么：令 返回类型表索引（rt_ti） = 类型表预分配：整数（TI_INT）
        否则如果 返回类型（rt）等于 浮点数（TY_FLOAT），那么：令 返回类型表索引（rt_ti） = 类型表预分配：浮点数（TI_FLOAT）
        否则如果 返回类型（rt）等于 布尔（TY_BOOL），那么：令 返回类型表索引（rt_ti） = 类型表预分配：布尔（TI_BOOL）
        否则如果 返回类型（rt）等于 字符串（TY_STRING），那么：令 返回类型表索引（rt_ti） = 类型表预分配：字符串（TI_STR）
        否则如果 返回类型（rt）等于 单元（TY_UNIT），那么：令 返回类型表索引（rt_ti） = 类型表预分配：单元（TI_UNIT）

    （@热补丁（hotpatch） 函数特殊处理）
    如果 热补丁版本号（hotpatch_ver）大于 0，那么：
        （用加工名称注册：函数名.值（v）版本号）
        令 函数名字符串（fn_name_str） = 调用 驻留字符串获取（istr_get）（name_idx）
        令 加工名（mangled_name） = 函数名字符串（fn_name_str） + ".值（v）" + 调用 整数转字符串（int_str）（hotpatch_ver）
        令 加工名索引（mangled_ni） = 调用 字符串驻留（str_intern）（mangled_name）
        调用 定义符号（def_sym）（加工名索引（mangled_ni），符号类别：函数（SYM_FN），返回类型表索引（rt_ti），函数节点（fn_node））

        （验证签名与第一个版本是否匹配）
        令 前向索引（fj） ：可推导类型，可变 = 0
        循环：
            如果 前向索引（fj）大于等于 索引（i），那么：跳出循环
            如果 调用 函数信息访问器：名称（fi_name）（fj）等于 名称索引（name_idx），那么：
                令 首个函数节点（first_fn） = 调用 函数信息访问器：AST 数组（ast）节点（fi_ast_node）（fj）
                令 首个返回类型（first_rt） = 调用 函数信息访问器：返回类型（fi_return_type）（fj）
                令 首个返回类型表索引（first_rt_ti） ：可推导类型，可变 = 类型表预分配：单元（TI_UNIT）
                令 类型节点2（type_node2） = 调用 AST 访问器：类型值（ast_type_val）（first_fn）
                如果 类型节点2（type_node2）大于 0 且 调用 AST 访问器：类别（ast_kind）（type_node2）不等于 0，那么：
                    令 首个返回类型表索引（first_rt_ti） = 调用 解析类型节点（res_type_node）（type_node2）
                否则如果 首个返回类型（first_rt）等于 整数（TY_INT），那么：令 首个返回类型表索引（first_rt_ti） = 类型表预分配：整数（TI_INT）
                否则如果 首个返回类型（first_rt）等于 浮点数（TY_FLOAT），那么：令 首个返回类型表索引（first_rt_ti） = 类型表预分配：浮点数（TI_FLOAT）
                否则如果 首个返回类型（first_rt）等于 布尔（TY_BOOL），那么：令 首个返回类型表索引（first_rt_ti） = 类型表预分配：布尔（TI_BOOL）
                否则如果 首个返回类型（first_rt）等于 字符串（TY_STRING），那么：令 首个返回类型表索引（first_rt_ti） = 类型表预分配：字符串（TI_STR）
                否则如果 首个返回类型（first_rt）等于 单元（TY_UNIT），那么：令 首个返回类型表索引（first_rt_ti） = 类型表预分配：单元（TI_UNIT）

                如果 非 调用 类型相等（equal）（type_equal）（返回类型表索引（rt_ti），首个返回类型表索引（first_rt_ti）），那么：
                    调用 检查错误（check_error）（EC_TF_RETURN，"热补丁返回类型不匹配，函数 '" + 函数名字符串（fn_name_str）+ "'"，调用 AST 访问器：行号（ast_line）（fn_node），调用 AST 访问器：列号（ast_col）（fn_node））

                令 首个参数个数（first_pc） = 调用 函数信息访问器：参数计数（fi_param_count）（fj）
                令 当前参数个数（cur_pc） = 调用 函数信息访问器：参数计数（fi_param_count）（i）
                如果 首个参数个数（first_pc）不等于 当前参数个数（cur_pc），那么：
                    调用 检查错误（check_error）（重复定义错误码（EC_N_DUPLICATE），"热补丁参数个数不匹配，函数 '" + 函数名字符串（fn_name_str）+ "'"，调用 AST 访问器：行号（ast_line）（fn_node），调用 AST 访问器：列号（ast_col）（fn_node））
                跳出循环
            前向索引（fj） = 前向索引（fj） + 1

        （同时注册原始名称用于调用解析（最新版本胜出））
        调用 定义符号（def_sym）（名称索引（name_idx），符号类别：函数（SYM_FN），返回类型表索引（rt_ti），函数节点（fn_node））

    否则：
        （普通函数：检查重复（允许覆盖已有的 @热补丁（hotpatch） 函数））
        令 已存在符号索引（existing_si） = 调用 查找泛型符号（gsym）（find_gsym）（name_idx）
        如果 已存在符号索引（existing_si）大于等于 0 且 调用 符号类别（sym_kind）（existing_si）等于 符号类别：函数（SYM_FN），那么：
            令 已存在节点（existing_node） = 调用 符号节点（sym_node）（existing_si）
            令 已存在是否热补丁（existing_is_hotpatch） ：可推导类型，可变 = 0
            如果 已存在节点（existing_node）大于等于 0 且 调用 AST 访问器：类别（ast_kind）（existing_node）等于 函数定义表达式（EXPR_FN），那么：
                令 已存在是否热补丁（existing_is_hotpatch） = 调用 AST 访问器：整数值（ast_int_val）（existing_node） / 256
            如果 已存在是否热补丁（existing_is_hotpatch）等于 0，那么：
                令 函数名字符串（fn_name_str） = 调用 驻留字符串获取（istr_get）（name_idx）
                调用 检查错误（check_error）（重复定义错误码（EC_N_DUPLICATE），"重复函数定义 '" + 函数名字符串（fn_name_str）+ "'"，调用 AST 访问器：行号（ast_line）（fn_node），调用 AST 访问器：列号（ast_col）（fn_node））
        调用 定义符号（def_sym）（名称索引（name_idx），符号类别：函数（SYM_FN），返回类型表索引（rt_ti），函数节点（fn_node））

    调用 函数信息访问器：设置是否纯净（fi_set_ispure）（索引（i），1）   （乐观假设：所有函数均为纯净的）
    索引（i） = 索引（索引） + 1

（第十步：注册外部函数声明（尚未在函数数组（g_funcs）中的 外部声明表达式（EXPR_EXTERN） 节点））
令 外部索引（ei） ：可推导类型，可变 = 0
循环：
    如果 外部索引（ei）大于等于 AST 节点计数（g_ast_count），那么：跳出循环
    如果 调用 AST 访问器：类别（ast_kind）（ei）等于 外部函数表达式（EXPR_EXTERN），那么：
        令 名称索引（name_ni） = 调用 AST 访问器：变量甲（a）（ast_a）（ei）
        令 首参（first_param） = 调用 AST 访问器：变量乙（b）（ast_b）（ei）
        令 参数个数（param_count） = 调用 AST 访问器：变量丙（c）（ast_c）（ei）
        令 返回类型（ret_type） = 调用 AST 访问器：类型值（ast_type_val）（ei）

        （将返回类型解析为类型表索引）
        令 返回类型表索引（rt_ti） ：可推导类型，可变 = 类型表预分配：单元（TI_UNIT）
        如果 返回类型（ret_type）等于 整数（TY_INT），那么：令 返回类型表索引（rt_ti） = 类型表预分配：整数（TI_INT）
        否则如果 返回类型（ret_type）等于 浮点数（TY_FLOAT），那么：令 返回类型表索引（rt_ti） = 类型表预分配：浮点数（TI_FLOAT）
        否则如果 返回类型（ret_type）等于 布尔（TY_BOOL），那么：令 返回类型表索引（rt_ti） = 类型表预分配：布尔（TI_BOOL）
        否则如果 返回类型（ret_type）等于 字符串（TY_STRING），那么：令 返回类型表索引（rt_ti） = 类型表预分配：字符串（TI_STR）
        否则如果 返回类型（ret_type）等于 单元（TY_UNIT），那么：令 返回类型表索引（rt_ti） = 类型表预分配：单元（TI_UNIT）
        否则如果 返回类型（ret_type）等于 字符（TY_CHAR），那么：令 返回类型表索引（rt_ti） = 类型表预分配：字符（TI_CHAR）

        （在符号表中注册（如果重复则跳过））
        如果 调用 查找泛型符号（gsym）（find_gsym）（name_ni）小于 0，那么：
            调用 定义符号（def_sym）（名称索引（name_ni），符号类别：函数（SYM_FN），返回类型表索引（rt_ti），外部索引（ei））

        （在函数数组（g_funcs）中注册，用于后端代码生成和链接）
        令 函数索引（func_idx） = 函数计数（g_func_count）
        调用 扩展函数数组（grow_funcs）（函数索引（func_idx） + 1）
        调用 函数信息访问器：设置名称（fi_set_name）（函数索引（func_idx），名称索引（name_ni））
        调用 函数信息访问器：设置参数计数（fi_set_param_count）（函数索引（func_idx），参数个数（param_count））
        调用 函数信息访问器：设置返回类型（fi_set_return_type）（函数索引（func_idx），返回类型（ret_type））
        调用 函数信息访问器：设置AST 数组（ast）节点（fi_set_ast_node）（函数索引（func_idx），外部索引（ei））
        调用 函数信息访问器：设置泛型计数（fi_set_generic_count）（函数索引（func_idx），0）
        调用 函数信息访问器：设置是否纯净（fi_set_ispure）（函数索引（func_idx），1）   （乐观假设：外部函数均为纯净的）
        令 函数计数（g_func_count） = 函数索引（func_idx） + 1
    外部索引（ei） = 外部索引（ei） + 1

（第十一步：注册所有全局变量）
令 索引（i） = 0
循环：
    如果 索引（i）大于等于 全局声明计数（g_global_let_count），那么：跳出循环
    令 节点（node） = 调用 读写字：读 64 位（r64）（全局声明数组（g_global_lets），索引（i） * 8）
    令 名称索引（name_idx） = 调用 AST 访问器：变量甲（a）（ast_a）（node）   （变量声明表达式（EXPR_LET）：变量甲 = 名称索引）
    令 类型节点（type_node） = 调用 AST 访问器：变量乙（b）（ast_b）（node）  （变量声明表达式（EXPR_LET）：第二子节点（变量乙） = 类型节点，-1 表示无）
    令 类型表索引（ti） ：可推导类型，可变 = 类型表预分配：单元（TI_UNIT）
    如果 类型节点（type_node）大于等于 0，那么：令 类型表索引（ti） = 调用 解析类型节点（res_type_node）（type_node）
    调用 定义符号（def_sym）（名称索引（name_idx），符号类别：全局变量（SYM_GLOBAL），类型表索引（ti），节点（node））
    索引（i） = 索引（索引） + 1

（第十二步：注册模块别名（来自 引入（import） 语句））
令 模块索引（mi） ：可推导类型，可变 = 0
循环：
    如果 模块索引（mi）大于等于 模块计数（g_mod_count），那么：跳出循环
    令 别名索引（alias_ni） = 调用 读写字：读 64 位（r64）（模块数组（g_mods），模块索引（mi） * 24）
    令 文件 ID 索引（fileid_ni） = 调用 读写字：读 64 位（r64）（模块数组（g_mods），模块索引（mi） * 24 + 8）
    调用 定义符号（def_sym）（别名索引（alias_ni），符号类别：模块（SYM_MODULE），文件 ID 索引（fileid_ni），-1）
    模块索引（mi） = 模块索引（mi） + 1

（第十三步：注册 mod 路径声明（例如 mod foo::bar；））
令 路径索引（pi） ：可推导类型，可变 = 0
循环：
    如果 路径索引（pi）大于等于 模块路径计数（g_mod_path_count），那么：跳出循环
    令 模块路径名（mpn） = 调用 读写字：读 64 位（r64）（模块路径名数组（g_mod_path_names），路径索引（pi） * 8）
    调用 定义符号（def_sym）（模块路径名（mpn），符号类别：模块（SYM_MODULE），模块路径名（mpn），-1）
    路径索引（pi） = 路径索引（pi） + 1

（第十四步：构建模块函数查找表，用于限定访问，例如 mymath.add）
令 主文件 ID 索引（main_fni） ：可推导类型，可变 = 0
如果 文件计数（g_file_count）大于 0，那么：令 主文件 ID 索引（main_fni） = 调用 读写字：读 64 位（r64）（文件数组（g_files），0）
令 模块函数计数（g_mod_func_count） = 0
令 模块函数容量（g_mod_func_cap） = 0

令 函数遍历索引（fi） ：可推导类型，可变 = 0
循环：
    如果 函数遍历索引（fi）大于等于 函数计数（g_func_count），那么：跳出循环
    令 函数节点（fn_node） = 调用 函数信息访问器：AST 数组（ast）节点（fi_ast_node）（fi）
    令 函数行号（fn_line） = 调用 AST 访问器：行号（ast_line）（fn_node）
    如果 函数行号（fn_line）大于 0 且 函数行号（fn_line）小于等于 行计数（g_line_count），那么：
        令 文件 ID 索引（fileid_ni） = 调用 读写字：读 64 位（r64）（行文件 ID 数组（g_line_fileid），（函数行号（fn_line） - 1） * 8）
        如果 文件 ID 索引（fileid_ni）不等于 主文件 ID 索引（main_fni）且 文件 ID 索引（fileid_ni）不等于 0 且 行计数（g_line_count）大于 0，那么：
            调用 扩展模块函数数组（grow_mod_funcs）（模块函数计数（g_mod_func_count） + 1）
            调用 读写字：写 64 位（w64）（模块函数文件 ID 数组（g_mod_func_fileids），模块函数计数（g_mod_func_count） * 8，文件 ID 索引（fileid_ni））
            调用 读写字：写 64 位（w64）（模块函数名数组（g_mod_func_names），模块函数计数（g_mod_func_count） * 8，调用 函数信息访问器：名称（fi_name）（fi））
            令 函数符号索引（fn_si） = 调用 查找符号（find_sym）（调用 函数信息访问器：名称（fi_name）（fi））
            如果 函数符号索引（fn_si）大于等于 0，那么：
                调用 读写字：写 64 位（w64）（模块函数类型索引数组（g_mod_func_tis），模块函数计数（g_mod_func_count） * 8，调用 符号类型（sym_type）（fn_si））
            令 模块函数计数（g_mod_func_count） = 模块函数计数（g_mod_func_count） + 1
    函数遍历索引（fi） = 函数遍历索引（fi） + 1
`

### 测试要点
1. 结构体注册后：通过 查找泛型符号（gsym）（find_gsym）查找结构体名能找到对应 符号：类型（SYM_TYPE） 符号
2. 枚举变体注册为 符号：函数（SYM_FN）：调用变体名作为函数得到正确返回类型
3. 内建 可选类型（Option） 类型：当无用户定义 可选类型 枚举时自动补充
4. @热补丁（hotpatch） 函数：产生加工名（name.vN）和原名两份注册
5. @热补丁（hotpatch） 版本签名不匹配：产生对应的错误诊断
6. 重复函数定义（非 热补丁（hotpatch） 覆盖）：产生 重复定义错误码（EC_N_DUPLICATE） 错误
7. 外部函数声明（EXPR_EXTERN）：在符号表和 函数数组（g_funcs） 中同时注册
8. 全局 令（let） 声明：类型节点为 -1 时 类型信息（TI） 为 类型信息：单元（TI_UNIT）
9. 模块函数查找表：非主文件的函数被纳入 模块函数数组族（g_mod_func_）* 数组
10. 泛型结构体和枚举的泛型参数：正确注册为 泛型参数类型（TYP_GENERIC_PARAM） 条目
