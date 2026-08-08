# corearch.cr 伪代码
> 源文件：src/compiler/corearch.cr（150 行）
> 功能概要：后端入口（corearch 二进制）：.线性指令流（ccr） 文件加载、命令行解析、ELF/共享库生成及动态/静态链接管线编排。

## 标识符对照表
| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 初始化后端数组 | init_backend_arrays | 初始化后端数组 |
| 拆分链接参数 | split_links | 拆分链接参数 |
| corearch 主入口 | corearch_main | corearch 主入口 |
| CLI：初始化 | cli_init | corearch 主入口 |
| CLI：添加标志 | cli_flag | corearch 主入口 |
| CLI：获取布尔标志 | cli_flag_bool | corearch 主入口 |
| CLI：判断标志存在 | cli_has | corearch 主入口 |
| CLI：获取参数值 | cli_get | corearch 主入口 |
| CLI：解析 | cli_parse | corearch 主入口 |
| CLI：位置参数个数 | cli_arg_count | corearch 主入口 |
| CLI：获取位置参数 | cli_arg | corearch 主入口 |
| 链接上下文：添加 .so | ctx_add_so | corearch 主入口 |
| 初始化链接上下文 | ctx_init | corearch 主入口 |
| 链接上下文：添加 PLT 条目 | ctx_add_plt | corearch 主入口 |
| 链接上下文：发射静态链接 | ctx_emit_static | corearch 主入口 |
| 链接上下文：发射动态链接 | ctx_emit_dyn | corearch 主入口 |
| 设置用户代码 | ctx_set_user_code | corearch 主入口 |
| 生成 ELF | elf_gen | corearch 主入口 |
| 加载 .ccr 文件 | load_ccr | corearch 主入口 |
| 字符串相等比较 | str_eq | corearch 主入口 |
| 字符串长度 | str_len | corearch 主入口 |
| 字符串切片 | str_sub | corearch 主入口 |
| 整数转字符串 | int_str | corearch 主入口 |
| 字符串转整数 | str_int | corearch 主入口 |
| 驻留字符串获取 | istr_get | corearch 主入口 |
| 读取文件 | read_file | corearch 主入口 |
| 获取命令行参数 | get_arg | corearch 主入口 |
| 输出字符串 | print | corearch 主入口 |
| 输出行 | println | corearch 主入口 |
| 分配内存 | alloc | corearch 主入口 |
| 写单字节 | w8 | corearch 主入口 |
| 写 16 位 | w16 | corearch 主入口 |
| 写 32 位 | w32 | corearch 主入口 |
| 读 64 位 | r64 | corearch 主入口 |
| 读字节/按偏移读字节 | load8 | corearch 主入口 |
| 写字节/按偏移写字节 | store8 | corearch 主入口 |
| ELF 输出缓冲区 | g_elf_buf | corearch 主入口 |
| 优化级别 | g_opt_level | corearch 主入口 |
| .so 计数 | g_so_count | corearch 主入口 |
| x86 外部重定位名称数组 | g_x86_ext_rel_name | corearch 主入口 |
| x86 外部重定位计数 | g_x86_ext_rel_count | corearch 主入口 |
| x86 RIP 修补位置数组 | g_x86_rip_patch_pos | corearch 主入口 |
| x86 RIP 修补计数 | g_x86_rip_patch_count | corearch 主入口 |
| x86 是否需要发射运行时桩标记 | g_x86_emit_rt_stubs | corearch 主入口 |
| x86 变量计数 | g_x86_var_count | 初始化后端数组 |
| x86 栈大小 | g_x86_stack_size | 初始化后端数组 |
| x86 当前函数索引 | g_x86_func_idx | 初始化后端数组 |
| x86 枚举变量计数 | g_x86_is_enum_count | 初始化后端数组 |
| x86 变量容量 | g_x86_var_cap | 初始化后端数组 |
| x86 枚举变量容量 | g_x86_is_enum_cap | 初始化后端数组 |
| x86 栈映射数组 | g_stack_map | 初始化后端数组 |
| 参数值字符串 | val | 拆分链接参数（参数） |
| 参数长度 | sl | 拆分链接参数（局部） |
| 段起始位置 | start | 拆分链接参数（局部） |
| 索引 | i | 拆分链接参数（局部） |
| 文件描述符 | fd | corearch 主入口（局部） |
| 文件大小 | fsize | corearch 主入口（局部） |
| 读取缓冲区 | buf | corearch 主入口（局部） |
| 读取字节数 | nread | corearch 主入口（局部） |
| 源路径 | src_path | corearch 主入口（局部） |
| 优化参数字符串 | ol | corearch 主入口（局部） |
| 发射共享库标记 | emit_so | corearch 主入口（局部） |
| 链接参数值 | link_val | corearch 主入口（局部） |
| 输出字符串路径 | out_path | corearch 主入口（局部） |
| ELF 总大小 | sz | corearch 主入口（局部） |
| 代码段大小 | cs | corearch 主入口（局部） |
| 代码数据缓冲 | cd | corearch 主入口（局部） |
| 拷贝索引 | ci | corearch 主入口（局部） |
| 修补索引 | rpi | corearch 主入口（局部） |
| 修补位置 | ppos | corearch 主入口（局部） |
| 自身路径 | sp | corearch 主入口（局部） |
| 自身路径长度 | sllen | corearch 主入口（局部） |
| 最后斜杠位置 | last_sl | corearch 主入口（局部） |
| 斜杠扫描索引 | sli | corearch 主入口（局部） |
| 库路径 | libp | corearch 主入口（局部） |
| 是否静态链接 | is_static | corearch 主入口（局部） |
| 重定位索引 | ri | corearch 主入口（局部） |
| 函数名 | fn_name | corearch 主入口（局部） |

