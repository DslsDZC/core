# dataflow.cr 伪代码
> 源文件：src/compiler/dataflow.cr（521 行）
> 功能概要：数据流图（.cir）的构建与向线性 CFG（.ccr）的降级。在 IR 生成期间，每次发射（emit）调用创建一个数据流节点（DFNode），并通过变量生产者映射（g_df_var_producer）追踪定义-使用边。全部 IR 生成后，降为线性 IR（lower_to_ccr）将图线性化到 IR 指令数组（g_ir_instrs）中，供 x86-64 后端消费。同时包含子图（region）管理、状态边（VSDG state chain）构建和 DOT 可视化导出。

## 标识符对照表
| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 初始化数据流图 | init_df | 初始化数据流图 |
| 压入结构图 | sg_push | 压入结构图 |
| 弹出结构图 | sg_pop | 弹出结构图 |
| 数据流图：创建节点 | df_create_node | 数据流图：创建节点 |
| 数据流图：添加带类别边 | df_add_edge_kind | 数据流图：添加带类别边 |
| 数据流图：添加边 | df_add_edge | 数据流图：添加边 |
| 数据流图：连接状态边 | df_connect_state | 数据流图：连接状态边 |
| 数据流图：使用变量 | df_use_var | 数据流图：使用变量 |
| 数据流图：连接源操作数 | df_connect_srcs | 数据流图：连接源操作数 |
| 扩展变量使用计数数组 | grow_var_use_count | 扩展变量使用计数数组 |
| 计算变量使用次数 | compute_usage_counts | 计算变量使用次数 |
| 降为线性 IR | lower_to_ccr | 降为线性 IR |
| 数据流图：开始函数 | df_begin_func | 数据流图：开始函数 |
| 数据流图：结束函数 | df_end_func | 数据流图：结束函数 |
| 数据流图：导出 DOT | df_graph_to_dot | 数据流图：导出 DOT |
| 数据流图：操作码名称 | df_opcode_name | 数据流图：操作码名称 |
| 扩展数据流数组 | grow_df_arrays | 初始化数据流图 |
| 扩展数据流节点数组 | grow_df_nodes | 数据流图：创建节点 |
| 扩展数据流节点区域数组 | grow_df_node_region | 数据流图：创建节点 |
| 扩展数据流边数组 | grow_df_edges | 数据流图：添加带类别边 |
| 扩展结构图数组 | grow_sg | 压入结构图 |
| 扩展 IR 指令数组 | grow_ir_instrs | 降为线性 IR |
| 查找函数 | find_func | 数据流图：连接状态边 |
| 获取 IR 变量名 | get_ir_var_name | 数据流图：导出 DOT |
| 整数转字符串 | int_str | 数据流图：导出 DOT |
| 字符串长度 | str_len | 数据流图：导出 DOT |
| 函数信息访问器：是否纯净 | fi_ispure | 数据流图：连接状态边 |
| IR 指令访问器：设置操作码 | iri_set_op | 降为线性 IR |
| IR 指令访问器：设置目标 | iri_set_dest | 降为线性 IR |
| IR 指令访问器：设置操作数1 | iri_set_s1 | 降为线性 IR |
| IR 指令访问器：设置操作数2 | iri_set_s2 | 降为线性 IR |
| IR 指令访问器：设置操作数3 | iri_set_s3 | 降为线性 IR |
| IR 指令访问器：设置类型类别 | iri_set_tk | 降为线性 IR |
| 写 64 位 | w64 | 初始化数据流图 |
| 读 64 位 | r64 | 压入结构图 |
| 分配 | alloc | 扩展变量使用计数数组 |
| 内部：动态拷贝 | _dyncpy | 扩展变量使用计数数组 |
| 数据流图各函数节点起始索引 | g_df_func_node_start | 初始化数据流图 |
| 数据流图各函数节点计数 | g_df_func_node_count | 初始化数据流图 |
| 数据流节点计数 | g_df_node_count | 初始化数据流图 |
| 数据流边计数 | g_df_edge_count | 初始化数据流图 |
| 数据流图数组容量 | g_df_cap | 初始化数据流图 |
| 数据流节点数组容量 | g_df_node_cap | 初始化数据流图 |
| 数据流边数组容量 | g_df_edge_cap | 初始化数据流图 |
| 数据流节点 region 映射容量 | g_df_node_region_cap | 初始化数据流图 |
| 当前结构图索引 | g_cur_sg | 初始化数据流图 |
| 最后一个状态节点 | g_last_state_node | 初始化数据流图 |
| 函数计数 | g_func_count | 初始化数据流图 |
| IR 变量总数 | g_ir_var_count | 初始化数据流图 |
| 结构图数组 | g_sgs | 压入结构图 |
| 结构图计数 | g_sg_count | 压入结构图 |
| 数据流节点数组 | g_df_nodes | 数据流图：创建节点 |
| 数据流节点所属 region | g_df_node_region | 数据流图：创建节点 |
| 数据流边数组 | g_df_edges | 数据流图：添加带类别边 |
| 变量生产者节点映射 | g_df_var_producer | 数据流图：创建节点 |
| 变量使用计数数组 | g_var_use_count | 扩展变量使用计数数组 |
| 变量使用计数容量 | g_var_use_count_cap | 扩展变量使用计数数组 |
| IR 指令总数 | g_ir_instr_count | 降为线性 IR |
| IR 函数个数 | g_ir_func_count | 降为线性 IR |
| IR 函数指令起始索引数组 | g_ir_func_instr_start | 降为线性 IR |
| IR 函数指令计数数组 | g_ir_func_instr_count | 降为线性 IR |
| ESZ 数据流节点大小 | ESZ_DFNODE | （结构体常量） |
| ESZ 数据流边大小 | ESZ_DFEDGE | （结构体常量） |
| 偏移\_DF\_操作码 | OFF_DF_OPCODE | （结构体字段偏移） |
| 偏移\_DF\_目标 | OFF_DF_DEST | （结构体字段偏移） |
| 偏移\_DF\_源1 | OFF_DF_S1 | （结构体字段偏移） |
| 偏移\_DF\_源2 | OFF_DF_S2 | （结构体字段偏移） |
| 偏移\_DF\_源3 | OFF_DF_S3 | （结构体字段偏移） |
| 偏移\_DF\_类型类别 | OFF_DF_TK | （结构体字段偏移） |
| 偏移\_DF\_首边索引 | OFF_DF_FIRST_EDGE | （结构体字段偏移） |
| 偏移\_DF\_边计数 | OFF_DF_EDGE_COUNT | （结构体字段偏移） |
| 偏移\_DFE\_源节点 | OFF_DFE_FROM | （结构体字段偏移） |
| 偏移\_DFE\_目标节点 | OFF_DFE_TO | （结构体字段偏移） |
| 偏移\_DFE\_类别 | OFF_DFE_KIND | （结构体字段偏移） |
| 偏移\_DFE\_下一边 | OFF_DFE_NEXT | （结构体字段偏移） |
| ESZ 结构图大小 | ESZ_SG | （结构体常量） |
| 偏移\_SG\_类别 | OFF_SG_KIND | （结构体字段偏移） |
| 偏移\_SG\_入口 | OFF_SG_ENTER | （结构体字段偏移） |
| 偏移\_SG\_出口 | OFF_SG_EXIT | （结构体字段偏移） |
| 偏移\_SG\_节点起始 | OFF_SG_NSTART | （结构体字段偏移） |
| 偏移\_SG\_节点计数 | OFF_SG_NCOUNT | （结构体字段偏移） |
| 偏移\_SG\_父节点 | OFF_SG_PARENT | （结构体字段偏移） |
| 结构图\_函数 | SG_FUNC | （常量） |
| 结构图\_IF | SG_IF | （常量） |
| 结构图\_循环 | SG_LOOP | （常量） |
| 结构图\_FOR | SG_FOR | （常量） |
| 结构图\_FLOW | SG_FLOW | （常量） |
| 结构图\_不安全 | SG_UNSAFE | （常量） |

