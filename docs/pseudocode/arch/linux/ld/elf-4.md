# 可执行文件格式（elf）-4.md 伪代码

> 源文件：src/arch/linux/ld/可执行文件格式（elf）.cr（第 972-1643 行：elf_gen 主函数——完整的三阶段 ELF 生成管线）
> 功能概要：ELF 生成核心的第四部分，涵盖 生成 ELF（elf_gen） 主函数。该函数实现完整的 ELF 可执行文件生成管线：Phase 0 标记全局变量并匹配 11 个内建函数名称索引；Phase 1 收集字符串常量布局 .只读数据段（rodata） 偏移表并查找竞技场/堆相关全局变量索引；Phase 2 估算所有函数（用户函数 + 分配函数（alloc） + heap_expand + sched_call 跳板 + runtime 桩）的总代码大小，并注册函数偏移量表；Phase 3 实际发射所有机器码到缓冲区，然后修补所有前向引用（RIP 相对引用、调用跳转、函数地址、返回（ret） 跳转、分配函数 调用、rodata 引用）、原地重新发射 分配函数（分配函数）/扩展堆（heap_expand）（使用最终 BSS VA）、分配 BSS 全局变量偏移量、修补 _start 内 call 主入口（main），并发射 BSS 清零入口（bss_init） 入口存根；Phase 4 写入 ELF 文件头，覆写入口点为 BSS 清零入口。最终返回完整 ELF 文件的总字节数。

## 标识符对照表

| 中文名 | 原名 | 首次出现阶段 |
|--------|------|-------------|
| 生成 ELF | elf_gen | elf_gen |
| 发射 _start | emit_start | Phase 2/3 |
| 发射 _start 大小 | emit_start_size | Phase 2 |
| 发射单条指令 | emit_instr | Phase 3 |
| 发射分配函数体 | emit_alloc_body | Phase 3 |
| 发射堆扩展代码 | emit_heap_expand | Phase 3 |
| 发射 curg 桩代码 | emit_curg_stubs | Phase 3 |
| 发射协程桩代码 | emit_goroutine_stubs | Phase 3 |
| 发射 m_start_workers | emit_m_start_workers | Phase 3 |
| 发射调度调用 | emit_sched_call | Phase 3 |
| 调度跳板大小 | sched_tramp_sz | Phase 2 |
| 调度：注册一个 | sched_reg_one | Phase 2/3 |
| ELF2 头写入 | elf2_hdr | Phase 4 |
| 全局变量初始化 | g2_init | Phase 2/3 |
| 全局变量槽位 | g2_slot | Phase 2/3 |
| 全局变量字符串偏移 | g2_str_off | Phase 1 |
| 全局变量只读数据大小 | g2_rodata_sz | Phase 2 |
| 解析标签 | res_labels | Phase 0（预先，在 elf_gen 之前已调用） |
| 获取变量寄存器 | get_reg_for_var | Phase 3 |
| 驻留字符串获取 | istr_get | Phase 0/1/2/3 |
| 驻留字符串长度 | istr_len | Phase 3 |
| 字符串驻留 | str_intern | Phase 1/2 |
| 字符串相等比较 | str_eq | Phase 0/1/2/3 |
| 字符串长度 | str_len | Phase 3 |
| 发射 REX 前缀 | emit_rex | Phase 3 |
| 发射 ModRM | emit_modrm | Phase 3 |
| 发射存储 | e2_st | Phase 3 |
| 发射加载双字 | e2_ld | Phase 3 |
| 发射写 8 位 | e2_w8 | Phase 3 |
| 发射写 32 位 | e2_w32 | Phase 3 |
| 发射写 64 位 | e2_w64 | Phase 3 |
| 写单字节 | w8 | Phase 3 |
| 写 16 位 | w16 | Phase 4（elf2_hdr 内部） |
| 写 32 位 | w32 | Phase 3 |
| 写 64 位 | w64 | Phase 0/1/2/3 |
| 读 8 位 | r8 / load8 | Phase 3 |
| 读 64 位 | r64 | Phase 0/1/2/3 |
| 读取无符号字节 | bu8 | Phase 3 |
| 写单字节有符号 | w8_signed | Phase 3 |
| 带符号扩展的缓冲区读取 | bu8_signed_expand | Phase 3（LEA 验证内部） |
| 扩展 RIP 修补数组 | grow_rip_patch | Phase 3 |
| 扩展调用修补数组 | grow_call_patch | Phase 3 |
| 扩展函数地址修补数组 | grow_fnaddr_patch | Phase 3 |
| 扩展分配修补数组 | grow_alloc_patch | Phase 3 |
| 扩展返回修补数组 | grow_ret_patch | Phase 3 |
| 扩展只读数据引用数组 | grow_rodataref | Phase 1/3 |
| 扩展函数偏移数组 | grow_func_offsets | Phase 2 |
| 扩展函数代码大小数组 | grow_func_code_sz | Phase 2 |
| 扩展函数当前指针数组 | grow_func_cp | Phase 3 |
| 扩展全局变量偏移数组 | grow_global_off | Phase 3 |
| 扩展是否全局标记数组 | grow_is_global | Phase 0 |
| 扩展标签位置数组 | grow_label_poses | Phase 3 |
| 向上对齐 | align_up | Phase 3 |
| 发射调用指令 | e2_call | Phase 3 |
| 发射存储 | e2_st | Phase 3 |
| 发射加载双字 | e2_ld | Phase 3 |
| IR 指令访问器：操作码 | iri_op | Phase 2 |
| IR 指令源操作数读取 | iri_s1 / iri_s2 / iri_s3 | Phase 2 |
| push rbp 大小 | sz_push_rbp | Phase 2 |
| mov rbp, rsp 大小 | sz_mov_rbp_rsp | Phase 2 |
| sub rsp 大小 | sz_sub_rsp | Phase 2 |
| 寄存器保存参数大小 | sz_save_param | Phase 2 |
| 栈保存参数大小 | sz_save_stack_param | Phase 2 |
| add rsp 大小 | sz_add_rsp | Phase 2 |
| pop rbp 大小 | sz_pop_rbp | Phase 2 |
| RET 指令大小 | sz_ret | Phase 2 |
| ELF 头大小常量 | EHDR_SIZE | Phase 2/3/4 |
| 程序头大小常量 | PHDR_SIZE | Phase 2/3/4 |
| P_TYPE 偏移量 | P_TYPE | Phase 4 |
| P_FLAGS 偏移量 | P_FLAGS | Phase 4 |
| P_OFFSET 偏移量 | P_OFFSET | Phase 4 |
| P_VADDR 偏移量 | P_VADDR | Phase 4 |
| P_PADDR 偏移量 | P_PADDR | Phase 4 |
| P_FILESZ 偏移量 | P_FILESZ | Phase 4 |
| P_MEMSZ 偏移量 | P_MEMSZ | Phase 4 |
| P_ALIGN 偏移量 | P_ALIGN | Phase 4 |
| E_ENTRY 偏移量 | E_ENTRY | Phase 4 |
| 向上对齐 | align_up | Phase 3 |

## 全局状态

| 中文名 | 原名 | 含义 |
|--------|------|------|
| IR 全局变量数组 | g_ir_globals | 每条记录 24 字节：+0 为名称驻留索引、+8 为 IR 变量索引、+16 为编译时常量初始值（0=无初始值） |
| IR 全局变量计数 | g_ir_global_count | g_ir_globals 的条目数 |
| IR 函数个数 | g_ir_func_count | g_ir_func_* 系列数组的条目数 |
| IR 函数名索引数组 | g_ir_func_name_idx | 每条记录 8 字节，为 g_str_table 中函数名的驻留索引 |
| IR 函数指令起始索引数组 | g_ir_func_instr_start | 每条记录 8 字节，该函数第一条指令在 g_ir_instrs 中的索引 |
| IR 函数指令计数数组 | g_ir_func_instr_count | 每条记录 8 字节，该函数的指令条数 |
| IR 函数变量起始索引数组 | g_ir_func_var_start | 每条记录 8 字节 |
| IR 函数变量计数数组 | g_ir_func_var_count | 每条记录 8 字节 |
| IR 函数参数计数数组 | g_ir_func_param_count | 每条记录 8 字节 |
| IR 字符串常量数组 | g_ir_str_consts | 每条记录 8 字节，字符串的驻留索引 |
| IR 字符串常量计数 | g_ir_str_const_count | g_ir_str_consts 的条目数 |
| IR 变量总数 | g_ir_var_count | 全局和局部变量的总数（在分配 BSS 和标记 is_global 时用作数组大小边界） |
| IR 指令总数 | g_ir_instr_count | g_ir_instrs 数组的总条目数 |
| 优化级别 | g_opt_level | 全局编译优化级别。>=1 时启用寄存器分配、被调用者保存寄存器压栈/弹出、额外参数栈预留 |
| 字符串常量计数 | g_str_count | 驻留字符串表 g_str_table 的条目数 |
| 标签计数 | g_label_count | 最大标签索引值（由 Phase 2 统计得出，Phase 3 依此分配 label_poses 数组） |
| 标签位置数组 | g_label_poses | 每条记录 8 字节，记录各标签在缓冲区中的绝对位置（-1 表示尚未遇到） |
| 待处理计数 | g_pending_count | 前向跳转占位符的计数 |
| 待处理位置数组 | g_pending_pos | 前向跳转的缓冲区位置 |
| 待处理标签数组 | g_pending_label | 前向跳转的目标标签索引 |
| 汇编代码大小 | g_asm_code_size | Phase 4 写入的最终 ELF 文件总大小 |
| ELF 输出缓冲区 | g_elf_buf | 传递给 elf_gen 的参数 buf，即 ELF 文件的完整输出缓冲区 |
| x86 RIP 修补计数 | g_x86_rip_patch_count | 当前记录的 LEA 占位符修补条目数 |
| x86 RIP 修补位置数组 | g_x86_rip_patch_pos | 每条 8 字节，记录 LEA 指令中 32 位位移字段的缓冲区位置 |
| x86 RIP 全局变量修补数组 | g_x86_rip_patch_globals | 每条 8 字节，记录对应全局变量的 IR 变量索引 |
| x86 调用修补计数 | g_x86_call_patch_count | 前向 call 占位符的条目数 |
| x86 调用修补位置数组 | g_x86_call_patch_pos | 每条 8 字节 |
| x86 调用修补名称数组 | g_x86_call_patch_name | 每条 8 字节，目标函数名称驻留索引 |
| x86 函数地址修补计数 | g_x86_fnaddr_patch_count | IR_FNADDR movabs 占位符条目数 |
| x86 函数地址修补位置数组 | g_x86_fnaddr_patch_pos | 每条 8 字节 |
| x86 函数地址修补名称数组 | g_x86_fnaddr_patch_name | 每条 8 字节 |
| x86 分配修补计数 | g_x86_alloc_patch_count | IR_ALLOC_STRUCT/ARRAY/MAKE_ENUM 的 call 占位符条目数 |
| x86 分配修补位置数组 | g_x86_alloc_patch_pos | 每条 8 字节 |
| x86 RET 修补计数 | g_x86_ret_patch_count | 函数体内 jmp 到尾声的占位符条目数 |
| x86 RET 修补位置数组 | g_x86_ret_patch_pos | 每条 8 字节 |
| x86 .rodata 引用计数 | g_x86_rodataref_count | LEA 引用 .rodata 字符串常量的条目数 |
| x86 .rodata 引用位置数组 | g_x86_rodataref_pos | 每条 8 字节 |
| x86 .rodata 引用目标数组 | g_x86_rodataref_ro | 每条 8 字节，目标字符串在 .rodata 段内的偏移量 |
| x86 外部重定位计数 | g_x86_ext_rel_count | 外部符号（动态链接）的调用占位符条目数 |
| x86 外部重定位位置数组 | g_x86_ext_rel_pos | 每条 8 字节 |
| x86 外部重定位名称数组 | g_x86_ext_rel_name | 每条 8 字节 |
| x86 .rodata 基址 | g_x86_rodata_base | .rodata 段在输出缓冲区中的绝对位置（Phase 2 估算，Phase 3 用实际 cp 覆写） |
| x86 字符串计数 | g_x86_str_count | .rodata 段中的字符串条目数 |
| x86 字符串偏移数组 | g_x86_str_offs | 每条 8 字节，各字符串在 rodata 段内的偏移量 |
| x86 变量是否全局标记数组 | g_x86_is_global | 每条 8 字节，索引为 IR 变量索引，值为 1 表示该变量是全局变量（需 BSS 槽位 + RIP 寻址） |
| x86 全局变量偏移数组 | g_x86_global_off | 每条 8 字节，索引为 IR 变量索引，值为该全局变量在 BSS 段内的字节偏移量 |
| x86 是否需要发射运行时桩标记 | g_x86_emit_rt_stubs | 非零时发射 curg 桩（g_set_curg/g_get_curg）和协程运行时桩（fiber_init/fiber_switch/goroutine_entry_wrapper/m_start_workers） |
| x86 函数偏移计数 | g_x86_func_off_count | g_x86_func_offsets 中的条目数（每对 16 字节：名称+偏移量） |
| x86 函数偏移数组 | g_x86_func_offsets | 每对 16 字节：+0 为函数名称驻留索引（8 字节），+8 为在代码段内的偏移量（8 字节，相对于 TEXT_BASE+176） |
| x86 函数代码大小数组 | g_x86_func_code_sz | 每条 8 字节，分别为各用户函数 Phase 2 估算的代码大小（ic×5） |
| x86 函数当前指针 | g_x86_func_cp | 每条 8 字节，Phase 3 在发射用户函数时写入该函数体的起始缓冲区位置 |
| x86 发射栈大小 | g_x86_emit_stack_size | 当前正在发射的函数的栈帧总大小（vc×8），在 prologue/epilogue 和 sub rsp 修补中使用 |
| x86 sub rsp 指令位置 | g_x86_sub_rsp_pos | 当前函数序言中 sub rsp, imm 指令的位移字段在缓冲区中的位置（后续按实际栈大小修补） |
| 当前函数变量起始（x86 后端） | g_current_func_var_start | Phase 3 发射函数时设置的当前函数第一个局部变量的 IR 索引 |
| x86 函数帧起始 | g_x86_func_frame_start | Phase 3 设置的当前函数体的缓冲区绝对位置（emit_instr 可能需要） |
| 调用 main 位置 | g_call_main_pos | emit_start 写入 call main 的缓冲区位置，Phase 3 末尾修补 |
| argc 全局变量索引 | gv_argc | Phase 1 通过名称匹配设置的 g_rt_argc 的 IR 变量索引 |
| argv 指针索引 | gv_argv | Phase 1 设置的 g_rt_argv_ptr 的 IR 变量索引 |
| 当前竞技场全局变量索引 | gv_current_arena | Phase 1 设置的 g_current_arena 的 IR 变量索引 |
| 竞技场游标全局变量索引 | gv_arena_cursors | Phase 1 设置 |
| 竞技场大小全局变量索引 | gv_arena_sizes | Phase 1 设置 |
| 竞技场池数据全局变量索引 | gv_arena_pool_data | Phase 1 设置 |
| 竞技场最大尺寸全局变量索引 | gv_arena_max_size | Phase 1 设置 |
| 堆指针全局变量索引 | gv_heap_ptr | Phase 1 设置 |
| 堆尾全局变量索引 | gv_heap_end | Phase 1 设置 |
| 堆配置全局变量索引 | gv_hp_config | Phase 1 设置 |
| 堆待处理全局变量索引 | gv_hp_inflight | Phase 1 设置 |
| curg 桩代码起始位置 | g_curg_stub_start | Phase 3 中 curg 桩的缓冲区起始位置（用于 re-emit） |
| 堆扩展调用位置 | g_heap_expand_call_pos | alloc 体内 call heap_expand 的位移字段位置（alloc re-emit 后修补） |
| 全局分配跳转位置 | g_alloc_gl_jmp_pos | alloc 体内 Part 1 末尾 jl .Lglobal 的位移字段位置（由 Part 8 修补） |
| 本地指令：__builtin_syscall3 索引 | g_ni_syscall3 | Phase 0 匹配的 __builtin_syscall3 在字符串表中的驻留索引 |
| 本地指令：__builtin_load8 索引 | g_ni_load8 | Phase 0 匹配 |
| 本地指令：__builtin_store8 索引 | g_ni_store8 | Phase 0 匹配 |
| 本地指令：__builtin_load64 索引 | g_ni_load64 | Phase 0 匹配 |
| 本地指令：__builtin_r64 索引 | g_ni_r64 | Phase 0 匹配 |
| 本地指令：__builtin_load_str_ptr 索引 | g_ni_load_str_ptr | Phase 0 匹配 |
| 本地指令：__builtin_store_str_ptr 索引 | g_ni_store_str_ptr | Phase 0 匹配 |
| 本地指令：__builtin_get_arg 索引 | g_ni_get_arg | Phase 0 匹配 |
| 本地指令：__builtin_w64 索引 | g_ni_w64 | Phase 0 匹配 |
| 本地指令：__builtin_dyncpy 索引 | g_ni_dyncpy | Phase 0 匹配 |
| 本地指令：goroutine_wrapper_addr 索引 | g_ni_goroutine_wrapper_addr | Phase 0 匹配 |
| 代码段基址 | TEXT_BASE | 常量 0x400000（4194304），ELF 代码段的起始虚拟地址 |
| ELF 头大小常量 | EHDR_SIZE | 常量 64，Elf64_Ehdr 结构体大小 |
| 程序头大小常量 | PHDR_SIZE | 常量 56，Elf64_Phdr 结构体大小 |
| BSS 零初始化大小 | BSS_ZERO_SIZE | 常量 131072（128 KB），bss_init 存根清零的字节数 |

