# elf-3.md 伪代码

> 源文件：src/arch/linux/ld/elf.cr（第 776-970 行：write_phdr 已含于 elf-2、全局变量 gv_argc/gv_argv、emit_start、emit_start_size）
> 功能概要：ELF 生成核心第三部分。包含 _start 函数的机器码发射（argc/argv 保存、全局变量初始化、call main、exit 系统调用）及其大小预估函数。_start 是用户程序的真正入口点，负责桥接 Linux 内核传递的栈上参数与 Core 运行时全局变量。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 发射 _start | emit_start | emit_start |
| 发射 _start 大小 | emit_start_size | emit_start_size |
| 发射 REX 前缀 | emit_rex | emit_start |
| 发射 ModRM | emit_modrm | emit_start |
| 发射 SIB | emit_sib | emit_start |
| 发射写 8 位 | e2_w8 | emit_start |
| 发射写 32 位 | e2_w32 | emit_start |
| 发射写 64 位 | e2_w64 | emit_start |
| 发射加载寄存器 | e2_lr | emit_start |
| 发射调用指令 | e2_call | emit_start |
| 写单字节 | w8 | emit_start |
| 读 64 位 | r64 | emit_start |
| 写 64 位 | w64 | emit_start |
| 扩展 RIP 修补数组 | grow_rip_patch | emit_start |
| _start 函数体大小 | sz_start_body | emit_start_size |
| _start argv 保存大小 | sz_start_argv_save | emit_start_size |
| 加载寄存器大小 | sz_lr | emit_start_size |
| 调用指令大小 | sz_call | emit_start_size |
| 系统调用大小 | sz_syscall | emit_start_size |
| 调用 main 位置 | g_call_main_pos | emit_start |
| argv 全局变量索引 | gv_argc | emit_start |
| argv 指针索引 | gv_argv | emit_start |
| 当前竞技场全局变量索引 | gv_current_arena | emit_start |
| 竞技场游标全局变量索引 | gv_arena_cursors | emit_start |
| 竞技场大小全局变量索引 | gv_arena_sizes | emit_start |
| 竞技场池数据全局变量索引 | gv_arena_pool_data | emit_start |
| 竞技场最大尺寸全局变量索引 | gv_arena_max_size | emit_start |
| 堆指针全局变量索引 | gv_heap_ptr | emit_start |
| 堆尾全局变量索引 | gv_heap_end | emit_start |
| 堆配置全局变量索引 | gv_hp_config | emit_start |
| 堆待处理全局变量索引 | gv_hp_inflight | emit_start |
| 堆扩展调用位置 | g_heap_expand_call_pos | emit_start |
| 全局分配跳转位置 | g_alloc_gl_jmp_pos | emit_start |

## 全局状态

| 中文名 | 原名 | 含义 |
|--------|------|------|
| 调用 main 位置 | g_call_main_pos | _start 内 call main 指令在缓冲区中的位置偏移量（set by emit_start, used for patching Phase 3） |
| argv 全局变量索引 | gv_argc | IR 变量索引，对应 g_rt_argc 全局变量。值为 -1 表示该全局变量未被用户代码引用、无需发射保存代码 |
| argv 指针索引 | gv_argv | IR 变量索引，对应 g_rt_argv_ptr 全局变量。值为 -1 表示未注册 |
| 当前竞技场全局变量索引 | gv_current_arena | IR 变量索引，对应 g_current_arena 全局变量。初始值 -1。由 elf_gen Phase 1 设置 |
| 竞技场游标全局变量索引 | gv_arena_cursors | IR 变量索引，对应 g_arena_cursors。由 elf_gen Phase 1 设置 |
| 竞技场大小全局变量索引 | gv_arena_sizes | IR 变量索引，对应 g_arena_sizes。由 elf_gen Phase 1 设置 |
| 竞技场池数据全局变量索引 | gv_arena_pool_data | IR 变量索引，对应 g_arena_pool_data。由 elf_gen Phase 1 设置 |
| 竞技场最大尺寸全局变量索引 | gv_arena_max_size | IR 变量索引，对应 g_arena_max_size。由 elf_gen Phase 1 设置 |
| 堆指针全局变量索引 | gv_heap_ptr | IR 变量索引，对应 g_heap_ptr。由 elf_gen Phase 1 设置 |
| 堆尾全局变量索引 | gv_heap_end | IR 变量索引，对应 g_heap_end。由 elf_gen Phase 1 设置 |
| 堆配置全局变量索引 | gv_hp_config | IR 变量索引，对应 g_hp_config。由 elf_gen Phase 1 设置 |
| 堆待处理全局变量索引 | gv_hp_inflight | IR 变量索引，对应 g_hp_inflight。由 elf_gen Phase 1 设置 |
| 堆扩展调用位置 | g_heap_expand_call_pos | alloc 函数体内 call heap_expand 指令的缓冲区位置（用于 re-emit 后修补）。初始值 -1 |
| 全局分配跳转位置 | g_alloc_gl_jmp_pos | Part 1 （arena fast） 末尾 jl .Lglobal 指令的位移字段位置（由 Part 8 修补）。初始值 -1 |

