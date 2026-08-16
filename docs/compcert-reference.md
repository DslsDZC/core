# CompCert 后端对照参考（形式化验证过的 C 编译器）

> CompCert：世界上唯一被形式化验证过的 C 编译器（INRIA，Leroy 团队）。
> 整个后端用 Coq 编写并被 Coq 证明正确——学习"验证过的后端"如何写、如何证的唯一教材。
> 本文件是对照 Core 后端的阅读地图。

## 获取源码

网络恢复后执行 `bash ~/get-compcert.sh`（自动尝试 GitHub / INRIA GitLab / 代理）。
或者手动下载 `https://github.com/AbsInt/CompCert/archive/refs/tags/v3.17.tar.gz`。

许可证：GPL v2（研究使用无问题）。

## 目录地图（v3.17 解压后，2026-08-11 已下载到 ~/compcert/）

```
compcert/
├── backend/          ← 后端核心（Coq 源码 + 证明并排）
│   ├── RTL.v         ← 3 地址中间表示（CFG，接近 Core 的 .cir HDFG）
│   ├── Allocation.v  ← 寄存器分配（图着色）
│   ├── Allocproof.v  ← 分配正确性证明（最著名的证明之一）
│   ├── Linearize.v   ← CFG → 线性指令序列
│   ├── Linearizeproof.v ← 线性化正确性证明
│   └── Mach.v        ← 机器抽象层
└── x86/              ← x86 目标（3.17 已合并 x86_32/64）
    ├── Asm.v         ← 每条指令的精确语义模型
    ├── Asmgen.v      ← 指令生成（Mach → Asm）
    ├── Asmgenproof.v + Asmgenproof1.v ← 生成正确性证明
    ├── Op.v          ← 操作语义（运算的数学定义）
    ├── Machregs.v    ← 寄存器定义
    └── TargetPrinter.ml ← 汇编文本打印（对应 Core 的 ELF 编码）
```

> 注：3.17 版本中 `backend/Asm.v`、`backend/Asmgen.v` 不存在——Asm/Asmgen 在目标目录 `x86/` 下；`Architecture.v` 也不存在（由 Machregs.v/Conventions1.v/Stacklayout.v 承担）。

## 与 Core 后端的对照表（v3.17 实际路径）

| CompCert 文件 | 内容 | 对照 Core 的 |
|---|---|---|
| `backend/RTL.v` | 3 地址 IR | `src/compiler/dataflow.cr`（HDFG） |
| `backend/Allocation.v` + `Allocproof.v` | 寄存器分配 + 正确性证明 | `src/compiler/opt.cr`（寄存器分配器） |
| `backend/Linearize.v` | 图 → 线性序列 | `src/compiler/ccr_io.cr` 的线性 CFG |
| `x86/Asm.v` | 每条机器指令的语义模型 | `src/arch/linux/ld/instr.cr`（指令编码） |
| `x86/Asmgen.v` + `Asmgenproof.v` | 指令生成 + 生成正确性 | `corearch.cr` 的发射逻辑 |
| `x86/TargetPrinter.ml` | 汇编文本打印 | `src/arch/linux/ld/elf.cr`（ELF 输出） |
| `arm/Asm.v` / `aarch64/Asm.v` / `riscV/Asm.v` | 各目标指令定义 | `bootstrap/corec/backend/arm64_asm.py` |

## 两个最值得先看的点

1. **`backend/Allocproof.v` 的证明结构**——回答"寄存器分配正确性到底意味着什么"：
   分配前程序与分配后程序在**什么等价关系**下行为一致（模拟关系 + 良基归纳）。
   这正是 `opt.cr` 缺的那层论证。

2. **`backend/Asm.v` 的指令语义**——CompCert 正确性的地基：每条指令先有精确语义
   （作为数学对象定义，而不是字符串/字节），才有正确性可言。
   Core 的 `instr.cr` 目前只有编码没有语义——差距就在这里。

## 与 Core 的关键差异

- CompCert 生成汇编文本交外部 `as`/`ld`；Core 自己发射 ELF（`src/arch/linux/ld/`）
  ——ELF 输出是 Core 独有、CompCert 没有对照的部分
- CompCert 不验证前端（Clight 语法解析）；它的验证从语义化的中间语言开始
- CompCert 用 pass 分阶段 + 每阶段一个证明；Core 是单趟管线（架构哲学不同，对照时注意）

## 审查发现与修复记录（2026-08-11）

对照 CompCert 审查 Core 后端 + 指针分析链，发现并修复 6 个连锁 bug（安全关键）：

### 已修复（越界检查绕过链——5 个 bug 连锁，单独每个都不生效）