## 全局状态
- **数据流节点计数（g_df_node_count）**：已创建的数据流节点总数，初始值为 0
- **数据流边计数（g_df_edge_count）**：已创建的数据流边总数，初始值为 0
- **数据流图数组容量（g_df_cap）**：变量生产者映射等辅助数组的容量，初始值为 0
- **数据流节点数组容量（g_df_node_cap）**：节点数组容量，初始值为 0
- **数据流边数组容量（g_df_edge_cap）**：边数组容量，初始值为 0
- **数据流节点 region 映射容量（g_df_node_region_cap）**：节点所属 region 映射数组容量，初始值为 0
- **当前结构图索引（g_cur_sg）**：当前打开的最内层 region 的索引，-1 表示未打开任何 region
- **最后一个状态节点（g_last_state_node）**：VSDG 状态链的当前尾节点，每个函数编译开始时重置为 -1

## 函数 初始化数据流图（init_df）
### 作用
将数据流图的所有全局数组计数器归零，并为每个函数预留起始节点位置（置为 -1 即"未生成"），同时为每个 IR 变量清除生产者节点映射（置为 -1 即"未产生"），确保每次编译的数据流图从干净状态开始。
### 逻辑
    令 数据流节点计数（g_df_node_count） = 0
    令 数据流边计数（g_df_edge_count） = 0
    令 数据流图数组容量（g_df_cap） = 0
    令 数据流节点数组容量（g_df_node_cap） = 0
    令 数据流边数组容量（g_df_edge_cap） = 0
    令 数据流节点 region 映射容量（g_df_node_region_cap） = 0
    令 当前结构图索引（g_cur_sg） = -1
    令 最后一个状态节点（g_last_state_node） = -1
    令 函数索引（fi） = 0（可变）
    循环（当 函数索引 小于 函数计数（g_func_count） 时）：
        扩展数据流数组（grow_df_arrays）（函数索引 + 1）
        写 64 位（w64）（数据流图各函数节点起始索引（g_df_func_node_start），函数索引 * 8，-1）
        写 64 位（w64）（数据流图各函数节点计数（g_df_func_node_count），函数索引 * 8，0）
        令 函数索引 = 函数索引 + 1
    令 变量索引（vi） = 0（可变）
    循环（当 变量索引 小于 IR 变量总数（g_ir_var_count） 时）：
        扩展数据流数组（grow_df_arrays）（变量索引 + 1）
        写 64 位（w64）（变量生产者节点映射（g_df_var_producer），变量索引 * 8，-1）
        令 变量索引 = 变量索引 + 1
### 测试要点
1. 两次连续调用 初始化数据流图（init_df） 不会残留上次的数据（所有计数归零，映射表全为 -1）
2. 函数计数（g_func_count）为 0 时不报错（循环体不执行）
3. IR 变量总数（g_ir_var_count）为 0 时不报错（循环体不执行）

## 函数 压入结构图（sg_push）
### 作用
在数据流图中打开一个新的嵌套 region（子图）。根据给定的类别（kind）创建结构图（SG）记录，记录入口节点位置，查找并绑定父 region（最内层当前未关闭的 region），然后将自身设为当前最内层活跃 region。用于标记函数体、if 分支、循环体等嵌套结构的边界。
### 逻辑
    扩展结构图数组（grow_sg）（结构图计数（g_sg_count） + 1）
    令 当前索引（idx） = 结构图计数（g_sg_count）
    写 64 位（w64）（结构图数组（g_sgs），当前索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_类别（OFF_SG_KIND），类别）
    写 64 位（w64）（结构图数组（g_sgs），当前索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_入口（OFF_SG_ENTER），数据流节点计数（g_df_node_count））
    写 64 位（w64）（结构图数组（g_sgs），当前索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_出口（OFF_SG_EXIT），-1）
    写 64 位（w64）（结构图数组（g_sgs），当前索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_节点起始（OFF_SG_NSTART），数据流节点计数（g_df_node_count））
    写 64 位（w64）（结构图数组（g_sgs），当前索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_节点计数（OFF_SG_NCOUNT），0）
    令 父索引（parent） = -1
    令 扫描索引（pi） = 当前索引 - 1
    循环（当 扫描索引 不小于 0 时）：
        如果 读 64 位（r64）（结构图数组（g_sgs），扫描索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_出口（OFF_SG_EXIT）） 小于 0，那么：
            令 父索引 = 扫描索引
            跳出循环
        令 扫描索引 = 扫描索引 - 1
    写 64 位（w64）（结构图数组（g_sgs），当前索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_父节点（OFF_SG_PARENT），父索引）
    令 当前结构图索引（g_cur_sg） = 当前索引
    令 结构图计数（g_sg_count） = 当前索引 + 1
