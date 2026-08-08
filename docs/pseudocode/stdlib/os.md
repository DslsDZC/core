# os.cr 伪代码

> 源文件：src/stdlib/os.cr（104 行）
> 功能概要：操作系统接口标准库。提供系统命令调用（fork/execve/wait4）、工作目录获取、可执行文件路径解析、环境变量读取等操作系统级功能。纯 Core 实现，通过 syscall3 直接使用 Linux 系统调用。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
|获取当前目录|get_cwd|获取当前目录（get_cwd）|
|获取可执行文件路径|get_exe_path|获取可执行文件路径（get_exe_path）|
|执行系统命令|system|执行系统命令（system）|
|获取环境变量|get_env|获取环境变量（get_env）|
|argv 参数块|Argv4|（结构体定义）|
|缓冲区|buf|获取当前目录（get_cwd）|
|系统调用返回值|n/pid|获取当前目录（get_cwd）/ 执行系统命令（system）|
|状态缓冲区|status_buf|执行系统命令（system）|
|argv 数组|argv|执行系统命令（system）|
|环境变量内容|env|获取环境变量（get_env）|
|环境变量长度|elen|获取环境变量（get_env）|
|等号位置|eq_pos|获取环境变量（get_env）|
|键长度|key_len|获取环境变量（get_env）|
|名称长度|nlen|获取环境变量（get_env）|
|是否匹配|is_match|获取环境变量（get_env）|
|值起始|val_start|获取环境变量（get_env）|
|值结束|val_end|获取环境变量（get_env）|
|循环变量|i/j/ki|获取环境变量（get_env）|

## 全局状态

无全局变量。

## 结构 参数块（Argv4）

内存布局：4 个连续的 8 字节值（指针数组）。d = 0 作为 NULL 终止符。

| 字段（原名字段名） | 中文说明 | 偏移 |
|---|---|---|
| a | 第一个参数字符串 | 0 |
| b | 第二个参数字符串 | 8 |
| c | 第三个参数字符串 | 16 |
| d | NULL 终止符（整数 0） | 24 |

## 函数 获取当前目录（get_cwd）

### 作用

获取进程的当前工作目录。使用 getcwd 系统调用（79）。

### 逻辑

令 buf = 分配（4096）
令 n = 系统调用3（79, buf, 4096, 0）  // getcwd(buf, 4096)
如果 n 不大于 1，那么：返回 ""
返回 字符串切片（buf, 0, n 减 1）  // 去掉末尾换行符/null

### 测试要点

1. 正常返回当前工作目录路径字符串
2. getcwd 失败（n <= 0）时返回空字符串
3. n = 1（仅 null 终止符）返回空字符串

## 函数 获取可执行文件路径（get_exe_path）

### 作用

即使 argv[0] 来自 PATH，也能解析出当前运行的可执行文件的真实路径。通过 readlink 读取 /proc/self/exe。

### 逻辑

令 buf = 分配（4096）
令 n = 系统调用3（89, "/proc/self/exe", buf, 4095）  // readlink，系统调用号 89
如果 n 不大于 0，那么：返回 ""
返回 字符串切片（buf, 0, n）

### 测试要点

1. 在正常 Linux 环境中返回可执行文件绝对路径
2. /proc 不可用时返回空字符串
3. readlink 失败返回空字符串

## 函数 执行系统命令（system）

### 作用

执行 shell 命令：fork 子进程，子进程中 execve("/bin/sh", ["/bin/sh", "-c", cmd], environ)；父进程 wait4 等待子进程结束，返回退出状态码。失败返回 -1。

### 逻辑

令 pid = 系统调用3（57, 0, 0, 0）  // fork()，系统调用号 57
如果 pid 小于 0，那么：返回 -1  // fork 失败
如果 pid 大于 0，那么：  // 父进程
    令 status_buf = 分配（16）
    系统调用3（61, pid, status_buf, 0）  // wait4(pid, &status, 0, NULL)，系统调用号 61
    返回 按字节读取（status_buf, 1）取模 256  // 退出码在 bits 8-15
// 否则：子进程
令 argv = 分配（32）
存储字符串指针（argv, 0, "/bin/sh"）
存储字符串指针（argv, 8, "-c"）
存储字符串指针（argv, 16, cmd）
令 zi = 0
循环（当 zi 小于 8 时）：
    写单字节（argv, 24 加 zi, 0）  // argv[3] = NULL 指针（8 字节清零）
    zi = zi 加 1
系统调用3（59, "/bin/sh", argv, 0）  // execve — 成功则不返回
系统调用3（60, 127, 0, 0）  // execve 失败时 _exit(127)
返回 -1

### 测试要点

1. 命令正常执行时返回退出码 0
2. 命令执行失败时返回非零退出码
3. fork 失败时返回 -1
4. execve 失败时子进程 _exit(127)
5. 空命令字符串执行 shell 并正常返回

## 函数 获取环境变量（get_env）

### 作用

从 /proc/self/environ 中读取指定名称的环境变量值。未找到返回空字符串。

### 逻辑

令 env = 读取文件（"/proc/self/environ"）
如果 字符串长度（env）等于 0，那么：返回 ""
令 elen = 字符串长度（env）
令 i = 0
循环（当 i 小于 elen 时）：
    令 eq_pos = -1
    令 j = i
    循环（当 j 小于 elen 时）：
        令 c = 按字节读取（env, j）
        如果 c 等于 61，那么：令 eq_pos = j，跳出循环  // '='
        如果 c 等于 0，那么：跳出循环  // null 分隔符
        j = j 加 1
    如果 eq_pos 不小于 0，那么：
        令 key_len = eq_pos 减 i
        令 nlen = 字符串长度（name）
        如果 key_len 等于 nlen，那么：
            令 is_match = 1
            令 ki = 0
            循环（当 ki 小于 key_len 时）：
                如果 按字节读取（env, i 加 ki）不等于 按字节读取（name, ki），那么：
                    令 is_match = 0，跳出循环
                ki = ki 加 1
            如果 is_match 不等于 0，那么：
                令 val_start = eq_pos 加 1
                令 val_end = val_start
                循环（当 val_end 小于 elen 时）：
                    如果 按字节读取（env, val_end）等于 0，那么：跳出循环
                    val_end = val_end 加 1
                返回 字符串切片（env, val_start, val_end 减 val_start）
    循环（当 i 小于 elen 且 按字节读取（env, i）不等于 0 时）：
        i = i 加 1
    i = i 加 1  // 跳过 null 分隔符
返回 ""

### 测试要点

1. 环境变量存在时返回其值
2. 环境变量不存在时返回空字符串
3. /proc/self/environ 不可读时返回空字符串
4. 环境变量值为空时返回空字符串
5. 环境变量名与查找名长度不等时继续搜索下一个变量
