# cir_cache.cr 伪代码
> 源文件：src/compiler/cir_cache.cr（314 行）
> 功能概要：增量编译缓存系统——按函数粒度将 HDFG（DFG）状态（节点、边、IR 指令、IR 变量、字符串常量）序列化到 .HDFG（cir） 缓存文件中，并在后续编译中通过指纹（函数体哈希 + 签名指纹哈希）验证后直接恢复，跳过重复的类型检查和 IR 生成。v5 格式中边以 4 个 8 字节（kind）存储，使状态边（种类）在缓存命中后完整恢复。

## 标识符对照表
| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 保存 CIR 缓存 | save_cir_cache | 保存 CIR 缓存 |
| 写 64 位（CIR 缓存） | w64_cir | 写 64 位（CIR 缓存） |
| 写单字节（CIR 缓存） | w8_cir | 写单字节（CIR 缓存） |
| 写入文件描述符 | write_fd | 写入文件描述符 |
| 加载 CIR 缓存 | load_cir_cache | 加载 CIR 缓存 |
| 创建 CIR 缓存目录 | make_cir_cache_dir | 创建 CIR 缓存目录 |
| 函数指纹 | func_fingerprint | 保存 CIR 缓存 |
| 签名指纹 | sig_fingerprint | 保存 CIR 缓存 |
| 驻留字符串获取 | istr_get | 保存 CIR 缓存 |
| 字符串长度 | str_len | 保存 CIR 缓存 |
| 字符串切片 | str_sub | 加载 CIR 缓存 |
| 字符串驻留 | str_intern | 加载 CIR 缓存 |
| 函数信息访问器：AST 节点 | fi_ast_node | 保存 CIR 缓存 |
| IR 变量访问器：名称 | irv_name | 保存 CIR 缓存 |
| IR 变量访问器：ID | irv_id | 保存 CIR 缓存 |
| IR 变量访问器：类型 | irv_type | 保存 CIR 缓存 |
| IR 变量访问器：设置名称 | irv_set_name | 加载 CIR 缓存 |
| IR 变量访问器：设置ID | irv_set_id | 加载 CIR 缓存 |
| IR 变量访问器：设置类型 | irv_set_type | 加载 CIR 缓存 |
| IR 指令访问器：操作码 | iri_op | 保存 CIR 缓存 |
| IR 指令访问器：目标 | iri_dest | 保存 CIR 缓存 |
| IR 指令访问器：操作数1 | iri_s1 | 保存 CIR 缓存 |
| IR 指令访问器：操作数2 | iri_s2 | 保存 CIR 缓存 |
| IR 指令访问器：操作数3 | iri_s3 | 保存 CIR 缓存 |
| IR 指令访问器：类型类别 | iri_tk | 保存 CIR 缓存 |
| IR 指令访问器：设置操作码 | iri_set_op | 加载 CIR 缓存 |
| IR 指令访问器：设置目标 | iri_set_dest | 加载 CIR 缓存 |
| IR 指令访问器：设置操作数1 | iri_set_s1 | 加载 CIR 缓存 |
| IR 指令访问器：设置操作数2 | iri_set_s2 | 加载 CIR 缓存 |
| IR 指令访问器：设置操作数3 | iri_set_s3 | 加载 CIR 缓存 |
| IR 指令访问器：设置类型类别 | iri_set_tk | 加载 CIR 缓存 |
| 追踪字符串常量 | track_str | 加载 CIR 缓存 |
| 读取文件 | read_file | 加载 CIR 缓存 |
| 分配 | alloc | 保存 CIR 缓存 |
| 写 64 位 | w64 | 写 64 位（CIR 缓存） |
| 读 64 位 | r64 | 加载 CIR 缓存 |
| 写单字节字节存储 | store8 | 写单字节（CIR 缓存） |
| 无符号单字节读取 | load8 | 保存 CIR 缓存 |
| 系统调用3 | syscall3 | 保存 CIR 缓存 |
| 扩展 IR 变量数组 | grow_ir_vars | 加载 CIR 缓存 |
| 扩展数据流节点数组 | grow_df_nodes | 加载 CIR 缓存 |
| 扩展数据流节点区域数组 | grow_df_node_region | 加载 CIR 缓存 |
| 扩展数据流边数组 | grow_df_edges | 加载 CIR 缓存 |
| 扩展 IR 指令数组 | grow_ir_instrs | 加载 CIR 缓存 |
| 扩展数据流数组 | grow_df_arrays | 加载 CIR 缓存 |
| CIR 写缓冲区 | g_cir_write_buf | （全局变量） |
| CIR 写缓冲区位置 | g_cir_write_pos | （全局变量） |
| CIR 写缓冲区容量 | g_cir_write_cap | （全局变量） |
| IR 函数名索引数组 | g_ir_func_name_idx | 保存 CIR 缓存 |
| IR 函数变量起始索引数组 | g_ir_func_var_start | 保存 CIR 缓存 |
| IR 函数变量计数数组 | g_ir_func_var_count | 保存 CIR 缓存 |
| IR 函数指令起始索引数组 | g_ir_func_instr_start | 保存 CIR 缓存 |
| IR 函数指令计数数组 | g_ir_func_instr_count | 保存 CIR 缓存 |
| HDFG各函数节点起始索引 | g_df_func_node_start | 保存 CIR 缓存 |
| HDFG各函数节点计数 | g_df_func_node_count | 保存 CIR 缓存 |
| 数据流节点计数 | g_df_node_count | 加载 CIR 缓存 |
| 数据流节点数组 | g_df_nodes | 保存 CIR 缓存 |
| 数据流边数组 | g_df_edges | 保存 CIR 缓存 |
| 数据流边计数 | g_df_edge_count | 保存 CIR 缓存 |
| 变量生产者节点映射 | g_df_var_producer | 加载 CIR 缓存 |
| 数据流节点所属 region | g_df_node_region | 加载 CIR 缓存 |
| 当前结构图索引 | g_cur_sg | 加载 CIR 缓存 |
| IR 变量总数 | g_ir_var_count | 加载 CIR 缓存 |
| IR 指令总数 | g_ir_instr_count | 加载 CIR 缓存 |
| IR 字符串常量计数 | g_ir_str_const_count | 保存 CIR 缓存 |
| IR 字符串常量数组 | g_ir_str_consts | 保存 CIR 缓存 |
| CIR 缓存魔数 | CIR_CACHE_MAGIC | （常量） |
| CIR 缓存版本 | CIR_CACHE_VER | （常量） |
| ESZ 数据流节点大小 | ESZ_DFNODE | （结构体常量） |
| ESZ 数据流边大小 | ESZ_DFEDGE | （结构体常量） |
| 数据流节点操作码偏移 | OFF_DF_OPCODE | （结构体字段偏移） |
| 数据流节点目标偏移 | OFF_DF_DEST | （结构体字段偏移） |
| 数据流节点源1偏移 | OFF_DF_S1 | （结构体字段偏移） |
| 数据流节点源2偏移 | OFF_DF_S2 | （结构体字段偏移） |
| 数据流节点源3偏移 | OFF_DF_S3 | （结构体字段偏移） |
| 数据流节点类型类别偏移 | OFF_DF_TK | （结构体字段偏移） |
| 数据流节点首边索引偏移 | OFF_DF_FIRST_EDGE | （结构体字段偏移） |
| 数据流节点边计数偏移 | OFF_DF_EDGE_COUNT | （结构体字段偏移） |
| 数据流边起点偏移 | OFF_DFE_FROM | （结构体字段偏移） |
| 数据流边终点偏移 | OFF_DFE_TO | （结构体字段偏移） |
| 数据流边下一边偏移 | OFF_DFE_NEXT | （结构体字段偏移） |
| 数据流边类别偏移 | OFF_DFE_KIND | （结构体字段偏移） |