### 测试要点
1. 首次压入（无任何已打开的 region）时，父索引为 -1，当前结构图索引（g_cur_sg）正确指向新 region
2. 嵌套压入：先压入函数 region，再压入 if region，if 的父索引指向函数 region
3. region 出口字段在压入时设为 -1，表示"尚未关闭"
4. 节点起始和节点计数字段正确记录入口时的节点数

## 函数 弹出结构图（sg_pop）
### 作用
关闭当前最内层未关闭的 region（出口字段为 -1 的 region）。从结构图数组末尾向前搜索第一个出口尚为 -1 的条目，将其出口设为当前节点计数、节点计数设为区间内节点个数。对于循环类 region（SG_LOOP/SG_FOR），若最后一个状态节点位于该 region 内，则添加一个终止依赖边（kind=1），确保循环退出依赖于循环体内最后一个副作用；并将状态链头推进到 region 出口节点，使得循环之后的副作用必须等待循环终止。最后将当前结构图索引恢复为其父 region。
### 逻辑
    如果 结构图计数（g_sg_count） 不大于 0，那么：返回
    令 关闭索引（idx） = -1（可变）
    令 扫描索引（pi） = 结构图计数（g_sg_count） - 1
    循环（当 扫描索引 不小于 0 时）：
        如果 读 64 位（r64）（结构图数组（g_sgs），扫描索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_出口（OFF_SG_EXIT）） 小于 0，那么：
            令 关闭索引 = 扫描索引
            跳出循环
        令 扫描索引 = 扫描索引 - 1
    如果 关闭索引 小于 0，那么：返回
    写 64 位（w64）（结构图数组（g_sgs），关闭索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_出口（OFF_SG_EXIT），数据流节点计数（g_df_node_count））
    写 64 位（w64）（结构图数组（g_sgs），关闭索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_节点计数（OFF_SG_NCOUNT），数据流节点计数（g_df_node_count） - 读 64 位（r64）（结构图数组（g_sgs），关闭索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_节点起始（OFF_SG_NSTART）））
    令 region 类别（kind） = 读 64 位（r64）（结构图数组（g_sgs），关闭索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_类别（OFF_SG_KIND））
    如果 region 类别 等于 结构图\_循环（SG_LOOP） 或 region 类别 等于 结构图\_FOR（SG_FOR），那么：
        令 最后节点（last_node） = 数据流节点计数（g_df_node_count） - 1
        如果 最后节点 不小于 读 64 位（r64）（结构图数组（g_sgs），关闭索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_节点起始（OFF_SG_NSTART）），那么：
            如果 最后一个状态节点（g_last_state_node） 不小于 读 64 位（r64）（结构图数组（g_sgs），关闭索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_节点起始（OFF_SG_NSTART）），那么：
                数据流图：添加带类别边（df_add_edge_kind）（最后一个状态节点（g_last_state_node），最后节点，1）
            令 最后一个状态节点（g_last_state_node） = 最后节点
    令 当前结构图索引（g_cur_sg） = 读 64 位（r64）（结构图数组（g_sgs），关闭索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_父节点（OFF_SG_PARENT））
### 测试要点
1. 结构图计数（g_sg_count）为 0 时直接返回，不崩溃
2. 关闭后当前结构图索引（g_cur_sg）正确恢复到父 region
3. 循环 region 的终止依赖边：当最后一个状态节点在 region 内部时，正确创建从该状态节点到 region 出口节点的 kind=1 边
4. 循环 region 的终止依赖边：当最后一个状态节点在 region 外部（例如循环体为纯函数、状态节点在循环前创建）时，不创建终止边
5. 循环 region 弹出后，最后一个状态节点（g_last_state_node）推进到 region 出口节点

## 函数 数据流图：创建节点（df_create_node）
### 作用
在数据流图中创建一个新节点，填写操作码、目标变量、源操作数和类型类别，并将其所属的 region 记录到节点-region 映射中。如果目标变量 dest >= 0，则更新变量生产者映射（g_df_var_producer）记录此节点产生该变量。随后自动连接源操作数边（通过 df_connect_srcs）和状态边（通过 df_connect_state），返回新节点的 ID。
### 逻辑
    令 节点 ID（nid） = 数据流节点计数（g_df_node_count）
    扩展数据流节点数组（grow_df_nodes）（节点 ID + 1）
    扩展数据流节点区域数组（grow_df_node_region）（节点 ID + 1）
    写 64 位（w64）（数据流节点所属 region（g_df_node_region），节点 ID * 8，当前结构图索引（g_cur_sg））
    写 64 位（w64）（数据流节点数组（g_df_nodes），节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_操作码（OFF_DF_OPCODE），操作码（opcode））
    写 64 位（w64）（数据流节点数组（g_df_nodes），节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_目标（OFF_DF_DEST），目标变量（dest））
    写 64 位（w64）（数据流节点数组（g_df_nodes），节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_源1（OFF_DF_S1），源操作数1（src1））
    写 64 位（w64）（数据流节点数组（g_df_nodes），节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_源2（OFF_DF_S2），源操作数2（src2））
    写 64 位（w64）（数据流节点数组（g_df_nodes），节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_源3（OFF_DF_S3），源操作数3（src3））
    写 64 位（w64）（数据流节点数组（g_df_nodes），节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_类型类别（OFF_DF_TK），类型类别（type_kind））
    写 64 位（w64）（数据流节点数组（g_df_nodes），节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_首边索引（OFF_DF_FIRST_EDGE），-1）
    写 64 位（w64）（数据流节点数组（g_df_nodes），节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_边计数（OFF_DF_EDGE_COUNT），0）
    令 数据流节点计数（g_df_node_count） = 节点 ID + 1
    如果 目标变量（dest） 不小于 0，那么：
        扩展数据流数组（grow_df_arrays）（目标变量（dest） + 1）
        写 64 位（w64）（变量生产者节点映射（g_df_var_producer），目标变量（dest） * 8，节点 ID（nid））
    数据流图：连接源操作数（df_connect_srcs）（节点 ID（nid），操作码（opcode），源操作数1（src1），源操作数2（src2），源操作数3（src3））
    数据流图：连接状态边（df_connect_state）（节点 ID（nid），操作码（opcode），源操作数3（src3））
    返回 节点 ID（nid）
