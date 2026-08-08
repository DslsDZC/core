# main.cr 伪代码

> 源文件：src/arch/linux/ld/main.cr（136 行）
> 功能概要：corearch 后端项目的入口点。负责解析命令行参数、加载 .ccr 文件、初始化后端数组，并根据选项（ELF/共享库/静态链接）协调整个 ELF 生成与动态链接管线。对应 `src/compiler/corearch.cr` 的自举版本。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 初始化后端数组 | init_backend_arrays | init_backend_arrays |
| 拆分链接参数 | split_links | split_links |
| corearch 主入口 | corearch_main | corearch_main |
| 主入口 | main | main |
| 加载 .ccr 文件 | load_ccr | corearch_main |
| 生成 ELF | elf_gen | corearch_main |
| 初始化链接上下文 | ctx_init | corearch_main |
| 链接上下文：添加 .so | ctx_add_so | split_links / corearch_main |
| 链接上下文：添加 PLT 条目 | ctx_add_plt | corearch_main |
| 链接上下文：设置用户代码 | ctx_set_user_code | corearch_main |
| 链接上下文：发射动态链接 | ctx_emit_dyn | corearch_main |
| 链接上下文：发射静态链接 | ctx_emit_static | corearch_main |
| CLI：初始化 | cli_init | corearch_main |
| CLI：判断标志存在 | cli_has | corearch_main |
| CLI：字符串参数匹配 | cli_eq | corearch_main |
| CLI：解析 | cli_parse | corearch_main |
| CLI：添加标志 | cli_flag | corearch_main |
| CLI：获取参数值 | cli_get | corearch_main |
| CLI：获取布尔标志 | cli_flag_bool | corearch_main |
| CLI：位置参数个数 | cli_arg_count | corearch_main |
| CLI：获取位置参数 | cli_arg | corearch_main |
| ELF 输出缓冲区 | g_elf_buf | corearch_main |
| x86 栈大小 | g_x86_stack_size | init_backend_arrays |
| x86 变量计数 | g_x86_var_count | init_backend_arrays |
| x86 当前函数索引 | g_x86_func_idx | init_backend_arrays |
| x86 枚举变量计数 | g_x86_is_enum_count | init_backend_arrays |
| x86 变量容量 | g_x86_var_cap | init_backend_arrays |
| x86 枚举变量容量 | g_x86_is_enum_cap | init_backend_arrays |
| x86 栈映射数组 | g_stack_map | init_backend_arrays |
| 优化级别 | g_opt_level | corearch_main |
| x86 RIP 修补位置数组 | g_x86_rip_patch_pos | corearch_main |
| x86 RIP 修补计数 | g_x86_rip_patch_count | corearch_main |
| x86 外部重定位计数 | g_x86_ext_rel_count | corearch_main |
| x86 外部重定位名称数组 | g_x86_ext_rel_name | corearch_main |
| .so 计数 | g_so_count | corearch_main |
| 字符串常量计数 | g_str_count | corearch_main |
| 输出字符串 | print | corearch_main |
| 输出行 | println | corearch_main |
| 整数转字符串 | int_str | corearch_main |
| 字符串长度 | str_len | split_links |
| 字符串切片 | str_sub | split_links |
| 字符串相等比较 | str_eq | corearch_main |
| 字符串转整数 | str_int | corearch_main |
| 读取文件 | read_file | corearch_main |

## 全局状态

本文件参与的全局变量（声明于 globals.cr）：
- `g_elf_buf`：ELF 输出缓冲区
- `g_x86_var_count`、`g_x86_stack_size`、`g_x86_func_idx`：后端状态
- `g_x86_is_enum_count`：枚举标记计数
- `g_x86_var_cap`、`g_x86_is_enum_cap`：容量
- `g_stack_map`：栈共享映射
- `g_opt_level`：优化级别（0-3）

## 函数 初始化后端数组（init_backend_arrays）
### 作用
复位所有后端数组和计数器，清零状态，准备新的编译。
### 逻辑
令 x86 变量计数 = 0
令 x86 栈大小 = 0
令 x86 当前函数索引 = 0
令 x86 枚举变量计数 = 0
令 x86 变量容量 = 0
令 x86 枚举变量容量 = 0
令 x86 栈映射数组 = ""（空字符串，零长度缓冲区）
### 测试要点
1. 所有计数器和容量置零。
2. 栈映射数组初始化为空字符串。

## 函数 拆分链接参数（split_links）
### 作用
按逗号（ASCII 44）分割链接参数字符串，将每个 .so 文件路径通过 ctx_add_so 注册到链接上下文。
### 逻辑
令 源字符串长度 = 字符串长度（输入字符串）
令 起始位置 = 0
令 当前索引 = 0
循环（当 当前索引 不大于 源字符串长度 时）：
    如果 当前索引 等于 源字符串长度 或 当前字符串[当前索引] 等于 逗号（44），那么：
        如果 当前索引 大于 起始位置，那么：
            令 子串 = 字符串切片（输入字符串, 起始位置, 当前索引 - 起始位置）
            调用 链接上下文：添加 .so（子串）
        令 起始位置 = 当前索引 + 1
    当前索引 = 当前索引 + 1
### 测试要点
1. 空字符串：不注册任何 .so。
2. 单个路径："a.so" 注册 1 个 .so。
3. 多个路径："a.so,b.so" 注册 2 个 .so。
4. 末尾逗号：不产生空名称注册。
5. 连续逗号："a.so,,b.so" 中间空项被跳过。