## 全局状态
- **HDFG（CIR） 缓存魔数（CIR_CACHE_MAGIC）**：.HDFG（cir） 缓存文件标识 = 0xC1C1C1C1C1C1C1C1
- **HDFG（CIR） 缓存版本（CIR_CACHE_VER）**：当前缓存格式版本 = 5（v5：边序列化为 4 个 8 字节，含 from/to/next/种类（kind））
- **HDFG（CIR） 写缓冲区（g_cir_write_buf）**：序列化时使用的内存缓冲区（字符串，可变），延迟分配
- **HDFG（CIR） 写缓冲区位置（g_cir_write_pos）**：当前写入偏移量（可变）
- **HDFG（CIR） 写缓冲区容量（g_cir_write_cap）**：缓冲区当前分配的字节数（可变）

## 函数 保存 HDFG（CIR） 缓存（save_cir_cache）
### 作用
将一个函数的 HDFG（DFG）状态序列化保存到 .HDFG（cir） 缓存文件中。先打开/创建文件（O_WRONLY|O_CREAT|O_TRUNC），计算函数指纹和签名指纹，将头信息（魔数、版本、指纹）、变量表、节点表、边表（v5 格式含 种类（kind） 字段）、指令表、字符串常量逐一写入内存缓冲区，最后通过单次系统调用写入文件。缓冲区策略（先序列化到内存再一次性写入）避免逐个字段的 写入（write） 调用产生数百万次系统调用。
### 逻辑
    令 文件描述符（fd） = 系统调用3（syscall3）（2，路径（path），577，420）
    如果 文件描述符（fd） 小于 0，那么：返回 -1
    令 函数 AST 节点（fn_node） = 函数信息访问器：AST 节点（fi_ast_node）（func_idx）
    令 函数体指纹（fp） = 函数指纹（func_fingerprint）（fn_node）
    令 签名指纹（sig） = 签名指纹（sig_fingerprint）（fn_node）
    令 名称索引（name_ni） = 读 64 位（r64）（IR 函数名索引数组（g_ir_func_name_idx），函数索引 * 8）
    令 函数名（name） = 驻留字符串获取（istr_get）（name_ni）
    令 名称长度（name_len） = 字符串长度（str_len）（name）
    令 变量起始（var_start） = 读 64 位（r64）（IR 函数变量起始索引数组（g_ir_func_var_start），函数索引 * 8）
    令 变量计数（var_count） = 读 64 位（r64）（IR 函数变量计数数组（g_ir_func_var_count），函数索引 * 8）
    令 节点起始（node_start） = 读 64 位（r64）（HDFG各函数节点起始索引（g_df_func_node_start），函数索引 * 8）
    令 节点计数（node_count） = 读 64 位（r64）（HDFG各函数节点计数（g_df_func_node_count），函数索引 * 8）
    令 指令起始（instr_start） = 读 64 位（r64）（IR 函数指令起始索引数组（g_ir_func_instr_start），函数索引 * 8）
    令 指令计数（instr_count） = 读 64 位（r64）（IR 函数指令计数数组（g_ir_func_instr_count），函数索引 * 8）
    令 总大小（total_size） = 40 + 名称长度（name_len）（可变）
    令 总大小（total_size） = 总大小（total_size） + 8 + 变量计数（var_count） * 24
    令 总大小（total_size） = 总大小（total_size） + 8 + 节点计数（node_count） * 64
    令 总大小（total_size） = 总大小（total_size） + 8 + 数据流边计数（g_df_edge_count） * 32
    令 总大小（total_size） = 总大小（total_size） + 8 + 指令计数（instr_count） * 48
    令 总大小（total_size） = 总大小（total_size） + 8
    令 大小遍历索引（size_si） = 0（可变）
    循环（当 大小遍历索引 小于 IR 字符串常量计数（g_ir_str_const_count） 时）：
        令 常量名索引（size_ni） = 读 64 位（r64）（IR 字符串常量数组（g_ir_str_consts），大小遍历索引 * 8）
        令 总大小（total_size） = 总大小（total_size） + 8 + 字符串长度（str_len）（驻留字符串获取（istr_get）（size_ni））
        令 大小遍历索引 = 大小遍历索引 + 1
    如果 总大小（total_size） 大于 HDFG（CIR） 写缓冲区容量（g_cir_write_cap），那么：
        令 新容量（new_cap） = HDFG（CIR） 写缓冲区容量（g_cir_write_cap） * 2
        如果 新容量（new_cap） 小于 4096，那么：令 新容量（new_cap） = 4096
        如果 新容量（new_cap） 小于 总大小（total_size），那么：令 新容量（new_cap） = 总大小（total_size）
        令 HDFG（CIR） 写缓冲区（g_cir_write_buf） = 分配（alloc）（new_cap）
        令 HDFG（CIR） 写缓冲区容量（g_cir_write_cap） = 新容量（new_cap）
    令 HDFG（CIR） 写缓冲区位置（g_cir_write_pos） = 0
    写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），HDFG 缓存魔数（CIR_CACHE_MAGIC））
    写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），HDFG 缓存版本（CIR_CACHE_VER））
    写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），函数体指纹（fp））
    写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），签名指纹（sig））
    写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），名称长度（name_len））
    写入文件描述符（write_fd）（文件描述符（fd），函数名（name），名称长度（name_len））
    写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），变量计数（var_count））
    令 变量索引（vi） = 0（可变）
    循环（当 变量索引 小于 变量计数（var_count） 时）：
        令 变量全局索引（v_idx） = 变量起始（var_start） + 变量索引
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），IR 变量访问器：名称（irv_name）（v_idx））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），IR 变量访问器：ID（irv_id）（v_idx））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），IR 变量访问器：类型（irv_type）（v_idx））
        令 变量索引 = 变量索引 + 1
    写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），节点计数（node_count））
    令 节点遍历索引（ni2） = 0（可变）
    循环（当 节点遍历索引 小于 节点计数（node_count） 时）：
        令 节点全局索引（n） = 节点起始（node_start） + 节点遍历索引
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流节点数组（g_df_nodes），节点全局索引 * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点操作码偏移（OFF_DF_OPCODE）））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流节点数组（g_df_nodes），节点全局索引 * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点目标偏移（OFF_DF_DEST）））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流节点数组（g_df_nodes），节点全局索引 * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点源1偏移（OFF_DF_S1）））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流节点数组（g_df_nodes），节点全局索引 * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点源2偏移（OFF_DF_S2）））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流节点数组（g_df_nodes），节点全局索引 * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点源3偏移（OFF_DF_S3）））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流节点数组（g_df_nodes），节点全局索引 * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点类型类别偏移（OFF_DF_TK）））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流节点数组（g_df_nodes），节点全局索引 * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点首边索引偏移（OFF_DF_FIRST_EDGE）））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流节点数组（g_df_nodes），节点全局索引 * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点边计数偏移（OFF_DF_EDGE_COUNT）））
        令 节点遍历索引 = 节点遍历索引 + 1
    写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），数据流边计数（g_df_edge_count））
    令 边索引（ei） = 0（可变）
    循环（当 边索引 小于 数据流边计数（g_df_edge_count） 时）：
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 数据流边起点偏移（OFF_DFE_FROM）））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 数据流边终点偏移（OFF_DFE_TO）））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 数据流边下一边偏移（OFF_DFE_NEXT）））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），读 64 位（r64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 数据流边类别偏移（OFF_DFE_KIND）））
        令 边索引 = 边索引 + 1
    写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），指令计数（instr_count））
    令 指令索引（ii） = 0（可变）
    循环（当 指令索引 小于 指令计数（instr_count） 时）：
        令 指令全局索引（inst） = 指令起始（instr_start） + 指令索引
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），IR 指令访问器：操作码（iri_op）（inst））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），IR 指令访问器：目标（iri_dest）（inst））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），IR 指令访问器：操作数1（iri_s1）（inst））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），IR 指令访问器：操作数2（iri_s2）（inst））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），IR 指令访问器：操作数3（iri_s3）（inst））
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），IR 指令访问器：类型类别（iri_tk）（inst））
        令 指令索引 = 指令索引 + 1
    写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），IR 字符串常量计数（g_ir_str_const_count））
    令 字符串索引（si） = 0（可变）
    循环（当 字符串索引 小于 IR 字符串常量计数（g_ir_str_const_count） 时）：
        令 常量名索引（ni3） = 读 64 位（r64）（IR 字符串常量数组（g_ir_str_consts），字符串索引 * 8）
        令 常量字符串（s） = 驻留字符串获取（istr_get）（ni3）
        令 字符串长度（sl） = 字符串长度（str_len）（s）
        写 64 位（HDFG（CIR） 缓存）（w64_cir）（文件描述符（fd），字符串长度（sl））
        令 变量索引（vi） = 0
        循环（当 变量索引 小于 字符串长度（sl） 时）：
            写单字节（HDFG（CIR） 缓存）（w8_cir）（文件描述符（fd），无符号单字节读取（load8）（常量字符串（s），变量索引））
            令 变量索引 = 变量索引 + 1
        令 字符串索引 = 字符串索引 + 1
    令 已写入（written） = 系统调用3（syscall3）（1，文件描述符（fd），HDFG（CIR） 写缓冲区（g_cir_write_buf），HDFG 写缓冲区位置（g_cir_write_pos））
    系统调用3（syscall3）（3，文件描述符（fd），0，0）
    如果 已写入（written） 不等于 HDFG（CIR） 写缓冲区位置（g_cir_write_pos），那么：返回 -1
    返回 0
