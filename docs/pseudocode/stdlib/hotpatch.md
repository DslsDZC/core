# hotpatch.cr 伪代码

> 源文件：src/stdlib/hotpatch.cr（47 行）
> 功能概要：热补丁（hotpatch）运行时——配置文件管理和进行中（in-flight）请求追踪。依赖 runtime/rt.cr 中声明的 g_hp_config / g_hp_inflight 全局变量，由 rt.s 中的 SIGHUP 信号处理器调用。

## 标识符对照表

| 中文名 | 原名 | 首次出现函数 |
|--------|------|-------------|
| 热补丁加载配置 | hp_load_config | 热补丁加载配置（hp_load_config） |
| 热补丁进行中计数加一 | hp_inflight_inc | 热补丁进行中计数加一（hp_inflight_inc） |
| 热补丁进行中计数减一 | hp_inflight_dec | 热补丁进行中计数减一（hp_inflight_dec） |
| 热补丁初始化 | hp_init | 热补丁初始化（hp_init） |
| 文件内容 | tc | 热补丁加载配置（hp_load_config） |
| 函数版本号 | fn_ver | 热补丁进行中计数加一（hp_inflight_inc） |
| 当前值 | cur | 热补丁进行中计数加一（hp_inflight_inc） |
| 循环变量 | i | 热补丁初始化（hp_init） |

## 全局状态

本文件内不声明全局变量。使用的全局变量由 `src/runtime/rt.cr` 声明：

| 中文名 | 原名 | 说明 | 初始值 |
|--------|------|------|--------|
| 热补丁配置 | g_hp_config | 存储 .hotpatch.toml 的配置文本 | 空字符串 |
| 热补丁进行中计数 | g_hp_inflight | 64 个槽位（每槽 8 字节）的进行中请求计数缓冲区 | 未初始化 |

## 函数 热补丁加载配置（hp_load_config）

### 作用

重新读取 .hotpatch.toml 文件内容到全局配置缓冲区。可在信号处理器上下文中安全调用（内核保存/恢复寄存器）。

### 逻辑

令 tc = 读取文件（".hotpatch.toml"）
如果 字符串长度（tc）大于 0，那么：
    令 g_hp_config = tc

### 测试要点

1. .hotpatch.toml 文件存在且有内容时更新 g_hp_config
2. 文件不存在或为空时 g_hp_config 保持不变
3. 在信号处理器上下文中调用安全（不分配内存）

## 函数 热补丁进行中计数加一（hp_inflight_inc）

### 作用

递增指定函数版本的进行中请求计数。用于追踪有多少个线程/协程正在执行该函数的某个版本。

### 逻辑

令 cur = 读 64 位（g_hp_inflight, fn_ver 乘以 8）
写 64 位（g_hp_inflight, fn_ver 乘以 8, cur 加 1）

### 测试要点

1. 初始值 0 时加一后变为 1
2. 多次调用正确累加
3. fn_ver 在 0-63 范围内

## 函数 热补丁进行中计数减一（hp_inflight_dec）

### 作用

递减指定函数版本的进行中请求计数。饱和于 0（不会变为负数）。

### 逻辑

令 cur = 读 64 位（g_hp_inflight, fn_ver 乘以 8）
如果 cur 大于 0，那么：
    写 64 位（g_hp_inflight, fn_ver 乘以 8, cur 减 1）

### 测试要点

1. cur = 1 时减一变为 0
2. cur = 0 时保持为 0（饱和，不变成负数）
3. 多次减一不会导致负值

## 函数 热补丁初始化（hp_init）

### 作用

在启动时初始化热补丁系统：分配进行中计数缓冲区（64 槽位，每槽 8 字节），清零所有槽位，加载初始配置。

### 逻辑

令 g_hp_config = ""
令 g_hp_inflight = 分配（64 乘以 8）  // 64 个版本槽位，每槽 8 字节
令 i = 0
循环（当 i 小于 64 时）：
    写 64 位（g_hp_inflight, i 乘以 8, 0）
    i = i 加 1
热补丁加载配置（）

### 测试要点

1. 分配 512 字节的 inflight 缓冲区
2. 所有 64 个槽位初始化为 0
3. 调用后 g_hp_config 已加载（若 .hotpatch.toml 存在）
