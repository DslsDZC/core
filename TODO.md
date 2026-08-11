# TODO

## 已完成

### P0 全量修复（2026-07-23, PR #16, RhineIris）
- **ELF struct/array/enum 寻址修复**：`emit_instr()` 的 disp32 写入补上当前指令基址 `pos`
- **变量数组索引修复**：修正 `IR_LOAD_INDEX_VAR`/`IR_STORE_INDEX_VAR` 的 REX/ModRM/SIB
- **corec2 自举阻塞解除**：corec2 --help、tokenizer/check 和 corec2→corec3 均正常
- **O1 自举稳定性**：corec→corec2→corec3 在 O0/O1 下均成功
- **原生回归测试**：struct、array、enum tag、O1 aggregate ELF

### 后端自举修复（2026-07-27）
- **corearch 自举贯通**：解除 Phase 3 的 `SIGFPE`/`SIGSEGV`，stage1 → stage2 → stage3 可连续发射且二进制逐字节一致
- **64 位编码修复**：后端不再使用会被 CCR i32 截断的 `2147483648`/`4294967296` 字面量，`w32`/`w64` 正确编码有符号值
- **CCR 有符号字段修复**：`buf_read_i32()` 显式符号扩展，避免 `-1` 被当作 `4294967295` 变量下标
- **CCR 大小修复**：变量条目按实际 12 字节计算，并纳入 v3 优化元数据大小，不再截断文件尾
- **优化元数据修复**：独立 64 字节槽位、capacity 和扩容复制，O2 寄存器分配 metadata 可序列化并由自举后端读取
- **后端回归测试**：新增三阶段自举、字节一致、O0/O2 CCR 和原生 ELF 运行验证

## 本阶段已完成（2026-07-28~29）

### Arena 内存模型（完整实现）
- `src/stdlib/arena.cr` — 完整生命周期：init/new/reset，动态元数据，free list，嵌套
- `src/compiler/ir_gen.cr` — 子图绑定：每个函数/loop/for/unsafe 自动 arena lifecycle + 大小预计算
- `src/arch/linux/ld/elf.cr` — ELF 后端双路径 alloc：arena 感知 + 全局 bump 回退
- `src/arch/linux/ld/instr.cr` — IR_ARENA_NEW(32)/IR_ARENA_RESET(33) 编码
- `src/runtime/rt.cr` — g_current_arena/g_heap_ptr/g_heap_end 全局注册
- `src/compiler/dataflow.cr` — df_use_var OOB 修复
- mmap 堆扩展：BSS 打满后自动 mmap 1GB 新区域
- emit_alloc_body 零初始化 + 链式扩容标记满

### @ 内建原语（12 个全部完整）
- `@sizeOf(T)` / `@alignOf(T)` — 编译期常量，ELF 验证 8 / 1 
- `@fields(T)` — 遍历 struct fields，返回逗号分隔名字符串
- `@hasField(T, name)` / `@field(T, name)` — 结构体字段存在性 + 偏移量
- `@typeInfo(T)` — 类型名称字符串
- `@comptime(expr)` — 透传 IR gen
- `@inline(fn)` — IR_INLINE(34)
- `@no_bounds_check` — IR_NO_BOUNDS_CHECK(35)
- `@fast` — IR_FAST(36)
- `@unroll(n)` — IR_UNROLL(37)
- `@section(name)` — IR_SECTION(38)

### 增量缓存（函数级 .cir，默认开启）
- `src/compiler/cir_cache.cr` — save/load 每函数 .cir 快照
- 管线集成：编译自动检查 .core/cache/cir/
- `clean-cache` 子命令
- 无感缓存，不需要 `--incremental` 标志

### @hotpatch 滚动更新
- `IR_HOTPATCH_ROUTE(39)` — 调用点路由指令
- Parser `@hotpatch(ver=N)` + checker 多版本签名校验
- ELF 后端编码 + `g_hp_config`/`g_hp_inflight` 全局变量
- 运行时 `hotpatch.cr` + rt.s SIGHUP 信号处理 + in_flight drain 追踪

### 自举构建与值语义修复（2026-07-30）
- **目录构建修复**：`_import.cr` 依赖可由自举编译器正确加载，具名/无名目录和缺失目录行为均有回归覆盖
- **增量缓存修复**：缓存指纹纳入完整解析源，导入文件变化不再复用过期 `.cir`；快照改为内存组包后单次写入，完整自举不再产生数百万次微小系统调用
- **调用返回值修复**：普通调用不再因局部 `dest` 遮蔽写入变量 0，并将实际返回类型传播到 IR
- **lazy 值传递修复**：ELF 后端和解释器中的 thunk/force 保留已计算值及其类型
- **原生字符串长度修复**：整数局部变量不再误判为指针，`str_len("hello") == 5` 和 `str_len(@fields(Point)) == 3`
- **Python bootstrap 词法修复**：`old` 不再被错误保留，可作为普通标识符
- **自举依赖补全**：bootstrap 构建纳入并发运行时依赖、共享 arena 全局和 fiber 声明

