# 解析器（parser）.cr 伪代码（第 4 部分：顶层声明解析 + 解析总入口）
> 源文件：src/compiler/解析器（parser）.cr（第 1229~1691 行）
> 功能概要：解析顶层声明（parse_declaration）：热补丁注解预处理、公开（pub） 修饰、外部（extern） 函数（fn） 声明（含 @外部函数接口（ffi） 注解）、函数/流程（flow） 函数声明、结构（struct） 结构体声明（含泛型与字段列表）、枚举（enum） 枚举声明（含泛型与变体及其关联类型）、接口（interface） 接口声明（含泛型与方法签名——自身（self）/&自身/&可变（mut） 自身 与普通参数类型、返回类型、最大方法计数 16、最大参数 8 的上限检查与诊断）、实现（impl） 块（含 实现 类型（Type） 「 方法（method）... 」 与 实现 Interface 遍历（for） 类型 「 方法... 」，方法体委托 parse_body，方法名按 类型.方法 格式拼接注册到查找表）、类型（type） 别名声明、mod 模块声明（路径拼接与块内容跳过）。顶层解析入口（parse_all）：重置所有全局计数后循环调用 解析声明（parse_declaration），跳过 引入（import）/文件标识（fileid） 声明（留给导入解析模块处理），遇 文件结束标记（EOF） 或单次声明 AST 增长超 10000 时中止。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 解析声明 | parse_declaration | 解析声明（parse_declaration） |
| 解析全部 | parse_all | 解析全部（parse_all） |
| 解析函数体 | parse_body | 解析声明（parse_declaration） |
| 解析 FFI 注解 | parse_ffi_annotation | 解析声明（parse_declaration） |
| 解析泛型参数到容器 | parse_generics_into | 解析声明（parse_declaration） |
| 解析代码块 | parse_block | 解析声明（parse_declaration） |
| 解析新变量声明 | parse_new_var_decl | 解析声明（parse_declaration） |
| 判断新变量声明 | is_new_var_decl | 解析声明（parse_declaration） |
| 提取热补丁版本号 | extract_hotpatch_ver | 解析声明（parse_declaration） |
| 添加函数 | add_func | 解析声明（parse_declaration） |
| 添加结构体 | add_struct | 解析声明（parse_declaration） |
| 添加枚举 | add_enum | 解析声明（parse_declaration） |
| 保存函数泛型参数 | save_func_generics | 解析声明（parse_declaration） |
| 保存函数泛型约束 | save_func_gen_constrs | 解析声明（parse_declaration） |
| 压入作用域 | push_scope | 解析声明（parse_declaration） |
| 查找插件入口 | find_plugin_entry | 全局引用 |
| 词法单元数组/计数 | g_tokens/g_token_count | 全局 |
| AST 节点数组/计数/容量 | g_ast/g_ast_count/g_ast_cap | 全局 |
| 函数数组/计数/容量 | g_funcs/g_func_count/g_func_cap | 全局 |
| 结构体数组/计数/容量 | g_structs/g_struct_count/g_struct_cap | 全局 |
| 枚举数组/计数/容量 | g_enums/g_enum_count/g_enum_cap | 全局 |
| 类型别名数组/计数/容量 | g_type_aliases/g_type_alias_count/g_type_alias_cap | 全局 |
| 方法数组/计数/容量 | g_methods/g_method_count/g_method_cap | 全局 |
| 接口数组/计数/容量 | g_ifaces/g_iface_count/g_iface_cap | 全局 |
| 接口实现数组/计数/容量 | g_impl_for/g_impl_for_count/g_impl_for_cap | 全局 |
| 全局声明数组/计数/容量 | g_global_lets/g_global_let_count/g_global_lets_cap | 全局 |
| 泛型约束数组/计数/容量 | g_generic_constr/g_generic_constr_count/g_generic_constr_cap | 全局 |
| 泛型参数数组/计数/容量 | g_gen_params/g_gen_param_count/g_gen_param_cap | 全局 |
| 模块路径名数组/计数/容量 | g_mod_path_names/g_mod_path_count/g_mod_path_cap | 全局 |
| 循环标签栈/容量 | g_loop_stack/g_loop_stack_cap | 全局 |
| 循环嵌套深度 | g_loop_depth | 全局 |
| 额外声明计数 | g_extra_let_count | 全局 |
| 代码块语句计数 | g_block_stmt_count | 全局 |
| 错误计数 | g_error_count | 全局 |
| 诊断数组/计数 | g_diags/g_diag_count | 全局 |
| 当前词法单元位置 | g_token_pos | 全局 |
| 插件标签数组/计数 | g_plugin_tags/g_plugin_tag_count | 全局 |

## 全局状态

本部分使用的全局变量：