## 全局状态
本文件不声明新全局变量（全局变量在 globals.cr 中定义），但读写多个后端相关全局变量（见上表）。

## 函数 初始化后端数组（init_backend_arrays）
### 作用
重置所有后端（x86 代码生成）相关的全局数组计数器（corearch）次 （corearch） 管线开始时调用，确保后端从干净状态启动。

### 逻辑
函数 初始化后端数组（init_backend_arrays）（）：
    令 x86 变量计数 = 0
    令 x86 栈大小 = 0
    令 x86 当前函数索引 = 0
    令 x86 枚举变量计数 = 0
    令 x86 变量容量 = 0
    令 x86 枚举变量容量 = 0
    令 x86 栈映射数组 = ""

### 测试要点
1. 调用后全部后端计数值归零
2. 栈映射数组被清空为空字符串
3. 容量变量也被重置为 0，确保后续 （grow） 函数从零开始分配

## 函数 拆分链接参数（split_links）
### 作用
将逗号分隔的 .so 文件列表字符串解析为单独的路径，并逐个调用链接上下文：添加 .so（ctx_add_so）注册到链接表中。

### 逻辑
函数 拆分链接参数（split_links）（参数值字符串（val）：字符串）：
    令 参数长度（sl） = 字符串长度（参数值字符串）
    令 段起始位置（start） = 0
    令 索引（i） = 0

    循环（当 索引 小于等于 参数长度 时）：
        如果 索引 等于 参数长度，或 读字节（load8）（参数值字符串，索引）等于 44，那么：    // 到达字符串末尾或遇到逗号
            如果 索引 大于 段起始位置，那么：
                令 路径 = 字符串切片（参数值字符串，段起始位置，索引 - 段起始位置）
                链接上下文：添加 .so（路径）
            令 段起始位置 = 索引 + 1
        令 索引 = 索引 + 1

### 测试要点
1. 单个 .so 路径正确注册
2. 逗号分隔的多个路径逐个注册
3. 空字符串不触发注册
4. 连续逗号（空段）被跳过，不注册空路径

## 函数 （corearch） 主入口（corearch_main）
### 作用
（corearch） 二进制的 CLI 入口与管线编排。解析命令行参数，加载 .线性指令流（ccr） 文件，根据选项（--elf / --shared / --static / --link）生成对应的输出字符串：ELF 可执行文件或共享库，支持纯静态、动态链接和手动 .so 指定。