## 函数 生成 ELF（elf_gen）
### 作用
ELF 后端的顶级编排函数，输入 ELF 输出缓冲区 缓冲区（buf）（已通过 扩容函数（grow） 预留了足够空间），通过四个阶段生成完整的 ELF 可执行文件。返回最终 ELF 的总字节数（写入 g_asm_code_size）。

Phase 0 负责全局变量标记和内建函数名称索引匹配；Phase 1 负责 .只读数据段（rodata） 字符串常量布局和全局变量索引查找；Phase 2 负责所有代码段大小估算和函数偏移量表注册；Phase 3 负责实际机器码发射和所有占位符修补；Phase 4 负责写入 ELF 文件头并设置入口点为 BSS 清零入口（bss_init）。

该函数是 ELF 后端的唯一公开入口，调用方（main.cr 或 corearch.cr）通过检查返回值 > 0 判断成功，之后将 缓冲区（buf）[0..总大小（total_sz）] 写入磁盘即为合法的 ELF 可执行文件。

### 逻辑

#### Phase 0：标记全局变量并匹配内建函数名称索引

—— 第一步：遍历所有 IR 全局变量，在 x86 变量是否全局标记数组（g_x86_is_global）中将对应的 IR 变量索引位置标记为 1
令 全局变量索引（gi）= 0
循环（当 全局变量索引 小于 IR 全局变量计数（g_ir_global_count）时）：
    调用 读 64 位（r64），从 IR 全局变量数组（g_ir_globals）偏移量 全局变量索引 × 24 + 8 处读取 IR 变量索引，存入 临时变量 变量编号（gv）
    如果 变量编号 大于等于 0，那么：
        调用 扩展是否全局标记数组（grow_is_global），参数 变量编号 + 1，确保数组容量覆盖该索引
        调用 写 64 位（w64），向 x86 变量是否全局标记数组（g_x86_is_global）偏移量 变量编号 × 8 处写入 1（标记该变量为全局变量）
    令 全局变量索引 = 全局变量索引 + 1
—— 扩展至 IR 变量总数边界（g_ir_var_count），确保数组覆盖所有变量索引范围
调用 扩展是否全局标记数组（grow_is_global），参数 IR 变量总数（g_ir_var_count）

—— 第二步：将 11 个内建函数的名称索引全部复位为 -1（表示未找到）
令 内建 三参系统调用（syscall3） 名称索引（g_ni_syscall3）= -1
令 内建 读取字节（load8） 名称索引（g_ni_load8）= -1
令 内建 写字节（store8） 名称索引（g_ni_store8）= -1
令 内建 读取 64 位（load64） 名称索引（g_ni_load64）= -1
令 内建 字符串指针加载（load_str_ptr） 名称索引（g_ni_load_str_ptr）= -1
令 内建 字符串指针存储（store_str_ptr） 名称索引（g_ni_store_str_ptr）= -1
令 内建 获取参数（get_arg） 名称索引（g_ni_get_arg）= -1
令 本地指令：内建写 64 位（__builtin_w64） 索引（g_ni_w64）= -1
令 内建 动态拷贝（dyncpy） 名称索引（g_ni_dyncpy）= -1
令 本地指令：内建读 64 位（__builtin_r64） 索引（g_ni_r64）= -1
令 内建 协程包装地址（goroutine_wrapper_addr） 名称索引（g_ni_goroutine_wrapper_addr）= -1

—— 第三步：遍历字符串常量表（g_str_count），将每个驻留字符串与 11 个已知内建名称逐一比对，匹配则记录其索引
令 名称遍历索引（ni_i）= 0
循环（当 名称遍历索引 小于 字符串常量计数（g_str_count）时）：
    调用 驻留字符串获取（istr_get），参数 名称遍历索引，获取该索引对应的字符串内容，存入 临时变量 名称字符串（ns）
    调用 字符串相等比较（str_eq），比较 名称字符串 与 字符串常量 "三参系统调用（syscall3）"；如果返回值不等于 0，那么：令 原生内建三参系统调用索引（g_ni_syscall3） = 名称遍历索引
    调用 字符串相等比较，比较 名称字符串 与 "读取字节（load8）"；如果不等于 0，那么：令 原生内建读取字节索引（g_ni_load8） = 名称遍历索引
    调用 字符串相等比较，比较 名称字符串 与 "写字节（store8）"；如果不等于 0，那么：令 原生内建写字节索引（g_ni_store8） = 名称遍历索引
    调用 字符串相等比较，比较 名称字符串 与 "读取 64 位（load64）"；如果不等于 0，那么：令 原生内建读取 64 位索引（g_ni_load64） = 名称遍历索引
    调用 字符串相等比较，比较 名称字符串 与 "读 64 位（r64）"；如果不等于 0，那么：令 原生内建读 64 位索引（g_ni_r64） = 名称遍历索引
    调用 字符串相等比较，比较 名称字符串 与 "字符串指针加载（load_str_ptr）"；如果不等于 0，那么：令 原生内建字符串指针加载索引（g_ni_load_str_ptr） = 名称遍历索引
    调用 字符串相等比较，比较 名称字符串 与 "字符串指针存储（store_str_ptr）"；如果不等于 0，那么：令 原生内建字符串指针存储索引（g_ni_store_str_ptr） = 名称遍历索引
    调用 字符串相等比较，比较 名称字符串 与 "获取参数（get_arg）"；如果不等于 0，那么：令 原生内建获取参数索引（g_ni_get_arg） = 名称遍历索引
    调用 字符串相等比较，比较 名称字符串 与 "写 64 位（w64）"；如果不等于 0，那么：令 原生内建写 64 位索引（g_ni_w64） = 名称遍历索引
    调用 字符串相等比较，比较 名称字符串 与 "动态拷贝内建（_dyncpy）"；如果不等于 0，那么：令 原生内建动态拷贝索引（g_ni_dyncpy） = 名称遍历索引
    调用 字符串相等比较，比较 名称字符串 与 "协程包装地址（goroutine_wrapper_addr）"；如果不等于 0，那么：令 原生内建协程包装地址索引（g_ni_goroutine_wrapper_addr） = 名称遍历索引
    令 名称遍历索引 = 名称遍历索引 + 1

—— 第四步：输出匹配结果调试信息（仅输出关键索引）
调用 输出函数（print），输出字符串 "  原生内建索引（ni）: 三参系统调用（syscall3）="
调用 输出函数，输出 整数转字符串（int_str）的结果，参数 原生内建三参系统调用索引（g_ni_syscall3）
调用 输出函数，输出 " 读取字节（load8）="
调用 输出函数，输出 整数转字符串（int_str）的结果，参数 原生内建读取字节索引（g_ni_load8）
调用 输出函数，输出 " 写 64 位（w64）="
调用 输出函数，输出 整数转字符串（int_str）的结果，参数 原生内建写 64 位索引（g_ni_w64）
调用 输出函数，输出 " 动态拷贝（dyncpy）="
调用 输出带换行函数（println），输出 整数转字符串（int_str）的结果，参数 原生内建动态拷贝索引（g_ni_dyncpy）

