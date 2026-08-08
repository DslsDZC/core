# 类型检查器（checker）.cr 伪代码（第 2 部分：符号表、作用域、借用检查）
> 源文件：src/compiler/类型检查器（checker）.cr 第 180～357 行
> 功能概要：作用域管理（压入/弹出/定义/查找符号）、借用检查（借用规则检查/使用检查/借用作用域）以及 非安全（unsafe） 作用域与借用持有者记录。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 压入作用域 | push_scope | 压入作用域 |
| 弹出作用域 | pop_scope | 弹出作用域 |
| 定义符号 | def_sym | 定义符号 |
| 查找符号 | find_sym | 查找符号 |
| 查找gsym | find_gsym | 查找gsym |
| 查找.so函数 | find_so_fn | 查找.so函数 |
| 查找借用条目 | find_borrow_entry | 查找借用条目 |
| 检查借用 | check_borrow | 检查借用 |
| 检查使用 | check_use | 检查使用 |
| 压入借用作用域 | push_borrow_scope | 压入借用作用域 |
| 弹出借用作用域 | pop_borrow_scope | 弹出借用作用域 |
| 压入不安全作用域 | push_unsafe_scope | 压入不安全作用域 |
| 弹出不安全作用域 | pop_unsafe_scope | 弹出不安全作用域 |
| 记录借用持有者 | record_borrow_holder | 记录借用持有者 |
| 借用变量名称 | borrow_var_name | 借用变量名称 |
| 符号数组 | g_syms | 定义符号 |
| 符号计数 | g_sym_count | 压入作用域 |
| 作用域边界数组 | g_scope_bounds | 压入作用域 |
| 作用域深度 | g_scope_depth | 压入作用域 |
| 作用域边界容量 | g_scope_bounds_cap | 压入作用域 |
| 借用变量数组 | g_borrow_vars | 检查借用 |
| 借用引用数组 | g_borrow_refs | 检查借用 |
| 借用可变标记数组 | g_borrow_muts | 检查借用 |
| 借用条目计数 | g_borrow_count | 检查借用 |
| 借用数组容量 | g_borrow_cap | 检查借用 |
| 借用作用域标记 | g_borrow_scope_markers | 压入借用作用域 |
| 借用作用域标记容量 | g_borrow_scope_markers_cap | 压入借用作用域 |
| 借用作用域深度 | g_borrow_scope_depth | 压入借用作用域 |
| 持有者-借用者 | g_holder_borrowers | 记录借用持有者 |
| 持有者-被借数 | g_holder_borrowed | 记录借用持有者 |
| 持有者可变标记 | g_holder_is_mut | 记录借用持有者 |
| 持有者计数 | g_holder_count | 弹出借用作用域 |
| 持有者容量 | g_holder_cap | 记录借用持有者 |
| unsafe 块深度 | g_unsafe_depth | 压入不安全作用域 |
| 扩展符号数组 | grow_syms | 定义符号 |
| 扩展作用域边界数组 | grow_scope_bounds | 压入作用域 |
| 扩展借用标记数组 | grow_borrow_markers | 压入借用作用域 |
| 扩展借用变量数组 | grow_borrow_vars | 检查借用 |
| 扩展持有者数组 | grow_holder | 记录借用持有者 |
| 符号名称 | sym_name | 查找符号 |
| 符号类别 | sym_kind | 查找gsym |
| 符号类型 | sym_type | 查找gsym |
| 符号节点 | sym_node | 查找符号 |
| 符号设置名称 | sym_set_name | 定义符号 |
| 符号设置类别 | sym_set_kind | 定义符号 |
| 符号设置类型 | sym_set_type | 定义符号 |
| 符号设置节点 | sym_set_node | 定义符号 |
| 读 64 位 | r64 | 弹出作用域 |
| 写 64 位 | w64 | 压入作用域 |
| 标识符表达式 | EXPR_IDENT | 借用变量名称 |
| AST 访问器：类别 | ast_kind | 借用变量名称 |
| AST 访问器：整数值 | ast_int_val | 借用变量名称 |
| 符号条目 | SymEntry | （结构体常量） |
| 符号类别：函数（SYM_FN） | SYM_FN | （全局常量） |
| 符号类别：类型（SYM_TYPE） | SYM_TYPE | （全局常量） |
| 符号类别：局部变量（SYM_LOCAL） | SYM_LOCAL | （全局常量） |
| 符号类别：参数（SYM_PARAM） | SYM_PARAM | （全局常量） |
| 符号类别：全局变量（SYM_GLOBAL） | SYM_GLOBAL | （全局常量） |
| 符号类别：模块（SYM_MODULE） | SYM_MODULE | （全局常量） |
| 符号类别：动态库函数（SYM_SO_FN） | SYM_SO_FN | （全局常量） |