| 中文名 | 原名 | 说明 |
|--------|------|------|
| 词法单元数组/计数 | g_tokens/g_token_count | 见第 1 部分/标识符对照表 |
| AST 节点数组/计数/容量 | g_ast/g_ast_count/g_ast_cap | 见第 1 部分/标识符对照表 |
| 函数数组/计数/容量 | g_funcs/g_func_count/g_func_cap | 见第 1 部分/标识符对照表 |
| 结构体数组/计数/容量 | g_structs/g_struct_count/g_struct_cap | 见第 1 部分/标识符对照表 |
| 枚举数组/计数/容量 | g_enums/g_enum_count/g_enum_cap | 见第 1 部分/标识符对照表 |
| 类型别名数组/计数/容量 | g_type_aliases/g_type_alias_count/g_type_alias_cap | 见第 1 部分/标识符对照表 |
| 方法数组/计数/容量 | g_methods/g_method_count/g_method_cap | 见第 1 部分/标识符对照表 |
| 接口数组/计数/容量 | g_ifaces/g_iface_count/g_iface_cap | 见第 1 部分/标识符对照表 |
| 接口实现数组/计数/容量 | g_impl_for/g_impl_for_count/g_impl_for_cap | 见第 1 部分/标识符对照表 |
| 全局声明数组/计数/容量 | g_global_lets/g_global_let_count/g_global_lets_cap | 见第 1 部分/标识符对照表 |
| 泛型约束数组/计数/容量 | g_generic_constr/g_generic_constr_count/g_generic_constr_cap | 见第 1 部分/标识符对照表 |
| 泛型参数数组/计数/容量 | g_gen_params/g_gen_param_count/g_gen_param_cap | 见第 1 部分/标识符对照表 |
| 模块路径名数组/计数/容量 | g_mod_path_names/g_mod_path_count/g_mod_path_cap | 见第 1 部分/标识符对照表 |
| 循环标签栈/容量 | g_loop_stack/g_loop_stack_cap | 见第 1 部分/标识符对照表 |
| 循环嵌套深度 | g_loop_depth | 见第 1 部分/标识符对照表 |
| 额外声明计数 | g_extra_let_count | 见第 1 部分/标识符对照表 |
| 代码块语句计数 | g_block_stmt_count | 见第 1 部分/标识符对照表 |
| 错误计数 | g_error_count | 见第 1 部分/标识符对照表 |
| 诊断数组/计数 | g_diags/g_diag_count | 见第 1 部分/标识符对照表 |
| 当前词法单元位置 | g_token_pos | 见第 1 部分/标识符对照表 |
| 插件标签数组/计数 | g_plugin_tags/g_plugin_tag_count | 见第 1 部分/标识符对照表 |