### 测试要点
1. 首次创建节点时节点 ID 为 0，数据流节点计数（g_df_node_count）更新为 1
2. 目标变量（dest）为 -1 时（无输出变量），不更新变量生产者映射（g_df_var_producer）
3. 目标变量（dest）的索引超过当前数组容量时，grow_df_arrays 正确扩展
4. 处于 region 内时（当前结构图索引（g_cur_sg） >= 0），节点所属 region 正确记录
5. 不处于任何 region 内时（当前结构图索引（g_cur_sg） = -1），节点所属 region 记录为 -1

## 函数 数据流图：添加带类别边（df_add_edge_kind）
### 作用
在数据流图中添加一条有向边，从 from_id 节点指向 to_id 节点，类别为 kind（0 = 数据边/定义-使用边，1 = 状态边/VSDG 顺序约束）。采用链表头插法：新边插入到源节点的边链表头部，边计数加一。
### 逻辑
    如果 源节点 ID（from_id） 小于 0 或 目标节点 ID（to_id） 小于 0，那么：返回
    令 边 ID（eid） = 数据流边计数（g_df_edge_count）
    扩展数据流边数组（grow_df_edges）（边 ID + 1）
    写 64 位（w64）（数据流边数组（g_df_edges），边 ID * 数据流边条目大小（ESZ_DFEDGE） + 偏移\_DFE\_源节点（OFF_DFE_FROM），源节点 ID（from_id））
    写 64 位（w64）（数据流边数组（g_df_edges），边 ID * 数据流边条目大小（ESZ_DFEDGE） + 偏移\_DFE\_目标节点（OFF_DFE_TO），目标节点 ID（to_id））
    写 64 位（w64）（数据流边数组（g_df_edges），边 ID * 数据流边条目大小（ESZ_DFEDGE） + 偏移\_DFE\_类别（OFF_DFE_KIND），类别（kind））
    令 旧的链表头（old_first） = 读 64 位（r64）（数据流节点数组（g_df_nodes），源节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_首边索引（OFF_DF_FIRST_EDGE））
    写 64 位（w64）（数据流边数组（g_df_edges），边 ID * 数据流边条目大小（ESZ_DFEDGE） + 偏移\_DFE\_下一边（OFF_DFE_NEXT），旧的链表头（old_first））
    写 64 位（w64）（数据流节点数组（g_df_nodes），源节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_首边索引（OFF_DF_FIRST_EDGE），边 ID（eid））
    令 旧的边计数（old_cnt） = 读 64 位（r64）（数据流节点数组（g_df_nodes），源节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_边计数（OFF_DF_EDGE_COUNT））
    写 64 位（w64）（数据流节点数组（g_df_nodes），源节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_边计数（OFF_DF_EDGE_COUNT），旧的边计数（old_cnt） + 1）
    令 数据流边计数（g_df_edge_count） = 边 ID + 1
### 测试要点
1. 源节点 ID（from_id）或目标节点 ID（to_id）为负数时直接返回，不创建边
2. 同一源节点连续添加多条边时，边链表为逆序（后添加的在链表头），边计数正确递增
3. 首次添加边时（源节点的首边索引为 -1），新边正确成为链表唯一元素（下一边字段为 -1）

## 函数 数据流图：添加边（df_add_edge）
### 作用
添加一条数据边（定义-使用边），类别固定为 0。是对 df_add_edge_kind 的便捷封装。
### 逻辑
    数据流图：添加带类别边（df_add_edge_kind）（源节点 ID（from_id），目标节点 ID（to_id），0）
### 测试要点
1. 等价于调用 df_add_edge_kind 且类别为 0

## 函数 数据流图：连接状态边（df_connect_state）
### 作用
维护 VSDG 状态链：对于有副作用的操作（存储、非纯函数调用），在它和上一个有副作用的节点之间创建一条状态边（kind=1），然后更新状态链尾节点。对于无副作用的操作不做处理。未知/外部函数被保守地视为有副作用。
### 逻辑
    令 是否副作用（is_side_effect） = 0（可变）
    如果 操作码（opcode） 等于 IR 存储（IR_STORE），那么：令 是否副作用 = 1
    如果 操作码（opcode） 等于 IR 存储字段（IR_STORE_FIELD），那么：令 是否副作用 = 1
    如果 操作码（opcode） 等于 IR 存储索引（IR_STORE_INDEX），那么：令 是否副作用 = 1
    如果 操作码（opcode） 等于 IR 可变索引存储（IR_STORE_INDEX_VAR），那么：令 是否副作用 = 1
    如果 操作码（opcode） 等于 IR 调用（IR_CALL），那么：
        令 被调用函数索引（cfi） = 查找函数（find_func）（源操作数3（s3））
        如果 被调用函数索引（cfi） 小于 0，那么：令 是否副作用 = 1
        否则如果 函数信息访问器：是否纯净（fi_ispure）（被调用函数索引（cfi）） 等于 0，那么：令 是否副作用 = 1
    如果 是否副作用 不等于 0，那么：
        如果 最后一个状态节点（g_last_state_node） 不小于 0，那么：数据流图：添加带类别边（df_add_edge_kind）（最后一个状态节点（g_last_state_node），节点 ID（node_id），1）
        令 最后一个状态节点（g_last_state_node） = 节点 ID（node_id）
### 测试要点
1. 同一函数内连续两条存储指令：第二条有一条来自第一条的状态边
2. 纯函数调用（fi_ispure 返回非零）不产生状态边，不推进状态链
3. 未知函数（find_func 返回负数）保守视为有副作用，产生状态边
4. 函数内首条副作用指令不创建状态边（因为 g_last_state_node = -1），但将自身设为链尾
5. 无副作用指令（如算术运算、加载）不产生状态边，不改变状态链

## 函数 数据流图：使用变量（df_use_var）
### 作用
将消费者节点连接到变量（var_idx）的生产者节点。如果该变量有生产者（g_df_var_producer[var_idx] >= 0），则创建一条从生产者到消费者的数据边。调用方需确保数组容量足够（若 var_idx 超过容量则触发扩展）。
### 逻辑
    如果 变量索引（var_idx） 小于 0，那么：返回
    如果 变量索引（var_idx） 不小于 数据流图数组容量（g_df_cap），那么：扩展数据流数组（grow_df_arrays）（变量索引（var_idx） + 1）
    令 生产者节点（producer） = 读 64 位（r64）（变量生产者节点映射（g_df_var_producer），变量索引（var_idx） * 8）
    如果 生产者节点（producer） 不小于 0，那么：
        数据流图：添加边（df_add_edge）（生产者节点（producer），消费者节点（consumer_node））