## 全局状态

| 全局变量 | 含义 | 初值 |
|---------|------|------|
| 符号数组（g_syms） | 扁平字节缓冲，每条目 32 字节（名称索引 + 类别 + 类型索引 + 节点索引） | 空 |
| 符号计数（g_sym_count） | 当前符号表中的符号总数 | 0 |
| 作用域边界数组（g_scope_bounds） | 各嵌套层级的起始符号计数 | 空 |
| 作用域深度（g_scope_depth） | 当前嵌套深度 | 0 |
| 借用变量数组（g_borrow_vars） | 被借用的变量名称索引列表 | 空 |
| 借用引用数组（g_borrow_refs） | 每个变量的不可变借用计数 | 空 |
| 借用可变标记数组（g_borrow_muts） | 每个变量是否存在可变借用标记 | 空 |
| 借用条目计数（g_borrow_count） | 借用的变量总数 | 0 |
| 借用作用域标记（g_borrow_scope_markers） | 各借用作用域起始时的持有者计数 | 空 |
| 借用作用域深度（g_borrow_scope_depth） | 借用作用域嵌套深度 | 0 |
| 持有者-借用者（g_holder_borrowers） | 借用者的变量名称索引 | 空 |
| 持有者-被借数（g_holder_borrowed） | 被借用者的变量名称索引 | 空 |
| 持有者可变标记（g_holder_is_mut） | 借用是否可变 | 空 |
| 持有者计数（g_holder_count） | 当前活跃的借用持有者总数 | 0 |
| unsafe 块深度（g_unsafe_depth） | 当前 unsafe 块嵌套深度 | 0 |

## 符号条目结构（SymEntry）
`
结构 符号条目（SymEntry）：
    字段：名称索引（name_idx），类型：整数    （字符串驻留索引）
    字段：类别（kind），类型：整数           （SYM_* 常量）
    字段：类型索引（type_idx），类型：整数    （类型表索引）
    字段：节点索引（node_idx），类型：整数    （AST 节点索引）
`

## 函数 压入作用域（push_scope）
函数 压入作用域（push_scope）（）

### 作用
在符号表中标记一个新作用域的起始位置。将当前符号表的符号条目数（g_sym_count）记录到作用域边界数组（g_scope_bounds）的当前深度偏移处，然后递增作用域嵌套深度。后续符号查找只会从当前作用域往前扫描到栈底。

### 逻辑
`
调用 扩展作用域边界数组（grow_scope_bounds）（作用域深度（g_scope_depth） + 1）
写 64 位（w64）（作用域边界数组（g_scope_bounds），作用域深度（g_scope_depth） * 8，符号计数（g_sym_count））
令 作用域深度（g_scope_depth） = 作用域深度（g_scope_depth） + 1
`

### 测试要点
1. 首次调用：作用域深度（g_scope_depth）从 0 升为 1，作用域边界数组（g_scope_bounds）位置 0 处记录当前符号计数（g_sym_count）
2. 嵌套多次：作用域深度（g_scope_depth）线性递增，每次记录新的符号边界
3. 容量不足时作用域边界数组自动扩展

## 函数 弹出作用域（pop_scope）
函数 弹出作用域（pop_scope）（）

### 作用
将符号表的当前作用域打开处之后的所有符号删除。通过恢复符号计数（g_sym_count）到父作用域记录的边界值实现，让新定义的符号"消失"。

### 逻辑
`
如果 作用域深度（g_scope_depth）大于 0，那么：
    令 作用域深度（g_scope_depth） = 作用域深度（g_scope_depth） - 1
    令 符号计数（g_sym_count） = 读 64 位（r64）（作用域边界数组（g_scope_bounds），作用域深度（g_scope_depth） * 8）
`

### 测试要点
1. 压入后定义一个符号再弹出：符号计数（g_sym_count）恢复到压入前的值
2. 作用域深度为 0 时调用弹出作用域：不执行任何操作
3. 嵌套弹出：由内到外逐层恢复符号计数（g_sym_count）