## 函数 发射 _start（emit_start）
### 作用
发射 _start 函数的完整机器码到 ELF 输出缓冲区。_start 是 ELF 可执行文件的逻辑入口点（bss_init 清零 BSS 后跳转至此），负责：（1） 从栈上加载 Linux 内核传入的 argc 和 argv；（2） 若 argc/argv 全局变量已注册，将其保存到对应的全局变量槽位；（3） 若当前竞技场全局变量已注册，初始化为 -1（表示无活跃竞技场）；（4） 遍历所有 IR 全局变量，对具有非零编译时常量初始值的条目发射初始化代码；（5） 发射 call 主入口（main） 占位符（后续由 elf_gen Phase 3 修补为实际偏移量）；（6） 将 主入口 的返回值（eax）移到第一个参数寄存器（edi），设置系统调用号 60（sys_exit），执行 syscall 指令退出进程。返回写入的总字节数。
### 逻辑

令 当前指针（cp）= 起始位置（pos）

—— 第一步：从栈上加载 argc 到 rdi
—— 指令为 mov rdi, [rsp]。Linux 内核在进入用户态时将 argc 压入栈顶，[rsp] 即 argc 的值。
—— 目的寄存器 rdi，编号为 7。源操作数为 [rsp] 间接寻址，基址寄存器 rsp 编号为 4。
—— 该指令需要 REX.W 前缀（64 位操作数）、ModRM 字节（mod=00 无位移，reg=7，rm=4 表示后续 SIB 字节决定寻址方式）、SIB 字节（基址为 rsp，无索引寄存器，无缩放）。
调用 发射 REX 前缀（emit_rex），参数 W=1（64 位操作数大小）、R=0（reg 字段高位扩展）、X=0（SIB.index 字段高位扩展）、B=0（SIB.base 或 ModRM.rm 字段高位扩展）。REX 字节计算公式：64 + W×8 + R×4 + X×2 + B = 64 + 8 + 0 + 0 + 0 = 72（即 0x48，REX.W 前缀）。
令 当前指针 = 当前指针 + 该函数返回的字节数（3 字节，即 REX 前缀自身大小。注：emit_rex 内部先写入 REX 字节再写操作码，但操作码由调用方通过 e2_w8 单独写入，故此处实际返回 REX 前缀 1 字节的偏移增量——但该函数设计上返回其写入的总字节数，需以实际实现为准）
—— 实际上 发射 REX 前缀（emit_rex） 的实现是：根据 W/R/X/B 计算 REX 字节值，写入 1 字节，返回 1。但由于调用约定中操作码由后续 发射写 8 位（e2_w8） 写入，此处 当前指针（cp） = 当前指针 + 1 才是正确语义。
调用 发射写 8 位（e2_w8），向缓冲区偏移量 当前指针 处写入操作码 139（0x8B，即 MOV r64, r/m64 指令，direction bit D=0 表示从 r/m 到 reg）
令 当前指针 = 当前指针 + 1
调用 发射 ModRM（emit_modrm），参数 mod=0（ModRM.mod 字段为二进制的 00，表示无位移的间接寻址，即 [reg] 形式）、reg=7（ModRM.reg 字段为 111，指定目的寄存器 rdi）、rm=4（ModRM.rm 字段为 100，此值在 x86-64 中表示实际寻址方式由紧接其后的 SIB 字节决定）
令 当前指针 = 当前指针 + 该函数返回的字节数（1 字节，即 ModRM 字节自身大小）
调用 发射 SIB（emit_sib），参数 scale=0（缩放因子 2^0 = 1，即无缩放）、index=4（SIB.index 字段为 100，在 index 字段中填写 rsp 的编号 4 表示"无索引寄存器"这一特殊含义——x86-64 规定 index=4 且 mod!=11 时 index 寄存器无效）、base=4（SIB.base 字段为 100，基址寄存器为 rsp）
令 当前指针 = 当前指针 + 该函数返回的字节数（1 字节，即 SIB 字节自身大小）
—— 至此 mov rdi, [rsp] 指令完成，共 1+1+1+1=4 字节（REX + opcode + ModRM + SIB）