### 测试要点
1. 变量索引（var_idx）为负数时直接返回
2. 变量无生产者（g_df_var_producer[var_idx] = -1）时不创建边
3. 变量索引超过当前数组容量时正确触发数组扩展
4. 变量有生产者时正确创建定义-使用边

## 函数 数据流图：连接源操作数（df_connect_srcs）
### 作用
根据操作码（opcode）的语义，将节点与其源操作数中的 IR 变量连接起来。不同的操作码有不同的源操作数布局：部分源字段是立即数/标签而非变量，不创建数据流边。该函数是数据流图中定义-使用边的主要构建点。
### 逻辑
    如果 操作码（opcode） 等于 IR 常量（IR_CONST），那么：返回
    如果 操作码（opcode） 等于 IR 二元运算（IR_BINARY），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数2（s2））
        返回
    如果 操作码（opcode） 等于 IR 一元运算（IR_UNARY），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        返回
    如果 操作码（opcode） 等于 IR 调用（IR_CALL） 或 操作码（opcode） 等于 IR 派生（IR_SPAWN），那么：
        令 参数计数（ac） = 0（可变）
        循环（当 参数计数 小于 源操作数2（s2） 时）：
            数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1） + 参数计数）
            令 参数计数 = 参数计数 + 1
        返回
    如果 操作码（opcode） 等于 IR 外部调用（IR_CALL_EXTERN），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数2（s2））
        返回
    如果 操作码（opcode） 等于 IR 返回（IR_RETURN），那么：
        如果 源操作数1（s1） 不小于 0，那么：数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        返回
    如果 操作码（opcode） 等于 IR 存储（IR_STORE），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数2（s2））
        返回
    如果 操作码（opcode） 等于 IR 加载（IR_LOAD），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        返回
    如果 操作码（opcode） 等于 IR 加载字段（IR_LOAD_FIELD），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        返回
    如果 操作码（opcode） 等于 IR 存储字段（IR_STORE_FIELD），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数2（s2））
        返回
    如果 操作码（opcode） 等于 IR 加载索引（IR_LOAD_INDEX），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        返回
    如果 操作码（opcode） 等于 IR 存储索引（IR_STORE_INDEX），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数2（s2））
        返回
    如果 操作码（opcode） 等于 IR 可变索引加载（IR_LOAD_INDEX_VAR），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数2（s2））
        返回
    如果 操作码（opcode） 等于 IR 可变索引存储（IR_STORE_INDEX_VAR），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数2（s2））
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数3（s3））
        返回
    如果 操作码（opcode） 等于 IR 分支（IR_BRANCH），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        返回
    如果 操作码（opcode） 等于 IR 引用（IR_REF），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        返回
    如果 操作码（opcode） 等于 IR 解引用（IR_DEREF），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        返回
    如果 操作码（opcode） 等于 IR 构造枚举（IR_MAKE_ENUM），那么：返回
    如果 操作码（opcode） 等于 IR 切片（IR_SLICE），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数2（s2））
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数3（s3））
        返回
    如果 操作码（opcode） 等于 IR 指针存储（IR_STORE_PTR），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数2（s2））
        返回
    如果 操作码（opcode） 等于 IR 加载枚举标签（IR_LOAD_ENUM_TAG），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））
        返回
    如果 操作码（opcode） 等于 IR 新建竞技场（IR_ARENA_NEW），那么：数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））；返回
    如果 操作码（opcode） 等于 IR 重置竞技场（IR_ARENA_RESET），那么：数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））；返回
    如果 操作码（opcode） 等于 IR 内联（IR_INLINE），那么：数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））；返回
    如果 操作码（opcode） 等于 IR 热补丁路由（IR_HOTPATCH_ROUTE），那么：
        数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数2（s2））
        返回
    如果 操作码（opcode） 等于 IR 动态标签（IR_DYN_TAG），那么：数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））；返回
    如果 操作码（opcode） 等于 IR 动态值（IR_DYN_VAL），那么：数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））；返回
    如果 操作码（opcode） 等于 IR 动态打包（IR_DYN_PACK），那么：数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））；返回
    如果 操作码（opcode） 等于 IR 动态分发（IR_DYN_DISPATCH），那么：数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））；返回
    如果 操作码（opcode） 等于 IR 惰性求值块（IR_LAZY_THUNK），那么：数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））；返回
    如果 操作码（opcode） 等于 IR 惰性求值强制（IR_LAZY_FORCE），那么：数据流图：使用变量（df_use_var）（节点 ID（node_id），源操作数1（s1））；返回
    （其他操作码 LABEL, JUMP, ALLOC, ALLOC_STRUCT, ALLOC_ARRAY, PHI 不追踪变量输入）
### 测试要点
1. IR 常量（IR_CONST）不创建任何数据流边
2. IR 调用（IR_CALL）的参数个数由源操作数2（s2）指定，循环连接 s1 到 s1 + s2 - 1 范围内的变量
3. IR 返回（IR_RETURN）仅在源操作数1（s1）不为负数时连接返回值变量
4. 无变量输入的操作（LABEL、JUMP、ALLOC 等）正确跳过
5. 未列出的新操作码不会创建边（安全的默认行为）

## 函数 扩展变量使用计数数组（grow_var_use_count）
### 作用
动态扩展变量使用计数数组（g_var_use_count）的容量。采用两倍增长策略，最小容量为 128，确保数组足够容纳指定的索引。
### 逻辑
    如果 所需容量（needed） 小于 变量使用计数容量（g_var_use_count_cap），那么：返回
    令 新容量（nc） = 变量使用计数容量（g_var_use_count_cap） * 2（可变）
    如果 新容量（nc） 小于 128，那么：令 新容量（nc） = 128
    如果 新容量（nc） 小于 所需容量（needed），那么：令 新容量（nc） = 所需容量（needed） + 128
    令 新数组（nb） = 分配（alloc）（新容量（nc） * 8）
    内部：动态拷贝（_dyncpy）（变量使用计数数组（g_var_use_count），变量使用计数容量（g_var_use_count_cap） * 8，新数组（nb））
    令 变量使用计数数组（g_var_use_count） = 新数组（nb）
    令 变量使用计数容量（g_var_use_count_cap） = 新容量（nc）