## 函数 corearch 主入口（corearch_main）
### 作用
corearch 二进制的主入口。解析命令行参数，加载 .ccr 文件，根据 --shared/--static/--link 选项协调 ELF 生成流水线（静态直写 / 动态链接 / 共享库模式），输出最终 ELF 文件。
### 逻辑
调用 CLI：初始化（"corearch", "Core architecture backend"）
调用 CLI：添加标志 "--elf"（输出 ELF 二进制）、"--shared"（输出 .so 共享库）、"--static"（静态链接）
调用 CLI：添加标志 "--link"（逗号分隔 .so 文件列表，或 "auto"）
调用 CLI：添加标志 "--output"（输出路径，简写 "-o"）
调用 CLI：添加标志 "--opt-level"（优化级别 0-3，简写 "-O"）

如果 CLI：解析（） 不等于 0，那么：返回 1（解析错误）

令 优化级别 = 0
令 选项值 = CLI：获取参数值（"opt-level"）
如果 字符串长度（选项值）> 0，那么：
    令 优化级别 = 字符串转整数（选项值）
    如果 优化级别 > 3，那么：令 优化级别 = 3
    如果 优化级别 < 0，那么：令 优化级别 = 0

如果 CLI：位置参数个数（）< 1，那么：
    输出使用帮助信息
    返回 1

令 源码路径 = CLI：获取位置参数（0）
—— 打开并读取 .ccr 文件
令 文件描述符 = 系统调用3（2, 源码路径, 0, 0）  —— sys_open
如果 文件描述符 < 0，那么：输出错误信息；返回 1
令 文件大小 = 系统调用3（8, 文件描述符, 0, 2）  —— lseek SEEK_END
调用 系统调用3（8, 文件描述符, 0, 0）  —— lseek SEEK_SET 回文件头
令 读取缓冲区 = 分配（文件大小 + 1）
令 读取字节数 = 系统调用3（0, 文件描述符, 读取缓冲区, 文件大小）
调用 系统调用3（3, 文件描述符, 0, 0）  —— close
如果 读取字节数 不等于 文件大小，那么：输出错误；返回 1
令 结果 = 加载 .ccr 文件（读取缓冲区, 文件大小）
如果 结果 不等于 0，那么：输出错误；返回 1

调用 初始化后端数组（）

令 是否共享库 = CLI：判断标志存在（"shared"）
令 链接选项值 = CLI：获取参数值（"link"）
令 输出路径 = CLI：获取参数值（"output"）

—— 共享库模式（--shared）
如果 是否共享库 不等于 0，那么：
    如果 字符串长度（输出路径）等于 0，那么：令 输出路径 = "core_lib.so"
    令 ELF 输出缓冲区 = 分配（16 MB）
    令 大小 = 生成 ELF（ELF 输出缓冲区）
    写入 16 位（ELF 输出缓冲区, 16, 3）  —— 将 ELF 类型改为 ET_DYN
    写输出文件并返回

—— 普通模式
如果 字符串长度（输出路径）等于 0，那么：令 输出路径 = "a.out"
令 ELF 输出缓冲区 = 分配（16 MB）

令 是否静态 = CLI：判断标志存在（"static"）

—— 有链接参数
如果 字符串长度（链接选项值）> 0，那么：
    调用 初始化链接上下文（）
    —— 自动发现 core_rt.so
    如果 字符串相等比较（链接选项值, "auto"）不等于 0，那么：
        在可执行文件同目录、./build/、~/.core/lib/ 等处查找 core_rt.so 并注册
    否则：
        调用 拆分链接参数（链接选项值）  —— 手动指定
    
    令 大小 = 生成 ELF（ELF 输出缓冲区）
    令 代码大小 = 大小 - 176（去掉 ELF 头 + 程序头）
    如果 代码大小 <= 0，那么：输出错误；返回 1
    令 代码数据 = 分配（代码大小）
    拷贝代码段（从 176 开始）到代码数据
    
    —— 清零 RIP 修补（动态链接模式下不需要）
    遍历所有 RIP 修补，将对应位置写为 NOP（0x90）或清零
    
    —— 静态链接或动态链接分发
    如果 是否静态 不等于 0，那么：
        如果 .so 计数 > 0，那么：
            调用 链接上下文：设置用户代码（代码数据, 代码大小）
            令 大小 = 链接上下文：发射静态链接（ELF 输出缓冲区, 输出路径）
        否则：直写 ELF
    否则：
        —— 动态链接：为每个外部重定位创建 PLT 条目
        遍历 外部重定位名称数组，逐一调用 链接上下文：添加 PLT 条目
        调用 链接上下文：设置用户代码（代码数据, 代码大小）
        令 大小 = 链接上下文：发射动态链接（ELF 输出缓冲区, 输出路径）
    
    如果 大小 <= 0，那么：输出错误；返回 1

否则：
    —— 无链接参数：直写 ELF
    令 大小 = 生成 ELF（ELF 输出缓冲区）
    写输出文件

输出 " -> [输出路径]"
返回 0

### 测试要点
1. 无参数启动：应输出帮助信息并返回 1。
2. 无效 .ccr 文件路径：应输出错误并返回 1。
3. 损坏的 .ccr 文件：load_ccr 返回非零值，应输出错误。
4. --shared 模式：输出文件类型应为 ET_DYN（3），文件扩展名为 .so。
5. --static --link auto：应找到 core_rt.so 并调用 ctx_emit_static。
6. --link auto（不含 --static）：应走到 ctx_emit_dyn 动态链接路径。
7. --link a.so,b.so：split_links 解析两个路径。
8. -o 指定输出路径：应使用用户指定的路径而非 "a.out"。
9. --opt-level 超出范围：应钳制到 0-3。

## 函数 主入口（main）
### 作用
委托调用 corearch_main，传递返回值。
### 逻辑
返回 corearch 主入口（）
### 测试要点
1. 仅作为包装函数，返回值应与 corearch_main 一致。