—— 第二步：从栈上加载 argv 指针到 rsi
—— 指令为 lea rsi, [rsp+8]。argv 指针位于 argc（8 字节）之后，因此地址为 rsp+8。
—— 目的寄存器 rsi，编号为 6。源操作数为 [rsp+disp8]，需要 ModRM.mod=01（8 位位移）和 disp8=8。
调用 发射 REX 前缀（emit_rex），参数 W=1, R=0, X=0, B=0，REX 字节 = 64+8+0+0+0 = 72（0x48，REX.W 前缀）
令 当前指针 = 当前指针 + 1
调用 发射写 8 位（e2_w8），向缓冲区偏移量 当前指针 处写入操作码 141（0x8D，即 LEA r64, m 指令，从内存地址计算有效地址但不实际访问内存）
令 当前指针 = 当前指针 + 1
调用 发射 ModRM（emit_modrm），参数 mod=1（ModRM.mod 字段为二进制的 01，表示带 8 位有符号位移的间接寻址，即 [reg+disp8] 形式）、reg=6（ModRM.reg 字段为 110，目的寄存器 rsi）、rm=4（通过后续 SIB 字节指定基址和索引）
令 当前指针 = 当前指针 + 1
调用 发射 SIB（emit_sib），参数 scale=0, index=4（无索引寄存器）, base=4（基址寄存器 rsp）
令 当前指针 = 当前指针 + 1
调用 发射写 8 位（e2_w8），向缓冲区偏移量 当前指针 处写入位移值 8（即 [rsp+8] 中的 +8，单字节有符号位移）
令 当前指针 = 当前指针 + 1
—— 至此 lea rsi, [rsp+8] 指令完成，共 1+1+1+1+1=5 字节

—— 第三步：若 argc 全局变量已注册（gv_argc >= 0），将 rdi 中的 argc 值写入该全局变量的内存槽位
如果 argv 全局变量索引（gv_argc）大于等于 0，那么：
    —— 子步骤 3a：将全局变量 命令行参数个数（g_rt_argc） 的地址加载到 r10 寄存器
    —— 指令为 lea r10, [rip + 0]。立即数 0 是占位符，生成 ELF（elf_gen） Phase 3 末尾的 RIP 修补（rip_patch） 修补阶段会将此处替换为 BSS 段中 命令行参数个数（g_rt_argc） 槽位相对于该指令末尾的真实偏移量。
    —— r10 编号为 10，10/8=1 即 REX.B=1，10%8=2 即 ModRM.rm=2。
    令 临时变量 RIP 修补位置（rip_pos） = 当前指针 + 3（记录 LEA 指令中 32 位位移字段在缓冲区内的起始位置，供 Phase 3 修补之用）
    调用 发射加载寄存器（e2_lr），参数 缓冲区、当前指针、位移值 0（占位符）。该函数内部执行：写入 REX.WR 前缀（0x4C，即 64+8+4+0+0=76，其中 R=1 是因为 reg 字段编码 r10 需要 R=1）、写入 LEA 操作码 0x8D、写入 ModRM（mod=00, reg=2, rm=5） 即 [rip+disp32] 寻址模式、写入 4 字节位移值 0。共 7 字节。
    令 当前指针 = 当前指针 + 7
    —— 将本次 LEA 的位移位置和目标全局变量索引记录到 RIP 修补数组，供 Phase 3 批量修补
    调用 扩展 RIP 修补数组（grow_rip_patch），传入参数 当前 RIP 修补计数 + 1，确保数组容量足够容纳新条目
    调用 写 64 位（w64），向 x86 RIP 修补位置数组（g_x86_rip_patch_pos）偏移量 当前 RIP 修补计数 × 8 处写入 RIP 修补位置（rip_pos）（LEA 指令中 32 位位移字段的缓冲区偏移量）
    调用 写 64 位（w64），向 x86 RIP 全局变量修补数组（g_x86_rip_patch_globals）偏移量 当前 RIP 修补计数 × 8 处写入 命令行参数个数索引（gv_argc）（对应全局变量的 IR 变量索引）
    令 x86 RIP 修补计数（g_x86_rip_patch_count）= x86 RIP 修补计数 + 1
    —— 子步骤 3b：将 rdi 的值写入 r10 指向的地址
    —— 指令为 mov [r10], rdi。源寄存器 rdi 编号为 7，目的操作数为 [r10] 间接寻址。
    —— REX 字节需要 W=1（64 位操作）和 B=1（rm 字段的扩展位，因为 r10 是扩展寄存器）。REG 字段（对应源寄存器 rdi）的高位是 0。
    调用 发射 REX 前缀（emit_rex），参数 W=1, R=0, X=0, B=10/8=1，REX 字节 = 64+8+0+0+1 = 73（0x49，REX.WB 前缀）
    令 当前指针 = 当前指针 + 1
    调用 发射写 8 位（e2_w8），向缓冲区偏移量 当前指针 处写入操作码 137（0x89，即 MOV r/m64, r64 指令，D=0 方向为从 reg 到 r/m）
    令 当前指针 = 当前指针 + 1
    调用 发射 ModRM（emit_modrm），参数 mod=0（无位移，[r10] 即纯间接寻址）、reg=7（源寄存器 rdi）、rm=10%8=2（目的操作数由 r10 寻址）
    令 当前指针 = 当前指针 + 1
    —— 至此 argc 保存序列完成，共 7+3=10 字节（lea + REX+opcode+ModRM）