### 测试要点
1. 所需容量小于当前容量时不进行扩展
2. 首次分配时（原容量为 0），最小分配 128 个槽位
3. 所需容量大于两倍当前容量时，分配 所需容量 + 128

## 函数 计算变量使用次数（compute_usage_counts）
### 作用
遍历所有数据流边，对每条非状态边（kind != 0 的边），统计其源节点的目标变量（dest）被使用的次数，记录到变量使用计数数组（g_var_use_count）中。状态边（kind != 0）不参与使用计数（它们不是数据消费者）。
### 逻辑
    令 边索引（ei） = 0（可变）
    循环（当 边索引 小于 数据流边计数（g_df_edge_count） 时）：
        如果 读 64 位（r64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 偏移\_DFE\_类别（OFF_DFE_KIND）） 不等于 0，那么：
            令 边索引 = 边索引 + 1
            继续下一次循环
        令 源节点 ID（from_id） = 读 64 位（r64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 偏移\_DFE\_源节点（OFF_DFE_FROM））
        令 目标变量（dest） = 读 64 位（r64）（数据流节点数组（g_df_nodes），源节点 ID * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_目标（OFF_DF_DEST））
        如果 目标变量（dest） 不小于 0，那么：
            扩展变量使用计数数组（grow_var_use_count）（目标变量（dest） + 1）
            令 之前计数（prev） = 读 64 位（r64）（变量使用计数数组（g_var_use_count），目标变量（dest） * 8）
            写 64 位（w64）（变量使用计数数组（g_var_use_count），目标变量（dest） * 8，之前计数（prev） + 1）
        令 边索引 = 边索引 + 1
### 测试要点
1. 状态边（kind != 0）不参与使用计数
2. 目标变量为 -1（无输出变量）时不统计
3. 同一变量被多条边使用时计数正确累加
4. 边计数为 0 时循环体不执行，不崩溃

## 函数 降为线性 IR（lower_to_ccr）
### 作用
将数据流图中的节点按创建顺序（即 AST 遍历顺序，已是有效的拓扑排序）线性化到 IR 指令数组（g_ir_instrs）中，重置 IR 指令计数后逐一拷贝节点的操作码、目标变量、源操作数和类型类别。完成后更新每个函数的指令起始/计数以匹配新的 IR 指令数组布局，并调用计算变量使用次数（compute_usage_counts）供后续优化 pass 使用。
### 逻辑
    令 IR 指令总数（g_ir_instr_count） = 0
    令 节点索引（ni） = 0（可变）
    循环（当 节点索引 小于 数据流节点计数（g_df_node_count） 时）：
        令 指令索引（idx） = IR 指令总数（g_ir_instr_count）
        扩展 IR 指令数组（grow_ir_instrs）（指令索引 + 1）
        IR 指令访问器：设置操作码（iri_set_op）（指令索引，读 64 位（r64）（数据流节点数组（g_df_nodes），节点索引 * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_操作码（OFF_DF_OPCODE）））
        IR 指令访问器：设置目标（iri_set_dest）（指令索引，读 64 位（r64）（数据流节点数组（g_df_nodes），节点索引 * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_目标（OFF_DF_DEST）））
        IR 指令访问器：设置操作数1（iri_set_s1）（指令索引，读 64 位（r64）（数据流节点数组（g_df_nodes），节点索引 * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_源1（OFF_DF_S1）））
        IR 指令访问器：设置操作数2（iri_set_s2）（指令索引，读 64 位（r64）（数据流节点数组（g_df_nodes），节点索引 * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_源2（OFF_DF_S2）））
        IR 指令访问器：设置操作数3（iri_set_s3）（指令索引，读 64 位（r64）（数据流节点数组（g_df_nodes），节点索引 * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_源3（OFF_DF_S3）））
        IR 指令访问器：设置类型类别（iri_set_tk）（指令索引，读 64 位（r64）（数据流节点数组（g_df_nodes），节点索引 * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_类型类别（OFF_DF_TK）））
        令 IR 指令总数（g_ir_instr_count） = 指令索引 + 1
        令 节点索引 = 节点索引 + 1
    令 函数索引（fi） = 0（可变）
    循环（当 函数索引 小于 IR 函数个数（g_ir_func_count） 时）：
        写 64 位（w64）（IR 函数指令起始索引数组（g_ir_func_instr_start），函数索引 * 8，读 64 位（r64）（数据流图各函数节点起始索引（g_df_func_node_start），函数索引 * 8））
        写 64 位（w64）（IR 函数指令计数数组（g_ir_func_instr_count），函数索引 * 8，读 64 位（r64）（数据流图各函数节点计数（g_df_func_node_count），函数索引 * 8））
        令 函数索引 = 函数索引 + 1
    计算变量使用次数（compute_usage_counts）（）
### 测试要点
1. 数据流节点计数（g_df_node_count）为 0 时，IR 指令总数（g_ir_instr_count）保持 0，后续循环不执行
2. 节点索引 n 映射到指令索引 n（一对一映射），确保函数边界在 df 和 ir 之间一致
3. 函数计数（g_ir_func_count）为 0 时，第二个循环不执行（不崩溃）
4. 降级后的 IR 指令数组全部字段与数据流节点一致（操作码、目标、源操作数、类型类别）

## 函数 数据流图：开始函数（df_begin_func）
### 作用
在数据流图中标记一个函数的起始边界：记录当前节点计数作为该函数的起始节点位置，为该函数压入一个结构图\_函数（SG_FUNC）region，并重置 VSDG 状态链（每个函数的状态链独立）。
### 逻辑
    如果 函数索引（func_idx） 不小于 0，那么：
        扩展数据流数组（grow_df_arrays）（函数索引 + 1）
        写 64 位（w64）（数据流图各函数节点起始索引（g_df_func_node_start），函数索引 * 8，数据流节点计数（g_df_node_count））
        压入结构图（sg_push）（结构图\_函数（SG_FUNC））
    令 最后一个状态节点（g_last_state_node） = -1
### 测试要点
1. 函数索引为负数时不记录起始位置也不压入 region
2. 函数索引为 0（第一个函数）时起始节点位置正确等于当前节点数
3. 状态链重置为 -1，确保函数间副作用不跨函数连接