## Region 化控制流（2026-08-08 完成）

RVSDG 式嵌套 region 已落地（规格 docs/superpowers/specs/2026-08-08-region-cfg-design.md）：
- SG_IF + g_df_node_region 显式映射 + sg_pop close 语义修复
- 解释器 region 迭代（回跳经 SG 表）+ lexer float/`..` 修复（`0..4` 的 `..` 被 float 扫描吃掉——for 循环 bug 真根因）
- state edges（副作用链 + 循环终止依赖）+ .ccr v5（SG 段 24B + edge kind + v4 兼容）

### 已知缺口（region 化相关，待修）
- 缓存命中路径 SG 段不完整（load_cir_cache 不恢复嵌套 region——仅函数级 region）
- while 循环无终止依赖（while 不生成 region）
- 终止边源边界与链头推进（已修复，2026-08-08——final review Important #1：sg_pop 终止边源须在 region 内 + 链头推进到 exit 节点，test_termination_edge_source_guard 覆盖）
- callee inline 执行中的循环崩溃（解释器限制，预存）
- P5 验收"自举 O0/O1 全绿"未达成——被预存 SIGSEGV 阻塞（TODO.md bug 1：corec build src/compiler 崩溃），归属自举修复分支

## 预存 Bug（不阻塞开发，待修复）

### 1. 完整编译器自举内存峰值
- 目录导入、冷缓存写入和 `corec check src/compiler` 已通过；目录构建逻辑本身不再崩溃
- `corec build src/compiler` 在约 477 个函数完成 IR/缓存后耗尽 `rt.s` 的固定 1 GiB bump heap
- 仅增加 mmap 扩容会让热缓存路径增长到约 7.6 GiB RSS 并触发 WSL OOM；需要按函数回收临时 IR/缓存数据，而不是继续扩大堆

### 2. 并发集成：单 M 已端到端验证，多 M 未验证
-  `go f(args)` 端到端已通：`sched_go(@addr(f), arg)` → g_new 存 saved_fn/saved_arg → 静态构建由 ELF 后端内联发射 fiber_init/fiber_switch/goroutine_entry_wrapper（不再依赖 rt.s 链接）→ wrapper 调用 saved_fn(saved_arg) → 结果经 result_ch 回传
-  主线程注册为 G 0，可经 channel 阻塞/唤醒；sched_yield 不再重排 Gwaiting
-  M 线程 worker loop（m_start_workers）未连到调度器完整测试——静态构建尚未内联发射 m_start_workers（rt.s 符号）
-  channel wait queue 链表操作未在多线程并发下验证
- 注意：G 结构 offset 56 同时用作 saved_fn（goroutine.cr）与 temp_val（chan.cr 等待队列 handoff）——单 G 流程可用（wrapper 在 chan 操作前读取 saved_fn），但字段语义重叠，重构时需拆分

### 3. 解释器局限
- **for 循环**: label/branch 与 dataflow 顺序执行不兼容
- **递归/跨函数调用**: inline 执行不支持 IR_CALL
- **泛型函数**: 类型检查通过但解释器返回 255

### 4. 标准库补全
- math.cr / collections.cr 均为 stub
- 字符串操作、JSON 序列化待补

## 架构规划

### 指针安全模型
见 `docs/pointer-model.md`。裸指针 + 数据流图 provenance 推导，编译器自动验证，退路 `unsafe`。
三 pass：PointerAnalysis、RegionCheck、ProvenanceVerify — 全部实现。

### Arena 内存模型
见 `docs/memory-model.md`。已完整实现。堆按数据流子图划分独立 Arena，指针碰撞分配，
游标重置回收。Arena 边界对应数据流子图边界。

### 文档更新
- `docs/memory-model.md` — 设计文档（待同步实现细节）
- `docs/pointer-model.md` — 指针安全完整设计
- `docs/language-syntax.md` — 指针、@ 内建语法已更新
- `docs/at-intrinsics.md` — @ 内建原语完整规格

### 5. arena bump 分配运行时死循环（2026-08-09 发现）
- 症状：启用 arena（`arena_init` + `arena_new` 后调用 `alloc`）的程序运行时挂起（无输出、CPU 占用）
- 已排除：ELF 后端 arena 相关编码全部 objdump 验证正确（`mov [r8],r10d` 的 44 89 00 错误已修复回 45 89 10）
- 定位方向：`emit_alloc_body` 生成的运行时逻辑（g_current_arena 检查 / bump 推进 / .Lretry 循环 / OOM 链式扩展）
- 复现：`arena_init(1<<20, 65536); arena_new(); alloc(64);`（/tmp/t_arena.cr）