### 测试要点
1. 文件无法创建时（open 返回负数）返回 -1
2. 缓冲区容量不足时正确扩展（最小 4096 字节）
3. 写入字节数不匹配时返回 -1
4. 空函数（变量、节点、指令、边计数均为 0）仍能正确写出底层结构（头 + 计数为 0 的各段）
5. 边的 种类（kind） 字段被正确序列化（v5 要求），使状态边信息不丢失
6. 节点计数字段和首边索引字段被序列化，使缓存恢复后可重建边链表结构

## 函数 写 64 位（HDFG（CIR） 缓存）（w64_cir）
### 作用
将一个 64 位整数写入序列化缓冲区（g_cir_write_buf）的当前位置，然后将写位置前进 8 字节。文件描述符（fd） 参数被保留以兼容旧接口但未使用。
### 逻辑
    写 64 位（w64）（HDFG（CIR） 写缓冲区（g_cir_write_buf），HDFG 写缓冲区位置（g_cir_write_pos），值（val））
    令 HDFG（CIR） 写缓冲区位置（g_cir_write_pos） = HDFG 写缓冲区位置（g_cir_write_pos） + 8
### 测试要点
1. 连续写入多个值后，写位置正确累加（每次 + 8）
2. 写入值可随后用 读 64 位（r64） 在同一位置读回且一致

