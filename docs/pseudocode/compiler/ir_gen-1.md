# ir_gen.cr 伪代码（第 1 部分：基础设施与辅助函数）
> 源文件：src/compiler/ir_gen.cr（第 1–226 行）
> 功能概要：定义子图竞技场（SG arena）跟踪所需全局变量及辅助函数，以及 IR 变量创建、指令发射（发射（emit））、标签生成、局部/全局变量查找、作用域管理、类型判断（指针/字节缓冲）、调用返回类型查询、字符串常量跟踪等底层基础设施函数。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 子图分配总量 | g_sg_alloc_total | （全局状态） |
| 子图分配容量 | g_sg_alloc_cap | （全局状态） |
| 子图竞技场变量 | g_sg_arena_var | （全局状态） |
| 子图竞技场变量容量 | g_sg_arena_var_cap | （全局状态） |
| IR 源哈希 | g_ir_source_hash | （全局状态） |
| IR 源哈希就绪 | g_ir_source_hash_ready | （全局状态） |
| 扩展 SG 分配数组 | grow_sg_alloc | 扩展 SG 分配数组（grow_sg_alloc） |
| 扩展 SG 竞技场变量数组 | grow_sg_arena_var | 扩展 SG 竞技场变量数组（grow_sg_arena_var） |
| 压入 SG 分配槽 | sg_alloc_push | 压入 SG 分配槽（sg_alloc_push） |
| 弹出 SG 分配槽 | sg_alloc_pop | 弹出 SG 分配槽（sg_alloc_pop） |
| 跟踪分配大小 | track_alloc_size | 跟踪分配大小（track_alloc_size） |
| 新建 IR 变量 | new_ir_var | 新建 IR 变量（new_ir_var） |
| 发射指令 | emit | 发射指令（emit） |
| 新建标签 | new_label | 新建标签（new_label） |
| 绑定局部变量 | bind_local | 绑定局部变量（bind_local） |
| 查找局部变量 | find_local | 查找局部变量（find_local） |
| 查找全局变量 | find_global | 查找全局变量（find_global） |
| 查找全局常量节点 | find_global_const_node | 查找全局常量节点（find_global_const_node） |
| 压入 IR 作用域 | push_ir_scope | 压入 IR 作用域（push_ir_scope） |
| 弹出 IR 作用域 | pop_ir_scope | 弹出 IR 作用域（pop_ir_scope） |
| 判断指针变量 | is_ptr_var | 判断指针变量（is_ptr_var） |
| 判断字节缓冲变量 | is_byte_buf_var | 判断字节缓冲变量（is_byte_buf_var） |
| IR 调用返回类型 | ir_call_return_type | IR 调用返回类型（ir_call_return_type） |
| 获取 IR 变量名 | get_ir_var_name | 获取 IR 变量名（get_ir_var_name） |
| 跟踪字符串常量 | track_str | 跟踪字符串常量（track_str） |
| 数据流图：创建节点 | df_create_node | 发射指令（emit） |
| IR 变量访问器：ID | irv_id | 新建 IR 变量（new_ir_var） |
| IR 变量访问器：名称 | irv_name | 新建 IR 变量（new_ir_var） |
| IR 变量访问器：类型 | irv_type | 新建 IR 变量（new_ir_var） |
| IR 变量访问器：设置名称 | irv_set_name | 新建 IR 变量（new_ir_var） |
| IR 变量访问器：设置ID | irv_set_id | 新建 IR 变量（new_ir_var） |
| IR 变量访问器：设置类型 | irv_set_type | 新建 IR 变量（new_ir_var） |
| IR 指令访问器：操作码 | iri_op | 发射指令（emit） |
| IR 指令访问器：操作数1 | iri_s1 | 发射指令（emit） |
| IR 指令访问器：操作数2 | iri_s2 | 发射指令（emit） |
| IR 指令访问器：操作数3 | iri_s3 | 发射指令（emit） |
| IR 指令访问器：目标 | iri_dest | 发射指令（emit） |
| IR 指令访问器：类型类别 | iri_tk | 发射指令（emit） |
| IR 指令访问器：设置操作码 | iri_set_op | 发射指令（emit） |
| IR 指令访问器：设置目标 | iri_set_dest | 发射指令（emit） |
| IR 指令访问器：设置操作数1 | iri_set_s1 | 发射指令（emit） |
| IR 指令访问器：设置操作数2 | iri_set_s2 | 发射指令（emit） |
| IR 指令访问器：设置操作数3 | iri_set_s3 | 发射指令（emit） |
| IR 指令访问器：设置类型类别 | iri_set_tk | 发射指令（emit） |
| 压入结构图 | sg_push | 压入 SG 分配槽（sg_alloc_push） |
| 弹出结构图 | sg_pop | 弹出 SG 分配槽（sg_alloc_pop） |
| AST 访问器：a | ast_a | 查找全局常量节点（find_global_const_node） |
| AST 访问器：b | ast_b | 查找全局常量节点（find_global_const_node） |
| AST 访问器：c | ast_c | 查找全局常量节点（find_global_const_node） |
| AST 访问器：数据 | ast_data | 查找全局常量节点（find_global_const_node） |
| AST 访问器：类别 | ast_kind | 查找全局常量节点（find_global_const_node） |
| AST 访问器：整数值 | ast_int_val | 查找全局常量节点（find_global_const_node） |
| 查找函数 | find_func | IR 调用返回类型（ir_call_return_type） |
| 查找gsym | find_gsym | IR 调用返回类型（ir_call_return_type） |
| 符号类别 | sym_kind | IR 调用返回类型（ir_call_return_type） |
| 符号类型 | sym_type | IR 调用返回类型（ir_call_return_type） |
| 符号节点 | sym_node | IR 调用返回类型（ir_call_return_type） |
| 函数信息访问器：返回类型 | fi_return_type | IR 调用返回类型（ir_call_return_type） |
| 驻留字符串获取 | istr_get | IR 调用返回类型（ir_call_return_type） |
| 字符串驻留 | str_intern | 新建 IR 变量（new_ir_var） |
| 读 64 位 | r64 | 判断指针变量（is_ptr_var） |
| 写 64 位 | w64 | 绑定局部变量（bind_local） |
| 内部：动态拷贝 | _dyncpy | 扩展 SG 分配数组（grow_sg_alloc） |
| 分配内存 | alloc | 扩展 SG 分配数组（grow_sg_alloc） |