## 函数 解析声明（parse_declaration）
### 作用
解析顶层声明，是 解析全部（parse_all） 循环调用的核心函数。处理以下声明的调度：
1. **热补丁注解预处理**：若以 `@` 开头且后跟 函数（fn）/流程（flow）/公开（pub）/外部（extern），则预览解析注解 AST 并提取 `@热补丁（hotpatch）（N）` 的版本号，然后回退 AST 计数（g_ast_count）以便正式解析
2. **公开（pub） 修饰符**：若以 公开关键字（T_PUB） 开头则消费并标记
3. **外部（extern） 函数（fn） 声明（FFI）**：解析 `外部 [@外部函数接口（ffi）（"lang"）] 函数 名称（name）（params...） [-> 返回类型（ret_type）]；`，构造 外部声明表达式（EXPR_EXTERN） 节点（无体）
4. **函数（fn） / 流程（flow） 函数声明**：解析 `函数 名称（name）（params...） [-> 返回（ret）] 函数体（AST 节点）（body）` 或 `流程 名称（...） 函数体（AST 节点）`，委托 解析函数体（parse_body）
5. **结构（struct） 结构体声明**：解析 `结构 名称（Name）[泛型列表（generics）] 「 字段1（field1）: 类型1（type1）, 字段2（field2）: 类型2（type2）, ... 」`，调用 添加结构体（add_struct） 注册并填充字段名/类型
6. **枚举（enum） 枚举声明**：解析 `枚举 名称（Name）[泛型列表（generics）] 「 变体1（Variant1）（type1）, 变体2（Variant2）, ... 」`，调用 添加枚举（add_enum） 注册并填充变体名/关联类型
7. **接口（interface） 接口声明**：解析 `接口 名称（Name）[泛型列表（generics）] 「 函数（fn） 方法（method）（自身（self）/params...）: 返回（ret）； ... 」`，分配接口条目，填充泛型与方法签名（最大 16 方法，每方法最大 8 参数）
8. **实现（impl） 块**：解析 `实现 类型（Type） 「 函数（fn） 方法（method）... 」` 或 `实现 特质（Trait） 遍历（for） 类型 「 函数 方法... 」`，方法体委托 解析函数体（parse_body），方法以 "类型.方法" 格式注册到方法查找表，实现-遍历 关系记录到 接口实现数组（g_impl_for）
9. **类型（type） 别名**：解析 `类型（type） 名称（Name） = 既有类型（ExistingType）；`
10. **mod 模块声明**：解析 `mod 变量甲（a）::变量乙（b）::变量丙（c）；` 或 `mod 名称（name） 「 ... 」`，路径存入模块路径表，块体内容按嵌套括号深度跳过
11. **全局变量声明**：若为 标识符（T_IDENT） 且 判断新变量声明（is_new_var_decl），调用 解析新变量声明（parse_new_var_decl） 并将结果及额外声明写入 全局声明数组（g_global_lets）
12. **未知**：消费当前词法单元
### 逻辑
`
函数 解析声明（parse_declaration）
    令 热补丁版本号（hotpatch_ver）：自动推导，可变 = 0

    -- 热补丁注解预处理：若当前词法单元为 @，则预览解析注解表达式并提取 @热补丁（hotpatch）（N）
    -- 的版本号，随后回退 AST 节点计数（g_ast_count）以便正式解析时复用节点槽位
    如果 检查（check）（T_AT），那么：
        令 保存的AST计数（saved_ast） = AST 节点计数（g_ast_count）
        令 注解节点（annotation） = 解析表达式（parse_expr）（）
        如果 检查（T_FN） 或 检查（T_FLOW） 或 检查（T_PUB） 或 检查（T_EXTERN），那么：
            令 表达式类别（k） = AST 访问器：类别（ast_kind）（注解节点）
            如果 表达式类别 等于 调用表达式（EXPR_CALL），那么：
                令 被调者节点（callee） = 第一子节点访问器（ast_a）（ast_a）（注解节点）
                如果 AST 访问器：类别（ast_kind）（被调者节点） 等于 属性访问表达式（EXPR_AT），那么：
                    令 名称索引（name_ni） = 第一子节点访问器（ast_a）（ast_a）（被调者节点）
                    令 名称（name） = 驻留字符串获取（istr_get）（名称索引）
                    如果 字符串相等比较（str_eq）（名称, "热补丁（hotpatch）"） 不等于 0，那么：
                        令 版本号提取值（hv） = 提取热补丁版本号（extract_hotpatch_ver）（ast_b（注解节点））
                        如果 版本号提取值 大于等于 0，那么：热补丁版本号 = 版本号提取值
                        否则：热补丁版本号 = 1
            否则如果 表达式类别 等于 属性访问表达式（EXPR_AT），那么：
                令 名称索引 = 第一子节点访问器（ast_a）（ast_a）（注解节点）
                令 名称 = 驻留字符串获取（名称索引）
                如果 字符串相等比较（名称, "热补丁（hotpatch）"） 不等于 0，那么：
                    热补丁版本号 = 1
            AST 节点计数（g_ast_count） = 保存的AST计数  -- 回退 AST 节点计数，后续解析从同一位置重新分配

    -- 公开（pub） 修饰符：消费 公开关键字（T_PUB） 并标记为公开
    令 是否公开（ip）：自动推导，可变 = 0
    如果 检查（T_PUB），那么：是否公开 = 1； 前进词法单元（advance_tok）（）

    -- 外部（extern） 函数（fn） 声明（FFI）：外部 [@外部函数接口（ffi）（"lang"）] 函数 名称（name）（params...） [-> 返回（ret）]；
    -- 产生 外部声明表达式（EXPR_EXTERN） 节点，无函数体，以分号结尾
    如果 检查（T_EXTERN），那么：
        令 当前词法单元索引（t） = 当前词法单元（cur_tok）（）
        前进词法单元（）
        令 外部函数接口（FFI）语言名索引（ffi_lang_ni）：自动推导，可变 = -1
        如果 检查（T_AT），那么：外部函数接口（FFI）语言名索引 = 解析 FFI 注解（parse_ffi_annotation）（parse_ffi_annotation）（）
        如果 词法单元类别（tok_k）（当前词法单元（）） 不等于 函数关键字（T_FN），那么：
            添加错误（add_error）（"期望（expected） '函数（fn）' after 外部（extern）"）
            返回
        前进词法单元（）  -- 跳过 函数（fn） 关键字
        令 名称词法单元索引（nt） = 前进词法单元（）
        令 名称 = 词法单元词素索引（tok_lx）（名称词法单元索引）
        令 函数名索引（fn_name_ni） = 字符串驻留（str_intern）（名称）
        前进词法单元（）  -- 跳过 （
        令 首参数索引（first_param）：自动推导，可变 = -1
        令 参数计数（param_count）：自动推导，可变 = 0
        如果 非 检查（T_RPAREN），那么：
            循环（当 真 成立时）：
                令 参数词法单元索引（pt） = 前进词法单元（）
                令 参数名索引（pn） = 字符串驻留（词法单元词素索引（参数词法单元索引））
                前进词法单元（）  -- 跳过 :
                令 参数类型节点（pty） = 解析类型（parse_type）（）
                如果 首参数索引 小于 0，那么：首参数索引 = AST 节点计数（g_ast_count）
                分配 AST 节点（alloc_node）（参数表达式（EXPR_PARAM）, 参数名索引, 0, 0, 0, 解包类型（unpack_type）（参数类型节点）, 参数类型节点, 词法单元行号（tok_ln）（参数词法单元索引）, 词法单元列号（tok_cl）（参数词法单元索引））
                参数计数 = 参数计数 + 1
                如果 非 检查（T_COMMA），那么：跳出循环
                前进词法单元（）
        前进词法单元（）  -- 跳过 ）
        令 返回类型值（ret_type）：自动推导，可变 = 单元类型（TY_UNIT）
        如果 检查（T_ARROW），那么：
            前进词法单元（）
            令 返回类型节点（ret_node） = 解析类型（）
            返回类型值 = 解包类型（返回类型节点）
        令 创建的节点（node）：自动推导，可变 = 分配 AST 节点（外部声明表达式（EXPR_EXTERN）, 函数名索引, 首参数索引, 参数计数, 0, 返回类型值, 外部函数接口（FFI）语言名索引, 词法单元行号（当前词法单元索引）, 词法单元列号（当前词法单元索引））
        如果 检查（T_SEMI），那么：前进词法单元（）
        返回

    -- 函数（fn） / 流程（flow） 函数声明：函数 名称（name）（params...） [-> 返回（ret）] 函数体（AST 节点）（body）  或  流程 名称（...） 函数体（AST 节点）
    -- 委托 解析函数体（parse_body）处理参数列表、返回类型和函数体
    如果 检查（T_FN） 或 检查（T_FLOW），那么：
        令 是否流函数（is_flow）：自动推导，可变 = 0
        如果 检查（T_FLOW），那么：是否流函数 = 1
        令 当前词法单元索引 = 前进词法单元（）
        令 名称词法单元索引 = 前进词法单元（）
        令 名称 = 词法单元词素索引（名称词法单元索引）
        令 名称驻留索引（ni） = 字符串驻留（名称）
        解析函数体（parse_body）（名称, 名称驻留索引, 词法单元行号（当前词法单元索引）, 词法单元列号（当前词法单元索引）, 热补丁版本号）
        如果 是否流函数 不等于 0，那么：
            -- 流函数：检查器（checker）通过检测函数体中的 让出（yield） 语句来判断应跳过返回类型检查
            -- （让出（yield） 语义不同于 返回（return）），此处无实际操作，仅保留标记供后续阶段使用
        返回

-- 结构（struct） 结构体声明：结构 名称（Name）[泛型参数] 「 字段名: 类型, ... 」
    -- 调用 添加结构体（add_struct）注册，随后填充泛型名和字段名/类型到结构体信息表
    如果 检查（T_STRUCT），那么：
        令 当前词法单元索引 = 前进词法单元（）
        令 名称词法单元索引 = 前进词法单元（）
        令 名称 = 词法单元词素索引（名称词法单元索引）
        令 结构体泛型名称（sg_names）：字符串，可变
        结构泛型名列表（sg_names） = 分配内存（alloc）（64 * 8）
        令 结构体泛型约束占位（sg_dummy）：字符串，可变
        结构泛型占位（sg_dummy） = 分配内存（64 * 8）
        令 结构体泛型计数（sg_count） = 解析泛型参数到容器（parse_generics_into）（结构体泛型名称, 结构体泛型约束占位）
前进词法单元（）  -- 跳过 「
        令 结构体索引（si） = 添加结构体（add_struct）（名称）
        如果 结构体索引 大于等于 0，那么：
            如果 结构体泛型计数 大于 0，那么：
                写 64 位（w64）（g_structs, 结构体索引 * 结构信息大小（ESZ_STRUCTINFO） + OFF_SI_GENERIC_COUNT, 结构体泛型计数）
                令 结构体泛型索引（sgi）：自动推导，可变 = 0
                循环（当 真 成立时）：
                    如果 结构体泛型索引 大于等于 结构体泛型计数，那么：跳出循环
                    写 64 位（g_structs, 结构体索引 * 结构信息大小（ESZ_STRUCTINFO） + OFF_SI_GENERIC_NAMES + 结构体泛型索引 * 8, 字符串驻留（读 64 位（r64）（结构体泛型名称, 结构体泛型索引 * 8）））
                    结构体泛型索引 = 结构体泛型索引 + 1
            令 字段计数（fc）：自动推导，可变 = 0
            循环（当 真 成立时）：
                如果 检查（T_RBRACE），那么：跳出循环
                令 字段词法单元索引（ft） = 前进词法单元（）
                令 字段名（fn2） = 词法单元词素索引（字段词法单元索引）
                写 64 位（g_structs, 结构体索引 * 结构信息大小（ESZ_STRUCTINFO） + OFF_SI_FIELD_NAMES + 字段计数 * 8, 字符串驻留（字段名））
                前进词法单元（）  -- 跳过 :
                令 字段类型节点（fty） = 解析类型（）
                写 64 位（g_structs, 结构体索引 * 结构信息大小（ESZ_STRUCTINFO） + OFF_SI_FIELD_TYPES + 字段计数 * 8, 解包类型（字段类型节点））
                写 64 位（g_structs, 结构体索引 * 结构信息大小（ESZ_STRUCTINFO） + OFF_SI_FIELD_TYPE_NODES + 字段计数 * 8, 字段类型节点）
                字段计数 = 字段计数 + 1
                如果 检查（T_COMMA），那么：前进词法单元（）
            写 64 位（g_structs, 结构体索引 * 结构信息大小（ESZ_STRUCTINFO） + OFF_SI_FIELD_COUNT, 字段计数）
前进词法单元（）  -- 跳过 」
        返回

-- 枚举（enum） 枚举声明：枚举 名称（Name）[泛型参数] 「 变体名, 变体名（关联类型...）, ... 」
    -- 调用 添加枚举（add_enum）注册，随后填充泛型名、变体名及关联类型
    如果 检查（T_ENUM），那么：
        令 当前词法单元索引 = 前进词法单元（）
        令 名称词法单元索引 = 前进词法单元（）
        令 名称 = 词法单元词素索引（名称词法单元索引）
        令 枚举泛型名称（eg_names）：字符串，可变
        枚举泛型名列表（eg_names） = 分配内存（64 * 8）
        令 枚举泛型约束占位（eg_dummy）：字符串，可变
        枚举泛型占位（eg_dummy） = 分配内存（64 * 8）
        令 枚举泛型计数（eg_count） = 解析泛型参数到容器（枚举泛型名称, 枚举泛型约束占位）
前进词法单元（）  -- 跳过 「
        令 枚举索引（ei） = 添加枚举（add_enum）（名称）
        如果 枚举索引 大于等于 0，那么：
            如果 枚举泛型计数 大于 0，那么：
                写 64 位（g_enums, 枚举索引 * 枚举信息大小（ESZ_ENUMINFO） + OFF_EI_GENERIC_COUNT, 枚举泛型计数）
                令 枚举泛型索引（egi）：自动推导，可变 = 0
                循环（当 真 成立时）：
                    如果 枚举泛型索引 大于等于 枚举泛型计数，那么：跳出循环
                    写 64 位（g_enums, 枚举索引 * 枚举信息大小（ESZ_ENUMINFO） + OFF_EI_GENERIC_NAMES + 枚举泛型索引 * 8, 字符串驻留（读 64 位（枚举泛型名称, 枚举泛型索引 * 8）））
                    枚举泛型索引 = 枚举泛型索引 + 1
            令 变体计数（vc）：自动推导，可变 = 0
            循环（当 真 成立时）：
                如果 检查（T_RBRACE），那么：跳出循环
                令 变体词法单元索引（vt） = 前进词法单元（）
                令 变体名（vname） = 词法单元词素索引（变体词法单元索引）
                写 64 位（g_enums, 枚举索引 * 枚举信息大小（ESZ_ENUMINFO） + OFF_EI_VARIANTS + 变体计数 * OFF_EV_SIZE + OFF_EV_NAME, 字符串驻留（变体名））
                令 变体关联类型计数（tc）：自动推导，可变 = 0
                如果 检查（T_LPAREN），那么：
                    前进词法单元（）  -- 跳过 （
                    循环（当 真 成立时）：
                        如果 检查（T_RPAREN），那么：跳出循环
                        令 字段类型节点 = 解析类型（）
                        写 64 位（g_enums, 枚举索引 * 枚举信息大小（ESZ_ENUMINFO） + OFF_EI_VARIANTS + 变体计数 * OFF_EV_SIZE + OFF_EV_TYPES + 变体关联类型计数 * 8, 解包类型（字段类型节点））
                        变体关联类型计数 = 变体关联类型计数 + 1
                        如果 非 检查（T_COMMA），那么：跳出循环
                        前进词法单元（）
                    前进词法单元（）  -- 跳过 ）
                写 64 位（g_enums, 枚举索引 * 枚举信息大小（ESZ_ENUMINFO） + OFF_EI_VARIANTS + 变体计数 * OFF_EV_SIZE + OFF_EV_TYPE_COUNT, 变体关联类型计数）
                变体计数 = 变体计数 + 1
                如果 检查（T_COMMA），那么：前进词法单元（）
            写 64 位（g_enums, 枚举索引 * 枚举信息大小（ESZ_ENUMINFO） + OFF_EI_VARIANT_COUNT, 变体计数）
前进词法单元（）  -- 跳过 」
        返回

-- 接口（interface） 接口声明：接口 名称（Name）[泛型参数] 「 函数（fn） 方法（method）（自身（self）/参数...）: 返回（ret）； ... 」
    -- 分配接口条目并清零，填充泛型与方法签名（最大 16 方法，每方法最大 8 参数，超出则诊断）
    如果 检查（T_INTERFACE），那么：
        令 当前词法单元索引 = 前进词法单元（）
        令 名称词法单元索引 = 前进词法单元（）
        令 接口名（iface_name） = 词法单元词素索引（名称词法单元索引）
        令 接口名索引（iface_ni） = 字符串驻留（接口名）
        令 接口泛型名称（ig_names）：字符串，可变
        接口泛型名列表（ig_names） = 分配内存（64 * 8）
        令 接口泛型约束占位（ig_dummy）：字符串，可变
        接口泛型占位（ig_dummy） = 分配内存（64 * 8）
        令 接口泛型计数（ig_count） = 解析泛型参数到容器（接口泛型名称, 接口泛型约束占位）
前进词法单元（）  -- 跳过 「
        扩展接口数组（grow_ifaces）（g_iface_count + 1）
        令 接口基地址偏移（iface_base） = 接口计数（g_iface_count） * 接口信息大小（ESZ_IFACEINFO）
        令 零初始化索引（zi）：自动推导，可变 = 0
        循环（当 真 成立时）：  -- 将接口条目全部字节清零
            如果 零初始化索引 大于等于 接口信息大小（ESZ_IFACEINFO），那么：跳出循环
            写单字节（w8）（g_ifaces, 接口基地址偏移 + 零初始化索引, 0）
            零初始化索引 = 零初始化索引 + 1
        写 64 位（g_ifaces, 接口基地址偏移 + OFF_IF_NAME, 接口名索引）
        写 64 位（g_ifaces, 接口基地址偏移 + OFF_IF_GENERIC_COUNT, 接口泛型计数）
        令 方法计数（method_count）：自动推导，可变 = 0
        循环（当 真 成立时）：
            如果 检查（T_RBRACE），那么：跳出循环
            如果 检查（T_FN），那么：
                前进词法单元（）  -- 跳过 函数（fn）
                令 方法名词法单元索引（mt） = 前进词法单元（）
                令 方法名索引（method_ni） = 字符串驻留（词法单元词素索引（方法名词法单元索引））
                前进词法单元（）  -- 跳过 （
                令 参数计数（pc）：自动推导，可变 = 0
                令 参数类型值数组（param_tis）：字符串，可变
                参数类型信息（param_tis） = 分配内存（128 * 8）
                令 初始化循环索引（pi2）：自动推导，可变 = 0
                循环（当 真 成立时）：  -- 将参数类型数组全部初始化为 单元类型（TY_UNIT）
                    如果 初始化循环索引 大于等于 8，那么：跳出循环
                    写 64 位（参数类型值数组, 初始化循环索引 * 8, 单元类型（TY_UNIT））
                    初始化循环索引 = 初始化循环索引 + 1
                如果 非 检查（T_RPAREN），那么：
                    循环（当 真 成立时）：
                        令 首词法单元索引（fst） = 当前词法单元（）
                        如果 词法单元类别（首词法单元索引） 等于 与号（T_AMPERSAND） 或 词法单元类别（首词法单元索引） 等于 自身关键字（T_SELF），那么：
                            如果 词法单元类别（首词法单元索引） 等于 与号（T_AMPERSAND），那么：
                                前进词法单元（）  -- 跳过 &
                                如果 检查（T_MUT），那么：前进词法单元（）  -- 跳过 可变（mut）
                            令 第二个名称词法单元索引（nt2） = 前进词法单元（）  -- 自身（self）
                            如果 参数计数 小于 8，那么：写 64 位（参数类型值数组, 参数计数 * 8, 0）  -- 自身（self）/&自身 的类型记为 0
                            参数计数 = 参数计数 + 1
                        否则：
                            前进词法单元（）  -- 跳过参数名
                            前进词法单元（）  -- 跳过 :
                            令 参数类型节点（ptype） = 解析类型（）
                            如果 参数计数 小于 8，那么：写 64 位（参数类型值数组, 参数计数 * 8, 解包类型（参数类型节点））
                            参数计数 = 参数计数 + 1
                        如果 非 检查（T_COMMA），那么：跳出循环
                        前进词法单元（）
                前进词法单元（）  -- 跳过 ）
                令 返回类型值（ret_ti）：自动推导，可变 = 单元类型（TY_UNIT）
                如果 检查（T_ARROW），那么：
                    前进词法单元（）
                    令 返回类型节点 = 解析类型（）
                    返回类型值 = 解包类型（返回类型节点）
                前进词法单元（）  -- 跳过 ；
                如果 方法计数 大于等于 16，那么：
                    扩展诊断数组（grow_diags）（g_diag_count + 1）
                    写 64 位（g_diags, 诊断计数（g_diag_count） * 32, EC_P_FIELD_SYNTAX）
                    字符串指针存储（store_str_ptr）（g_diags, 诊断计数（g_diag_count） * 32 + 8, "接口（interface） '" + 接口名 + "' exceeds 取最大值（max） 16 methods"）
                    写 64 位（g_diags, 诊断计数（g_diag_count） * 32 + 16, 词法单元行号（当前词法单元索引））
                    写 64 位（g_diags, 诊断计数（g_diag_count） * 32 + 24, 词法单元列号（当前词法单元索引））
                    诊断计数（g_diag_count） = 诊断计数 + 1
                否则：
                    令 方法基地址偏移（mbase） = 接口基地址偏移 + 接口方法表偏移（OFF_IF_METHODS） + 方法计数 * 接口方法大小（ESZ_IFMETHOD）
                    写 64 位（g_ifaces, 方法基地址偏移 + OFF_IFM_NAME, 方法名索引）
                    写 64 位（g_ifaces, 方法基地址偏移 + OFF_IFM_PARAM_COUNT, 参数计数）
                    写 64 位（g_ifaces, 方法基地址偏移 + OFF_IFM_RET_TI, 返回类型值）
                    令 参数复制索引（pj）：自动推导，可变 = 0
                    循环（当 真 成立时）：  -- 从临时数组复制参数类型到接口条目
                        如果 参数复制索引 大于等于 8 或 参数复制索引 大于等于 参数计数，那么：跳出循环
                        写 64 位（g_ifaces, 方法基地址偏移 + OFF_IFM_PARAM_TYPES + 参数复制索引 * 8, 读 64 位（参数类型值数组, 参数复制索引 * 8））
                        参数复制索引 = 参数复制索引 + 1
                    如果 参数计数 大于 8，那么：
                        扩展诊断数组（g_diag_count + 1）
                        写 64 位（g_diags, 诊断计数（g_diag_count） * 32, EC_P_PARAM_TYPE）
                        字符串指针存储（store_str_ptr）（g_diags, 诊断计数（g_diag_count） * 32 + 8, "方法（method） '" + 驻留字符串获取（方法名索引） + "' in 接口（interface） exceeds 取最大值（max） 8 params"）
                        写 64 位（g_diags, 诊断计数（g_diag_count） * 32 + 16, 词法单元行号（当前词法单元索引））
                        写 64 位（g_diags, 诊断计数（g_diag_count） * 32 + 24, 词法单元列号（当前词法单元索引））
                        诊断计数（g_diag_count） = 诊断计数 + 1
                方法计数 = 方法计数 + 1
            否则：
                前进词法单元（）  -- 跳过非 函数（fn） 条目（容错）
        写 64 位（g_ifaces, 接口基地址偏移 + OFF_IF_METHOD_COUNT, 方法计数）
        接口计数（g_iface_count） = 接口计数 + 1
前进词法单元（）  -- 跳过 」
        返回

-- 实现（impl） 块：实现 类型（Type） 「 函数（fn） 方法（method）... 」  或  实现 特质（Trait） 遍历（for） 类型 「 函数 方法... 」
    -- 方法体委托 解析函数体，方法以 "类型（Type）.方法（method）" 格式拼接注册到方法查找表
    -- 若为 实现（impl） 特质（Trait） 遍历（for） 类型（Type） 形式，则额外记录 实现-遍历 关系到 接口实现数组（g_impl_for）
    如果 检查（T_IMPL），那么：
        令 当前词法单元索引 = 前进词法单元（）
        令 首个名称词法单元索引（first_nt） = 前进词法单元（）
        令 首个名称（first_name） = 词法单元词素索引（首个名称词法单元索引）
        令 首个名称索引（first_ni） = 字符串驻留（首个名称）
        令 接口名索引（trait_ni）：自动推导，可变 = -1
        令 类型名索引（type_ni）：自动推导，可变 = 首个名称索引
        令 类型名（type_name）：自动推导，可变 = 首个名称
        如果 检查（T_FOR），那么：  -- 实现（impl） 特质（Trait） 遍历（for） 类型（Type） 形式
            前进词法单元（）
            接口名索引 = 首个名称索引
            令 类型词法单元索引（type_nt） = 前进词法单元（）
            类型名 = 词法单元词素索引（类型词法单元索引）
            类型名索引 = 字符串驻留（类型名）
前进词法单元（）  -- 跳过 「
        循环（当 真 成立时）：
            如果 检查（T_RBRACE），那么：跳出循环
            如果 检查（T_FN），那么：
                令 函数词法单元索引（ft） = 前进词法单元（）
                令 方法名词法单元索引（method_nt） = 前进词法单元（）
                令 方法名（method_name） = 词法单元词素索引（方法名词法单元索引）
                令 方法名索引（method_ni） = 字符串驻留（方法名）
                令 拼接方法名（mangled） = 类型名 + "." + 方法名
                令 拼接方法名索引（mangled_ni） = 字符串驻留（拼接方法名）
                解析函数体（拼接方法名, 拼接方法名索引, 词法单元行号（函数词法单元索引）, 词法单元列号（函数词法单元索引）, 0）
                扩展方法数组（grow_methods）（g_method_count + 1）
                写 64 位（g_methods, 方法计数（g_method_count） * 24, 类型名索引）
                写 64 位（g_methods, 方法计数（g_method_count） * 24 + 8, 方法名索引）
                写 64 位（g_methods, 方法计数（g_method_count） * 24 + 16, 拼接方法名索引）
                方法计数（g_method_count） = 方法计数 + 1
            否则：
                前进词法单元（）  -- 跳过非 函数（fn） 条目（容错）
前进词法单元（）  -- 跳过 」
        如果 接口名索引 大于等于 0，那么：  -- 仅在 实现（impl） 特质（Trait） 遍历（for） 类型（Type） 时记录关系
            扩展接口实现数组（grow_impl_for）（g_impl_for_count + 1）
            写 64 位（g_impl_for, 接口实现计数（g_impl_for_count） * 16, 接口名索引）
            写 64 位（g_impl_for, 接口实现计数（g_impl_for_count） * 16 + 8, 类型名索引）
            接口实现计数（g_impl_for_count） = 接口实现计数 + 1
        返回

    -- 类型（type） 别名声明：类型（type） 名称（Name） = 既有类型（ExistingType）；
    -- 将别名和对应的类型 AST 节点写入 类型别名数组（g_type_aliases）
    如果 检查（T_TYPE），那么：
        前进词法单元（）
        令 名称词法单元索引 = 前进词法单元（）
        令 名称索引（name_idx） = 字符串驻留（词法单元词素索引（名称词法单元索引））
        前进词法单元（）  -- 跳过 =
        令 类型节点（type_node） = 解析类型（）
        前进词法单元（）  -- 跳过 ；
        扩展类型别名数组（grow_type_aliases）（g_type_alias_count + 1）
        写 64 位（g_type_aliases, 类型别名计数（g_type_alias_count） * 16, 名称索引）
        写 64 位（g_type_aliases, 类型别名计数（g_type_alias_count） * 16 + 8, 类型节点）
        类型别名计数（g_type_alias_count） = 类型别名计数 + 1
        返回

-- mod 模块声明：mod 名称（name）；  或  mod 变量甲（a）::变量乙（b）::变量丙（c）；  或  mod 名称 「 ... 」
    -- 路径按 :: 连接后存入模块路径名表；若带块体则按嵌套括号深度跳过块内容
    如果 检查（T_MOD），那么：
        令 当前词法单元索引 = 前进词法单元（）
        令 名称词法单元索引 = 前进词法单元（）
        令 路径名（path_name） = 词法单元词素索引（名称词法单元索引）
        循环（当 真 成立时）：  -- 收集 :: 分隔的多段路径
            如果 检查（T_PATHSEP），那么：
                前进词法单元（）
                令 第二个名称词法单元索引（nt2） = 前进词法单元（）
                路径名 = 路径名 + "::" + 词法单元词素索引（第二个名称词法单元索引）
            否则：跳出循环
        令 模块名索引（mod_ni） = 字符串驻留（路径名）
        扩展模块路径数组（grow_mod_paths）（g_mod_path_count + 1）
        写 64 位（g_mod_path_names, 模块路径计数（g_mod_path_count） * 8, 模块名索引）
        模块路径计数（g_mod_path_count） = 模块路径计数 + 1
如果 检查（T_LBRACE），那么：  -- mod 名称（name） 「 ... 」 带块体形式
            压入作用域（push_scope）（）
前进词法单元（）  -- 跳过 「
            令 嵌套深度（depth）：自动推导，可变 = 1  -- 已进入一层大括号
            循环（当 真 成立时）：
                如果 嵌套深度 小于等于 0，那么：跳出循环
                令 词法单元索引（tk） = 前进词法单元（）
                如果 词法单元类别（词法单元索引） 等于 右花括号（T_RBRACE），那么：嵌套深度 = 嵌套深度 - 1
                否则如果 词法单元类别（词法单元索引） 等于 左花括号（T_LBRACE），那么：嵌套深度 = 嵌套深度 + 1
                否则如果 词法单元类别（词法单元索引） 等于 文件结束（T_EOF），那么：跳出循环
        否则：
            如果 检查（T_SEMI），那么：前进词法单元（）
        返回

    -- 全局变量声明：若当前为标识符且 判断新变量声明（is_new_var_decl）成立，
    -- 则调用 解析新变量声明（parse_new_var_decl）并将结果及批量声明产生的额外声明写入 全局声明数组（g_global_lets）
    如果 检查（T_IDENT） 且 判断新变量声明（is_new_var_decl）（），那么：
        令 声明节点（node） = 解析新变量声明（parse_new_var_decl）（）
        扩展全局声明数组（grow_global_lets）（g_global_let_count + 1）
        写 64 位（g_global_lets, 全局声明计数（g_global_let_count） * 8, 声明节点）
        全局声明计数（g_global_let_count） = 全局声明计数 + 1
        令 排出计数（_drained）：自动推导，可变 = 0
        循环（当 真 成立时）：  -- 将批量声明（如 变量甲（a）, 变量乙（b） : 整数（int） = 1, 2）产生的额外声明全部排出到全局
            如果 额外声明计数（g_extra_let_count） 小于等于 0，那么：跳出循环
            额外声明计数（g_extra_let_count） = 额外声明计数 - 1
            扩展全局声明数组（g_global_let_count + 1）
            写 64 位（g_global_lets, 全局声明计数（g_global_let_count） * 8, 读 64 位（g_extra_lets, 额外声明计数（g_extra_let_count） * 8））
            全局声明计数（g_global_let_count） = 全局声明计数 + 1
            排出计数 = 排出计数 + 1
        返回

    -- 未知顶层词法单元：消费之以防止死循环
    前进词法单元（）
`
### 测试要点
1. "@热补丁（hotpatch）（ver=3） 函数（fn） f（） 「」" 热补丁版本号正确提取后函数正常解析
2. "@热补丁（hotpatch） 函数（fn） f（） 「」" 无 版本号（ver）参数时版本号默认为 1
3. "外部（extern） 函数（fn） puts（状态（s）: 字符串（string）） -> 整数（int）；" 产生 外部声明表达式（EXPR_EXTERN） 节点（无体，有分号）
4. "外部（extern） @外部函数接口（ffi）（"C"） 函数（fn） printf（string） -> 整数（int）；" 外部函数接口（FFI） 语言原生内建索引（ffi_lang_ni） 正确记录
5. "函数（fn） add（变量甲（a）: 整数（int）, 变量乙（b）: 整数） -> 整数（整数） 「 第一子节点（变量甲） + 第二子节点（变量乙） 」" 正常解析
6. "结构（struct） Point[泛型参数 泛型参数（T）（泛型参数 T）] 「 变量甲（x）: 泛型参数 泛型参数, y: 泛型参数 泛型参数 」" 泛型 结构 正确填充字段
7. "枚举（enum） 可选类型（Option）[泛型参数 泛型参数（T）（泛型参数 T）] 「 无值（None）, 某些值（Some）（泛型参数 T） 」" 变体 无值 无关联类型（tc=0）、某些值 有关联类型（tc=1）
8. "接口（interface） 显示特质（Show） 「 函数（fn） show（self） -> 字符串（string）； 」" 方法签名正确写入接口条目
9. 接口方法超过 16 时诊断报错
10. 接口方法参数超过 8 时诊断报错
11. "实现（impl） 显示特质（Show） 遍历（for） Point 「 函数（fn） show（self） -> 字符串（string） 「 ... 」 」" 方法注册为 "Point.show"，实现-遍历 记录写入 接口实现数组（g_impl_for）
12. "类型（type） MyInt = 整数（int）；" 类型别名写入 类型别名数组（g_type_aliases）
13. "mod 变量甲（a）::变量乙（b）::变量丙（c）；" 路径正确按 "::" 连接并写入 模块路径名数组（g_mod_path_names）
14. "mod foo 「 ... 」" 块体内容按嵌套括号深度正确跳过
15. 顶层全局变量 "变量甲（x） : 整数（int） = 1；" 写入 全局声明数组（g_global_lets），批量 "变量甲（a）, 变量乙（b） : 整数 = 1, 2；" 额外声明全部排出
16. 未知词法单元消费后不造成死循环
17. 非声明类的 引入（import）/文件标识（fileid） 语句不会进入 解析声明（parse_declaration）（由 parse_all 外层过滤）