## 函数 写单字节（HDFG（CIR） 缓存）（w8_cir）
### 作用
将一个字节写入序列化缓冲区的当前位置，然后将写位置前进 1 字节。
### 逻辑
    写单字节字节存储（store8）（HDFG（CIR） 写缓冲区（g_cir_write_buf），HDFG 写缓冲区位置（g_cir_write_pos），值（val））
    令 HDFG（CIR） 写缓冲区位置（g_cir_write_pos） = HDFG 写缓冲区位置（g_cir_write_pos） + 1
### 测试要点
1. 连续写入多个字节后，写位置正确累加（每次 + 1）
2. 和 写 64 位（HDFG（CIR） 缓存）（w64_cir） 交替使用时写位置保持正确

## 函数 写入文件描述符（write_fd）
### 作用
将指定数据（data）的前 长度（len） 个字节拷贝到序列化缓冲区中。逐字节读取源数据并写入缓冲区，前进写位置。
### 逻辑
    令 写入位置（write_pos） = 0（可变）
    循环（当 写入位置 小于 长度（len） 时）：
        写单字节字节存储（store8）（HDFG（CIR） 写缓冲区（g_cir_write_buf），HDFG 写缓冲区位置（g_cir_write_pos），无符号单字节读取（load8）（数据（data），写入位置））
        令 HDFG（CIR） 写缓冲区位置（g_cir_write_pos） = HDFG 写缓冲区位置（g_cir_write_pos） + 1
        令 写入位置 = 写入位置 + 1