## 函数 数据流图：结束函数（df_end_func）
### 作用
在数据流图中标记一个函数的结束边界：计算该函数的节点计数（当前节点数减去起始位置），然后弹出对应的结构图\_函数（SG_FUNC）region。
### 逻辑
    如果 函数索引（func_idx） 不小于 0，那么：
        令 起始位置（start） = 读 64 位（r64）（数据流图各函数节点起始索引（g_df_func_node_start），函数索引 * 8）
        写 64 位（w64）（数据流图各函数节点计数（g_df_func_node_count），函数索引 * 8，数据流节点计数（g_df_node_count） - 起始位置（start））
        弹出结构图（sg_pop）（）
### 测试要点
1. 函数索引为负数时不执行任何操作
2. 函数索引对应的起始位置和当前节点计数正确计算出节点数
3. 弹出 region 后当前结构图索引（g_cur_sg）恢复到父级

## 函数 数据流图：导出 DOT（df_graph_to_dot）
### 作用
将整个数据流图导出为 Graphviz DOT 格式的字符串。输出包括：region 子图簇（每个结构图一个 DOT cluster，含节点列表）、节点定义（操作码名加上变量名作为标签）、边定义（状态边用红色虚线以突出顺序约束）。用于调试可视化数据流图的结构。
### 逻辑
    令 DOT 字符串（dot） = "digraph G {\n"（可变）
    令 DOT 字符串（dot） = DOT 字符串（dot） + "    rankdir=TB;\n"
    令 结构图索引（si） = 0（可变）
    循环（当 结构图索引 小于 结构图计数（g_sg_count） 时）：
        令 结构图类别（skind） = 读 64 位（r64）（结构图数组（g_sgs），结构图索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_类别（OFF_SG_KIND））
        令 结构图名称（sname） = "region"（可变）
        如果 结构图类别（skind） 等于 结构图\_IF（SG_IF），那么：令 结构图名称（sname） = "if"
        如果 结构图类别（skind） 等于 结构图\_循环（SG_LOOP），那么：令 结构图名称（sname） = "loop"
        如果 结构图类别（skind） 等于 结构图\_FOR（SG_FOR），那么：令 结构图名称（sname） = "for"
        如果 结构图类别（skind） 等于 结构图\_FLOW（SG_FLOW），那么：令 结构图名称（sname） = "flow"
        如果 结构图类别（skind） 等于 结构图\_不安全（SG_UNSAFE），那么：令 结构图名称（sname） = "unsafe"
        令 DOT 字符串（dot） = DOT 字符串（dot） + "  subgraph cluster_" + 结构图名称（sname） + 整数转字符串（int_str）（结构图索引） + " { label=\"" + 结构图名称（sname） + "\";\n"
        令 节点起始（n0） = 读 64 位（r64）（结构图数组（g_sgs），结构图索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_节点起始（OFF_SG_NSTART））
        令 节点结束（n1） = 读 64 位（r64）（结构图数组（g_sgs），结构图索引 * 结构图条目大小（ESZ_SG） + 偏移\_SG\_出口（OFF_SG_EXIT））
        如果 节点结束（n1） 不小于 0，那么：
            令 节点遍历索引（ni） = 节点起始（n0）（可变）
            循环（当 节点遍历索引 小于 节点结束（n1） 时）：
                令 DOT 字符串（dot） = DOT 字符串（dot） + "    n" + 整数转字符串（int_str）（节点遍历索引） + ";\n"
                令 节点遍历索引 = 节点遍历索引 + 1
        令 DOT 字符串（dot） = DOT 字符串（dot） + "  }\n"
        令 结构图索引 = 结构图索引 + 1
    令 节点索引（ni） = 0（可变）
    循环（当 节点索引 小于 数据流节点计数（g_df_node_count） 时）：
        令 节点操作码（n_op） = 读 64 位（r64）（数据流节点数组（g_df_nodes），节点索引 * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_操作码（OFF_DF_OPCODE））
        令 节点目标变量（n_dest） = 读 64 位（r64）（数据流节点数组（g_df_nodes），节点索引 * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_目标（OFF_DF_DEST））
        令 节点源3（n_s3） = 读 64 位（r64）（数据流节点数组（g_df_nodes），节点索引 * 数据流节点条目大小（ESZ_DFNODE） + 偏移\_DF\_源3（OFF_DF_S3））
        令 标签（label） = 数据流图：操作码名称（df_opcode_name）（节点操作码（n_op），节点源3（n_s3））（可变）
        如果 节点目标变量（n_dest） 不小于 0，那么：
            令 变量名（vname） = 获取 IR 变量名（get_ir_var_name）（节点目标变量（n_dest））
            如果 字符串长度（str_len）（变量名（vname）） 大于 0，那么：
                令 标签（label） = 变量名（vname） + ":" + 标签（label）
        令 DOT 字符串（dot） = DOT 字符串（dot） + "    n" + 整数转字符串（int_str）（节点索引） + " [label=\"" + 标签（label） + "\", shape=box];\n"
        令 节点索引 = 节点索引 + 1
    令 边索引（ei） = 0（可变）
    循环（当 边索引 小于 数据流边计数（g_df_edge_count） 时）：
        令 边源节点（e_from） = 读 64 位（r64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 偏移\_DFE\_源节点（OFF_DFE_FROM））
        令 边目标节点（e_to） = 读 64 位（r64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 偏移\_DFE\_目标节点（OFF_DFE_TO））
        如果 读 64 位（r64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 偏移\_DFE\_类别（OFF_DFE_KIND）） 不等于 0，那么：
            令 DOT 字符串（dot） = DOT 字符串（dot） + "    n" + 整数转字符串（int_str）（边源节点（e_from）） + " -> n" + 整数转字符串（int_str）（边目标节点（e_to）） + " [style=dashed,color=red];\n"
        否则：
            令 DOT 字符串（dot） = DOT 字符串（dot） + "    n" + 整数转字符串（int_str）（边源节点（e_from）） + " -> n" + 整数转字符串（int_str）（边目标节点（e_to）） + ";\n"
        令 边索引 = 边索引 + 1
    令 DOT 字符串（dot） = DOT 字符串（dot） + "}\n"
    返回 DOT 字符串（dot）
### 测试要点
1. 空图（节点计数和边计数均为 0）时输出合法的空 DOT 图
2. 未关闭的 region（出口为 -1）不包含节点列表（跳过该 cluster 的节点输出）
3. 函数 region（SG_FUNC）的 cluster 名称正确显示
4. 状态边（kind != 0）输出为红色虚线，数据边为实线
5. 有名称的变量在节点标签中显示为"变量名:操作码"格式