## 函数 定义符号（def_sym）
函数 定义符号（def_sym）（名称索引 name_idx：整数，类别 种类（kind）：整数，类型索引 type_idx：整数，节点索引 node_idx：整数）

### 作用
在符号表中追加一条新的符号条目（SymEntry），包含名称索引/类别/类型索引/节点索引四个字段。

### 逻辑
`
调用 扩展符号数组（grow_syms）（符号计数（g_sym_count） + 1）
调用 符号设置名称（sym_set_name）（符号计数（g_sym_count），名称索引（name_idx））
调用 符号设置类别（sym_set_kind）（符号计数（g_sym_count），类别（kind））
调用 符号设置类型（sym_set_type）（符号计数（g_sym_count），类型索引（type_idx））
调用 符号设置节点（sym_set_node）（符号计数（g_sym_count），节点索引（node_idx））
令 符号计数（g_sym_count） = 符号计数（g_sym_count） + 1
`

### 测试要点
1. 定义符号后符号计数（g_sym_count）+1
2. 新条目各字段（名称索引/类别/类型/节点）与传入值一致
3. 重复定义同名符号：不会检查重复（由调用者在必要时检查）

## 函数 查找符号（find_sym）
函数 查找符号（find_sym）（名称索引 name_idx：整数）-> 整数

### 作用
在符号表中从后往前（最近定义优先）搜索指定名称索引的符号。找到时返回符号表索引，找不到返回 -1。支持作用域遮蔽：内层同名符号覆盖外层。

### 逻辑
`
令 索引（i） = 符号计数（g_sym_count） - 1（可变）
循环：
    如果 索引（i）小于 0，那么：返回 -1
    如果 调用 符号名称（sym_name）（i）等于 名称索引（name_idx），那么：返回 索引（索引）
    索引（i） = 索引（索引） - 1
返回 -1
`

### 测试要点
1. 查找已定义符号：返回正确索引
2. 在作用域嵌套时内层符号遮蔽外层
3. 查找不存在的符号：返回 -1
4. 符号表为空时：返回 -1

## 函数 查找泛型符号（gsym）（find_gsym）
函数 查找泛型符号（gsym）（find_gsym）（名称索引 name_idx：整数）-> 整数

### 作用
从后往前搜索符号表中指定名称索引的"全局级别"符号（类别为 符号：函数（SYM_FN） 到 符号：动态库函数（SYM_SO_FN） 之间的任何类别）。用于函数调用/类型引用等全局名称解析。

### 逻辑
`
令 索引（i） = 符号计数（g_sym_count） - 1（可变）
循环：
    如果 索引（i）小于 0，那么：返回 -1
    如果 调用 符号名称（sym_name）（i）等于 名称索引（name_idx）且 调用 符号类别（sym_kind）（索引（索引））大于等于 符号类别：函数（SYM_FN）且 调用 符号类别（sym_kind）（索引（索引））小于等于 符号类别：动态库函数（SYM_SO_FN），那么：
        返回 索引（i）
    索引（i） = 索引（索引） - 1
返回 -1
`

### 测试要点
1. 查找已注册的函数符号：返回正确索引
2. 跳过局部变量类别（符号类别：局部变量（SYM_LOCAL）/符号类别：参数（SYM_PARAM））的同名符号
3. 查找不存在的全局符号：返回 -1

## 函数 查找.so函数（find_so_fn）
函数 查找.so函数（find_so_fn）（名称索引 name_idx：整数）-> 整数

### 作用
从前往后在符号表中搜索指定名称的 符号类别：动态库函数（SYM_SO_FN）（.so 动态库函数）条目。与 查找泛型符号（gsym）（find_gsym）不同，此函数向前扫描，因为 符号类别：动态库函数（符号：动态库函数）条目在符号表中的位置通常靠前。

### 逻辑
`
（向前扫描——符号类别：动态库函数（SYM_SO_FN）条目在 符号类别：函数（SYM_FN）之前）
令 索引（i） = 0（可变）
循环：
    如果 索引（i）大于等于 符号计数（g_sym_count），那么：返回 -1
    如果 调用 符号名称（sym_name）（i）等于 名称索引（name_idx）且 调用 符号类别（sym_kind）（索引（索引））等于 符号类别：动态库函数（SYM_SO_FN），那么：
        返回 索引（i）
    索引（i） = 索引（索引） + 1
返回 -1
`

### 测试要点
1. 查找已注册的 符号类别：动态库函数（SYM_SO_FN）条目：返回正确索引（因为向前扫描）
2. 非 符号类别：动态库函数（SYM_SO_FN）类别的同名条目被跳过
3. 无匹配时返回 -1