### 测试要点
1. 长度为 0 时不执行任何写入，写位置不变
2. 全量字节正确拷贝到缓冲区

## 函数 加载 HDFG（CIR） 缓存（load_cir_cache）
### 作用
从 .HDFG（cir） 缓存文件中恢复一个函数的 HDFG（DFG）状态。先读取整个文件到内存，验证魔数、版本（必须为 v5）、函数体指纹和签名指纹——若指纹与当前 AST 不匹配（函数体或签名已更改）则缓存失效，返回 -1。验证通过后，将缓存的变量、节点（含 节点（node）-region 映射和变量生产者映射）、边（kind）、指令和字符串常量逐一恢复到全局数组中。恢复后的节点直接追加到现有节点数组末尾（base_node），其第一边索引和边计数字段也被还原，无需重新计算边链表。
### 逻辑
    令 文件数据（data） = 读取文件（read_file）（path）
    如果 字符串长度（str_len）（data） 小于 48，那么：返回 -1
    令 位置（pos） = 0（可变）
    令 魔数（magic） = 读 64 位（r64）（文件数据（data），位置（pos））
    令 位置（pos） = 位置（位置） + 8
    如果 魔数（magic） 不等于 HDFG（CIR） 缓存魔数（CIR_CACHE_MAGIC），那么：返回 -1
    令 版本（ver） = 读 64 位（r64）（文件数据（data），位置（pos））
    令 位置（pos） = 位置（位置） + 8
    如果 版本（ver） 不等于 HDFG（CIR） 缓存版本（CIR_CACHE_VER），那么：返回 -1
    令 函数体指纹（fp） = 读 64 位（r64）（文件数据（data），位置（pos））
    令 位置（pos） = 位置（位置） + 8
    令 签名指纹（sig） = 读 64 位（r64）（文件数据（data），位置（pos））
    令 位置（pos） = 位置（位置） + 8
    令 函数 AST 节点（fn_node） = 函数信息访问器：AST 节点（fi_ast_node）（func_idx）
    令 当前函数体指纹（current_fp） = 函数指纹（func_fingerprint）（fn_node）
    如果 函数体指纹（fp） 不等于 当前函数体指纹（current_fp），那么：返回 -1
    令 当前签名指纹（current_sig） = 签名指纹（sig_fingerprint）（fn_node）
    如果 签名指纹（sig） 不等于 当前签名指纹（current_sig），那么：返回 -1
    令 名称长度（name_len） = 读 64 位（r64）（文件数据（data），位置（pos））
    令 位置（pos） = 位置（位置） + 8
    令 位置（pos） = 位置（位置） + 名称长度（name_len）
    令 变量计数（var_count） = 读 64 位（r64）（文件数据（data），位置（pos））
    令 位置（pos） = 位置（位置） + 8
    令 变量索引（vi） = 0（可变）
    循环（当 变量索引 小于 变量计数（var_count） 时）：
        令 名称索引（name_ni） = 读 64 位（r64）（文件数据（data），位置（pos））
        令 位置（pos） = 位置（位置） + 8
        令 变量 ID（v_id） = 读 64 位（r64）（文件数据（data），位置（pos））
        令 位置（pos） = 位置（位置） + 8
        令 变量类型（v_type） = 读 64 位（r64）（文件数据（data），位置（pos））
        令 位置（pos） = 位置（位置） + 8
        如果 变量 ID（v_id） 大于等于 IR 变量总数（g_ir_var_count），那么：
            扩展 IR 变量数组（grow_ir_vars）（变量 ID（v_id） + 1）
            令 IR 变量总数（g_ir_var_count） = 变量 ID（v_id） + 1
        IR 变量访问器：设置名称（irv_set_name）（变量 ID（v_id），名称索引（name_ni））
        IR 变量访问器：设置ID（irv_set_id）（变量 ID（v_id），变量 ID（v_id））
        IR 变量访问器：设置类型（irv_set_type）（变量 ID（v_id），变量类型（v_type））
        令 变量索引 = 变量索引 + 1
    令 节点计数（node_count） = 读 64 位（r64）（文件数据（data），位置（pos））
    令 位置（pos） = 位置（位置） + 8
    令 基础节点位置（base_node） = 数据流节点计数（g_df_node_count）
    扩展数据流节点数组（grow_df_nodes）（数据流节点计数（g_df_node_count） + 节点计数（node_count））
    扩展数据流节点区域数组（grow_df_node_region）（基础节点位置（base_node） + 节点计数（node_count））
    令 节点索引（ni） = 0（可变）
    循环（当 节点索引 小于 节点计数（node_count） 时）：
        令 当前节点全局位置（n） = 基础节点位置（base_node） + 节点索引
        写 64 位（w64）（数据流节点所属 region（g_df_node_region），当前节点全局位置（n） * 8，当前结构图索引（g_cur_sg））
        写 64 位（w64）（数据流节点数组（g_df_nodes），当前节点全局位置（n） * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点操作码偏移（OFF_DF_OPCODE），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        写 64 位（w64）（数据流节点数组（g_df_nodes），当前节点全局位置（n） * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点目标偏移（OFF_DF_DEST），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        写 64 位（w64）（数据流节点数组（g_df_nodes），当前节点全局位置（n） * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点源1偏移（OFF_DF_S1），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        写 64 位（w64）（数据流节点数组（g_df_nodes），当前节点全局位置（n） * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点源2偏移（OFF_DF_S2），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        写 64 位（w64）（数据流节点数组（g_df_nodes），当前节点全局位置（n） * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点源3偏移（OFF_DF_S3），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        写 64 位（w64）（数据流节点数组（g_df_nodes），当前节点全局位置（n） * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点类型类别偏移（OFF_DF_TK），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        写 64 位（w64）（数据流节点数组（g_df_nodes），当前节点全局位置（n） * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点首边索引偏移（OFF_DF_FIRST_EDGE），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        写 64 位（w64）（数据流节点数组（g_df_nodes），当前节点全局位置（n） * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点边计数偏移（OFF_DF_EDGE_COUNT），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        令 节点目标变量（dest） = 读 64 位（r64）（数据流节点数组（g_df_nodes），当前节点全局位置（n） * 数据流节点条目大小（ESZ_DFNODE） + 数据流节点目标偏移（OFF_DF_DEST））
        如果 节点目标变量（dest） 大于等于 0，那么：
            扩展数据流数组（grow_df_arrays）（节点目标变量（dest） + 1）
            写 64 位（w64）（变量生产者节点映射（g_df_var_producer），节点目标变量（dest） * 8，当前节点全局位置（n））
        令 节点索引 = 节点索引 + 1
    令 数据流节点计数（g_df_node_count） = 基础节点位置（base_node） + 节点计数（node_count）
    令 边计数（edge_count） = 读 64 位（r64）（文件数据（data），位置（pos））
    令 位置（pos） = 位置（位置） + 8
    扩展数据流边数组（grow_df_edges）（edge_count）
    令 数据流边计数（g_df_edge_count） = 边计数（edge_count）
    令 边索引（ei） = 0（可变）
    循环（当 边索引 小于 边计数（edge_count） 时）：
        令 边源节点（e_from） = 读 64 位（r64）（文件数据（data），位置（pos））
        令 位置（pos） = 位置（位置） + 8
        令 边目标节点（e_to） = 读 64 位（r64）（文件数据（data），位置（pos））
        令 位置（pos） = 位置（位置） + 8
        令 边链表下一项（e_next） = 读 64 位（r64）（文件数据（data），位置（pos））
        令 位置（pos） = 位置（位置） + 8
        令 边类别（e_kind） = 读 64 位（r64）（文件数据（data），位置（pos））
        令 位置（pos） = 位置（位置） + 8
        写 64 位（w64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 数据流边起点偏移（OFF_DFE_FROM），边源节点（e_from））
        写 64 位（w64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 数据流边终点偏移（OFF_DFE_TO），边目标节点（e_to））
        写 64 位（w64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 数据流边下一边偏移（OFF_DFE_NEXT），边链表下一项（e_next））
        写 64 位（w64）（数据流边数组（g_df_edges），边索引 * 数据流边条目大小（ESZ_DFEDGE） + 数据流边类别偏移（OFF_DFE_KIND），边类别（e_kind））
        令 边索引 = 边索引 + 1
    令 指令计数（instr_count） = 读 64 位（r64）（文件数据（data），位置（pos））
    令 位置（pos） = 位置（位置） + 8
    令 基础指令位置（base_instr） = IR 指令总数（g_ir_instr_count）
    扩展 IR 指令数组（grow_ir_instrs）（IR 指令总数（g_ir_instr_count） + 指令计数（instr_count））
    令 指令索引（ii） = 0（可变）
    循环（当 指令索引 小于 指令计数（instr_count） 时）：
        令 当前指令全局位置（inst） = 基础指令位置（base_instr） + 指令索引
        IR 指令访问器：设置操作码（iri_set_op）（当前指令全局位置（inst），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        IR 指令访问器：设置目标（iri_set_dest）（当前指令全局位置（inst），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        IR 指令访问器：设置操作数1（iri_set_s1）（当前指令全局位置（inst），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        IR 指令访问器：设置操作数2（iri_set_s2）（当前指令全局位置（inst），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        IR 指令访问器：设置操作数3（iri_set_s3）（当前指令全局位置（inst），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        IR 指令访问器：设置类型类别（iri_set_tk）（当前指令全局位置（inst），读 64 位（r64）（文件数据（data），位置（pos）））
        令 位置（pos） = 位置（位置） + 8
        令 指令索引 = 指令索引 + 1
    令 IR 指令总数（g_ir_instr_count） = 基础指令位置（base_instr） + 指令计数（instr_count）
    令 字符串计数（str_count） = 读 64 位（r64）（文件数据（data），位置（pos））
    令 位置（pos） = 位置（位置） + 8
    令 字符串索引（si） = 0（可变）
    循环（当 字符串索引 小于 字符串计数（str_count） 时）：
        令 字符串长度（sl） = 读 64 位（r64）（文件数据（data），位置（pos））
        令 位置（pos） = 位置（位置） + 8
        令 常量字符串（s） = 字符串切片（str_sub）（文件数据（data），位置（pos），字符串长度（sl））
        令 位置（pos） = 位置（位置） + 字符串长度（sl）
        追踪字符串常量（track_str）（字符串驻留（str_intern）（s））
        令 字符串索引 = 字符串索引 + 1
    返回 0