—— 第五步：复位所有暂存修补计数（res_labels → emit_instr 阶段曾污染这些数组，Phase 3 将重新填充）
令 x86 RIP 修补计数（g_x86_rip_patch_count）= 0
令 x86 只读数据段（rodata） 引用计数（g_x86_rodataref_count）= 0
令 x86 分配修补计数（g_x86_alloc_patch_count）= 0
令 x86 函数地址修补计数（g_x86_fnaddr_patch_count）= 0

#### Phase 1：只读数据段（rodata） 布局——收集字符串常量并查找全局变量索引

—— 第一步：输出阶段提示
调用 输出带换行函数（println），输出 "  可执行文件格式（elf）: Phase 1 （rodata layout）..."

—— 第二步：遍历所有 IR 字符串常量，调用 全局变量字符串偏移（g2_str_off） 为每个字符串在 .只读数据段（rodata） 段中分配偏移量
令 x86 字符串计数（g_x86_str_count）= 0
令 字符串索引（si）= 0
循环（当 字符串索引 小于 IR 字符串常量计数（g_ir_str_const_count）时）：
    调用 读 64 位（r64），从 IR 字符串常量数组（g_ir_str_consts）偏移量 字符串索引 × 8 处读取字符串的驻留索引
    调用 全局变量字符串偏移（g2_str_off），传入上述驻留索引（该函数内部：将字符串写入 g_x86_str_offs 数组、递增 g_x86_str_count、返回字符串在 rodata 段内的偏移量）
    令 字符串索引 = 字符串索引 + 1

—— 第三步：查找 argc/argv 及竞技场/堆相关的 11 个全局变量 IR 索引
—— 通过字符串驻留（str_intern）获取目标名称的驻留索引，然后遍历 IR 全局变量数组（g_ir_globals） 将名称匹配的条目的 IR 变量索引（+8 字段）保存到 全局索引（gv_）* 系列变量中
令 argc 全局变量索引（gv_argc）= -1
令 argv 指针索引（gv_argv）= -1
调用 字符串驻留（str_intern），参数 "命令行参数个数（g_rt_argc）"，获取其驻留索引，存入 临时变量 argc 名称索引（argc_ni）
调用 字符串驻留（str_intern），参数 "argv 指针（g_rt_argv_ptr）"，获取其驻留索引，存入 临时变量 argv 名称索引（argv_ni）

令 当前竞技场全局变量索引（gv_current_arena）= -1
令 竞技场游标全局变量索引（gv_arena_cursors）= -1
令 竞技场大小全局变量索引（gv_arena_sizes）= -1
令 竞技场池数据全局变量索引（gv_arena_pool_data）= -1
令 竞技场最大尺寸全局变量索引（gv_arena_max_size）= -1
调用 字符串驻留，参数 "当前竞技场（g_current_arena）"，存入 临时变量 当前原生内建索引（cur_ni）
调用 字符串驻留，参数 "竞技场游标数组（g_arena_cursors）"，存入 临时变量 当前原生内建索引2（cur_ni2）
调用 字符串驻留，参数 "竞技场大小数组（g_arena_sizes）"，存入 临时变量 当前原生内建索引3（cur_ni3）
调用 字符串驻留，参数 "竞技场内存池数据（g_arena_pool_data）"，存入 临时变量 当前原生内建索引4（cur_ni4）
调用 字符串驻留，参数 "竞技场最大大小（g_arena_max_size）"，存入 临时变量 当前原生内建索引5（cur_ni5）

调用 字符串驻留，参数 "堆指针（g_heap_ptr）"，存入 临时变量 当前原生内建索引6（cur_ni6）
调用 字符串驻留，参数 "堆末尾（g_heap_end）"，存入 临时变量 当前原生内建索引7（cur_ni7）
调用 字符串驻留，参数 "热补丁配置（g_hp_config）"，存入 临时变量 当前原生内建索引8（cur_ni8）
调用 字符串驻留，参数 "热补丁进行中计数（g_hp_inflight）"，存入 临时变量 当前原生内建索引9（cur_ni9）

令 全局变量扫描索引（gvsi）= 0
循环（当 全局变量扫描索引 小于 IR 全局变量计数（g_ir_global_count）时）：
    调用 读 64 位（r64），从 IR 全局变量数组 偏移量 全局变量扫描索引 × 24 + 0 处读取该条目的名称驻留索引，存入 临时变量 名称索引（ni）
    如果 名称索引 等于 参数个数原生内建索引（argc_ni），那么：调用 读 64 位（r64），读取偏移 +8 处的 IR 变量索引，存入 命令行参数个数索引（gv_argc）
    如果 名称索引 等于 参数指针原生内建索引（argv_ni），那么：调用 读 64 位，读取偏移 +8，存入 命令行参数指针索引（gv_argv）
    如果 名称索引 等于 当前原生内建索引（cur_ni），那么：调用 读 64 位，读取偏移 +8，存入 当前竞技场索引（gv_current_arena）
    如果 名称索引 等于 当前原生内建索引2（cur_ni2），那么：调用 读 64 位，读取偏移 +8，存入 竞技场游标索引（gv_arena_cursors）
    如果 名称索引 等于 当前原生内建索引3（cur_ni3），那么：调用 读 64 位，读取偏移 +8，存入 竞技场大小索引（gv_arena_sizes）
    如果 名称索引 等于 当前原生内建索引4（cur_ni4），那么：调用 读 64 位，读取偏移 +8，存入 竞技场内存池数据索引（gv_arena_pool_data）
    如果 名称索引 等于 当前原生内建索引5（cur_ni5），那么：调用 读 64 位，读取偏移 +8，存入 竞技场最大大小索引（gv_arena_max_size）
    如果 名称索引 等于 当前原生内建索引6（cur_ni6），那么：调用 读 64 位，读取偏移 +8，存入 堆指针索引（gv_heap_ptr）
    如果 名称索引 等于 当前原生内建索引7（cur_ni7），那么：调用 读 64 位，读取偏移 +8，存入 堆末尾索引（gv_heap_end）
    如果 名称索引 等于 当前原生内建索引8（cur_ni8），那么：调用 读 64 位，读取偏移 +8，存入 热补丁配置索引（gv_hp_config）
    如果 名称索引 等于 当前原生内建索引9（cur_ni9），那么：调用 读 64 位，读取偏移 +8，存入 热补丁进行中计数索引（gv_hp_inflight）
    令 全局变量扫描索引 = 全局变量扫描索引 + 1

#### Phase 2：计算所有代码段的大小

—— 第一步：输出阶段提示
调用 输出带换行函数（println），输出 "  可执行文件格式（elf）: Phase 2 （size calc）..."

—— 第二步：统计最大标签索引（用于 Phase 3 分配 g_label_poses）并估算各用户函数的代码大小（每条指令均值约 5 字节，后续在 Phase 3 实际发射时才确定精确值）
令 最大标签索引（max_labels）= 0
令 函数遍历索引（sfi）= 0
循环（当 函数遍历索引 小于 IR 函数个数（g_ir_func_count）时）：
    调用 读 64 位（r64），从 IR 函数指令起始索引数组（g_ir_func_instr_start）偏移量 函数遍历索引 × 8 处读取起始指令索引，存入 临时变量 指令起始（ist2）
    调用 读 64 位（r64），从 IR 函数指令计数数组（g_ir_func_instr_count）偏移量 函数遍历索引 × 8 处读取指令数，存入 临时变量 指令数（ic2）
    —— 遍历该函数的所有指令，统计 标签指令（IR_LABEL）、分支指令（IR_BRANCH）、跳转指令（IR_JUMP） 中引用的标签索引的最大值
    令 当前函数标签数（cur_labels）= 0
    令 指令遍历索引（ii2）= 0
    循环（当 指令遍历索引 小于 指令数 时）：
        调用 指令操作码（iri_op），参数 指令起始 + 指令遍历索引，获取该指令的操作码，存入 临时变量 操作码（op）
        如果 操作码 等于 标签指令（IR_LABEL），那么：
            调用 指令源1（iri_s1），参数 指令起始 + 指令遍历索引，获取标签索引，存入 临时变量 标签索引（lx）
            如果 标签索引 大于等于 0 且 标签索引 + 1 大于 当前函数标签数，那么：令 当前函数标签数 = 标签索引 + 1
        如果 操作码 等于 分支指令（IR_BRANCH），那么：
            调用 指令源2（iri_s2），获取条件为真时的跳转目标标签索引，存入 标签索引（lx）；如果 标签索引 + 1 大于 当前函数标签数，那么：令 当前函数标签数 = 标签索引 + 1
            调用 指令源3（iri_s3），获取条件为假时的跳转目标标签索引，存入 临时变量 标签索引2（ly）；如果 标签索引2 + 1 大于 当前函数标签数，那么：令 当前函数标签数 = 标签索引2 + 1
        如果 操作码 等于 跳转指令（IR_JUMP），那么：
            调用 指令源1（iri_s1），获取跳转目标标签索引，存入 临时变量 标签索引3（lz）；如果 标签索引3 + 1 大于 当前函数标签数，那么：令 当前函数标签数 = 标签索引3 + 1
        令 指令遍历索引 = 指令遍历索引 + 1
    如果 当前函数标签数 大于 最大标签索引，那么：令 最大标签索引 = 当前函数标签数
    —— 粗略估计该函数的代码大小：指令数 × 5 字节/指令
    调用 扩展函数代码大小数组（grow_func_code_sz），参数 函数遍历索引 + 1
    调用 写 64 位（w64），向 x86 函数代码大小数组（g_x86_func_code_sz）偏移量 函数遍历索引 × 8 处写入 指令数 × 5
    令 函数遍历索引 = 函数遍历索引 + 1
令 标签计数（g_label_count）= 最大标签索引

—— 第三步：累加 _start 函数的大小
令 总代码大小（total_code）= 调用 发射 _start 大小（emit_start_size（））

—— 第四步：遍历所有用户函数，累加序言、函数体、尾声的大小
令 函数索引（fi）= 0
调用 全局变量初始化（g2_init）—— 重置 全局变量寻址（g2） 插槽分配器状态
循环（当 函数索引 小于 IR 函数个数 时）：
    —— 每 50 个函数输出一次进度提示
    如果 函数索引 除以 50 的余数 等于 0，那么：
        调用 输出函数（print），输出 "    函数（func） "
        调用 输出函数，输出 整数转字符串（int_str）的结果，参数 函数索引
        调用 输出函数，输出 "/"
        调用 输出带换行函数（println），输出 整数转字符串（int_str）的结果，参数 IR 函数计数（g_ir_func_count）

    调用 读 64 位（r64），从 IR 函数名索引数组（g_ir_func_name_idx）偏移量 函数索引 × 8 处读取名称驻留索引，存入 临时变量 名称索引（ni）

    —— 在函数偏移量表中注册该函数（名称 + 当前累计偏移量）
    调用 扩展函数偏移数组（grow_func_offsets），参数 当前偏移计数 × 2 + 2（确保容纳一对 16 字节条目）
    调用 写 64 位（w64），向 x86 函数偏移数组（g_x86_func_offsets）偏移量 当前偏移计数 × 16 + 0 处写入 名称索引
    调用 写 64 位（w64），向 x86 函数偏移数组 偏移量 当前偏移计数 × 16 + 8 处写入 总代码大小（该函数在代码段内的估计偏移量）
    令 x86 函数偏移计数（g_x86_func_off_count）= x86 函数偏移计数 + 1

    调用 读 64 位（r64），从 IR 函数变量计数数组（g_ir_func_var_count）偏移量 函数索引 × 8 处读取变量数，存入 变量数（vc2）
    调用 读 64 位（r64），从 IR 函数参数计数数组（g_ir_func_param_count）偏移量 函数索引 × 8 处读取参数数，存入 参数数（pc2）

    调用 读 64 位（r64），从 x86 函数代码大小数组 偏移量 函数索引 × 8 处读取估算的代码大小，存入 函数体大小（fsz）
    令 x86 发射栈大小（g_x86_emit_stack_size）= 变量数 × 8

    —— 累加序言大小
    令 总代码大小 = 总代码大小 + push rbp 大小（sz_push_rbp（），=1）
    令 总代码大小 = 总代码大小 + mov rbp, rsp 大小（sz_mov_rbp_rsp（），=3）
    如果 优化级别（g_opt_level）大于等于 1，那么：令 总代码大小 = 总代码大小 + 18（push rbx,r12-r15 共 9 字节 + pop r15-r12,rbx 共 9 字节）
    令 临时变量 栈帧大小（ss_dry）= x86 发射栈大小（g_x86_emit_stack_size）
    令 总代码大小 = 总代码大小 + sub rsp 大小（ss_dry），即 栈大小试算（ss_dry）>127 时为 7，0<栈大小试算<=127 时为 4，栈大小试算<=0 时为 0

    —— 累加参数保存大小
    令 寄存器参数数量（reg_pc2）= 参数数；如果 寄存器参数数量 大于 6，那么：令 寄存器参数数量 = 6（前 6 个参数通过寄存器传递）
    令 栈参数数量（stack_pc2）= 参数数 - 6；如果 栈参数数量 小于 0，那么：令 栈参数数量 = 0
    令 总代码大小 = 总代码大小 + 寄存器参数数量 × 寄存器保存参数大小（sz_save_param（），=4）
    令 总代码大小 = 总代码大小 + 栈参数数量 × 栈保存参数大小（sz_save_stack_param（），=8，需要从调用者帧加载再本地存储）

    —— 累加函数体和尾声大小
    令 总代码大小 = 总代码大小 + 函数体大小
    令 总代码大小 = 总代码大小 + add rsp 大小（ss_dry）+ pop rbp 大小（sz_pop_rbp（），=1）+ RET 指令大小（sz_ret（），=1）
    如果 优化级别 大于等于 1，那么：令 总代码大小 = 总代码大小 + 9（pop r15,r14,r13,r12,rbx 共 9 字节，注意 Phase 2 的 9+9=18 已包含了 push 和 pop 的总量）

    令 函数索引 = 函数索引 + 1