### 逻辑
函数 （corearch） 主入口（corearch_main）（） -> 整数：
    // ===== 命令行初始化 =====
    CLI：初始化（"corearch"，"Core architecture backend"）
    CLI：获取布尔标志（"elf"，""，"Output ELF binary （default）"）
    CLI：获取布尔标志（"shared"，""，"Output shared library （.so）"）
    CLI：获取布尔标志（"static"，""，"Static linking （embed runtime）"）
    CLI：添加标志（"link"，"l"，"Comma-sep .so files, or 'auto' 遍历（for） ~/.核心（core）/lib/"）
    CLI：添加标志（"output"，"o"，"Output path"）
    CLI：添加标志（"opt-level"，"O"，"Optimization level （0-3, default=0）"）

    如果 CLI：解析（） 不等于 0，那么：返回 1

    // 解析优化级别（默认 O0）
    令 优化级别 = 0
    令 优化参数字符串（ol） = CLI：获取参数值（"opt-level"）
    如果 字符串长度（优化参数字符串）大于 0，那么：
        令 优化级别 = 字符串转整数（优化参数字符串）
        如果 优化级别 大于 3，那么：令 优化级别 = 3
        如果 优化级别 小于 0，那么：令 优化级别 = 0

    // 检查是否提供了 .线性指令流（ccr） 文件参数
    如果 CLI：位置参数个数（） 小于 1，那么：
        输出行（"usage: corearch <file.线性指令流（ccr）> [options]"）
        输出行（"  --elf           ELF binary （default: dynamic）"）
        输出行（"  --static        static linking （embed runtime）"）
        输出行（"  --shared        shared library （.so）"）
        输出行（"  --link auto     link ~/.核心（core）/lib/*.so （default）"）
        输出行（"  --link s1,s2   link specific .so files"）
        输出行（"  -o FILE         output path"）
        返回 1

    // ===== 加载 .线性指令流（ccr） 文件 =====
    令 源路径（src_path） = CLI：获取位置参数（0）
    令 文件描述符（fd） = 系统调用3（（sy）（open）（l3））（2，源路径，0，0）    // （open）（O_RDONLY）
    如果 文件描述符 小于 0，那么：
        输出字符串（"error: cannot open "）
        输出行（源路径）
        返回 1

    令 文件大小（fsize） = 系统调用3（lseek）描（fd），0，2）    // 文件定位（文件定位）（（文件描述符）, 0, SEEK_END）
    系统调用3（lseek）（fd）  // 文件定位（文件定位）（（文件描述符）, 0, SEEK_SET）

    令 读取缓冲区（buf） = 分配内存（文件大小 + 1）
    令 读取字节数（nread） = 系统调用3（read）件（fd）符，（buf）冲区（size）小）    // （read）（（文件描述符）, （缓冲区）, （size））
    系统调用3（close）（fd）  // （close）（（文件描述符））

    如果 读取字节数 不等于 文件大小，那么：
        输出行（"error: cannot read"）
        返回 1

    令 加载结果 = 加载 .线性指令流（ccr） 文件（读取缓冲区，文件大小）
    如果 加载结果 不等于 0，那么：
        输出行（"error: invalid .线性指令流（ccr） file"）
        返回 1

    // ===== 初始化后端状态 =====
    初始化后端数组（）

    // ===== 解析输出字符串选项 =====
    令 发射共享库标记（emit_so） = CLI：判断标志存在（"shared"）
    令 链接参数值（link_val） = CLI：获取参数值（"link"）
    令 输出字符串路径（out_path） = CLI：获取参数值（"output"）

    // 纯静态模式（无 --link，非 --shared）：
    // 后端发射 （g_set_curg）/（g_get_curg） 桥接桩代码（不需要 rt.状态（s） 链接）
    // 有 --（link） 时，桩代码保持外部引用，从 （core_rt）.so（s）解析
    令 x86 是否需要发射运行时桩标记 = 0
    如果 字符串长度（链接参数值）等于 0 且 发射共享库标记 等于 0，那么：
        令 x86 是否需要发射运行时桩标记 = 1

    // ===== --（shared）：生成共享库（ET_DYN） =====
    如果 发射共享库标记 不等于 0，那么：
        如果 字符串长度（输出字符串路径）等于 0，那么：
            令 输出字符串路径 = "（core_lib）.so"

        令 ELF 输出缓冲区 = 分配内存（16777216）
        令 ELF 总大小（sz） = 生成 ELF（ELF 输出缓冲区）
        写 16 位（ELF 输出缓冲区（e_type）    // 修改 （e_type） 字段为 共享对象类型（ET_DYN）（3）

        令 文件描述符 = 系统调用3（2，输出字符串路径（open），420）    // （open）（O_WRONLY|O_CREAT|O_TRUNC, 0644）
        如果 文件描述符 小于 0，那么：
            输出字符串（"error: cannot 写入（write） "）
            输出行（输出字符串路径）
            返回 1

        系统调用3（1，文件描述（write） 输出字符串缓冲区，ELF 总大小）    // （写入）
        系统调用3（close）    // （close）

        输出字符串（" -> "）
        输出行（输出字符串路径）
        返回 0

    // ===== 默认：ELF（静态或动态链接） =====
    如果 字符串长度（输出字符串路径）等于 0，那么：
        令 输出字符串路径 = "（a）.（out）"

    令 ELF 输出缓冲区 = 分配内存（16777216）
    令 是否静态链接（is_static） = CLI：判断标志存在（"static"）

    如果 字符串长度（链接参数值）大于 0，那么：
        // ---- 有链接参数：初始化链接上下文 ----
        初始化链接上下文（）

        如果 字符串相等比较（链接参数值，"auto"）不等于 0，那么：
            // 自动模式：从编译器二进制旁查找 （core_rt）.so
            令 自身路径（sp） = 获取命令行参数（0）
            令 自身路径长度（sllen） = 字符串长度（自身路径）
            令 最后斜杠位置（last_sl） = -1
            令 斜杠扫描索引（sli） = 0
            循环（当 斜杠扫描索引 小于 自身路径长度 时）：
                如果 读字节（load8）（自身路径，斜杠扫描索引）等于 47，那么：    // "/"
                    令 最后斜杠位置 = 斜杠扫描索引
                令 斜杠扫描索引 = 斜杠扫描索引 + 1

            如果 最后斜杠位置 大于等于 0，那么：
                令 库路径（libp） = 字符（core_rt）径，0，最后斜杠位置 + 1）+ "（core_rt）.so"
                如果 字符串长度（读取文件（库路径））大于 0，那么：
                    链接上下文：添加 .so（库路径）

            // 按序尝试 ./（build）/、./ 和 ~/.（core）/（lib）/
            如果 字符串长度（读取文件（"./build/core_rt.so"））大于 0，那么：
                链接上下文：添加 .so（"./build/core_rt.so"）
            否则如果 字符串长度（读取文件（"./core_rt.so"））大于 0，那么：
                链接上下文：添加 .so（"./core_rt.so"）

            如果 字符串长度（读取文件（"~/.核心（core）/lib/core_rt.so"））大于 0，那么：
                链接上下文：添加 .so（"~/.核心（core）/lib/core_rt.so"）
        否则：
            拆分链接参数（链接参数值）

        // ---- 生成 ELF 并提取代码段 ----
        令 ELF 总大小（sz） = 生成 ELF（ELF 输出缓冲区）
        令 代码段大小（cs） = ELF 总大小 - 176
        如果 代码段大小 小于等于 0，那么：
            输出行（"error: empty code"）
            返回 1

        令 代码数据缓冲（cd） = 分配内存（代码段大小）
        令 拷贝索引（ci） = 0
        循环（当 拷贝索引 小于 代码段大小 时）：
            写字节（store8）（代码数据缓冲，拷贝索引，读字节（load8）（ELF 输出缓冲区，176 + 拷贝索引））
            令 拷贝索引 = 拷贝索引 + 1

        // ---- 清除用户代码中的 RIP 相对修补（原指向 BSS） ----
        // 将 lea r10,[rip+...] 后面的 mov [r10],（rXX） （NOP） 掉
        令 修补索引（rpi） = 0
        循环（当 修补索引 小于 x86 RIP 修补计数 时）：
            令 修补位置（ppos） = 读 64 位（x86 RIP 修补位置数组，修补索引 * 8）
            如果 修补位置 大于等于 176 且 修补位置 - 176 + 4 小于等于 代码段大小，那么：
                写 32 位（代码数据缓冲，修补位置 - 176，0）
                写单字节（代码数据缓冲（NOP）位置 + 4 - 176，144）    // 空操作指令（空操作指令）
                写单字节（代码数据缓冲（NOP）位置 + 5 - 176，144）    // 空操作指令（空操作指令）
                写单字节（代码数据缓冲（NOP）位置 + 6 - 176，144）    // 空操作指令（空操作指令）
            令 修补索引 = 修补索引 + 1

        // ---- 根据链接模式输出字符串 ----
        如果 是否静态链接 不等于 0，那么：
            如果 .so 计数 大于 0，那么：
                // 静态链接但有 .so 依赖：委托给链接上下文
                设置用户代码（代码数据缓冲，代码段大小）
                令 ELF 总大小 = 链接上下文：发射静态链接（ELF 输出缓冲区，输出字符串路径）
            否则：
                // 纯静态：直接写入文件（rt.cr 已由前端预置到源码中）
                令 文件描述符 = 系统调用3（2，输出字符串路径，577，420）
                如果 文件描述符 小于 0，那么：
                    输出字符串（"error: cannot 写入（write） "）
                    输出行（输出字符串路径）
                    返回 1
                系统调用3（1，文件描述符，ELF 输出缓冲区，ELF 总大小）
                系统调用3（3，文件描述符，0，0）
        否则：
            // ---- 动态链接：PLT/GOT 解析 ----
            令 重定位索引（ri） = 0
            循环（当 重定位索引 小于 x86 外部重定位计数 时）：
                令 函数名（fn_name） = 驻留字符串获取（读 64 位（x86 外部重定位名称数组，重定位索引 * 8））
                链接上下文：添加 PLT 条目（函数名，0）
                令 重定位索引 = 重定位索引 + 1

            设置用户代码（代码数据缓冲，代码段大小）
            令 ELF 总大小 = 链接上下文：发射动态链接（ELF 输出缓冲区，输出字符串路径）

        如果 ELF 总大小 小于等于 0，那么：
            输出行（"error: linking failed"）
            返回 1

    否则：
        // ---- 无链接参数：直接生成 ELF 并输出字符串 ----
        令 ELF 总大小（sz） = 生成 ELF（ELF 输出缓冲区）
        令 文件描述符 = 系统调用3（2，输出字符串路径，577，420）
        如果 文件描述符 小于 0，那么：
            输出字符串（"error: cannot 写入（write） "）
            输出行（输出字符串路径）
            返回 1
        系统调用3（1，文件描述符，ELF 输出缓冲区，ELF 总大小）
        系统调用3（3，文件描述符，0，0）

    输出字符串（" -> "）
    输出行（输出字符串路径）
    返回 0