### 测试要点
1. 文件小于 48 字节时返回 -1（文件头不完整）
2. 魔数不匹配时返回 -1
3. 版本号不等于 HDFG（CIR） 缓存版本（CIR_CACHE_VER）（5）时返回 -1（旧版本缓存被拒绝）
4. 函数体指纹不匹配时返回 -1（函数源代码已更改，缓存失效）
5. 签名指纹不匹配时返回 -1（函数签名已更改，缓存失效）
6. 恢复的节点正确写入 节点（node）-region 映射（归属到当前打开的 func region）
7. 恢复的节点正确更新变量生产者映射（g_df_var_producer）
8. 边的 种类（kind） 字段被恢复（v5），使状态边信息不丢失
9. 空函数（节点/边/指令/变量计数均为 0）的缓存加载不崩溃
10. 字符串常量正确恢复并通过 追踪字符串常量（track_str） 注册

## 函数 创建 HDFG（CIR） 缓存目录（make_cir_cache_dir）
### 作用
创建 .HDFG（cir） 缓存所需的目录层级（.核心（core）/、.核心/cache/、.核心/cache/HDFG/）。使用 Linux 建目录（mkdir） 系统调用（83），权限 0700（448 = 0x1C0）。对已存在的目录忽略 已存在错误码（EEXIST） 错误——系统调用本身的返回值不被检查，目录已存在时 建目录 返回 -已存在错误码 但不影响后续操作。
### 逻辑
    系统调用3（syscall3）（83，".核心（core）"，448，0）
    系统调用3（syscall3）（83，".核心（core）/cache"，448，0）
    系统调用3（syscall3）（83，".核心（core）/cache/HDFG（cir）"，448，0）
### 测试要点
1. 目录已存在时不报错（建目录（mkdir） 的 已存在错误码（EEXIST） 被忽略）
2. 父目录 .核心（core） 首次创建时成功，后续子目录依赖父目录存在
3. 权限不足时（如只读文件系统）建目录（mkdir） 返回负数但函数不检查，调用方通过后续文件操作失败间接感知