## 全局状态

| 变量名 | 说明 | 初始值 |
|--------|------|--------|
| 子图分配总量（g_sg_alloc_total） | 每子图累积分配大小（字节数组），每项 8 字节 | 空字符串（动态分配） |
| 子图分配容量（g_sg_alloc_cap） | 子图分配总量数组容量（项数） | 0 |
| 子图竞技场变量（g_sg_arena_var） | 每子图对应的竞技场 IR 变量（8 字节/项） | 空字符串（动态分配） |
| 子图竞技场变量容量（g_sg_arena_var_cap） | 子图竞技场变量数组容量（项数） | 0 |
| IR 源哈希（g_ir_source_hash） | 源码全文哈希值（用于缓存命中检测） | 0 |
| IR 源哈希就绪（g_ir_source_hash_ready） | 哈希是否已计算的标记 | 0 |

## 函数 扩展 SG 分配数组（grow_sg_alloc）

### 作用
动态扩展子图分配总量（子图分配总量（g_sg_alloc_total））数组的容量。当需要的项数超出当前容量时，分配更大的缓冲区并拷贝旧数据。

### 逻辑
令 所需项数（needed） = 参数传入的需要项数
如果 所需项数 小于 子图分配容量（g_sg_alloc_cap），那么：
    返回（无需扩展）

令 新容量（nc） = 子图分配容量（g_sg_alloc_cap） * 2
如果 新容量 小于 64，那么：
    令 新容量 = 64
如果 新容量 小于 所需项数，那么：
    令 新容量 = 所需项数 + 64

令 新缓冲区（nb） = 分配内存（alloc）（新容量 * 8）
内部：动态拷贝（_dyncpy）（子图分配总量（g_sg_alloc_total）, 子图分配容量（g_sg_alloc_cap） * 8, 新缓冲区（nb））
令 子图分配总量（g_sg_alloc_total） = 新缓冲区（nb）
令 子图分配容量（g_sg_alloc_cap） = 新容量（nc）

### 测试要点
1. 所需项数 小于当前容量时，函数立即返回，数组不变
2. 容量翻倍后仍不够时，以 所需项数 + 64 作为新容量
3. 初始容量为 0 时，翻倍得 0，小于 64 故新容量为 64
4. 旧数据被完整拷贝到新缓冲区

---