### 测试要点
1. 无参数运行输出字符串用法提示并返回 1
2. .线性指令流（ccr） 文件不存在时打印错误返回 1
3. .线性指令流（ccr） 文件读取失败（读取字节数不等于文件大小）返回 1
4. .线性指令流（ccr） 文件格式无效（load_ccr 返回非 0）返回 1
5. --（shared） 模式生成 共享对象类型（ET_DYN） 类型 ELF 并正确输出字符串到指定路径或默认 "（core_lib）.so"
6. --（link） （auto） 在编译器自身路径旁、./（build）/、./、~/.（core）/（lib）/ 依次查找 （core_rt）.so
7. --（link） 逗号分隔列表调用拆分链接参数（split_links）逐个注册
8. 纯静态无 --（link） 模式设置 x86 是否需要发射运行时桩标记 = 1
9. --（static） 且 .so 计数 > 0 时调用链接上下文：发射静态链接
10. --（static） 且 .so 计数 = 0 时直接输出字符串 ELF（前端已预置 rt.cr）
11. 动态链接模式遍历 x86 外部重定位，为每个外部符号添加 PLT 条目
12. 链接失败（大小 <= 0）输出字符串错误并返回 1
13. RIP 修补 （NOP） 化逻辑：仅对位置在代码段内的修补操作
14. 空代码（代码大小 <= 0）输出字符串错误返回 1