—— 第五步：累加 .只读数据段（rodata） 只读数据段和 初始化全局变量（_init_globals） 空函数的大小
调用 临时变量 只读数据大小（rd_sz）= 全局变量只读数据大小（g2_rodata_sz（））
令 总代码大小 = 总代码大小 + 6（初始化全局变量（_init_globals） 空函数：push rbp（1） + mov rbp,rsp（3） + pop rbp（1） + 返回（ret）（1） = 6 字节）

—— 第六步：在函数偏移量表中注册 分配函数（alloc） 内置分配函数
—— 首先在字符串表中查找 "分配函数（alloc）" 名称的驻留索引；若未找到（用户代码未引用 分配函数），则通过 字符串驻留（str_intern） 新注册
令 临时变量 分配器名称索引（alloc_ni）= -1
令 临时变量 分配器搜索索引（asi）= 0
循环（当 分配器搜索索引 小于 字符串常量计数（g_str_count）时）：
    调用 字符串相等比较（str_eq），比较 驻留字符串获取（分配器搜索索引）与 "分配函数（alloc）"；如果返回值不等于 0，那么：令 分配原生内建索引（alloc_ni） = 分配器搜索索引；跳出循环
    令 分配器搜索索引 = 分配器搜索索引 + 1
如果 分配原生内建索引（alloc_ni） 小于 0，那么：调用 字符串驻留（str_intern），参数 "分配函数（alloc）"，存入 分配原生内建索引
—— 注册到函数偏移量表
调用 扩展函数偏移数组（grow_func_offsets），参数 当前偏移计数 × 2 + 2
调用 写 64 位（w64），向 x86 函数偏移数组 写入名称（alloc_ni）和偏移量（total_code）
令 x86 函数偏移计数 = x86 函数偏移计数 + 1
令 总代码大小 = 总代码大小 + 330（竞技场感知双路径分配器主体的估计大小：约 323 字节含 OOM 检查 + 零初始化 + 链式扩展 + 当前竞技场检查，外加安全余量）

—— 第七步：注册 扩展堆（heap_expand） 函数
调用 扩展函数偏移数组（grow_func_offsets），参数 当前偏移计数 × 2 + 2
调用 写 64 位（w64），写入 字符串驻留（"heap_expand"） 和 总代码大小（total_code）
令 x86 函数偏移计数 = x86 函数偏移计数 + 1
令 总代码大小 = 总代码大小 + 80（heap_expand 估计大小约 71 字节 + 安全余量）

—— 第八步：注册 5 个 调度调用（sched_call） 跳板（sched_call_0 到 sched_call_4），每个大小由 调度跳板大小（sched_tramp_sz）（n） 决定
对每个调度级别（n） 从 0 到 4，分别执行：
    调用 扩展函数偏移数组，写入 字符串驻留（"sched_call_" + 数量（n） 的字符串表示）和 总代码大小（total_code）
    令 x86 函数偏移计数 = x86 函数偏移计数 + 1
    令 总代码大小 = 总代码大小 + 调度跳板大小（n）

—— 第九步：若需要发射运行时桩（g_x86_emit_rt_stubs != 0），注册 设置当前协程函数索引（g_set_curg） 和 获取当前协程函数索引（g_get_curg）（纯静态自包含桥接函数，各 11 字节）
如果 x86 是否需要发射运行时桩标记（g_x86_emit_rt_stubs）不等于 0，那么：
    调用 扩展函数偏移数组，写入 字符串驻留（"g_set_curg"）和 总代码大小（total_code）
    令 x86 函数偏移计数 = x86 函数偏移计数 + 1
    令 总代码大小 = 总代码大小 + 11
    调用 扩展函数偏移数组，写入 字符串驻留（"g_get_curg"）和 总代码大小（total_code）
    令 x86 函数偏移计数 = x86 函数偏移计数 + 1
    令 总代码大小 = 总代码大小 + 11

—— 第十步：计算 ELF 头 + 程序头的总大小，以及 .只读数据段（rodata） 段在输出缓冲区中的基址
令 临时变量 头总大小（hdr_total）= ELF 头大小常量（EHDR_SIZE=64）+ 2 × 程序头大小常量（PHDR_SIZE=56）= 64 + 112 = 176
令 临时变量 只读数据段（rodata） 基址（rodata_base）= 总代码大小
令 x86 只读数据段（rodata） 基址（g_x86_rodata_base）= 头总大小 + 只读数据段 基址（即 .rodata 段在输出文件中的绝对偏移量，Phase 3 末尾会再次覆写为实际值）

#### Phase 3：实际发射所有机器码到缓冲区

—— 第一步：输出阶段提示
调用 输出带换行函数（println），输出 "  可执行文件格式（elf）: Phase 3 （emit）..."

—— 第二步：将当前指针定位到 ELF 头之后
令 临时变量 当前指针（cp）= 头总大小（176，跳过 ELF 文件头 + 程序头区域，Phase 4 将在此写入头信息）

—— 第三步：发射 _start 入口函数
令 当前指针 = 当前指针 + 发射 _start（emit_start）的结果，参数 缓冲区（buf）和 当前指针。发射起始函数（emit_start） 返回实际写入的字节数。

—— 第四步：复位所有修补计数器（Phase 3 将重新填充这些数组）
令 x86 RET 修补计数（g_x86_ret_patch_count）= 0
令 x86 调用修补计数（g_x86_call_patch_count）= 0
令 x86 函数地址修补计数（g_x86_fnaddr_patch_count）= 0
令 x86 只读数据段（rodata） 引用计数（g_x86_rodataref_count）= 0
令 x86 分配修补计数（g_x86_alloc_patch_count）= 0
令 x86 外部重定位计数（g_x86_ext_rel_count）= 0