—— 第四步：若 argv 指针全局变量已注册（gv_argv >= 0），将 rsi 中的 argv 指针值写入该全局变量的内存槽位
如果 argv 指针索引（gv_argv）大于等于 0，那么：
    —— 逻辑与第三步完全对称，唯一区别是使用 rsi（编号 6）代替 rdi。
    —— 子步骤 4a：lea r10, [rip+0]，获取 argv 指针（g_rt_argv_ptr） 的地址
    令 临时变量 RIP 修补位置2（rip_pos2） = 当前指针 + 3
    调用 发射加载寄存器（e2_lr），参数 缓冲区、当前指针、0（占位符），共 7 字节
    令 当前指针 = 当前指针 + 7
    调用 扩展 RIP 修补数组（grow_rip_patch），传入 x86 RIP 修补计数 + 1
    调用 写 64 位（w64），向 x86 RIP 修补位置数组 偏移量 当前 RIP 修补计数 × 8 处写入 RIP 修补位置2（rip_pos2）
    调用 写 64 位（w64），向 x86 RIP 全局变量修补数组 偏移量 当前 RIP 修补计数 × 8 处写入 命令行参数指针索引（gv_argv）
    令 x86 RIP 修补计数 = x86 RIP 修补计数 + 1
    —— 子步骤 4b：mov [r10], rsi
    调用 发射 REX 前缀（emit_rex），参数 W=1, R=0, X=0, B=10/8=1，REX 字节 = 64+8+0+0+1 = 73（0x49）
    令 当前指针 = 当前指针 + 1
    调用 发射写 8 位（e2_w8），写入操作码 137（0x89）
    令 当前指针 = 当前指针 + 1
    调用 发射 ModRM（emit_modrm），参数 mod=0, reg=6（源寄存器 rsi）, rm=10%8=2（目的 [r10]）
    令 当前指针 = 当前指针 + 1
    —— 至此 argv 保存序列完成，共 10 字节