## 函数 扩展 SG 竞技场变量数组（grow_sg_arena_var）

### 作用
动态扩展子图竞技场变量（子图竞技场变量（g_sg_arena_var））数组容量，逻辑与 扩展 SG 分配数组（grow_sg_alloc）完全对称。

### 逻辑
令 所需项数（needed） = 参数传入的需要项数
如果 所需项数 小于 子图竞技场变量容量（g_sg_arena_var_cap），那么：
    返回

令 新容量（nc） = 子图竞技场变量容量（g_sg_arena_var_cap） * 2
如果 新容量 小于 64，那么：
    令 新容量 = 64
如果 新容量 小于 所需项数，那么：
    令 新容量 = 所需项数 + 64

令 新缓冲区（nb） = 分配内存（alloc）（新容量 * 8）
内部：动态拷贝（_dyncpy）（子图竞技场变量（g_sg_arena_var）, 子图竞技场变量容量（g_sg_arena_var_cap） * 8, 新缓冲区（nb））
令 子图竞技场变量（g_sg_arena_var） = 新缓冲区（nb）
令 子图竞技场变量容量（g_sg_arena_var_cap） = 新容量（nc）

### 测试要点
1. 已满足需求时不执行任何操作
2. 容量翻倍、下限 64、按需补 64 逻辑与 扩展 SG 分配数组（grow_sg_alloc）一致
3. 旧数据被完整拷贝

---

## 函数 压入 SG 分配槽（sg_alloc_push）

### 作用
在进入一个新的子图（SG）区域时调用。扩展两个跟踪数组并压入初始值为 0 的新项，然后调用 压入结构图（sg_push）创建子图节点。

### 逻辑
扩展 SG 分配数组（grow_sg_alloc）（g_sg_count + 1）
扩展 SG 竞技场变量数组（grow_sg_arena_var）（g_sg_count + 1）
写 64 位（w64）（子图分配总量（g_sg_alloc_total）, g_sg_count * 8, 0）
压入结构图（sg_push）（子图类别（kind））

### 测试要点
1. 新项的分配总量被初始化为 0
2. 同时扩展两个数组，确保容量足够
3. 之后调用 压入结构图（sg_push）创建数据流子图节点

---

## 函数 弹出 SG 分配槽（sg_alloc_pop）

### 作用
离开当前子图区域时调用。读取当前子图的累计分配总量和竞技场变量，弹出子图节点，并发射竞技场重置指令（IR_ARENA_RESET）。

### 逻辑
令 累计分配总量（total） = 读 64 位（r64）（子图分配总量（g_sg_alloc_total）, （g_sg_count - 1） * 8）
令 竞技场变量（arena_var） = 读 64 位（r64）（子图竞技场变量（g_sg_arena_var）, （g_sg_count - 1） * 8）
弹出结构图（sg_pop）（）
发射指令（emit）（IR_ARENA_RESET, -1, 竞技场变量（arena_var）, 0, 0, 0）

### 测试要点
1. 从子图分配总量 和 子图竞技场变量 中读取当前子图的数据
2. 发射 IR_ARENA_RESET 指令重置竞技场
3. 调用顺序为先读数据、再弹出 SG、最后发射重置指令

---

## 函数 跟踪分配大小（track_alloc_size）

### 作用
在 IR 生成过程中遇到分配操作时调用，将分配大小累加到当前子图的分配总量中，用于编译期大小估算。

### 逻辑
令 分配大小（size） = 参数传入的大小
如果 g_sg_count 大于 0 且 字符串长度（str_len）（子图分配总量（g_sg_alloc_total）） 大于 0，那么：
    令 之前累计（prev） = 读 64 位（r64）（子图分配总量（g_sg_alloc_total）, （g_sg_count - 1） * 8）
    写 64 位（w64）（子图分配总量（g_sg_alloc_total）, （g_sg_count - 1） * 8, 之前累计（prev） + 分配大小（size））

### 测试要点
1. 在 SG_FUNC 或 SG_LOOP/FOR 区域外调用时不执行任何操作（g_sg_count 小于等于 0）
2. 子图分配总量（g_sg_alloc_total）为空字符串时不操作
3. 正确累加多次分配的字节数

---

## 函数 新建 IR 变量（new_ir_var）

### 作用
创建新的 IR 变量，分配唯一的变量索引，设置名称（驻留字符串索引）和类型索引，返回变量索引。