—— 第五步：遍历所有用户函数，逐个发射序言、参数保存、函数体、尾声
令 函数索引（fi）= 0
循环（当 函数索引 小于 IR 函数个数 时）：
    —— 每 50 个函数输出进度
    如果 函数索引 % 50 == 0：输出 "    发射（emit） 函数（func） " + 函数信息（fi） + "/" + IR 函数计数（g_ir_func_count）

    调用 读 64 位，获取该函数的名称驻留索引（ni = g_ir_func_name_idx[fi]）

    —— 记录该函数在缓冲区中的绝对起始位置（用于前向调用修补和函数地址修补）
    调用 扩展函数当前指针数组（grow_func_cp），参数 函数索引 + 1
    调用 写 64 位，向 x86 函数当前指针（g_x86_func_cp）偏移量 函数索引 × 8 处写入 当前指针

    —— 将函数偏移量表中 Phase 2 的估计值覆写为实际位置（用于 Phase 3 末尾的后向调用修补）
    令 临时变量 偏移查找索引（fi3）= 0
    循环（当 偏移查找索引 小于 x86 函数偏移计数 时）：
        如果 驻留字符串获取（从 g_x86_func_offsets[fi3×16] 读取名称）等于 驻留字符串获取（ni），那么：
            调用 写 64 位，向 x86 函数偏移数组（g_x86_func_offsets）[函数信息3（fi3）×16+8] 写入 当前指针 - 176（代码段内偏移量）
            跳出循环
        令 偏移查找索引 = 偏移查找索引 + 1

    —— 读取该函数的元数据
    调用 读 64 位，获取指令起始索引：指令起始（ist） = IR 函数指令起始（g_ir_func_instr_start）[函数信息（fi）]
    调用 读 64 位，获取指令数量：指令计数（ic） = IR 函数指令计数（g_ir_func_instr_count）[函数信息（fi）]
    调用 读 64 位，获取变量数量：变量计数（vc） = IR 函数变量计数（g_ir_func_var_count）[函数信息（fi）]
    调用 读 64 位，获取变量起始索引：变量起始（vs） = IR 函数变量起始（g_ir_func_var_start）[函数信息（fi）]
    调用 读 64 位，获取参数数量：程序计数器（pc） = IR 函数参数计数（g_ir_func_param_count）[函数信息（fi）]

    —— 初始化 全局变量寻址（g2） 槽位分配器，为所有局部变量分配栈槽位
    调用 全局变量初始化（g2_init）
    令 当前函数变量起始（x86 后端）（g_current_func_var_start）= 变量起始（vs）
    令 临时变量 变量索引（vi）= 0
    循环（当 变量索引 小于 变量数量 时）：
        调用 全局变量槽位（g2_slot），参数 变量起始（vs） + 变量索引（为该变量分配一个相对于 rbp 的栈偏移量）
        令 变量索引 = 变量索引 + 1
    令 x86 发射栈大小（g_x86_emit_stack_size）= 变量数量 × 8

    —— 初始化标签状态数组（所有标签位置设为 -1 = 尚未遇到，用于单遍后向修补）
    令 临时变量 标签初始化索引（li2）= 0
    循环（当 标签初始化索引 小于 标签计数 时）：
        调用 扩展标签位置数组（grow_label_poses），参数 标签初始化索引 + 1
        调用 写 64 位，向 标签位置数组（g_label_poses）偏移量 标签初始化索引 × 8 处写入 -1
        令 标签初始化索引 = 标签初始化索引 + 1
    令 待处理计数（g_pending_count）= 0

    —— 写入序言：被调用者保存寄存器（仅优化级别 >= 1）
    如果 优化级别 大于等于 1，那么：
        调用 写单字节（w8），写入 0x53（push rbx），令 当前指针 = 当前指针 + 1
        调用 写单字节，写入 0x41；调用 写单字节，写入 0x54（push r12），令 当前指针 = 当前指针 + 2
        调用 写单字节，写入 0x41；调用 写单字节，写入 0x55（push r13），令 当前指针 = 当前指针 + 2
        调用 写单字节，写入 0x41；调用 写单字节，写入 0x56（push r14），令 当前指针 = 当前指针 + 2
        调用 写单字节，写入 0x41；调用 写单字节，写入 0x57（push r15），令 当前指针 = 当前指针 + 2

    —— 建立栈帧
    调用 写单字节，写入 0x55（push rbp），令 当前指针 = 当前指针 + 1
    调用 写单字节，写入 0x48；调用 写单字节，写入 0x89；调用 写单字节，写入 0xE5（mov rbp, rsp：REX.W=0x48 + 操作码 0x89 + ModRM mod=11,reg=5,rsp=4 → 0xE5），令 当前指针 = 当前指针 + 3
    令 x86 sub rsp 指令位置（g_x86_sub_rsp_pos）= 当前指针
    如果 发射栈大小 大于 0，那么：
        如果 发射栈大小 大于 127，那么：
            —— 7 字节形式：REX.W（0x48） + 0x81 /5 + disp32
            调用 写单字节，写入 0x48；调用 写单字节，写入 0x81；调用 写单字节，写入 0xEC（sub rsp, imm32）
            调用 发射写 32 位（e2_w32），写入 0（占位符）
            令 当前指针 = 当前指针 + 7
        否则：
            —— 4 字节形式：REX.W（0x48） + 0x83 /5 + disp8
            调用 写单字节，写入 0x48；调用 写单字节，写入 0x83；调用 写单字节，写入 0xEC；调用 写单字节，写入 0（占位符）
            令 当前指针 = 当前指针 + 4

    —— 将寄存器和调用者栈中的参数保存到函数的局部变量槽位
    令 临时变量 参数索引（pi）= 0
    循环（当 参数索引 小于 参数数量 时）：
        令 临时变量 参数栈偏移（po2）= -（vs + 参数索引 + 1 - g_current_func_var_start） × 8（强制使用栈槽位，忽略寄存器分配）
        如果 参数索引 等于 0，那么：调用 发射存储（e2_st），参数 rdi=7（第一个参数寄存器），偏移量=参数偏移2（po2）（mov [rbp+disp], rdi）；令 当前指针 = 当前指针 + 返回值
        如果 参数索引 等于 1，那么：REX.W（0x48） + 0x89 + ModRM mod=01,reg=6（rsi）,rm=5（rbp） → 0x75 + disp8=参数偏移2（po2）（mov [rbp+disp8], rsi）；令 当前指针 = 当前指针 + 4
        如果 参数索引 等于 2，那么：REX.W（0x48） + 0x89 + ModRM mod=01,reg=2（rdx）,rm=5 → 0x55 + disp8=参数偏移2（po2）；令 当前指针 = 当前指针 + 4
        如果 参数索引 等于 3，那么：REX.W（0x48） + 0x89 + ModRM mod=01,reg=1（rcx）,rm=5 → 0x4D + disp8=参数偏移2（po2）；令 当前指针 = 当前指针 + 4
        如果 参数索引 等于 4，那么：REX.WR（0x4C） + 0x89 + ModRM mod=01,reg=1（r8）,rm=5 → 0x45 + disp8=参数偏移2（po2）；令 当前指针 = 当前指针 + 4
        如果 参数索引 等于 5，那么：REX.WR（0x4C） + 0x89 + ModRM mod=01,reg=1（r9）,rm=5 → 0x4D + disp8=参数偏移2（po2）；令 当前指针 = 当前指针 + 4
        如果 参数索引 大于等于 6，那么：
            —— 第 7+ 个参数在调用者的栈帧中（[rbp+16+...]），需要先从调用者帧加载到 r10，再存储到本地槽位
            令 临时变量 调用者偏移（caller_off）= 16 + （参数索引 - 6） × 8
            如果 优化级别 大于等于 1，那么：令 调用者偏移 = 调用者偏移 + 40（被调用者保存的 rbx,r12-r15 各占 8 字节，共 5×8=40 字节）
            调用 发射加载双字（e2_ld），参数 r10=10，偏移量=调用者偏移（从 [rbp+caller_off] 加载到 r10）；令 当前指针 = 当前指针 + 返回值
            调用 发射存储（e2_st），参数 r10=10，偏移量=参数栈偏移（存储到本地槽位）；令 当前指针 = 当前指针 + 返回值
        令 参数索引 = 参数索引 + 1

    —— 若优化级别 >= 1，将已分配寄存器的参数从栈槽位加载到分配的寄存器
    如果 优化级别 大于等于 1，那么：
        令 临时变量 寄存器参数索引（pi2）= 0
        循环（当 寄存器参数索引 小于 参数数量 且 寄存器参数索引 小于 6 时）：
            调用 获取变量寄存器（get_reg_for_var），参数 变量起始（vs） + 寄存器参数索引，获取分配给该参数的寄存器编号，存入 临时变量 参数寄存器（pri）
            如果 参数寄存器 大于等于 0，那么：
                —— 从栈槽位加载到分配的寄存器
                令 临时变量 参数源偏移（pso2）= -（vs + 寄存器参数索引 + 1 - g_current_func_var_start） × 8
                调用 发射 REX 前缀（emit_rex），参数 W=1, R=优先级（pri）/8（reg 高位）, X=0, B=0；令 当前指针 = 当前指针 + 返回值
                调用 发射写 8 位（e2_w8），写入 139（0x8B，MOV r64, r/m64）；令 当前指针 = 当前指针 + 1
                调用 发射 ModRM（emit_modrm），参数 mod=1（disp8）, reg=优先级（pri）%8（目的寄存器）, rm=5（[rbp+disp8]）；令 当前指针 = 当前指针 + 返回值
                调用 发射写 8 位，写入 参数源偏移（有符号 8 位偏移量）；令 当前指针 = 当前指针 + 1
            令 寄存器参数索引 = 寄存器参数索引 + 1

    —— 函数体：逐条发射 IR 指令
    令 x86 函数帧起始（g_x86_func_frame_start）= 当前指针（记录函数体开始的缓冲区绝对位置）
    令 临时变量 保存的栈大小（save_ss）= x86 发射栈大小（g_x86_emit_stack_size）（保存栈帧大小，用于稍后的 sub rsp 修补和尾声发射）
    令 临时变量 指令索引（ii）= 0
    循环（当 指令索引 小于 指令数量 时）：
        令 临时变量 当前指令全局索引（inst_idx）= 指令起始（ist） + 指令索引
        调用 发射单条指令（emit_instr），参数 当前指令全局索引、缓冲区、当前指针。返回该指令写入的字节数，存入 临时变量 指令大小（sz）
        令 当前指针 = 当前指针 + 指令大小
        令 指令索引 = 指令索引 + 1

    —— 修补所有 RETURN 占位符，使它们跳转到稍后发射的尾声
    令 临时变量 尾声位置（epi_pos）= 当前指针
    调用 输出函数，输出 "  返回序列（rets）: " + 整数转字符串（g_x86_ret_patch_count）
    令 临时变量 返回（ret） 修补索引（rpi）= 0
    循环（当 返回（ret） 修补索引 小于 x86 RET 修补计数 时）：
        调用 读 64 位，从 x86 RET 修补位置数组 偏移量 返回（ret） 修补索引 × 8 处读取 jmp 占位符的缓冲区位置，存入 跳转位置（jmp_pos）
        令 临时变量 相对偏移（rel）= 尾声位置 - （跳转位置 + 5）（计算 E9 后 rel32 的实际值，5 是 jmp 指令总长度）
        调用 写 32 位（w32），向缓冲区偏移量 跳转位置 + 1 处写入 相对偏移（覆盖占位符 0）
        令 返回（ret） 修补索引 = 返回 修补索引 + 1
    令 x86 返回修补计数（g_x86_ret_patch_count） = 0

    —— 修补序言 sub rsp 的实际栈大小
    如果 保存的栈大小 大于 0，那么：
        如果 保存的栈大小 大于 127，那么：调用 发射写 32 位，向缓冲区偏移量 x86 栈帧预留位置（g_x86_sub_rsp_pos） + 3 处写入 保存的栈大小（7 字节形式的位移字段）
        否则：调用 写单字节，向缓冲区偏移量 x86 栈帧预留位置（g_x86_sub_rsp_pos） + 3 处写入 保存的栈大小（4 字节形式的位移字段）

    —— 发射尾声（使用实际栈大小，非占位符）
    如果 保存的栈大小 大于 0，那么：
        如果 保存的栈大小 大于 127，那么：REX.W（0x48） + 0x81 /0 + disp32 = 7 字节形式；令 当前指针 + 7
        否则：REX.W（0x48） + 0x83 /0 + disp8 = 4 字节形式；令 当前指针 + 4
    如果 优化级别 大于等于 1，那么：
        —— 按逆序弹出：rbp, r15, r14, r13, r12, rbx（对应 push 的逆序）
        调用 写单字节，写入 0x5D（pop rbp）；令 当前指针 + 1
        调用 写单字节，写入 0x41；写入 0x5F（pop r15）；令 当前指针 + 2
        调用 写单字节，写入 0x41；写入 0x5E（pop r14）；令 当前指针 + 2
        调用 写单字节，写入 0x41；写入 0x5D（pop r13）；令 当前指针 + 2
        调用 写单字节，写入 0x41；写入 0x5C（pop r12）；令 当前指针 + 2
        调用 写单字节，写入 0x5B（pop rbx）；令 当前指针 + 1
    否则：
        调用 写单字节，写入 0x5D（pop rbp）；令 当前指针 + 1
    调用 写单字节，写入 0xC3（ret）；令 当前指针 + 1

    令 函数索引 = 函数索引 + 1

—— 第六步：发射 初始化全局变量（_init_globals） 空函数（仅栈帧建立和拆除，无函数体）
调用 写单字节，写入 0x55（push rbp）；令 当前指针 + 1
调用 写单字节，写入 0x48；写入 0x89；写入 0xE5（mov rbp, rsp）；令 当前指针 + 3
调用 写单字节，写入 0x5D（pop rbp）；令 当前指针 + 1
调用 写单字节，写入 0xC3（ret）；令 当前指针 + 1

—— 第七步：计算临时的 BSS 虚拟地址（基于当前 cp + 页对齐余量），统计最大全局变量索引以确定 BSS 区域大小
令 临时变量 BSS 虚拟地址（bss_va）= （（代码段基址 代码段基址（TEXT_BASE） + 当前指针 + 4096 + 4095） / 4096） × 4096（向上对齐到下一页边界）
令 临时变量 最大变量编号（max_gv）= 0
令 临时变量 全局扫描索引（gsi）= 0
循环（当 全局扫描索引 小于 IR 全局变量计数 时）：
    调用 读 64 位，从 IR 全局变量数组（g_ir_globals）[全局扫描索引 × 24 + 8] 读取变量编号（gvv）
    如果 变量编号 大于等于 0 且 变量编号 大于 最大变量编号，那么：令 最大变量编号 = 变量编号
    令 全局扫描索引 = 全局扫描索引 + 1
令 临时变量 全局变量总大小（globals_size）= （最大变量编号 + 1） × 8（每个全局变量指针 8 字节）
如果 全局变量总大小 小于 256，那么：令 全局变量总大小 = 256（最低保证 256 字节 BSS）
如果 x86 是否需要发射运行时桩标记 不等于 0，那么：令 全局变量总大小 = 全局变量总大小 + 8（为 current_g 指针额外预留 8 字节在 BSS 末尾）

—— 第八步：发射 分配函数（alloc） 分配函数体（使用临时 BSS VA）
调用 发射分配函数体（emit_alloc_body）（缓冲区（buf）, 当前指针, BSS 起始虚拟地址（bss_va）, 全局变量总大小），返回写入字节数，存入 临时变量 分配器大小（alloc_sz）
令 临时变量 分配函数（alloc） 起始位置（alloc_start）= 当前指针
令 当前协程（curg） 桩起始位置（g_curg_stub_start）= -1（稍后若需要会覆写）
令 当前指针 = 当前指针 + 分配器大小

—— 第九步：发射 扩展堆（heap_expand） 堆扩展函数体，并更新其在函数偏移量表中的偏移
令 临时变量 堆扩展起始位置（heap_expand_start）= 当前指针
调用 发射扩展堆（emit_heap_expand）（缓冲区（buf）, 当前指针, bss_va），返回写入字节数
令 当前指针 = 当前指针 + 返回值
—— 更新 扩展堆（heap_expand） 在函数偏移量表中的条目为实际位置
令 临时变量 堆扩展查找索引（hefi）= 0
循环（当 堆扩展查找索引 小于 x86 函数偏移计数 时）：
    如果 驻留字符串获取（g_x86_func_offsets[hefi×16]）等于 "扩展堆（heap_expand）"，那么：
        调用 写 64 位，将 x86 函数偏移数组（g_x86_func_offsets）[扩展堆函数信息（hefi）×16+8] 覆写为 扩展堆起始（heap_expand_start） - 176
        跳出循环
    令 堆扩展查找索引 = 堆扩展查找索引 + 1

—— 第十步：更新 分配函数（alloc） 在函数偏移量表中的条目为实际位置
令 临时变量 分配函数（alloc） 查找索引（afi2）= 0
循环（当 分配函数（alloc） 查找索引 小于 x86 函数偏移计数 时）：
    如果 驻留字符串获取（g_x86_func_offsets[afi2×16]）等于 驻留字符串获取（alloc_ni），那么：
        调用 写 64 位，将 x86 函数偏移数组（g_x86_func_offsets）[函数信息访问器2（afi2）×16+8] 覆写为 分配起始（alloc_start） - 176
        跳出循环
    令 分配函数（alloc） 查找索引 = 分配函数 查找索引 + 1