## 函数 查找借用条目（find_borrow_entry）
函数 查找借用条目（find_borrow_entry）（变量名称索引 var_ni：整数）-> 整数

### 作用
在借用变量数组（g_borrow_vars）中从前往后搜索指定变量名称索引。找到时返回其索引，找不到返回 -1。

### 逻辑
`
令 索引（i） = 0（可变）
循环：
    如果 索引（i）大于等于 借用条目计数（g_borrow_count），那么：返回 -1
    如果 读 64 位（r64）（借用变量数组（g_borrow_vars），索引（i） * 8）等于 变量名称索引（var_ni），那么：
        返回 索引（i）
    索引（i） = 索引（索引） + 1
返回 -1
`

### 测试要点
1. 已借用的变量可找到对应条目
2. 未借用的变量返回 -1
3. 借用条目计数（g_borrow_count）为 0 时返回 -1

## 函数 检查借用（check_borrow）
函数 检查借用（check_borrow）（变量名称索引 var_ni：整数，是否可变 is_mut：整数）-> 布尔值

### 作用
执行借用规则的验证：对新借用请求（变量名 + 是否可变），检查是否与现有借用冲突。规则：1） 可变借用（mut）要求当前无任何借用；2） 不可变借用（&）要求当前无可变借用。如果通过检查则更新借用状态。

### 逻辑
`
令 借用索引（bi） = 调用 查找借用条目（find_borrow_entry）（var_ni）
如果 借用索引（bi）大于等于 0，那么：
    如果 是否可变（is_mut）不等于 0，那么：
        （&可变（mut） 变量甲（x）：如果存在任何借用则失败）
        如果 读 64 位（r64）（借用引用数组（g_borrow_refs），借用索引（bi） * 8）大于 0 或 读 64 位（r64）（借用可变标记数组（g_borrow_muts），借用索引（二元信息） * 8）不等于 0，那么：
            返回 假
        写 64 位（w64）（借用可变标记数组（g_borrow_muts），借用索引（bi） * 8，1）
        返回 真
    否则：
        （&变量甲（x）：如果存在可变借用则失败）
        如果 读 64 位（r64）（借用可变标记数组（g_borrow_muts），借用索引（bi） * 8）不等于 0，那么：
            返回 假
        写 64 位（w64）（借用引用数组（g_borrow_refs），借用索引（bi） * 8，读 64 位（r64）（借用引用数组（g_borrow_refs），借用索引（二元信息） * 8） + 1）
        返回 真

（该变量的首次借用：创建新条目）
调用 扩展借用变量数组（grow_borrow_vars）（借用条目计数（g_borrow_count） + 1）
写 64 位（w64）（借用变量数组（g_borrow_vars），借用条目计数（g_borrow_count） * 8，变量名称索引（var_ni））
写 64 位（w64）（借用引用数组（g_borrow_refs），借用条目计数（g_borrow_count） * 8，0）
写 64 位（w64）（借用可变标记数组（g_borrow_muts），借用条目计数（g_borrow_count） * 8，0）
如果 是否可变（is_mut）不等于 0，那么：
    写 64 位（w64）（借用可变标记数组（g_borrow_muts），借用条目计数（g_borrow_count） * 8，1）
否则：
    写 64 位（w64）（借用引用数组（g_borrow_refs），借用条目计数（g_borrow_count） * 8，1）
令 借用条目计数（g_borrow_count） = 借用条目计数（g_borrow_count） + 1
返回 真
`

### 测试要点
1. 首次不可变借用（x）：成功，借用引用数组对应条目 = 1
2. 两次不可变借用（&变量甲（x）, &变量甲）：都成功，借用引用数组对应条目 = 2
3. 不可变借用后可变借用（&变量甲（x） 然后 &可变（mut） 变量甲）：返回 假（借用引用数组对应条目仍为 1）
4. 可变借用后再做任何借用：返回 假
5. 不同变量的借用互不干扰（各自独立条目）

## 函数 检查使用（check_use）
函数 检查使用（check_use）（变量名称索引 var_ni：整数）-> 布尔值

### 作用
检查被借用的变量是否允许在当前作用域被使用。如果变量有未解除的借用（不可变借用计数大于 0 或可变借用标记为 1），则返回 假（禁止使用）；否则返回 真。