—— 第五步：若当前竞技场全局变量已注册，将其初始化为 -1（表示进程启动时无活跃竞技场）
如果 当前竞技场全局变量索引（gv_current_arena）大于等于 0，那么：
    —— 子步骤 5a：lea r10, [rip+0]，获取 当前竞技场（g_current_arena） 的 BSS 地址
    令 临时变量 RIP 修补位置（当前竞技场）（rip_ca） = 当前指针 + 3
    调用 发射加载寄存器（e2_lr），参数 缓冲区、当前指针、0（占位符），共 7 字节
    令 当前指针 = 当前指针 + 7
    调用 扩展 RIP 修补数组（grow_rip_patch），传入 当前 RIP 修补计数 + 1
    调用 写 64 位（w64），向 x86 RIP 修补位置数组 写入 RIP 修补位置（当前竞技场）（rip_ca）
    调用 写 64 位（w64），向 x86 RIP 全局变量修补数组 写入 当前竞技场索引（gv_current_arena）
    令 x86 RIP 修补计数 = x86 RIP 修补计数 + 1
    —— 子步骤 5b：mov qword [r10], -1
    —— 指令为 MOV r/m64, imm32（操作码 0xC7，/0 操作码扩展），立即数 -1 以 32 位有符号形式编码（0xFFFFFFFF），写入 64 位目标时自动符号扩展为 -1（全 1）。
    —— 编码序列：REX.WB（0x49，因 r10 需要 B=1）+ 操作码 0xC7 + ModRM（mod=00, reg=000 即 /0, rm=010 即 r10%8=2） + 4 字节立即数
    调用 发射 REX 前缀（emit_rex），参数 W=1, R=0, X=0, B=10/8=1，REX 字节 = 64+8+0+0+1 = 73（0x49）
    令 当前指针 = 当前指针 + 1
    调用 发射写 8 位（e2_w8），写入操作码 199（0xC7，即 MOV r/m64, imm32 指令。x86-64 中 /0 操作码扩展字段隐含于 ModRM.reg=000）
    令 当前指针 = 当前指针 + 1
    调用 发射 ModRM（emit_modrm），参数 mod=0, reg=0（/0 操作码扩展，表示 MOV 指令的目的为 r/m64）, rm=10%8=2（[r10]）
    令 当前指针 = 当前指针 + 1
    调用 发射写 32 位（e2_w32），向缓冲区偏移量 当前指针 处写入立即数值 4294967295（有符号整数 -1 的 32 位二进制补码表示）
    令 当前指针 = 当前指针 + 4
    —— 至此 当前竞技场（g_current_arena） 初始化完成，共 7+7=14 字节