—— 第十一步：修补所有 IR_ALLOC_STRUCT/ARRAY/MAKE_ENUM 的 call 占位符，使其指向 分配函数（alloc） 函数
—— 分配修补位置（alloc_patch_pos） 数组中的条目是 5 字节 CALL 指令的缓冲区位置（由 emit_instr 在遇到分配 IR 指令时记录）
—— 分配函数（alloc） 在代码段内的偏移量为 分配起始（alloc_start） - 176（相对于 TEXT_BASE+176 即代码段起始）
令 临时变量 分配函数（alloc） 代码偏移（alloc_code_off）= 分配起始（alloc_start） - 176
令 临时变量 分配函数（alloc） 修补索引（api）= 0
循环（当 分配函数（alloc） 修补索引 小于 x86 分配修补计数 时）：
    调用 读 64 位，从 x86 分配修补位置（g_x86_alloc_patch_pos）[应用接口（api）×8] 读取 call 指令缓冲区位置，存入 调用位置（call_pos）
    令 相对偏移（rel）= （176 + alloc_code_off） - （调用位置 + 5）（计算从 call 指令末尾到 分配函数（alloc） 入口的字节距离）
    调用 写 32 位（w32），向缓冲区偏移量 调用位置 + 1 处写入 相对偏移
    令 分配函数（alloc） 修补索引 = 分配函数 修补索引 + 1
令 x86 分配修补计数（g_x86_alloc_patch_count） = 0

—— 第十二步：发射 竞技场新建（arena_new） / 竞技场重置（arena_reset） 桩（各 1 字节 返回（ret），当 arena.cr 未导入时的 fallback）
—— 若用户代码导入了 竞技场（arena） 模块，编译后的版本在 IR 函数名索引（g_ir_func_name_idx） 中优先匹配，调用修补位置（call_patch） 会选择实际编译版本；桩仅作为后备
调用 扩展函数偏移数组，写入 字符串驻留（"arena_new"）和 当前指针 - 176
令 x86 函数偏移计数 = x86 函数偏移计数 + 1
调用 写单字节，写入 0xC3（ret）；令 当前指针 + 1

调用 扩展函数偏移数组，写入 字符串驻留（"arena_reset"）和 当前指针 - 176
令 x86 函数偏移计数 = x86 函数偏移计数 + 1
调用 写单字节，写入 0xC3（ret）；令 当前指针 + 1

—— 第十三步：发射 5 个 调度调用（sched_call） 跳板（sched_call_0 到 sched_call_4）
对每个调度级别（n） 从 0 到 4：
    调用 调度：注册一个（sched_reg_one），参数 "调度调用族（sched_call_）" + 调度级别（n） 的字符串、调度级别、当前指针。该函数在函数偏移量表中注册该跳板。
    调用 发射调度调用（emit_sched_call），参数 缓冲区、当前指针、调度级别（n）。返回写入的字节数。
    令 当前指针 = 当前指针 + 返回值

—— 第十四步：若需要运行时桩，发射 当前协程（curg） 桥接桩（g_set_curg / g_get_curg）
—— 使用临时 BSS VA = 0，后续 重新发射（emit） 阶段用实际 BSS VA 原地覆盖
如果 x86 发射运行时桩（g_x86_emit_rt_stubs） 不等于 0，那么：
    令 当前协程桩起始（g_curg_stub_start） = 当前指针
    调用 发射当前协程桩（emit_curg_stubs）（缓冲区（buf）, 当前指针, 0），返回写入字节数
    令 当前指针 = 当前指针 + 返回值
    —— 更新函数偏移量表中的 当前协程（curg） 条目为实际位置（call_patch 的 fallback 路径使用此表）
    令 临时变量 当前协程（curg） 偏移查找索引（gsi2）= 0
    循环（当 curg 偏移查找索引 小于 x86 函数偏移计数 时）：
        令 临时变量 当前协程（curg） 名称（nm2）= 驻留字符串获取（g_x86_func_offsets[curg偏移查找索引×16]）
        如果 当前协程（curg） 名称 等于 "设置当前协程函数索引（g_set_curg）"，那么：调用 写 64 位，将偏移条目覆写为 当前协程桩起始（g_curg_stub_start） - 176
        如果 当前协程（curg） 名称 等于 "获取当前协程函数索引（g_get_curg）"，那么：调用 写 64 位，将偏移条目覆写为 当前协程桩起始（g_curg_stub_start） - 176 + 11（g_get_curg 在 g_set_curg 之后 11 字节）
        令 当前协程（curg） 偏移查找索引 = 当前协程 偏移查找索引 + 1

—— 第十五步：若需要运行时桩，发射协程运行时桩（fiber_init / fiber_switch / goroutine_entry_wrapper / m_start_workers）
—— 协程初始化（fiber_init） 构建伪栈帧，协程切换（fiber_switch） 执行上下文切换，协程入口包装（goroutine_entry_wrapper） 为纤程入口包装器，启动工作线程桩（m_start_workers） 为工作线程启动器
如果 x86 发射运行时桩（g_x86_emit_rt_stubs） 不等于 0，那么：
    调用 调度单寄存器注册（sched_reg_one），注册 "协程初始化（fiber_init）"，偏移 0，当前指针
    调用 调度单寄存器注册（sched_reg_one），注册 "协程切换（fiber_switch）"，偏移 0，当前指针 + 20（fiber_switch 位于 fiber_init 之后 20 字节）
    调用 调度单寄存器注册（sched_reg_one），注册 "协程入口包装（goroutine_entry_wrapper）"，偏移 0，当前指针 + 47（位于 fiber_init 之后 47 字节）
    调用 发射协程桩（emit_goroutine_stubs）（缓冲区（buf）, 当前指针），返回写入字节数；令 当前指针 = 当前指针 + 返回值
    —— 启动工作线程桩（m_start_workers）：工作协程入口（worker_entry）（15 字节）位于公开入口之前，以便其 RIP 相对 LEA 向后引用；公开符号注册在 当前指针（cp）+15 处
    调用 调度单寄存器注册（sched_reg_one），注册 "启动工作线程桩（m_start_workers）"，偏移 0，当前指针 + 15
    调用 发射启动工作线程桩（emit_m_start_workers）（缓冲区（buf）, 当前指针），返回写入字节数；令 当前指针 = 当前指针 + 返回值

—— 第十六步：修补所有前向调用占位符（call_patch）
—— 遍历 x86 调用修补数组族（g_x86_call_patch_）* 数组，首先在 IR 函数名索引（g_ir_func_name_idx）/x86 函数当前指针（g_x86_func_cp） 中查找用户函数（含已发射的实际位置），若未找到再 回退（fallback） 到 x86 函数偏移数组（g_x86_func_offsets）（内建函数/桩）
令 临时变量 调用修补索引（cpi）= 0
循环（当 调用修补索引 小于 x86 调用修补计数 时）：
    调用 读 64 位，从 x86 调用修补位置（g_x86_call_patch_pos）[调用修补索引（cpi）×8] 读取 call 指令位置，存入 调用位置（call_pos）
    调用 读 64 位，从 x86 调用修补名称（g_x86_call_patch_name）[调用修补索引（cpi）×8] 读取目标函数名称索引，存入 函数名称索引（fn_ni）

    —— 主查找路径：遍历用户函数表
    令 临时变量 用户函数查找索引（cfi2）= 0
    循环（当 用户函数查找索引 小于 IR 函数个数 时）：
        调用 读 64 位，从 IR 函数名索引（g_ir_func_name_idx）[调用函数索引2（cfi2）×8] 读取函数名索引，存入 名称索引（name_at）
        如果 驻留字符串获取（名称索引）等于 驻留字符串获取（函数名称索引），那么：
            调用 读 64 位，从 x86 函数当前指针（g_x86_func_cp）[调用函数索引2（cfi2）×8] 读取该函数的缓冲区位置，存入 函数当前指针（func_cp）
            如果 函数当前指针 大于 0（函数已被发射到缓冲区），那么：
                令 相对偏移（rel）= 函数当前指针 - （调用位置 + 5）
                调用 写 32 位，向缓冲区偏移量 调用位置 + 1 处写入 相对偏移
            跳出循环
        令 用户函数查找索引 = 用户函数查找索引 + 1

    —— 备用查找路径：若主路径未找到（cfi2 >= g_ir_func_count），在函数偏移量表中搜索内建函数/桩
    如果 用户函数查找索引 大于等于 IR 函数个数，那么：
        令 临时变量 内建查找索引（bfi2）= 0
        循环（当 内建查找索引 小于 x86 函数偏移计数 时）：
            如果 驻留字符串获取（g_x86_func_offsets[bfi2×16]）等于 驻留字符串获取（函数名称索引），那么：
                调用 读 64 位，从 x86 函数偏移数组（g_x86_func_offsets）[函数体索引2（bfi2）×16+8] 读取代码段内偏移量，存入 函数偏移（func_off）
                令 临时变量 目标位置（target_pos）= 176 + 函数偏移（TEXT_BASE + 176 即代码段起始对应的缓冲区绝对位置）
                如果 目标位置 大于 0 且 目标位置 小于 当前指针（安全性检查：目标必须在已发射代码内），那么：
                    令 相对偏移 = 目标位置 - （调用位置 + 5）
                    调用 写 32 位，向缓冲区偏移量 调用位置 + 1 处写入 相对偏移
                跳出循环
            令 内建查找索引 = 内建查找索引 + 1

    令 调用修补索引 = 调用修补索引 + 1
令 x86 调用修补计数（g_x86_call_patch_count） = 0

—— 第十七步：修补所有函数地址占位符（函数地址指令（IR_FNADDR） movabs 占位符）
—— 每个占位符是 movabs r10, imm64 指令（12 字节），位于 x86 函数地址修补位置（g_x86_fnaddr_patch_pos） 记录的缓冲区位置
—— 按相同策略解析：先查用户函数表（g_ir_func_name_idx + g_x86_func_cp），再 回退（fallback） 到内建函数表（g_x86_func_offsets）
令 临时变量 函数地址修补索引（fpi）= 0
循环（当 函数地址修补索引 小于 x86 函数地址修补计数 时）：
    调用 读 64 位，读取补丁位置：帧指针位置（fp_pos） = x86 函数地址修补位置（g_x86_fnaddr_patch_pos）[函数地址修补索引（fpi）×8]
    调用 读 64 位，读取目标函数名索引：函数原生内建索引（fn_ni） = x86 函数地址修补名称（g_x86_fnaddr_patch_name）[函数地址修补索引（fpi）×8]
    令 临时变量 函数虚拟地址（fn_va）= 0

    —— 主查找路径：用户函数表
    令 临时变量 函数查找索引（fcfi）= 0
    循环（当 函数查找索引 小于 IR 函数个数 时）：
        调用 读 64 位，读取 名称索引（name_at） = IR 函数名索引（g_ir_func_name_idx）[函数调用索引（fcfi）×8]
        如果 驻留字符串获取（name_at）等于 驻留字符串获取（fn_ni），那么：
            调用 读 64 位，读取 函数当前指针（func_cp） = x86 函数当前指针（g_x86_func_cp）[函数调用索引（fcfi）×8]
            如果 函数当前指针（func_cp） > 0，那么：令 函数虚拟地址（fn_va） = 代码段基址（TEXT_BASE） + 函数当前指针（TEXT_BASE=0x400000 加上缓冲区内的代码位置 = 运行时 VA）
            跳出循环
        令 函数查找索引 = 函数查找索引 + 1

    —— 备用查找路径：内建函数表
    如果 函数虚拟地址（fn_va） == 0，那么：
        令 临时变量 内建查找索引（bfi3）= 0
        循环（当 内建查找索引 小于 x86 函数偏移计数 时）：
            如果 驻留字符串获取（g_x86_func_offsets[bfi3×16]）等于 驻留字符串获取（fn_ni），那么：
                调用 读 64 位，读取 函数偏移（func_off） = x86 函数偏移数组（g_x86_func_offsets）[函数体索引3（bfi3）×16+8]
                令 目标位置 = 176 + 函数偏移（func_off）
                如果 目标位置 > 0 且 目标位置 < 当前指针，那么：令 函数虚拟地址（fn_va） = 代码段基址（TEXT_BASE） + 目标位置
                跳出循环
            令 内建查找索引 = 内建查找索引 + 1

    如果 函数虚拟地址（fn_va） > 0，那么：调用 写 64 位（w64），向缓冲区偏移量 帧指针位置（fp_pos） + 2 处写入 函数虚拟地址（movabs 指令的 imm64 字段位于操作码 49 BB 之后 2 字节）
    令 函数地址修补索引 = 函数地址修补索引 + 1