| # | 位置 | Bug | 修复 |
|---|---|---|---|
| 1 | `ptr_analysis.cr` IR_ADDR_INDEX | `&arr[i]` 运行时索引的 offset 无条件传播为数组 offset（0），provenance 误判"编译期安全"→ 越界裸读 | 索引常量可精确算（idx×8），运行时索引 → offset=-1（迫使运行时检查） |
| 2 | `instr.cr` IR_DEREF s3≠0 | ud2 写 `buf[cp]`（应为 `buf[pos+cp]`，污染函数头）；jae 越界跳 .safe（不崩溃）；jne 多 +2 跳指令中间 | 三处编码修正 |
| 3 | `ptr_analysis.cr` alloc 分支 + `get_alloc_size` | 所有 alloc 的 pts 恒设 bit 0（无 alloc 序号）；`get_alloc_size(bi)` 把位号当 DF 节点序号查节点 0 → 恒 -1 → 运行时检查**从设计上不可达** | 新增 `g_pa_alloc_count`/`g_pa_alloc_nodes` 映射表（alloc_seq → 节点序号），get_alloc_size 查表 + 修正 IR_ALLOC_ARRAY size（s1×8 非 s1×s2） |
| 4 | `ptr_analysis.cr` LOAD/STORE 传播 | STORE 传播混进 LOAD 分支（用 dest d，而 IR_STORE 的 d 恒 -1）→ 永不执行 → `p = &arr[i]` 的 offset 传播链断 | STORE 分支独立（s1 ← s2），移到 `if d >= 0` 块外 |
| 5 | `main.cr` build 流程 | provenance 的诊断只记录不拦截，编译期确定的越界照常生成二进制 | build 流程检查新增诊断数 → 打印 + return 1 |
| 6 | `region_check.cr`（3 处） | `alloc_seq := bi + nstart`（位号+函数起点）——修复 3 后位号是全局 alloc 序号，语义错位 → B11 误报 | 查 `g_pa_alloc_nodes` 映射表 |

验证：常量越界（`&arr[100]`）编译期拦截 ✓；运行时索引越界生成 `and $0xfff` + `cmp` + `jae→ud2` + `test` + `jne→.safe` 检查序列（objdump 确认跳转精确）✓。

### 第二轮审查（栈布局/调用约定，任务 2）新增修复

| # | 位置 | Bug | 修复 |
|---|---|---|---|
| 8 | `elf.cr` emit_alloc_body 全局 bump 路径 jbe | jbe 偏移 +14 漏了 `mov rdi,r9`（3 字节）→ 跳到指令中间 → 死循环（**所有无 arena 的堆分配程序挂起**） | jbe 改为 +17 |
| 11 | `elf.cr` 栈帧大小（dry run + 实际两处） | `size = vc*8` 未按 SysV 16 字节对齐：opt≥1 时需 ≡8 (mod 16)（6 个 push 后 rsp%16=8），vc 偶数时未对齐 → 调用点 rsp 未 16 对齐（FFI/外部调用会崩） | 对齐规则：opt≥1 → %16==8；opt<1 → %16==0 |
| 12 | `ptr_analysis.cr` alloc 分支 + `get_alloc_size` | `IR_ALLOC`（标量变量槽标记，不发射代码）被当作堆分配参与 pts 追踪 → `p = &arr[i]` 的 pts 含多个位（污染）→ s3 取错 alloc（标量 8 而非数组 40）→ 正常程序被误杀 | 只追踪 IR_ALLOC_STRUCT/IR_ALLOC_ARRAY |

验证（干净构建）：正常索引 `v=30` exit 0 ✓；越界索引 exit 132（SIGILL）✓；常量越界编译期拦截 ✓。

### 未修复（预先存在，另行处理）

| # | 现象 | 影响 |
|---|---|---|
| 7 | 字符串拼接 + println 崩溃/挂起（`"AB"+"CD"`） | 自举产物坏代码；check_error 的错误 msg 因此为空 |
| 9 | 数组读取值错位（ptr_arith 的 `*p != 30`——旧工具链产物） | 数组布局/header 问题（新工具链下正常程序已通过，待复核） |
| 10 | region_check B11 对 deref 读出的 int 误报指针逃逸 | 部分合法程序被拦（region_check 的 pts 语义需按类型过滤） |
| 13 | ~~float 类型是壳~~ **已实现（2026-08-11）**：字面量（IEEE 754 位模式，±1ulp）+ 算术（addsd/subsd/mulsd/divsd）+ 比较（comisd+setcc），运行时验证通过——即 apx 后端快路径（binary64）的早期实现（当时类型名为 float，2026-08-16 设计定案迁移为 dex + apx） | 待续：int↔小数转换、XMM 参数传递、小数打印（阶段 4-6 完成） |
| 14 | `.ccr` 序列化 s1 用 32 位（buf_write_i32）——大 int 常量 / 小数（当时 float）位模式 > 2^31 被截断（静默损坏） | 修复：s1 改 64 位（写/读/尺寸同步） |
| 15 | `buf_read_i64` 缺 `h3 < 128` 的 else 分支——高位字节（bit 56-62）贡献丢失（0x4009... → 0x0009...） | 修复：补 else 分支 |
| 16 | `int_str` 对部分值返回空字符串（int_str(7) 恒空、int_str(567) 编译相关不稳定）——打印链 bug（预先存在，大数路径暴露） | 未修——影响小数（当时 float）打印的精度显示（3.14 → "3.4"）；单独处理 |