## 函数 解析全部（parse_all）
### 作用
语法解析的顶层入口。重置所有全局解析状态（AST 计数、词法单元位置、各声明表计数等），然后循环：先跳过 引入（import）/文件标识（fileid） 声明（留给导入模块处理），再调用 解析声明（parse_declaration） 解析一个顶层声明。若遇 文件结束标记（EOF） 则结束；若单次声明导致 AST 节点增长超过 10000 则紧急中止（防止无限循环）。循环中每 6 次迭代重置一次计数器 声明索引（ci）。
### 逻辑
`
函数 解析全部（parse_all）
    -- 重置所有全局解析状态（AST 计数、词法单元位置、各声明表计数等）
    AST 节点计数（g_ast_count） = 0
    当前词法单元位置（g_token_pos） = 0
    全局声明计数（g_global_let_count） = 0； 全局声明容量（g_global_lets_cap） = 0
    函数计数（g_func_count） = 0
    结构体计数（g_struct_count） = 0
    枚举计数（g_enum_count） = 0
    类型别名计数（g_type_alias_count） = 0； 类型别名容量（g_type_alias_cap） = 0
    方法计数（g_method_count） = 0； 方法容量（g_method_cap） = 0
    循环嵌套深度（g_loop_depth） = 0； 循环栈容量（g_loop_stack_cap） = 0
    额外声明计数（g_extra_let_count） = 0
    代码块语句计数（g_block_stmt_count） = 0
    错误计数（g_error_count） = 0
    模块路径计数（g_mod_path_count） = 0； 模块路径容量（g_mod_path_cap） = 0
    接口计数（g_iface_count） = 0； 接口容量（g_iface_cap） = 0
    接口实现计数（g_impl_for_count） = 0； 接口实现容量（g_impl_for_cap） = 0
    泛型约束计数（g_generic_constr_count） = 0； 泛型约束容量（g_generic_constr_cap） = 0
    泛型参数计数（g_gen_param_count） = 0； 泛型参数容量（g_gen_param_cap） = 0

    令 循环计数器（ci）：自动推导，可变 = 0
    循环（当 真 成立时）：
        -- 内层循环：跳过 引入（import） / 文件标识（fileid） 声明（留给导入解析模块处理）
        循环（当 真 成立时）：
            令 当前类别（tk） = 词法单元类别（tok_k）（当前词法单元（cur_tok）（））
            如果 当前类别 等于 文件结束（T_EOF），那么：返回  -- 文件结束，直接返回
            如果 当前类别 不等于 引入关键字（T_IMPORT） 且 当前类别 不等于 文件标识词法单元（T_FILEID），那么：跳出循环
            前进词法单元（advance_tok）（）
        令 当前词法单元索引（t_cur） = 当前词法单元（）
        令 当前类别（t_kind） = 词法单元类别（当前词法单元索引）
        如果 当前类别 等于 文件结束（T_EOF），那么：跳出循环  -- 跳过 引入（import） 后抵达文件末尾
        如果 循环计数器 大于 5，那么：循环计数器 = 0  -- 每 6 次迭代归零，防止溢出
        令 之前的AST计数（prev_ast） = AST 节点计数（g_ast_count）
        解析声明（parse_declaration）（）
        如果 词法单元类别（当前词法单元（）） 等于 文件结束（T_EOF），那么：跳出循环  -- 解析后再次检查 文件结束标记（EOF）
        令 AST增长量（ast_grown） = AST 节点计数（g_ast_count） - 之前的AST计数
        如果 AST增长量 大于 10000，那么：跳出循环  -- 紧急中止：单次声明 AST 增长异常，防止无限循环
        循环计数器 = 循环计数器 + 1
`
### 测试要点
1. 空文件（EOF）正常返回，不产生任何声明
2. 含 引入（import） 声明的文件：引入 被跳过，后续 函数（fn）/结构（struct） 等正常解析
3. 单次声明 AST 增长超 10000 时紧急中止（如声明嵌套过多导致无穷解析）
4. 所有全局计数在入口处正确归零
5. 多次调用 解析全部（parse_all） 之间状态不残留
6. 文件结束（T_EOF） 在主循环开头和 解析声明（parse_declaration） 之后双重检查
7. 声明索引（ci） 计数器每超过 5 就归零（防止溢出，无实际逻辑用途）