令 x86 函数地址修补计数（g_x86_fnaddr_patch_count） = 0

—— 第十八步：将代码段填充到下一页边界（防止 RW 数据段与 RX 代码段共享同一物理页，否则内核会将该页映射为 RW 导致代码不可执行）
令 临时变量 代码填充结束位置（code_pad_end）= （当前指针 + 4095） / 4096 × 4096（向上对齐到 4096 的倍数）
循环（当 当前指针 小于 代码填充结束位置 时）：
    调用 写单字节（w8），向缓冲区偏移量 当前指针 处写入 0（填充零字节）
    令 当前指针 = 当前指针 + 1

—— 第十九步：将 .只读数据段（rodata） 基址设置为当前指针的实际位置（覆写 Phase 2 的估计值）
令 x86 只读数据段基址（g_x86_rodata_base） = 当前指针

—— 第二十步：修补所有 LEA .只读数据段（rodata） 引用（rodataref）
—— 只读数据引用（rodataref） 在 发射指令（emit_instr） 发射字符串常量访问时记录：LEA 指令的位置和目标字符串在 只读数据段（rodata） 段内的偏移
令 临时变量 只读数据段（rodata） 修补索引（rri）= 0
循环（当 rodata 修补索引 小于 x86 .rodata 引用计数 时）：
    调用 读 64 位，读取 LEA 指令位置：加载地址位置（lea_pos） = x86 只读数据引用位置（g_x86_rodataref_pos）[只读数据引用索引（rri）×8]
    调用 读 64 位，读取目标偏移：只读偏移（ro_off） = x86 只读数据引用段（g_x86_rodataref_ro）[只读数据引用索引（rri）×8]
    令 相对偏移（rel）= x86 只读数据段基址（g_x86_rodata_base） + 只读偏移（ro_off） - （lea_pos + 7）（计算从 LEA 指令末尾到目标字符串数据的距离，LEA 为 7 字节）
    调用 写 32 位（w32），向缓冲区偏移量 加载地址位置（lea_pos） + 3 处写入 相对偏移（LEA 的 rel32 字段位于指令的第 4-7 字节）
    令 只读数据段（rodata） 修补索引 = 只读数据段 修补索引 + 1
令 x86 只读数据引用计数（g_x86_rodataref_count） = 0

—— 第二十一步：发射 .只读数据段（rodata） 段（字符串常量数据）
—— 每个字符串以 8 字节长度头（字符串长度 + 1 含 null 终止符）为前缀，后跟字符串内容和 空字符（null） 终止符，最后填充到 8 字节对齐
令 字符串索引（si）= 0（复用 Phase 1 的变量名）
循环（当 字符串索引 小于 x86 字符串计数 时）：
    调用 读 64 位，从 x86 字符串偏移数组（g_x86_str_offs）[si×8] 读取字符串驻留索引
    调用 驻留字符串获取（istr_get），获取字符串内容，存入 临时变量 字符串内容（s）
    调用 字符串长度（str_len），获取字符串内容 的长度，存入 临时变量 字符串长度（sl）
    —— 写入 8 字节长度头（sl + 1，含 null 终止符），使得 读取 64 位（load64）（状态（s）, -8） 可以读取字符串长度
    调用 写 64 位（w64），向缓冲区偏移量 当前指针 处写入 字符串长度（sl） + 1；令 当前指针 = 当前指针 + 8
    —— 逐字节写入字符串内容
    令 临时变量 字符索引（ci）= 0
    循环（当 字符索引 小于 字符串长度 时）：
        调用 读 8 位（load8），从 字符串内容 偏移量 字符索引 处读取字符
        调用 写单字节（w8），向缓冲区偏移量 当前指针 处写入该字符
        令 字符索引 = 字符索引 + 1；令 当前指针 = 当前指针 + 1
    —— 写入 空字符（null） 终止符
    调用 写单字节（w8），向缓冲区偏移量 当前指针 处写入 0；令 当前指针 = 当前指针 + 1
    —— 填充零字节到 8 字节对齐边界
    循环（当 当前指针 % 8 不等于 0 时）：
        调用 写单字节，向缓冲区偏移量 当前指针 处写入 0
        令 当前指针 = 当前指针 + 1
    令 字符串索引 = 字符串索引 + 1

—— 第二十二步：基于实际 当前指针（cp） 重新计算 BSS 虚拟地址（Phase 2 的 total_code 低估了实际大小）
—— +1 确保 BSS 从不同于代码的新页开始
令 BSS 起始虚拟地址（bss_va） = （（TEXT_BASE + 当前指针 + 4096 + 4095） / 4096） × 4096

—— 第二十三步：使用最终的 BSS VA 原地重新发射 分配函数（alloc） 和 扩展堆（heap_expand）（覆盖临时 VA 版本）
—— 分配函数（alloc） 和 扩展堆（heap_expand） 内部包含基于 BSS 起始虚拟地址（bss_va） 的 RIP 相对寻址，临时 VA 不准确
调用 发射分配函数体（emit_alloc_body），参数 缓冲区、分配起始（alloc_start）（原 分配函数（alloc） 的起始位置）、BSS 起始虚拟地址（bss_va）、全局变量总大小

—— 第二十四步：重新发射 扩展堆（heap_expand）
调用 发射扩展堆（emit_heap_expand），参数 缓冲区、扩展堆起始（heap_expand_start）（原 heap_expand 的起始位置）、BSS 起始虚拟地址（bss_va）

—— 第二十五步：若需要运行时桩，使用正确的 BSS VA 重新发射 当前协程（curg） 桩
—— 当前协程（current_g） 指针位于全局变量区域末尾（globals_size 已包含 +8 预留），计算其准确的 VA 后重新发射
如果 x86 发射运行时桩（g_x86_emit_rt_stubs） 不等于 0 且 当前协程桩起始（g_curg_stub_start） 大于等于 0，那么：
    令 临时变量 当前协程（curg） 虚拟地址（curg_va）= BSS 起始虚拟地址（bss_va） + 16 + 全局变量总大小 - 8（16 是 BSS 头部预留偏移，全局变量总大小末尾的 8 字节即为 current_g 槽位）
    调用 发射当前协程桩（emit_curg_stubs），参数 缓冲区、当前协程桩起始（g_curg_stub_start）、当前协程虚拟地址（curg_va）

—— 第二十六步：修补 分配函数（alloc） 函数体内对 扩展堆（heap_expand） 的调用（重新发射后 heap_expand 的相对偏移量已变化）
如果 堆扩展调用位置（g_heap_expand_call_pos）大于等于 0，那么：
    令 临时变量 堆扩展调用相对偏移（rel_he_call）= 扩展堆起始（heap_expand_start） - （g_heap_expand_call_pos + 5）
    调用 写 32 位（w32），向缓冲区偏移量 堆扩展调用位置（g_heap_expand_call_pos） + 1 处写入 堆扩展调用相对偏移
    令 堆扩展调用位置（g_heap_expand_call_pos） = -1

—— 第二十七步：为所有全局变量分配 BSS 段偏移量（序列化 8 字节对齐分配）
令 临时变量 全局变量索引2（gi2）= 0
令 临时变量 全局偏移量（goff）= 0
循环（当 全局变量索引2 小于 IR 全局变量计数 时）：
    调用 读 64 位，从 IR 全局变量数组（g_ir_globals）[全局索引2（gi2）×24+8] 读取 IR 变量索引，存入 临时变量 变量编号2（gv2）
    如果 变量编号2 大于等于 0，那么：
        调用 扩展全局变量偏移数组（grow_global_off），参数 变量编号2 + 1
        调用 写 64 位，向 x86 全局变量偏移数组（g_x86_global_off）偏移量 变量编号2 × 8 处写入 全局偏移量（该变量在 BSS 段内的字节偏移量）
        令 全局偏移量 = 全局偏移量 + 8（每个全局变量 8 字节指针大小）
    令 全局变量索引2 = 全局变量索引2 + 1

—— 第二十八步：修补所有全局变量的 RIP 相对引用（rip_patch）
—— 遍历 发射起始函数（emit_start） 和 发射指令（emit_instr） 期间记录的 LEA 占位符，将 4 字节位移字段替换为实际的 LEA 目标地址与 LEA 指令末尾之间的相对偏移量
令 临时变量 RIP 修补索引2（rpi2）= 0
循环（当 RIP 修补索引2 小于 x86 RIP 修补计数 时）：
    调用 读 64 位，读取 LEA 中位移字段位置：修补位置（ppos） = x86 RIP 修补位置数组（g_x86_rip_patch_pos）[修补索引2（rpi2）×8]
    调用 读 64 位，读取目标全局变量索引：全局变量索引（gvi） = x86 RIP 修补全局数组（g_x86_rip_patch_globals）[修补索引2（rpi2）×8]

    —— 验证 LEA 前缀字节的正确性（ppos-3 处应为 LEA REX 前缀：0x4C=REX.WR 或 0x4D=REX.WRB 或 0x49=REX.WB 或 0x4F=REX.WRXB）
    调用 读取无符号字节（bu8），从缓冲区偏移量 修补位置（ppos） - 3 处读取字节，存入 临时变量 LEA 前缀检查（lea_check）
    如果 加载地址检查（lea_check） 不等于 76（0x4C）且不等于 77（0x4D）且不等于 73（0x49）且不等于 79（0x4F），那么：
        调用 输出函数，输出 "  BAD rip[" + 修补索引2（rpi2） + "] 修补位置（ppos）=" + 修补位置 + " 全局变量索引（gvi）=" + 全局变量索引 + " byte=" + 加载地址检查（lea_check）（异常调试输出，提示可能的数据损坏）

    如果 全局变量索引（gvi） 大于等于 0，那么：
        —— 计算目标 VA 和相对偏移量
        令 临时变量 LEA 结束虚拟地址（lea_end_va）= 代码段基址（TEXT_BASE） + 修补位置（ppos） + 4（LEA 为 7 字节指令，位移字段从字节 3 开始，+4 即位移字段末尾 = LEA 指令末尾的 VA）
        调用 读 64 位，从 x86 全局偏移数组（g_x86_global_off）[全局变量索引（gvi）×8] 读取该全局变量在 BSS 内的偏移量，存入 偏移量（off）
        令 临时变量 目标虚拟地址（target_va）= BSS 起始虚拟地址（bss_va） + 16 + 偏移量（BSS 起始于标志/头部之后 16 字节偏移处）
        令 临时变量 相对偏移（rel）= 目标虚拟地址 - LEA 结束虚拟地址
        调用 写 32 位（w32），向缓冲区偏移量 修补位置（ppos） 处写入 相对偏移

        —— 读回验证（仅对前 10 个全局变量做，检测硬件/软件写入错误）
        调用 读取无符号字节（bu8），读取 修补位置（ppos）+0 处的字节，存入 读回字节0（rb0）
        调用 读取无符号字节（bu8），读取 修补位置（ppos）+1 处的字节，存入 读回字节1（rb1）
        调用 读取无符号字节（bu8），读取 修补位置（ppos）+2 处的字节，存入 读回字节2（rb2）
        调用 读取无符号字节（bu8），读取 修补位置（ppos）+3 处的字节，存入 读回字节3（rb3）
        令 临时变量 读回值（rbv）= 读回字节0（rb0） + 读回字节1（rb1） × 256 + 读回字节2（rb2） × 65536（手工组合为 32 位有符号整数）
        如果 读回字节3（rb3） >= 128，那么：令 读回值 = 读回值 + （rb3 - 256） × 16777216（处理符号位扩展）
        否则：令 读回值 = 读回值 + 读回字节3（rb3） × 16777216
        如果 读回值 不等于 相对偏移 且 全局变量索引（gvi） >= 0 且 全局变量索引 < 10，那么：
            调用 输出函数，输出 "  不一致（MISMATCH） 修补位置（ppos）=" + 修补位置 + " 相对偏移（rel）=" + 相对偏移 + " 读回值（rbv）=" + 读回值（写入值与读回值不一致的警告）

    令 RIP 修补索引2 = RIP 修补索引2 + 1
令 x86 RIP 修补计数（g_x86_rip_patch_count） = 0