## 小数运算（binary64）实现记录（阶段 4-6，2026-08-11；当时类型名为 float，2026-08-16 设计定案后语义归入 apx 后端快路径）

| 阶段 | 内容 | 验证 |
|---|---|---|
| 4 | int↔小数转换（当时 float = binary64，即 apx 快路径）：IR_I2F/IR_F2I + cvtsi2sd（F2 0F 2A）/cvttsd2si（F2 48 0F 2C）；ir_gen 小数运算中 int 操作数隐式转换 | `3.14 + 2`（int 2 隐式转）> 5.0 → exit 0 ✓ |
| 5 | XMM 参数传递（SysV：int 用 ir 0-5 → rdi..r9，小数（当时 float）用 fr 0-7 → xmm0-7，独立编号）+ 小数返回（xmm0）+ 栈参数（小数超 8 用 sub+movsd） | `add_f(1.5, 2.5)` = 4.0 > 3.9 → exit 0 ✓ |
| 6 | 小数打印：`float_str_bits`（位模式 → 十进制，长除小数提取 + 去尾零 + 简单舍入）——迁移后为 dex 打印（保留为 apx 路径实现） | 2.0→"2"、0.5→"0.5"、6.5→"6.5"、-1.0→"-1" ✓；3.14→"3.4"（int_str bug 干扰，见发现 16） |

## 寄存器分配对照结论（任务 3，2026-08-11）

对照 CompCert `backend/Allocation.v` + `Allocproof.v`（图着色 + 溢出 + 模拟关系证明）审查 `opt.cr` 的 `alloc_registers`（线性扫描）：

| 对照点 | CompCert | Core | 结论 |
|---|---|---|---|
| 分配算法 | 冲突图着色（干涉图）+ 溢出 | 线性扫描：活跃区间 [first,last]，每变量独占寄存器、**从不重用** | ⚠️ 保守正确但浪费（5 寄存器后全栈） |
| 正确性条件 | 着色无冲突 + 模拟关系证明 | 变量独占寄存器 → 无冲突（隐式满足） | ✅ 正确 |
| 活跃性 | 精确 liveness（控制流敏感） | 线性区间近似（保守） | ✅ 正确（保守） |
| 跨调用存活 | caller/callee-saved 混合 | 只用 callee-saved（rbx,r12-15，prologue push/epilogue pop） | ✅ 正确（简化但有效） |
| 溢出 | 图着色溢出到栈 | 无溢出——超 5 变量全栈 | ⚠️ 性能差距 |

**O2 运行验证**（首次验证，全部通过）：简单运算（42 ✓）、跨函数调用（callee-saved 保护，30 ✓）、循环（45 ✓）、指针 deref（✓）、越界 SIGILL（132 ✓）。

**未发现正确性 bug**——差距在优化能力（寄存器重用/溢出/精确活跃性），非正确性。

## 调用约定对照结论（任务 2 完整版）

| 约定点 | CompCert（SysV） | Core | 结论 |
|---|---|---|---|
| 整数参数寄存器 | DI,SI,DX,CX,R8,R9 | rdi,rsi,rdx,rcx,r8,r9 | ✅ 一致 |
| callee-saved | rbx,rbp,r12-r15 | 同 | ✅ 一致 |
| 栈参数（第 7+ 个） | S Outgoing，调用点 [rsp+0..] | push r10（右到左）+ add rsp 清理 | ✅ 一致 |
| 栈帧 16 字节对齐 | frame_env_aligned 证明 | 修复 11 前未对齐 | ✅ 已修 |
| 返回值 | rax（128 位用 rdx:rax） | rax（无 128 位类型） | ✅ 一致 |
| varargs | 调用点 AL = XMM 参数数 | 不设 AL（无小数参数 → AL 无意义） | ✅ 无小数参数时正确 |
| outgoing 区域 | 固定帧内区域 | push/add 临时区 | ✅ 功能等价 |
| 小数参数（当时 float） | XMM0-7 | 无 SSE 实现（发现 13；阶段 4-5 已补 XMM 传递） | ❌ 当时为类型壳（apx 快路径后已实现） |