### 逻辑
令 索引（idx） = g_ir_var_count
扩展 IR 变量数组（grow_ir_vars）（索引（idx） + 1）
IR 变量访问器：设置名称（irv_set_name）（索引（idx）, 字符串驻留（str_intern）（变量名（name）））
IR 变量访问器：设置ID（irv_set_id）（索引（idx）, 索引（idx））
IR 变量访问器：设置类型（irv_set_type）（索引（idx）, 类型索引（type_idx））
令 g_ir_var_count = 索引（idx） + 1
返回 索引（idx）

### 测试要点
1. 索引从当前 g_ir_var_count 开始，创建后全局计数加一
2. 变量名通过 字符串驻留（str_intern）转为驻留索引存储
3. 变量 ID 等于其索引
4. 数组空间不足时 扩展 IR 变量数组 自动扩容

---

## 函数 发射指令（emit）

### 作用
向线性 IR（.ccr）指令数组追加一条新指令，同时同步调用 数据流图：创建节点（df_create_node）构建并行数据流图（.cir）节点。这是 IR 生成的唯一指令出口。

### 逻辑
令 索引（idx） = g_ir_instr_count
扩展 IR 指令数组（grow_ir_instrs）（索引（idx） + 1）
IR 指令访问器：设置操作码（iri_set_op）（索引（idx）, 操作码（opcode））
IR 指令访问器：设置目标（iri_set_dest）（索引（idx）, 目标（dest））
IR 指令访问器：设置操作数1（iri_set_s1）（索引（idx）, 源操作数1（src1））
IR 指令访问器：设置操作数2（iri_set_s2）（索引（idx）, 源操作数2（src2））
IR 指令访问器：设置操作数3（iri_set_s3）（索引（idx）, 源操作数3（src3））
IR 指令访问器：设置类型类别（iri_set_tk）（索引（idx）, 类型类别（type_kind））
令 g_ir_instr_count = 索引（idx） + 1
（同步构建数据流图）
数据流图：创建节点（df_create_node）（操作码（opcode）, 目标（dest）, 源操作数1（src1）, 源操作数2（src2）, 源操作数3（src3）, 类型类别（type_kind））

### 测试要点
1. 每条指令在 .ccr 和 .cir 中同时创建，保持同步
2. 指令索引由全局计数器 g_ir_instr_count 分配
3. 所有六个字段（操作码、目标、三个源操作数、类型类别）均写入

---

## 函数 新建标签（new_label）

### 作用
生成唯一的跳转标签编号，用于 IR 中的 IR_LABEL 和 IR_JUMP/IR_BRANCH 指令。

### 逻辑
令 标签号（lbl） = g_next_label
令 g_next_label = g_next_label + 1
返回 标签号（lbl）

### 测试要点
1. 每次调用返回递增的整数，从初始值 1 开始
2. 返回值用于后续 IR_LABEL 指令的源操作数

---

## 函数 绑定局部变量（bind_local）

### 作用
将变量名（驻留字符串索引）与 IR 变量索引关联，存入局部变量表（g_ir_locals）。查找时从后往前扫描，因此最近绑定的优先级最高（作用域遮蔽）。

### 逻辑
扩展 IR 局部变量数组（grow_ir_locals）（g_ir_local_count + 1）
写 64 位（w64）（g_ir_locals, g_ir_local_count * 16, 名字索引（name_idx））
写 64 位（w64）（g_ir_locals, g_ir_local_count * 16 + 8, 变量索引（var_idx））
令 g_ir_local_count = g_ir_local_count + 1

### 测试要点
1. 每条局部绑定占 16 字节：前 8 字节为名字索引，后 8 字节为变量索引
2. 多次绑定同一名字时，新绑定追加在末尾，查找时优先命中

---

## 函数 查找局部变量（find_local）

### 作用
从局部变量表中查找给定名字索引对应的 IR 变量索引。从后往前扫描，实现最近绑定优先的作用域遮蔽语义。

### 逻辑
令 当前索引（i） = g_ir_local_count - 1
循环（当 当前索引（i） 不小于 0 时）：
    如果 当前索引（i） 小于 0，那么：
        返回 -1
    如果 读 64 位（r64）（g_ir_locals, 当前索引（i） * 16） 等于 名字索引（name_idx），那么：
        返回 读 64 位（r64）（g_ir_locals, 当前索引（i） * 16 + 8）
    令 当前索引（i） = 当前索引（i） - 1