—— 第六步：写入所有编译时常量全局变量的初始化值
—— 遍历 IR 全局变量数组（g_ir_globals） 数组（每条记录 24 字节：偏移 +0 为名称驻留索引、+8 为 IR 变量索引、+16 为编译时常量初始化值 0 表示无初始值需 BSS 清零）。
—— 对每个具有非零初始值（init_val != 0）且已注册全局变量索引（gvv0 >= 0）的条目，发射将初始值写入该全局变量 BSS 槽位的代码。
—— 注意：第五步显式设置了 当前竞技场（g_current_arena） = -1，若该条目同时满足本循环条件也会被再次写入相同的值，结果正确但冗余（无害）。
令 全局变量遍历索引（gi0）= 0
循环（当 全局变量遍历索引 小于 IR 全局变量计数（g_ir_global_count）时）：
    调用 读 64 位（r64），从 IR 全局变量数组（g_ir_globals）偏移量 全局变量遍历索引 × 24 + 16 处读取编译时常量初始值，存入 临时变量 初始值（iv）
    调用 读 64 位（r64），从 IR 全局变量数组 偏移量 全局变量遍历索引 × 24 + 8 处读取 IR 变量索引，存入 临时变量 变量编号（gvv0）
    如果 初始值 不等于 0 且 变量编号 大于等于 0，那么：
        —— 子步骤 6a：lea r10, [rip+0]，获取该全局变量的 BSS 槽位地址
        令 临时变量 RIP 修补位置（全局）（rip_pos_g） = 当前指针 + 3
        调用 发射加载寄存器（e2_lr），参数 缓冲区、当前指针、0（占位符），共 7 字节
        令 当前指针 = 当前指针 + 7
        调用 扩展 RIP 修补数组（grow_rip_patch），传入 当前 RIP 修补计数 + 1
        调用 写 64 位（w64），向 x86 RIP 修补位置数组 写入 RIP 修补位置（全局）（rip_pos_g）
        调用 写 64 位（w64），向 x86 RIP 全局变量修补数组 写入 全局变量值槽 0（gvv0）
        令 x86 RIP 修补计数 = x86 RIP 修补计数 + 1
        —— 子步骤 6b：根据初始值的数值范围选择指令编码方式
        如果 初始值 大于等于 -2147483648（即 -（2^31））且 初始值 小于等于 2147483647（即 2^31 - 1），那么：
            —— 初始值在 32 位有符号整数范围内，使用 mov qword [r10], imm32 单指令（符号扩展）
            —— 编码序列：REX.WB（0x49） + 操作码 0xC7 + ModRM（mod=00, reg=000 即 /0, rm=010） + 4 字节有符号立即数。总计 7 字节。
            调用 写单字节（w8），向缓冲区偏移量 当前指针+0 处写入 73（0x49，REX.WB 前缀：W=1, R=0, X=0, B=1）
            调用 写单字节（w8），向缓冲区偏移量 当前指针+1 处写入 199（0xC7，MOV r/m64, imm32）
            调用 写单字节（w8），向缓冲区偏移量 当前指针+2 处写入 2（ModRM 字节编码：mod=00, reg=000, rm=010 → 二进制 00 000 010 = 2）
            调用 发射写 32 位（e2_w32），向缓冲区偏移量 当前指针+3 处写入 初始值（有符号 32 位整数，符号位自动扩展到 64 位）
            令 当前指针 = 当前指针 + 7
        否则：
            —— 初始值超出 32 位有符号范围（如 64 位大整数），需要用两步：先加载到 rax，再写入内存
            —— 子步骤 6b-循环索引（i）：mov rax, imm64
            —— 编码序列：REX.W（0x48） + 操作码 0xB8（MOV rax, imm64，rax 的累加器特化编码，无 ModRM 字节） + 8 字节立即数。总计 10 字节。
            调用 写单字节（w8），向缓冲区偏移量 当前指针+0 处写入 72（0x48，REX.W 前缀：W=1, R=0, X=0, B=0）
            调用 写单字节（w8），向缓冲区偏移量 当前指针+1 处写入 184（0xB8，即 0xB8+0=0xB8，rax 寄存器的特化操作码）
            调用 发射写 64 位（e2_w64），向缓冲区偏移量 当前指针+2 处写入 初始值（完整的 64 位有符号整数）
            令 当前指针 = 当前指针 + 10
            —— 子步骤 6b-指令索引（ii）：mov [r10], rax
            —— 编码序列：REX.WB（0x49） + 操作码 0x89（MOV r/m64, r64） + ModRM（mod=00, reg=000 即 rax, rm=010）。总计 3 字节。
            调用 写单字节（w8），向缓冲区偏移量 当前指针+0 处写入 73（0x49，REX.WB）
            调用 写单字节（w8），向缓冲区偏移量 当前指针+1 处写入 137（0x89，MOV r/m64, r64，D=0）
            调用 写单字节（w8），向缓冲区偏移量 当前指针+2 处写入 2（ModRM：mod=00, reg=000, rm=010）
            令 当前指针 = 当前指针 + 3
    令 全局变量遍历索引 = 全局变量遍历索引 + 1

—— 第七步：发射 call 主入口（main） 指令（5 字节占位符，后续 Phase 3 修补）
—— 记录 call 指令的缓冲区位置，生成 ELF（elf_gen） Phase 3 末尾根据 主入口（main） 函数的实际偏移量计算相对跳转距离并写入。
令 调用 主入口（main） 位置（g_call_main_pos）= 当前指针
调用 发射调用指令（e2_call），参数 缓冲区、当前指针、0（占位符立即数）。该函数内部：写入 0xE8（CALL rel32 操作码）+ 写入 4 字节 rel32=0（占位符）。总计 5 字节。
令 当前指针 = 当前指针 + 5

—— 第八步：将 主入口（main） 的返回值从 eax 移到 edi（exit 系统调用的第一个参数）
—— 指令为 mov edi, eax（32 位操作，无需 REX 前缀）。按 x86-64 调用约定，主入口（main） 的返回值在 eax 中；按 Linux 系统调用约定，退出码应放在 edi 中。
调用 发射写 8 位（e2_w8），向缓冲区偏移量 当前指针 处写入操作码 137（0x89，即 MOV r/m32, r32 指令。32 位操作模式下自动零扩展到 64 位）
令 当前指针 = 当前指针 + 1
调用 发射 ModRM（emit_modrm），参数 mod=3（ModRM.mod=11，两个操作数均为寄存器）、reg=0（源寄存器 eax）、rm=7（目的寄存器 edi）。ModRM 字节编码：mod=11, reg=000, rm=111 → 二进制 11 000 111 = 0xC7。
令 当前指针 = 当前指针 + 1