—— 第二十九步：修补 _start 内 call 主入口（main） 的相对偏移量
—— 在函数偏移量表中按名称查找 "主入口（main）"
令 临时变量 主入口（main） 偏移量（mo）= -1
令 临时变量 主入口（main） 查找索引（bfi3）= 0
循环（当 main 查找索引 小于 x86 函数偏移计数 时）：
    如果 驻留字符串获取（g_x86_func_offsets[bfi3×16]）等于 "主入口（main）"，那么：
        调用 读 64 位，从 x86 函数偏移数组（g_x86_func_offsets）[函数体索引3（bfi3）×16+8] 读取偏移量，存入 内存操作数偏移（mo）
        跳出循环
    令 主入口（main） 查找索引 = 主入口 查找索引 + 1

—— 调试输出：列出所有名为 "主入口（main）" 的条目（用于排查重复注册问题）
令 临时变量 主入口（main） 调试索引（bfi4）= 0
循环（当 main 调试索引 小于 x86 函数偏移计数 时）：
    调用 驻留字符串获取，读取 x86 函数偏移数组（g_x86_func_offsets）[函数索引4（bfi4）×16]，存入 名称（nm）
    如果 名称 等于 "主入口（main）"，那么：
        调用 读 64 位，读取偏移量（off） = x86 函数偏移数组（g_x86_func_offsets）[函数索引4（bfi4）×16+8]
        调用 输出函数，输出 "  主入口（main） at [" + 函数索引4（bfi4） + "] 偏移量（off）=" + 偏移量 + " 当前指针（cp）=" + （off + 176）
    令 主入口（main） 调试索引 = 主入口 调试索引 + 1

如果 内存操作数偏移（mo） >= 0，那么：
    令 相对偏移（rel）= 内存操作数偏移（mo） + 176 - 调用主函数位置（g_call_main_pos） - 5（计算从 call 指令末尾到 main 入口的字节距离）
    调用 写 32 位（w32），向缓冲区偏移量 调用主函数位置（g_call_main_pos） + 1 处写入 相对偏移

—— 第三十步：发射 BSS 清零入口（bss_init） 存根——入口点，零初始化 BSS 全局变量区域
—— WSL2 及某些内核不会可靠地清零 BSS 段，因此显式使用 rep stosb 将前 BSS 清零大小（BSS_ZERO_SIZE）（128KB）字节清零
—— 该存根成为 ELF 文件的实际入口点（e_entry），执行后跳转至真正的 _start
令 临时变量 BSS 清零入口（bss_init） 当前位置（bss_init_cp）= 当前指针

—— 子步骤 甲（a）：lea rdi, [rip + 相对偏移（rel）] → rdi = BSS 起始虚拟地址（bss_va）（BSS 起始虚拟地址）
令 临时变量 rdi 相对偏移（rel_di）= BSS 起始虚拟地址（bss_va） - （TEXT_BASE + 当前指针 + 7）（7 字节 LEA 指令长度）
调用 写单字节，写入 0x48（REX.W 前缀）
调用 写单字节，写入 0x8D（LEA 操作码）
调用 写单字节，写入 0x3D（ModRM mod=00, reg=7（rdi）, rm=5（[rip+disp32]））
调用 写单字节有符号（w8_signed），向缓冲区偏移量 当前指针+3 处写入 相对位移偏移（rel_di） 的低 8 位（实际上调用的是 e2_w32 写完整 4 字节，此处为伪代码简化）
—— 实际代码中使用 写单字节有符号（w8_signed） 写入 相对位移偏移（rel_di） 的 4 字节形式（手动展开为 4 次 w8 写入小端字节）
令 当前指针 = 当前指针 + 7

—— 子步骤 乙（b）：mov ecx, BSS 清零大小（BSS_ZERO_SIZE）（128KB = 131072）
调用 写单字节，写入 0xB9（MOV ecx, imm32 操作码）
调用 发射写 32 位（e2_w32），写入 131072
令 当前指针 = 当前指针 + 5

—— 子步骤 丙（c）：xor eax, eax；cld； rep stosb（串存储：将 al 零写入 [rdi], rdi+=1, ecx-=1，重复直到 ecx=0）
调用 写单字节，写入 0x31；调用 写单字节，写入 0xC0（xor eax, eax，两字节指令）
令 当前指针 = 当前指针 + 2
调用 写单字节，写入 0xFC（cld，清除方向标志，确保 stosb 递增 rdi）
令 当前指针 = 当前指针 + 1
调用 写单字节，写入 0xF3；调用 写单字节，写入 0xAA（rep stosb：重复前缀 0xF3 + STOSB 0xAA）
令 当前指针 = 当前指针 + 2

—— 子步骤 丁（d）：jmp _start（跳转到真正的 _start 入口，位于 TEXT_BASE + 176）
令 临时变量 跳转相对偏移（jmp_rel）= 代码段基址（TEXT_BASE） + 176 - （TEXT_BASE + 当前指针 + 5）（计算从 jmp 指令末尾到 _start 的距离）
调用 写单字节，写入 0xE9（JMP rel32 操作码）
调用 发射写 32 位（e2_w32），写入 跳转相对偏移
令 当前指针 = 当前指针 + 5

#### Phase 4：写入 ELF 文件头并设置入口点

—— 第一步：计算最终文件大小，调用 ELF2 头写入（elf2_hdr） 写入 ELF 头和程序头
令 临时变量 总大小（total_sz）= 当前指针
—— 使用实际 总大小（total_sz） 作为 代码段结束偏移（code_end） 参数，使代码段覆盖所有已发射内容（含 .rodata）
调用 ELF2 头写入（elf2_hdr），参数 缓冲区、总大小（code_end）、总大小（total_sz）

—— 第二步：覆写 ELF 入口点为 BSS 清零入口（bss_init）（而非 _start）
—— BSS 清零入口（bss_init） 先清零 BSS，然后跳转 _start；这才是进程的实际入口
调用 写 64 位（w64），向缓冲区偏移量 E_ENTRY 偏移量（E_ENTRY） 偏移量（E_ENTRY）（24）处写入 代码段基址（TEXT_BASE） + BSS 清零入口当前指针（bss_init_cp）

—— 第三步：修补数据段（PHDR[1]）的文件偏移量、虚拟地址、物理地址为 BSS 的实际页对齐位置
—— PHDR[1] 的基址 = ELF 头大小常量（EHDR_SIZE）（64） + 程序头大小常量（PHDR_SIZE）（56） = 120 偏移处
令 临时变量 数据程序头基址（data_phdr_base）= ELF 头大小常量（EHDR_SIZE） + 程序头大小常量（PHDR_SIZE） = 64 + 56 = 120
调用 写 64 位，向缓冲区偏移量 数据程序头基址（data_phdr_base） + P_OFFSET 偏移量（P_OFFSET） 偏移量（P_OFFSET）（偏移 +4 在 Phdr 中）处写入 BSS 起始虚拟地址（bss_va） - 代码段基址（TEXT_BASE）（文件内偏移 = VA - TEXT_BASE，因为代码段从文件偏移 0 开始）
调用 写 64 位，向缓冲区偏移量 数据程序头基址（data_phdr_base） + P_VADDR 偏移量（P_VADDR） 偏移量（P_VADDR）（偏移 +16）处写入 BSS 起始虚拟地址（bss_va）
调用 写 64 位，向缓冲区偏移量 数据程序头基址（data_phdr_base） + P_PADDR 偏移量（P_PADDR） 偏移量（P_PADDR）（偏移 +24）处写入 BSS 起始虚拟地址（bss_va）

—— 第四步：记录最终大小并返回
令 汇编代码大小（g_asm_code_size）= 总大小
返回 总大小

### 测试要点
1. 无全局变量、无内建函数调用时的最小化 ELF：Phase 0 标记 0 个全局变量，Phase 1 收集 0 个字符串，Phase 2 估算仅 _start + 分配函数（alloc） + 扩展堆（heap_expand） + 跳板的大小，Phase 3 实际发射后各修补数组均为空（或无有效条目），Phase 4 写入正确的 ELF 文件头。最终生成合法的 ET_EXEC ELF 文件。
2. 内建函数名称匹配：Phase 0 在字符串表中正确匹配 "三参系统调用（syscall3）"/"读取字节（load8）"/"写字节（store8）"/"读取 64 位（load64）"/"读 64 位（r64）"/"字符串指针加载（load_str_ptr）"/"字符串指针存储（store_str_ptr）"/"获取参数（get_arg）"/"写 64 位（w64）"/"动态拷贝内建（_dyncpy）"/"协程包装地址（goroutine_wrapper_addr）"，验证 原生内建索引族（g_ni_）* 不为 -1。若任何内建名称未出现在字符串表中（用户代码未引用），对应索引保持 -1，发射指令（emit_instr） 不应尝试内联发射。
3. 字符串常量 .只读数据段（rodata） 段：Phase 1 正确收集所有 IR 字符串常量，Phase 2 的 全局变量只读数据大小（g2_rodata_sz） 与 Phase 3 实际写入的字节数一致。每个字符串含 8 字节长度头 + 内容 + 空字符（null） + 对齐填充。Phase 3 第二十步的 只读数据引用（rodataref） 修补使得所有 LEA 引用正确指向 .只读数据段 中的数据。
4. 用户函数发射与修补：多函数场景下（50+ 函数），Phase 2 的代码大小估算（ic*5）虽不精确但能覆盖 Phase 3 的实际写入（允许超额估算，emit_instr 返回值 <= Phase 2 估计值时不会溢出）。Phase 3 中 sub rsp 占位符被正确修补为实际栈大小。RETURN 跳转到尾声的相对偏移量正确。调用修补位置（call_patch） 和 函数地址修补（fnaddr_patch） 正确解析前向引用和后向引用（包括跨函数交叉引用）。
5. 分配函数（alloc） 分配函数与 扩展堆（heap_expand）：Phase 3 第七步使用临时 BSS VA 发射 分配函数，第九步发射 扩展堆。第二十三步用最终 BSS VA 原地重新发射，覆盖临时版本。第二十六步修补 分配函数 内部对 扩展堆 的调用（g_heap_expand_call_pos）。分配修补（alloc_patch） 数组中的所有 IR_ALLOC_STRUCT/ARRAY/MAKE_ENUM 调用站点正确指向 分配函数。
6. BSS 全局变量分配与 RIP 修补：Phase 3 第二十七步序列化分配全局变量偏移量（每个 8 字节）。第二十八步遍历所有 RIP 修补（rip_patch） 条目，计算 目标虚拟地址（target_va） = BSS 起始虚拟地址（bss_va） + 16 + 偏移量（off），写入 LEA 的 rel32 字段。前 10 个全局变量执行读回验证，若读回值与写入值不一致则输出 不一致（MISMATCH） 警告。LEA 前缀字节验证（检查 ppos-3 处是否为 0x4C/0x4D/0x49/0x4F）防止数据损坏。
7. BSS 清零入口（bss_init） 存根：入口点代码清零 BSS 128KB 后跳转 _start。LEA rdi 指令的 RIP 相对偏移量计算正确（bss_va - TEXT_BASE - cp - 7 = rel）。jmp _start 的目标为 代码段基址（TEXT_BASE） + 176（即紧接 ELF 头之后的 _start 位置）。Phase 4 将 e_entry 覆写为 代码段基址 + BSS 清零入口当前指针（bss_init_cp）。
8. 协程运行时桩（g_x86_emit_rt_stubs != 0）：设置当前协程函数索引（g_set_curg）/获取当前协程函数索引（g_get_curg） 的 重新发射（emit）（使用正确 curg_va）确保 当前协程（current_g） 指针正确解析。协程初始化（fiber_init）/协程切换（fiber_switch）/协程入口包装（goroutine_entry_wrapper）/启动工作线程桩（m_start_workers） 注册到函数偏移量表使 call/函数地址（fnaddr） 修补能解析。
9. 页对齐：Phase 3 第十八步将代码段填充零字节到 下一页（next_page） 边界（4096 的倍数），确保内核将 RW 数据段映射到独立页面（而非与 RX 代码段共享一页导致代码不可执行）。
10. Phase 4 ELF 文件头：e_ident 魔数 \x7fELF，e_type=ET_EXEC（2），e_machine=EM_X86_64（62），PHDR[0] 为 RX 代码段，PHDR[1] 为 RW 数据段（memsz=1GB 虚拟增长堆）。入口点覆写为 BSS 清零入口（bss_init） 而非 _start。
11. 调试输出：Phase 0 输出内建函数索引，Phase 2 每 50 个函数输出进度，Phase 3 每 50 个函数输出 发射（emit） 进度及 返回序列（rets） 计数，主入口（main） 函数的所有偏移表条目输出。