## 函数 数据流图：操作码名称（df_opcode_name）
### 作用
将 IR 操作码整数转换为可读的字符串名称。对于 IR 二元运算（IR_BINARY），根据源操作数3（s3）中的子操作码（如指针加/减/差）返回更具体的名称。未识别的操作码返回 "?"。
### 逻辑
    如果 操作码（opcode） 等于 IR 常量（IR_CONST），那么：返回 "const"
    如果 操作码（opcode） 等于 IR 二元运算（IR_BINARY），那么：
        如果 源操作数3（s3） 等于 OP 指针加（OP_PTR_ADD），那么：返回 "ptr_add"
        如果 源操作数3（s3） 等于 OP 指针减（OP_PTR_SUB），那么：返回 "ptr_sub"
        如果 源操作数3（s3） 等于 OP 指针差（OP_PTR_DIFF），那么：返回 "ptr_diff"
        返回 "binary"
    如果 操作码（opcode） 等于 IR 一元运算（IR_UNARY），那么：返回 "unary"
    如果 操作码（opcode） 等于 IR 调用（IR_CALL），那么：返回 "call"
    如果 操作码（opcode） 等于 IR 返回（IR_RETURN），那么：返回 "return"
    如果 操作码（opcode） 等于 IR 分配（IR_ALLOC），那么：返回 "alloc"
    如果 操作码（opcode） 等于 IR 分配结构体（IR_ALLOC_STRUCT），那么：返回 "alloc_struct"
    如果 操作码（opcode） 等于 IR 分配数组（IR_ALLOC_ARRAY），那么：返回 "alloc_array"
    如果 操作码（opcode） 等于 IR 存储（IR_STORE），那么：返回 "store"
    如果 操作码（opcode） 等于 IR 加载（IR_LOAD），那么：返回 "load"
    如果 操作码（opcode） 等于 IR 加载字段（IR_LOAD_FIELD），那么：返回 "load_field"
    如果 操作码（opcode） 等于 IR 存储字段（IR_STORE_FIELD），那么：返回 "store_field"
    如果 操作码（opcode） 等于 IR 加载索引（IR_LOAD_INDEX），那么：返回 "load_index"
    如果 操作码（opcode） 等于 IR 存储索引（IR_STORE_INDEX），那么：返回 "store_index"
    如果 操作码（opcode） 等于 IR 可变索引加载（IR_LOAD_INDEX_VAR），那么：返回 "load_index_var"
    如果 操作码（opcode） 等于 IR 可变索引存储（IR_STORE_INDEX_VAR），那么：返回 "store_index_var"
    如果 操作码（opcode） 等于 IR 构造枚举（IR_MAKE_ENUM），那么：返回 "make_enum"
    如果 操作码（opcode） 等于 IR 引用（IR_REF），那么：返回 "ref"
    如果 操作码（opcode） 等于 IR 分支（IR_BRANCH），那么：返回 "branch"
    如果 操作码（opcode） 等于 IR 跳转（IR_JUMP），那么：返回 "jump"
    如果 操作码（opcode） 等于 IR 标签（IR_LABEL），那么：返回 "label"
    如果 操作码（opcode） 等于 IR PHI（IR_PHI），那么：返回 "phi"
    如果 操作码（opcode） 等于 IR 加载枚举标签（IR_LOAD_ENUM_TAG），那么：返回 "load_enum_tag"
    如果 操作码（opcode） 等于 IR 切片（IR_SLICE），那么：返回 "slice"
    如果 操作码（opcode） 等于 IR 解引用（IR_DEREF），那么：返回 "deref"
    如果 操作码（opcode） 等于 IR 指针存储（IR_STORE_PTR），那么：返回 "store_ptr"
    如果 操作码（opcode） 等于 IR 派生（IR_SPAWN），那么：返回 "spawn"
    如果 操作码（opcode） 等于 IR 让出（IR_YIELD），那么：返回 "yield"
    如果 操作码（opcode） 等于 IR 函数地址（IR_FNADDR），那么：返回 "fnaddr"
    如果 操作码（opcode） 等于 IR 新建竞技场（IR_ARENA_NEW），那么：返回 "arena_new"
    如果 操作码（opcode） 等于 IR 重置竞技场（IR_ARENA_RESET），那么：返回 "arena_reset"
    如果 操作码（opcode） 等于 IR 内联（IR_INLINE），那么：返回 "inline"
    如果 操作码（opcode） 等于 IR 无边界检查（IR_NO_BOUNDS_CHECK），那么：返回 "no_bounds_check"
    如果 操作码（opcode） 等于 IR 快速（IR_FAST），那么：返回 "fast"
    如果 操作码（opcode） 等于 IR 展开（IR_UNROLL），那么：返回 "unroll"
    如果 操作码（opcode） 等于 IR 段（IR_SECTION），那么：返回 "section"
    如果 操作码（opcode） 等于 IR 热补丁路由（IR_HOTPATCH_ROUTE），那么：返回 "hotpatch_route"
    如果 操作码（opcode） 等于 IR 动态标签（IR_DYN_TAG），那么：返回 "dyn_tag"
    如果 操作码（opcode） 等于 IR 动态值（IR_DYN_VAL），那么：返回 "dyn_val"
    如果 操作码（opcode） 等于 IR 动态打包（IR_DYN_PACK），那么：返回 "dyn_pack"
    如果 操作码（opcode） 等于 IR 动态分发（IR_DYN_DISPATCH），那么：返回 "dyn_dispatch"
    如果 操作码（opcode） 等于 IR 外部调用（IR_CALL_EXTERN），那么：返回 "call_extern"
    如果 操作码（opcode） 等于 IR 惰性求值块（IR_LAZY_THUNK），那么：返回 "lazy_thunk"
    如果 操作码（opcode） 等于 IR 惰性求值强制（IR_LAZY_FORCE），那么：返回 "lazy_force"
    返回 "?"
### 测试要点
1. 所有已知操作码都返回正确的字符串名称
2. IR 二元运算（IR_BINARY）的指针运算子操作码（OP_PTR_ADD、OP_PTR_SUB、OP_PTR_DIFF）返回对应名称
3. 未知操作码返回 "?"，不会崩溃
4. 源操作数3（s3）仅对 IR 二元运算有意义，对其他操作码无影响