返回 -1

### 测试要点
1. 未找到时返回 -1
2. 同一名字多次绑定时返回最近绑定的变量索引
3. 空表（g_ir_local_count 等于 0）时直接返回 -1

---

## 函数 查找全局变量（find_global）

### 作用
从全局 IR 变量表中查找给定名字索引对应的 IR 变量索引。扫描逻辑与 查找局部变量（find_local）类似。

### 逻辑
令 当前索引（i） = g_ir_global_count - 1
循环（当 当前索引（i） 不小于 0 时）：
    如果 当前索引（i） 小于 0，那么：
        返回 -1
    如果 读 64 位（r64）（g_ir_globals, 当前索引（i） * 24） 等于 名字索引（name_idx），那么：
        返回 读 64 位（r64）（g_ir_globals, 当前索引（i） * 24 + 8）
    令 当前索引（i） = 当前索引（i） - 1
返回 -1

### 测试要点
1. 未找到时返回 -1
2. 全局 IR 变量每条记录占 24 字节（名字 + 变量索引 + 初始值）
3. 空表时直接返回 -1

---

## 函数 查找全局常量节点（find_global_const_node）

### 作用
查找模块级不可变常量（immutable global let）的编译时常量 AST 节点。仅返回类型为整数（EXPR_INT）或布尔（EXPR_BOOL）的常量值，用于编译期常量折叠。不处理可变变量（mut）和运行时初始化的常量。

### 逻辑
令 当前索引（i） = g_global_let_count - 1
循环（当 当前索引（i） 不小于 0 时）：
    如果 当前索引（i） 小于 0，那么：
        跳出循环
    令 当前节点（node） = 读 64 位（r64）（g_global_lets, 当前索引（i） * 8）
    如果 AST 访问器：a（ast_a）（当前节点（node）） 等于 名字索引（name_idx） 且 AST 访问器：数据（ast_data）（当前节点（node）） 等于 0，那么：
        令 值节点（value_node） = AST 访问器：c（ast_c）（当前节点（node））
        如果 值节点（value_node） 不小于 0，那么：
            令 值类别（value_kind） = AST 访问器：类别（ast_kind）（值节点（value_node））
            如果 值类别（value_kind） 等于 EXPR_INT 或 值类别（value_kind） 等于 EXPR_BOOL，那么：
                返回 值节点（value_node）
    令 当前索引（i） = 当前索引（i） - 1
返回 -1

### 测试要点
1. 只返回不可变常量（ast_data 等于 0）的整数/布尔初始值
2. 可变变量（mut）或在 checker 阶段被标记为非零 data 的声明被跳过
3. 未找到或非编译时常量时返回 -1
4. 空表时返回 -1

---

## 函数 压入 IR 作用域（push_ir_scope）

### 作用
进入新的词法作用域（如函数体、代码块）时调用，记录当前局部变量计数，以便退出作用域时回滚（弹出 IR 作用域（pop_ir_scope））。

### 逻辑
扩展 IR 局部作用域数组（grow_ir_local_scopes）（g_ir_local_depth + 1）
写 64 位（w64）（g_ir_local_scopes, g_ir_local_depth * 8, g_ir_local_count）
令 g_ir_local_depth = g_ir_local_depth + 1

### 测试要点
1. 保存当前局部变量计数作为回滚点
2. 作用域深度递增
3. 可在同一深度多次压入/弹出形成嵌套作用域

---

## 函数 弹出 IR 作用域（pop_ir_scope）

### 作用
退出当前词法作用域，将局部变量计数恢复到进入该作用域前的值，丢弃该作用域内绑定的所有局部变量。

### 逻辑
令 g_ir_local_depth = g_ir_local_depth - 1
令 g_ir_local_count = 读 64 位（r64）（g_ir_local_scopes, g_ir_local_depth * 8）

### 测试要点
1. 作用域退出后，内部绑定的变量不再可见（查找局部变量 从后往前扫描到更小索引）
2. 深度减一
3. 深度为 0 时不能再弹出

---

## 函数 判断指针变量（is_ptr_var）

### 作用
判断给定 IR 变量是否为指针语义（由 IR_ALLOC、IR_ADDR_INDEX、IR_REF、IR_ALLOC_STRUCT、IR_ALLOC_ARRAY 等指令产生）。用于指针算术检测（区分普通加减与 PTR_ADD/PTR_SUB）。