—— 第九步：将系统调用号 60（sys_exit）写入 rax
—— 指令为 mov eax, 60（32 位操作，rax 的累加器特化短编码）
调用 发射写 8 位（e2_w8），向缓冲区偏移量 当前指针 处写入操作码 184（0xB8，即 MOV eax, imm32。累加器寄存器 rax/eax 享有 0xB8+0 的特化编码，比通用的 0xC7 /0 短 1 字节）
令 当前指针 = 当前指针 + 1
调用 发射写 32 位（e2_w32），向缓冲区偏移量 当前指针 处写入立即数值 60（sys_exit 系统调用号，x86-64 Linux 中 60 为 exit，60+2^28 为 exit_group）
令 当前指针 = 当前指针 + 4

—— 第十步：执行 syscall 指令，陷入内核
—— x86-64 的 syscall 指令为两字节：0x0F 0x05。执行时从 rax 读取系统调用号，从 rdi/rsi/rdx/r10/r8/r9 读取参数，切换至内核态。
调用 发射写 8 位（e2_w8），向缓冲区偏移量 当前指针 处写入 15（0x0F，两字节操作码的第一字节）
令 当前指针 = 当前指针 + 1
调用 发射写 8 位（e2_w8），向缓冲区偏移量 当前指针 处写入 5（0x05，两字节操作码的第二字节）
令 当前指针 = 当前指针 + 1

返回 当前指针 - 起始位置（即 emit_start 写入的总字节数）

### 测试要点
1. 命令行参数个数索引（gv_argc） < 0 且 命令行参数指针索引（gv_argv） < 0：不发射 argc/argv 保存代码，_start 总大小仅含基础体。验证 发射起始函数大小（emit_start_size） 返回值与 发射起始函数（emit_start） 实际写入字节数一致。
2. 命令行参数个数索引（gv_argc） >= 0：验证 RIP 修补数组中记录了正确的位置和目标全局变量索引 命令行参数个数索引。
3. 命令行参数指针索引（gv_argv） >= 0：同上，验证 命令行参数指针索引 被正确记录。
4. 当前竞技场索引（gv_current_arena） >= 0：验证 发射起始函数大小（emit_start_size） 多加 14 字节，且 RIP 修补记录与 发射起始函数（emit_start） 一致。
5. 多个 IR 全局变量数组（g_ir_globals） 条目具有 32 位范围初始值：每个条目贡献 14 字节，验证纯手写机器码字节序列（0x49 0xC7 0x02 + imm32）正确。
6. 某个 IR 全局变量数组（g_ir_globals） 条目具有超出 32 位范围的初始值（如 0x100000000）：贡献 20 字节，验证两步编码（mov rax, imm64； mov [r10], rax）的字节序列正确。
7. call 主入口（main） 始终为 5 字节占位符（E8 00 00 00 00），调用主函数位置（g_call_main_pos） 被正确设置。
8. exit 系统调用序列：mov edi, eax + mov eax, 60 + syscall，共 2+5+2=9 字节固定部分。
9. 边界情况：IR 全局计数（g_ir_global_count） = 0 时循环不执行，无额外开销。
10. 边界情况：所有 IR 全局变量数组（g_ir_globals） 的 初始值（init_val） 均为 0 时，循环遍历全部但不产生任何字节输出。

## 函数 发射 _start 大小（emit_start_size）
### 作用
预计算 发射起始函数（emit_start） 将写入的总字节数，用于 生成 ELF（elf_gen） Phase 2 的代码段总大小估算。必须与 发射起始函数 的实际输出逐字节完全一致——Phase 2 基于此值预留代码段空间，Phase 3 的 发射起始函数 写入恰好填满预留空间。任何偏差将导致 BSS 定位错误和后续的 RIP 修补偏移量计算错误。
### 逻辑