### 逻辑
`
令 借用索引（bi） = 调用 查找借用条目（find_borrow_entry）（var_ni）
如果 借用索引（bi）大于等于 0，那么：
    如果 读 64 位（r64）（借用引用数组（g_borrow_refs），借用索引（bi） * 8）大于 0 或 读 64 位（r64）（借用可变标记数组（g_borrow_muts），借用索引（二元信息） * 8）不等于 0，那么：
        返回 假
返回 真
`

### 测试要点
1. 未被借用的变量：返回 真
2. 有活跃不可变借用的变量：返回 假
3. 有可变借用的变量：返回 假
4. 借用已解除（引用数和可变标记均为 0）：返回 真

## 函数 压入借用作用域（push_borrow_scope）
函数 压入借用作用域（push_borrow_scope）（）

### 作用
在借用检查器中标记一个新借用作用域的起始位置。将当前持有者总数（g_holder_count）记录到借用作用域标记数组的当前深度处。

### 逻辑
`
调用 扩展借用标记数组（grow_borrow_markers）（借用作用域深度（g_borrow_scope_depth） + 1）
写 64 位（w64）（借用作用域标记（g_borrow_scope_markers），借用作用域深度（g_borrow_scope_depth） * 8，持有者计数（g_holder_count））
令 借用作用域深度（g_borrow_scope_depth） = 借用作用域深度（g_borrow_scope_depth） + 1
`

### 测试要点
1. 首次调用：借用作用域深度（g_borrow_scope_depth）从 0 变为 1
2. 记录了当前持有者计数（g_holder_count）
3. 嵌套多次：借用作用域深度（g_borrow_scope_depth）递增

## 函数 弹出借用作用域（pop_borrow_scope）
函数 弹出借用作用域（pop_borrow_scope）（）

### 作用
弹出一个借用作用域。从持有者表中删除该作用域内新增的所有借用持有者记录，并释放对应的借用条目（递减引用计数或清除可变标记）。如果某借用变量的引用计数和可变标记均归零，则从借用条目中彻底删除该条目。

### 逻辑
`
如果 借用作用域深度（g_borrow_scope_depth）大于 0，那么：
    令 借用作用域深度（g_borrow_scope_depth） = 借用作用域深度（g_borrow_scope_depth） - 1
    令 标记值（marker） = 读 64 位（r64）（借用作用域标记（g_borrow_scope_markers），借用作用域深度（g_borrow_scope_depth） * 8）

    （释放从标记值到末尾为止持有的所有借用）
    循环：
        如果 持有者计数（g_holder_count）小于等于 标记值（marker），那么：跳出循环
        令 持有者计数（g_holder_count） = 持有者计数（g_holder_count） - 1

        令 被借用者名称索引（borrowed_ni） = 读 64 位（r64）（持有者-被借数（g_holder_borrowed），持有者计数（g_holder_count） * 8）
        令 是否可变（is_mut） = 读 64 位（r64）（持有者可变标记（g_holder_is_mut），持有者计数（g_holder_count） * 8）

        令 借用索引（bi） = 调用 查找借用条目（find_borrow_entry）（borrowed_ni）

        如果 借用索引（bi）大于等于 0，那么：
            如果 是否可变（is_mut）不等于 0，那么：
                写 64 位（w64）（借用可变标记数组（g_borrow_muts），借用索引（bi） * 8，0）
            否则：
                如果 读 64 位（r64）（借用引用数组（g_borrow_refs），借用索引（bi） * 8）大于 0，那么：
                    写 64 位（w64）（借用引用数组（g_borrow_refs），借用索引（bi） * 8，读 64 位（r64）（借用引用数组（g_borrow_refs），借用索引（二元信息） * 8） - 1）

            （如果没有剩余的借用，则清理条目）
            如果 读 64 位（r64）（借用引用数组（g_borrow_refs），借用索引（bi） * 8）等于 0 且 读 64 位（r64）（借用可变标记数组（g_borrow_muts），借用索引（二元信息） * 8）等于 0，那么：
                令 移位索引（si） = 借用索引（bi）（可变）
                循环：
                    如果 移位索引（si） + 1 大于等于 借用条目计数（g_borrow_count），那么：跳出循环
                    写 64 位（w64）（借用变量数组（g_borrow_vars），移位索引（si） * 8，读 64 位（r64）（借用变量数组（g_borrow_vars），（移位索引（si） + 1） * 8））
                    写 64 位（w64）（借用引用数组（g_borrow_refs），移位索引（si） * 8，读 64 位（r64）（借用引用数组（g_borrow_refs），（移位索引（si） + 1） * 8））
                    写 64 位（w64）（借用可变标记数组（g_borrow_muts），移位索引（si） * 8，读 64 位（r64）（借用可变标记数组（g_borrow_muts），（移位索引（si） + 1） * 8））
                    移位索引（si） = 移位索引（si） + 1
                令 借用条目计数（g_borrow_count） = 借用条目计数（g_borrow_count） - 1
`