### 逻辑
令 变量索引（var_idx） = 参数传入的变量索引
如果 变量索引（var_idx） 小于 0，那么：
    返回 0
令 生产者（prod） = 读 64 位（r64）（g_df_var_producer, 变量索引（var_idx） * 8）
如果 生产者（prod） 小于 0，那么：
    返回 0
令 生产者操作码（prod_op） = 读 64 位（r64）（g_df_nodes, 生产者（prod） * ESZ_DFNODE + OFF_DF_OPCODE）
如果 生产者操作码（prod_op） 等于 IR_ALLOC，那么：
    令 类型索引（ti） = IR 变量访问器：类型（irv_type）（变量索引（var_idx））
    如果 类型索引（ti） 等于 TI_INT 或 类型索引（ti） 等于 TI_FLOAT 或 类型索引（ti） 等于 TI_BOOL 或 类型索引（ti） 等于 TI_CHAR，那么：
        返回 0
    返回 1
如果 生产者操作码（prod_op） 等于 IR_ADDR_INDEX 或 生产者操作码（prod_op） 等于 IR_REF 或 生产者操作码（prod_op） 等于 IR_ALLOC_STRUCT 或 生产者操作码（prod_op） 等于 IR_ALLOC_ARRAY，那么：
    返回 1
返回 0

### 测试要点
1. 变量索引无效（小于 0）时返回 0
2. 基本类型（int/float/bool/char）的 IR_ALLOC 不被视为指针
3. 结构体、数组、枚举的 IR_ALLOC 被视为指针
4. IR_ADDR_INDEX、IR_REF、IR_ALLOC_STRUCT、IR_ALLOC_ARRAY 的直接产物总是指针

---

## 函数 判断字节缓冲变量（is_byte_buf_var）

### 作用
判断给定 IR 变量是否为原始字节缓冲区（由 分配内存（alloc）() 生成，类型为 TI_UNIT 内部哨兵值，对应 Core 语言的 string 类型）。字节缓冲区的地址运算不进行元素大小缩放。

### 逻辑
令 变量索引（var_idx） = 参数传入的变量索引
如果 变量索引（var_idx） 小于 0，那么：
    返回 0
令 生产者（prod） = 读 64 位（r64）（g_df_var_producer, 变量索引（var_idx） * 8）
如果 生产者（prod） 小于 0，那么：
    返回 0
令 生产者操作码（prod_op） = 读 64 位（r64）（g_df_nodes, 生产者（prod） * ESZ_DFNODE + OFF_DF_OPCODE）
如果 生产者操作码（prod_op） 等于 IR_ALLOC，那么：
    返回 1
返回 0

### 测试要点
1. 变量索引无效时返回 0
2. 仅 IR_ALLOC 产生的变量被视为字节缓冲区
3. 用于指针算术检测时决定是否跳过缩放

---

## 函数 IR 调用返回类型（ir_call_return_type）

### 作用
根据函数名字索引查询其 IR 级别的返回类型（TI_INT/TI_FLOAT/TI_BOOL/TI_STR/TI_UNIT/TI_CHAR）。覆盖内置函数（如 分配内存（alloc））返回 TI_UNIT 的特殊处理、运行时内置函数表查找、用户定义函数查找，以及 .so 外部函数（SYM_SO_FN）的类型编码解析。

### 逻辑
令 函数名字索引（func_ni） = 参数传入的函数名字索引
如果 函数名字索引（func_ni） 小于 0，那么：
    返回 TI_UNIT
（特殊处理：分配内存（alloc） 返回原始字节缓冲区，保持 TI_UNIT 哨兵值）
如果 驻留字符串获取（istr_get）（函数名字索引（func_ni）） 等于 "alloc"，那么：
    返回 TI_UNIT
（查运行时内置函数返回类型表）
令 内置索引（bi） = 0
循环（当 内置索引（bi） 小于 g_rt_builtin_count 时）：
    如果 内置索引（bi） 不小于 g_rt_builtin_count，那么：
        跳出循环
    如果 读 64 位（r64）（g_rt_builtin_names, 内置索引（bi） * 8） 等于 函数名字索引（func_ni），那么：
        返回 读 64 位（r64）（g_rt_builtin_ret_types, 内置索引（bi） * 8）
    令 内置索引（bi） = 内置索引（bi） + 1