令 预估大小（sz）= 调用 _start 函数体基础大小（sz_start_body（））
—— 起始函数体大小（sz_start_body）（） 返回值为 4 + 5 + 调用大小（sz_call）（） + 2 + 5 + 系统调用大小（sz_syscall）（） = 4 + 5 + 5 + 2 + 5 + 2 = 23 字节。该值涵盖了 发射起始函数（emit_start） 的第一步（mov rdi,[rsp] 4 字节）、第二步（lea rsi,[rsp+8] 5 字节）、第七步（call main 5 字节）、第八步（mov edi,eax 2 字节）、第九步（mov eax,60 5 字节）、第十步（syscall 2 字节）。不包含可选的 argc/argv 保存和全局变量初始化。

如果 argv 全局变量索引（gv_argc）大于等于 0，那么：令 预估大小 = 预估大小 + 调用 _start argv 保存大小（sz_start_argv_save（））
—— 起始参数保存大小（sz_start_argv_save）（） 返回 发射加载寄存器大小（sz_lr）（） + 3 = 7 + 3 = 10 字节。其中 发射加载寄存器大小（）=7 是 lea r10,[rip+0] 的大小（REX.WR + 0x8D + ModRM + 4 字节 rel32），+3 是 REX.WB（1） + 0x89（1） + ModRM（1） 即 mov [r10], rdi/rsi 的大小。

如果 argv 指针索引（gv_argv）大于等于 0，那么：令 预估大小 = 预估大小 + 调用 _start argv 保存大小（sz_start_argv_save（））= 10 字节

如果 当前竞技场全局变量索引（gv_current_arena）大于等于 0，那么：令 预估大小 = 预估大小 + 14
—— 当前竞技场（g_current_arena） 初始化 = lea r10,[rip+0]（7 字节）+ REX.WB（1） + 0xC7（1） + ModRM（1） + imm32（4） = 7 + 7 = 14 字节

—— 编译时常量全局变量初始化值的大小估算
令 全局变量遍历索引（gi0s）= 0
循环（当 全局变量遍历索引 小于 IR 全局变量计数（g_ir_global_count）时）：
    调用 读 64 位（r64），从 IR 全局变量数组（g_ir_globals）偏移量 全局变量遍历索引 × 24 + 16 处读取初始值，存入 临时变量 初始值（ivs）
    调用 读 64 位（r64），从 IR 全局变量数组 偏移量 全局变量遍历索引 × 24 + 8 处读取 IR 变量索引，存入 临时变量 变量编号（gvvs）
    如果 初始值 不等于 0 且 变量编号 大于等于 0，那么：
        如果 初始值 大于等于 -2147483648（即 -2^31）且 初始值 小于等于 2147483647（即 2^31 - 1），那么：
            —— 32 位有符号范围内：lea r10（7 字节）+ mov qword [r10], imm32（7 字节）= 14 字节
            令 预估大小 = 预估大小 + 14
        否则：
            —— 超出 32 位范围：lea r10（7 字节）+ mov rax, imm64（10 字节）+ mov [r10], rax（3 字节）= 20 字节
            令 预估大小 = 预估大小 + 20
    令 全局变量遍历索引 = 全局变量遍历索引 + 1

返回 预估大小

### 测试要点
1. 无任何可选全局变量（gv_argc/gv_argv/gv_current_arena 均 < 0，且所有 init_val=0）：返回值等于 起始函数体大小（sz_start_body）（）=23。必须与 发射起始函数（emit_start） 实际输出完全吻合。
2. 命令行参数个数索引（gv_argc） >= 0 时：额外增加 起始参数保存大小（sz_start_argv_save）（） = 发射加载寄存器大小（sz_lr）（） + 3 = 10 字节。
3. 命令行参数指针索引（gv_argv） >= 0 时：额外增加相同的 10 字节。
4. 当前竞技场索引（gv_current_arena） >= 0 时：额外增加 14 字节（7+7）。
5. 对于每个 初始值（init_val） != 0 且 全局变量值槽 0（gvv0） >= 0 的 IR 全局变量数组（g_ir_globals） 条目：32 位范围内贡献 14 字节，超出范围贡献 20 字节。
6. 混合场景（argc+argv+arena+多个初始化值）：逐项累加验证总数与 发射起始函数（emit_start） 实际输出一致。
7. 无条件分支导致的偏差：发射起始函数大小（emit_start_size） 是纯算术计算，不涉及 发射 REX 前缀（emit_rex） 等编码函数内部的条件分支——发射起始函数（emit_start） 中所有条件（gv_* >= 0、iv 范围）在 发射起始函数大小 中以相同逻辑复制，保证一致性。