### 6. 同步源码修改到伪代码文档（2026-08-09 记）
- 背景：伪代码（docs/pseudocode/）基于源码快照翻译；以下源码变更后对应文档未同步
- 待同步清单：
  - `elf.cr` 编码修复（mov [r8],r10d → 45 89 10、BAD rip 检查白名单 0x48）→ elf-1.md / elf-4.md
  - `parser.cr` local_stmts 动态扩容 + parse_all 防死循环 → parser-1/2/3/4.md
  - `instr.cr` get_arg r10 push/pop 保护 → instr-2/3.md
  - `main.cr` 静态桥接桩发射逻辑 → arch main.md
  - `ptr_analysis.cr` 注释修正 → ptr_analysis.md
  - `lexer.cr` 浮点/`..` 范围修复（main 已有）→ 核对 lexer.md 是否已反映
- 完成后需重跑 `python3 tools/pseudocode_check.py` 并更新相应文档的源行数标注

### 7. 类型双关验证缺口（2026-08-10 记）
- 背景：设计讨论定论——指针模型扩展收敛：**"程序内部地址直接指"（0x 字面量指内部对象）不做**（YAGNI：内部对象用 `&` 取址更优——无漂移/类型全/验证无条件；外部契约地址 unsafe 已够用；0x 字面量仅保留 unsafe 外部入口角色）；**类型双关保留**——图只认字节（pts/offset/alloc_size 全字节级，无类型检查），双关在图层天然合法，验证 = 边界 + 宽度
- 现状核实（源码）：
  - checker EXPR_AS **无类型兼容检查**（checker.cr:2188 仅推断内层 + 返回目标类型）→ `*(float*)&i` 已放行
  - cast 透传（ir_gen.cr:1595 EXPR_AS 返回内层表达式）→ provenance 边不断
  - DEREF 边界检查只查 `off >= alloc_size`（provenance_verify.cr:58-64）→ 越界双关照拦
  - DEREF 节点不携带类型（ir_gen.cr:735 `emit(IR_DEREF, dv, inner_var, 0, 0, 0)`，type_kind=0）→ 访问宽度无从查
  - **asp 无主机制**：checker.cr:404/1451 写入 TYP_PTR 的 asp 标志（unsafe 块内 = 外部地址空间），全仓库无任何消费点——`0x... as *int` 在 safe 代码同样放行，安全语义未落地
- 待修：
  1. DEREF 宽度检查：`off + width <= alloc_size`（width 从 s1 指针变量的 TYP_PTR 指向类型经 type_size（ir_gen.cr:295）取；DEREF 的 type_kind 是占位 0，需从变量类型推导或改 emit 传真实类型）
  2. asp 机制收尾：完成（asp=1 指针的 DEREF 要求 unsafe 包裹）或删除（当前写入无人消费，是隐患）
- 参考：docs/pointer-model.md（unsafe 边界表已删"类型双关"行 + 新增类型双关节 + 2026-08-10 设计定论）

## 待实现特性

### 控制流自动惰性（2026-08-09 记）
- 目标：控制流结构（if / while / for 等）的分支表达式自动惰性求值——未被执行的路径不产生求值开销。判定表见 `docs/lazy.md`：结果只用一个分支 → 延迟；有副作用（IO/FFI/unsafe/volatile）→ 永远 eager；循环体内每次都用 → eager；循环体内条件性用 → 惰性
- 现状（源码核实，2026-08-09）：
  - IR_LAZY_THUNK(46)/IR_LAZY_FORCE(47) 已存在（ast.cr:571）；ir_gen 在纯函数调用后包 THUNK（ir_gen.cr:1106），`force_if_thunk()` 在所有操作数位置发 FORCE
  - **但当前 thunk 不产生实际延迟**：IR_CALL 在 THUNK 之前已急切发射，ELF 后端（instr.cr:1091，注释明言 "Calls are currently emitted eagerly… typed value transfer"）和解释器（interp.cr:194）都按纯值搬运降级——语义上是 no-op，只保证输出不变
  - **use_count 时序问题**：`compute_usage_counts()`（dataflow.cr:325）在全部 ir_gen 之后才运行（dataflow.cr:381），而 THUNK 判定在 ir_gen 当时读 `g_var_use_count`（ir_gen.cr:1108）→ 判定时恒 0/未初始化，`use_count <= 1` 恒真，实际每个纯调用都被包——"单次使用"条件名存实亡
  - 无 `lazy()` 显式惰性内建（旧条目"共存策略"为过时信息；docs/lazy.md 明确"无关键字"）
  - 控制流级惰性（if/while/for 分支表达式）与循环体内条件性惰性均未实现——即本条目