### 测试要点
1. 单次借用后弹出作用域：借用者记录被清除，借用条目引用计数归零，条目被移除
2. 嵌套借用作用域：内层作用域的借用者只影响内层范围内新增的持有者
3. 借用作用域深度为 0 时调用：不执行任何操作
4. 借用条目被移除后数组紧凑化（后续元素前移）

## 函数 压入不安全作用域（push_unsafe_scope）
函数 压入不安全作用域（push_unsafe_scope）（）

### 作用
不安全（unsafe）块标志的入栈操作。压入不安全作用域递增 非安全（非安全） 块深度（g_unsafe_depth），用于影响指针类型的地址空间属性。

### 逻辑
`
令 非安全（unsafe） 块深度（g_unsafe_depth） = 非安全 块深度（g_unsafe_depth） + 1
`

### 测试要点
1. 嵌套 不安全（unsafe）块的深度递增计数
2. 非安全（unsafe） 块深度（g_unsafe_depth）影响指针类型地址空间（在 解析类型节点（res_type_node）中使用）

## 函数 弹出不安全作用域（pop_unsafe_scope）
函数 弹出不安全作用域（pop_unsafe_scope）（）

### 作用
不安全（unsafe）块标志的出栈操作。弹出不安全作用域递减 非安全（非安全） 块深度（g_unsafe_depth）。

### 逻辑
`
如果 非安全（unsafe） 块深度（g_unsafe_depth）大于 0，那么：
    令 非安全（unsafe） 块深度（g_unsafe_depth） = 非安全 块深度（g_unsafe_depth） - 1
`

### 测试要点
1. 弹出不安全作用域在深度为 0 时不执行操作
2. 与压入不安全作用域配对使用，正确追踪 不安全（unsafe）块的嵌套层级

## 函数 记录借用持有者（record_borrow_holder）
函数 记录借用持有者（record_borrow_holder）（借用者名称索引 borrower_ni：整数，被借用者名称索引 borrowed_ni：整数，是否可变 is_mut：整数）

### 作用
在持有者表中记录一条借用关系：谁借用了谁以及是否可变。用于在借用作用域弹出时追踪应释放哪些借用。

### 逻辑
`
调用 扩展持有者数组（grow_holder）（持有者计数（g_holder_count） + 1）
写 64 位（w64）（持有者-借用者（g_holder_borrowers），持有者计数（g_holder_count） * 8，借用者名称索引（borrower_ni））
写 64 位（w64）（持有者-被借数（g_holder_borrowed），持有者计数（g_holder_count） * 8，被借用者名称索引（borrowed_ni））
写 64 位（w64）（持有者可变标记（g_holder_is_mut），持有者计数（g_holder_count） * 8，是否可变（is_mut））
令 持有者计数（g_holder_count） = 持有者计数（g_holder_count） + 1
`

### 测试要点
1. 记录后持有者计数（g_holder_count）+1
2. 三条数组写入的数据（借用者/被借用者/是否可变）均可对应读出
3. 容量不足时自动扩展

## 函数 借用变量名称（borrow_var_name）
函数 借用变量名称（borrow_var_name）（节点 节点（node）：整数）-> 整数

### 作用
从 AST 节点中提取被借用的变量名称索引。如果节点是标识符表达式（EXPR_IDENT），返回其 整数值字段（int_val）（名称字符串驻留索引）；否则返回 -1。

### 逻辑
`
如果 节点（node）小于 0，那么：返回 -1
如果 调用 AST 访问器：类别（ast_kind）（node）等于 标识符表达式（EXPR_IDENT），那么：
    返回 调用 AST 访问器：整数值（ast_int_val）（node）
返回 -1
`

### 测试要点
1. 节点（node）为 -1：返回 -1
2. 标识符节点（如 `变量甲（x）`）：返回对应的名称驻留索引
3. 非标识符节点（如 `&变量甲（x）` 整体）：返回 -1（因为整体是一元引用表达式而非标识符）