（查用户定义函数）
令 函数索引（fi） = 查找函数（find_func）（函数名字索引（func_ni））
如果 函数索引（fi） 不小于 0，那么：
    令 返回类型（rt） = 函数信息访问器：返回类型（fi_return_type）（函数索引（fi））
    如果 返回类型（rt） 等于 TY_INT，那么：返回 TI_INT
    如果 返回类型（rt） 等于 TY_FLOAT，那么：返回 TI_FLOAT
    如果 返回类型（rt） 等于 TY_BOOL，那么：返回 TI_BOOL
    如果 返回类型（rt） 等于 TY_STRING，那么：返回 TI_STR
    如果 返回类型（rt） 等于 TY_UNIT，那么：返回 TI_UNIT
    如果 返回类型（rt） 等于 TY_CHAR，那么：返回 TI_CHAR
（查 .so 外部函数符号）
令 符号索引（si） = 查找gsym（find_gsym）（函数名字索引（func_ni））
如果 符号索引（si） 小于 0，那么：
    返回 TI_UNIT
如果 符号类别（sym_kind）（符号索引（si）） 等于 SYM_FN，那么：
    返回 符号类型（sym_type）（符号索引（si））
如果 符号类别（sym_kind）（符号索引（si）） 等于 SYM_SO_FN，那么：
    令 类型编码（type_enc） = 符号节点（sym_node）（符号索引（si））
    令 返回码（ret_code） = 类型编码（type_enc） - （类型编码（type_enc） / 100） * 100
    如果 返回码（ret_code） 等于 0，那么：返回 TI_INT
    如果 返回码（ret_code） 等于 1，那么：返回 TI_STR
    如果 返回码（ret_code） 等于 2，那么：返回 TI_UNIT
    如果 返回码（ret_code） 等于 3，那么：返回 TI_FLOAT
    如果 返回码（ret_code） 等于 4，那么：返回 TI_BOOL
返回 TI_UNIT

### 测试要点
1. 函数名字索引无效（小于 0）时返回 TI_UNIT
2. 分配内存（alloc） 函数始终返回 TI_UNIT
3. 运行时内置函数表中找到匹配时直接返回内置返回类型
4. 用户函数按 TY_* 到 TI_* 映射返回
5. .so 外部函数按类型编码尾部两位数字解析返回类型
6. 所有路径均未找到时返回 TI_UNIT

---

## 函数 获取 IR 变量名（get_ir_var_name）

### 作用
根据 IR 变量索引返回其可读名称字符串（通过驻留字符串获取（istr_get）反查）。用于调试和诊断输出。

### 逻辑
令 变量索引（var_idx） = 参数传入的变量索引
如果 变量索引（var_idx） 不小于 0 且 变量索引（var_idx） 小于 g_ir_var_count，那么：
    令 名字索引（ni） = IR 变量访问器：名称（irv_name）（变量索引（var_idx））
    返回 驻留字符串获取（istr_get）（名字索引（ni））
返回 ""

### 测试要点
1. 合法索引返回变量名称字符串
2. 越界或负索引返回空字符串
3. 变量名通过驻留字符串系统管理，返回的是 Intern 池中的字符串

---

## 函数 跟踪字符串常量（track_str）

### 作用
将字符串驻留索引记录到 IR 字符串常量表（g_ir_str_consts）中，用于后续生成 .rodata 段中的字符串常量数据。已存在的字符串索引不重复添加。

### 逻辑
令 字符串索引（str_idx） = 参数传入的字符串驻留索引
令 当前索引（i） = 0
循环（当 当前索引（i） 小于 g_ir_str_const_count 时）：
    如果 当前索引（i） 不小于 g_ir_str_const_count，那么：
        跳出循环
    如果 读 64 位（r64）（g_ir_str_consts, 当前索引（i） * 8） 等于 字符串索引（str_idx），那么：
        返回（已存在，不重复添加）
    令 当前索引（i） = 当前索引（i） + 1
（未找到，追加新项）
扩展 IR 字符串常量数组（grow_ir_str_consts）（g_ir_str_const_count + 1）
写 64 位（w64）（g_ir_str_consts, g_ir_str_const_count * 8, 字符串索引（str_idx））
令 g_ir_str_const_count = g_ir_str_const_count + 1

### 测试要点
1. 重复添加同一字符串索引时只保留一条记录
2. 空表时直接追加
3. 数组容量不足时自动扩展