- 方向（2026-08-09 定为编译期指令下沉路线，不做运行时实现）：
  - 原理：惰性 = 指令放置问题（docs/lazy.md:5 "图本来就是惰性的"）。纯函数调用无副作用 → 把 IR_CALL 从分支前下沉到唯一消费点，执行恰好一次且只在被执行的路径上；不需要运行时 thunk/flag/9 字节结构
  - 实现：ir_gen 之后的 CFG 后置 pass（`compute_usage_counts()` 正好提供 sink 所需输入）：纯 + 单次使用 → 把 CALL 移到唯一消费点之前
    - if 分支惰性：下沉进分支块（phi 输入仍合法——值定义在各路径上）
    - 循环体内条件性用：下沉进循环内条件块；参数 loop-invariant 时先 hoist 出循环再下沉（顺带 LICM）
    - 多条路径需要 → 不 sink，放公共支配点（自动升级 eager，用户不感知）
  - 约束：alloc 类下沉须检查 arena 归属——不能把分配下沉到会在使用点之前 reset 的 arena（SG_LOOP 每次迭代 reset）；纯函数陷阱（div0 等）时机会移到执行点，按"惰性不改变语义"接受
  - 现有 IR_LAZY_THUNK/IR_LAZY_FORCE（no-op 值搬运）可退役或保留兼容；**interp / ELF 后端零改动**
  - 循环体内"条件性用"与 if 分支惰性并列但需分开验证
- 参考：`docs/lazy.md`、`docs/superpowers/specs/2026-07-30-lazy-eval-design.md`、`src/compiler/ir_gen.cr`、`src/compiler/dataflow.cr`、`tests/suite/lazy_test.cr`（当前仅验证"包装后输出不变"）

### .crasm 统一汇编抽象层（2026-08-09 记）
- 目标：内核路线（project-book 第五阶段）的汇编级能力——MMIO、特权指令、中断。跨平台统一指令集 + 无限虚拟寄存器 + 平台映射表，寄存器分配复用 `alloc_registers` 线性扫描器
- 现状：设计已批准（2026-08-08 brainstorming 逐节确认），2026-08-09 整理为正式文档 `docs/crasm.md`；**尚未实现**——lexer/parser 无 asm 语法，汇编仅存在于 rt.s 手工汇编与 ELF 后端机器码发射
- 方向（按里程碑顺序）：
  1. `.crasm` 词法/解析（结构化指令 → AST 复用）
  2. 寄存器生命周期 pass + 测试（未初始化读/重复写/生命周期逃逸/宽度一致/分支一致性）
  3. 特权约束表 + 用法验证 + unsafe 隔离
  4. x86-64 映射表（翻译器）+ 字节级测试
  5. .cr extern 接口接线 + 端到端
  6. （后补）ARM64/RISC-V 映射表
- 明确不做（YAGNI）：模拟器/调试器、C 生态兼容、指令级时序验证、特权副作用验证（隔离，人工保证）
- 参考：`docs/crasm.md`（正式文档）、`docs/superpowers/specs/2026-08-08-crasm-design.md`（批准记录）

### 对照 CompCert 审查发现的未修复 bug（2026-08-11 记，详见 docs/compcert-reference.md）

- **int_str 空字符串 bug**：`int_str(7)` 恒返回空、`int_str(567)` 随编译产物不稳定——打印链问题（预先存在，修复 .ccr s1 64 位后被大数路径暴露）。影响：float 打印精度（`float_str_bits(3.14)` 显示 "3.4"）、大 int 常量打印
- **字符串拼接 + println 崩溃**：`println("AB" + "CD")` 程序核心转储（预先存在，concat 相关）。影响：check_error 的拼接错误信息不可读
- **region_check 误报（B11）**：deref 读出的 int 值被当作指针做区域逃逸检查——`v := *p; return v;` 被拦（预先存在，pts 语义需按类型过滤）
- **float 打印精度**：float_str_bits 的舍入为简单实现（第 7 位 ≥5 时第 6 位 +1，无进位传播）——±1ulp 显示误差可接受，但依赖 int_str 修复后重新验证

### float 支持实现记录（2026-08-11，对照 IEEE 754 / SysV 标准实现）

- 字面量：decimal → binary64 位模式（纯整数算法，≤18 位有效数字，±1ulp）
- 算术：addsd/subsd/mulsd/divsd（F2 0F 5x C1）；比较：comisd + setcc 无符号标志
- 转换：IR_I2F/IR_F2I（cvtsi2sd/cvttsd2si）+ float 运算 int 操作数隐式转换
- 参数/返回：SysV XMM0-7（int/float 独立编号）+ XMM0 返回 + 栈参数（float 超 8）
- 打印：float_str_bits（位模式 → 十进制，长除 + 去尾零）
- 验证：O0/O1/O2 运行全部通过；待办：float 打印精度（int_str 修复后）、f32 单精度、printf 风格最短表示
