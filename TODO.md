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

### 首次堆扩展与动态字符串修复（2026-08-14）
- **分配器状态保留**：`heap_expand` 在设置 `mmap` 参数前保存并恢复对齐分配跨度、原始请求长度和当前 arena ID，扩容重试不再重叠后续分配或写入 0 长度头
- **整数转字符串修复**：`int_str(7)` / `int_str(567)` 的内容和隐藏长度头稳定正确
- **字符串拼接修复**：`println("AB" + "CD")` 正常输出，不再因首次动态分配的长度头损坏而崩溃
- **float 舍入修复**：六位小数舍入支持连续 9 的进位传播，`1.9999996` / `9.9999996` / `-1.9999996` 正确输出 `2` / `10` / `-2`
- **CIR/DOT 输出堆耗尽修复**：`df_graph_to_dot()` 与 `cir_text_dump()` 改用 growable buffer，消除逐片段拼接造成的二次方临时分配；`corec cir` 不再在固定 1 GiB 堆耗尽后 SIGSEGV
- **CCR v5 格式回归修复**：测试 walker 按实际 28 字节 instruction 记录前进，SG 段布局检查恢复为有效断言
- **arena 回归确认**：`arena_test.cr` 的基本分配、嵌套和 free-list 复用均通过
- **完整自举确认**：`corec build src/compiler` 在 O0/O1 下均成功，三代后端输出逐字节一致

### 指针宽度、外部地址与动态边界修复（2026-08-16）
- **访问宽度传递**：`IR_DEREF` / `IR_STORE_PTR` 保留 pointee 宽度，静态验证改为 `offset + width <= allocation_size`
- **读写统一验证**：越界 store 不再绕过 ProvenanceVerify，静态可确定的越界读写均阻止编译
- **外部地址空间**：整数转指针标记 `asp=1`，safe 代码解引被拒绝，`unsafe` 边界内保留原有能力
- **动态边界根因修复**：ELF 检查从错误的页内偏移改为 `pointer - allocation_base`，合法变量索引不再误触发 `SIGILL`
- **保守多目标语义**：运行时偏移且 points-to 存在多个 allocation 时拒绝编译，不伪造已证明的边界
- **回归与自举**：15 个指针回归覆盖静态/动态读写、类型双关与 unsafe；`corec2` / `corec3` 逐字节一致

## Region 化控制流（2026-08-08 完成）

嵌套 region 已落地（HDFG 结构；规格 docs/superpowers/specs/2026-08-08-region-cfg-design.md——该规格中的"RVSDG 式"为当时路线记录，结构后定名 HDFG）：
- SG_IF + g_df_node_region 显式映射 + sg_pop close 语义修复
- 解释器 region 迭代（回跳经 SG 表）+ lexer float/`..` 修复（`0..4` 的 `..` 被 float 扫描吃掉——for 循环 bug 真根因）
- state edges（副作用链 + 循环终止依赖）+ .ccr v5（SG 段 24B + edge kind + v4 兼容）

### 已知缺口（region 化相关，待修）
- 缓存命中路径 SG 段不完整（已修复，2026-08-18：CIR v13 保存/恢复嵌套 region 与 node→region 映射；`test_nested_regions_cache_persist` 覆盖）
- while 循环无终止依赖（已修复，2026-08-18：while 使用 SG_LOOP、arena reset 与终止 state edge；`test_while_region_and_termination_edge` / `test_while_break_continue_run` 覆盖）
- 终止边源边界与链头推进（已修复，2026-08-08——final review Important #1：sg_pop 终止边源须在 region 内 + 链头推进到 exit 节点，test_termination_edge_source_guard 覆盖）
- 解释器内联 callee 循环不更新局部状态（已修复，2026-08-18：补齐 callee `ALLOC/STORE/LOAD`、arena 与立即 return 语义；`test_inline_callee_while_run` 覆盖）
- callee inline 执行中的循环崩溃（解释器限制，预存）

## 预存 Bug（不阻塞开发，待修复）

### 1. 并发集成：单 M 已端到端验证，多 M 未验证
-  `go f(args)` 端到端已通：`sched_go(@addr(f), arg)` → g_new 存 saved_fn/saved_arg → 静态构建由 ELF 后端内联发射 fiber_init/fiber_switch/goroutine_entry_wrapper（不再依赖 rt.s 链接）→ wrapper 调用 saved_fn(saved_arg) → 结果经 result_ch 回传
-  主线程注册为 G 0，可经 channel 阻塞/唤醒；sched_yield 不再重排 Gwaiting
-  M 线程 worker loop（m_start_workers）未连到调度器完整测试——静态构建尚未内联发射 m_start_workers（rt.s 符号）
-  channel wait queue 链表操作未在多线程并发下验证
- 注意：G 结构 offset 56 同时用作 saved_fn（goroutine.cr）与 temp_val（chan.cr 等待队列 handoff）——单 G 流程可用（wrapper 在 chan 操作前读取 saved_fn），但字段语义重叠，重构时需拆分

### 2. 解释器局限
- **for 循环**: label/branch 与 dataflow 顺序执行不兼容
- **递归/跨函数调用**: inline 执行不支持 IR_CALL
- **泛型函数**: 类型检查通过但解释器返回 255

### 3. 标准库补全
- math.cr / collections.cr 均为 stub
- 字符串操作、JSON 序列化待补（JSON-RPC 序列化已完成；动态字符串索引边界与字节读写已接入，通用字符串 API 仍待补）

## 第四轮 CompCert 对照遗留项（2026-08-17 记）

来源：`docs/compcert-round4-findings.md`（F1-F20 修复后残留）+ 波 1-3 修复审查产出。F1-F20 已全部修复，以下为范围外/需 IR 形态演进的遗留项：

- ~~**M-2**：字符串索引 `s[5]` 静默 OOB（TI_STR 无检查）~~（2026-08-29 已修：常量下标与动态下标均生成边界检查，字符串读写按字节处理）
- ~~**I-3**：模块别名导入断裂（`import fmt : f` / 模块限定调用生成对伪函数 "import" 的调用）~~（2026-08-29 已修：bootstrap 保留导入元数据并按 alias 解析限定调用；`tests/bootstrap/test_modules.py` 覆盖）
- ~~**lexer 字面量解析 2 项**：`2305843009213693952.0` 字面量解析为垃圾值（bi>53 时 pow2i(负数)=1）；>18 位整数部分静默截断~~（2026-08-29 已修：宽整数显式报错，宽小数避免负指数幂；`test_dex_type.py` 覆盖）
- ~~**Minor-2**：SPAWN 结果存储用 e2_st(rax) 非 e2_store_ret——float 返回值 spawn 存垃圾~~（2026-08-29 已修：IR_SPAWN 按返回类型保存 XMM0/rax）
- **F11 运行时界切片长度**：需 IR 形态演进（slice 类型）——已标注设计项（来源：compcert-round4-findings.md F11 / 语义表 BC7）
- **ccr v5 指令记录 i32 截断** ≥2³¹ 的 s3（被 64MB alloc 上限 + null 陷阱兜底）（来源：波 1 修复审查）
- **core_pattern 管道**致陷阱程序 core dump 挂起——CI 建议 `ulimit -c 0`（来源：波 3 测试审查）
- **BC-CONST**：interp TI_STR 字符串表索引近似——未核实，后续轮次（来源：compcert-round4-findings.md §2 注）

## 架构规划

### 指针安全模型
见 `docs/pointer-model.md`。裸指针 + HDFG provenance 推导，编译器自动验证，退路 `unsafe`。
三 pass：PointerAnalysis、RegionCheck、ProvenanceVerify — 全部实现。

### Arena 内存模型
见 `docs/memory-model.md`。已完整实现。堆按 HDFG 子图划分独立 Arena，指针碰撞分配，
游标重置回收。Arena 边界对应 HDFG 子图边界。

### 文档更新
- `docs/memory-model.md` — 设计文档（待同步实现细节）
- `docs/pointer-model.md` — 指针安全完整设计
- `docs/language-syntax.md` — 指针、@ 内建语法已更新
- `docs/at-intrinsics.md` — @ 内建原语完整规格

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

### 7. 类型双关验证（2026-08-16 已修复）
- 类型双关保留，合法判据为 provenance + 字节偏移 + 访问宽度
- cast 通过有类型的 `IR_LOAD` 保留值流和 `asp`，不会断开 points-to 传播
- `IR_DEREF` / `IR_STORE_PTR` 统一执行 `off + width <= alloc_size`
- 整数转指针产生 `asp=1`，解引必须位于 `unsafe`
- 动态偏移使用 points-to 目标的实际 allocation base 生成 ELF 检查；多目标无法唯一定位基址时保守拒绝
- 回归见 `tests/selfhost/test_pointer_safety.py`

### 内存模型方向：能力 + 格（v4 发布，2026-08-27）
- 备忘：`docs/memory-model-capability-lattice.md`（v1 2026-08-16 → v2 2026-08-20 → v3 2026-08-26 → **v4 发布**；上下文包已删并入）
- **v4 定稿**：**规则封闭对象开放**（层规则零签名 = 缓存七条；对象无界；新范式三件事 = 图标注 / CIC 内部定义 / 硬件映射，无枚举）；**无格承诺**（格代数 = 映射参数，判定/定理只在关系层面）；**M1 定论：能力不提升一等公民**（语义还原图上：身份 = 图节点 / 无配方 = 标注 / 授权归治理层；可逆、暂不执行）；**M4 输入：图内不可重算条款**（已并入 memory-model.md 条款 4b）；**寄存器分配 = 缓存语义映射实例**（`docs/regalloc-cache-mapping.md` 正式参考 + `docs/superpowers/specs/2026-08-27-regalloc-cache-mapping-design.md` 设计记录）
- **三层映射正式晋升：图 → 格 → 编码**（2026-08-27 更名：原「二进制」硬编码经典惯例，零硬件惯例；编码 = 物理编码空间）
- 能力形态（v2/v3 保留，重定位治理层）：能力 = ⟨身份符号, 授权集, 域约束, 派生源⟩；结构 = 能力树（编译期兑现，运行期经典路径零新增）；代数 = PCM × 布尔格（经典行组织参数，非层本体承诺）
- **验证主线**：Graph → Lattice 映射通用性 8 项清单（备忘 §十二）——因果 / 非因果 / 模糊 / 非确定 / 并发异步 / 反馈 / 超图灵 / 格层不重引入顺序执行；v4 实证 = 寄存器分配判定以纯格对象写出（无路径结构）
- 待办：
  - 开放问题收敛（授权集完整枚举 / 可复制性规则 / 用户面句柄 / 分数权限 / 能力进规约 / 寄存器分配落地）
  - 记忆模型文档一致性复查（memory-model.md 并入条款 4b 后）
  - 寄存器分配实现规划：共存关系落定（图活性）→ 判定规约 → 贪心放置（opt.cr 升级）→ checker 自检
  - 实现规划（远期）：能力流分析（PointerAnalysis 推广）+ 三 pass 能力化重写——内存模型层面大改

### 格形态 IR 升级（C 路线，2026-08-27 记）
- 设计：`docs/superpowers/specs/2026-08-27-lattice-form-ir-design.md`——`.ccr` 升级为格形态（v6）；三层形态：图 = `.cir` / 格 = `.ccr`（格形态）/ 编码 = ELF
- 命名已定案（2026-08-27）：方案 A——扩展名 `.ccr` 保留，缩写展开 = Core Region Representation；扩展名 / magic / CLI 不动
- 执行人：第二维护者（TODO 横向扩展）；验证闭环：DslsDZC
- 事项：
  - 命名落地（方案 A 已定案：扩展名 / magic / CLI 不动；展开 = Core Region Representation，文档已先行更新，执行阶段复核）
  - 格式 v6 序列化/反序列化（ccr_io.cr）+ v5 → v6 一次性转换工具（数学结构大改：线性程序 → 存在结构，不承诺后向兼容）
  - v6 存在结构段：条目版本 + 存在区间（图活性）+ 共存 + home + 无配方标记（memory-model 条款 4b）
  - ELF 后端适配（src/arch/linux/ld/）
  - CLI / corearch 参数迁移（若走方案 B）
  - 自举管线（build_selfhost_native.py、bootstrap/corec/ir/ccr.py）
  - 测试迁移（tests/selfhost/、tests/bootstrap/）
  - 文档复核（coreir-schema / CLAUDE.md / project-book / compcert-reference——描述已先行更新）
  - 寄存器分配判定接入格形态（存在区间/共存消费 + 贪心放置，docs/regalloc-cache-mapping.md §4）

### 寄存器分配 = 缓存语义映射实例（落地，2026-08-27 记）
- 设计：`docs/regalloc-cache-mapping.md`（正式参考）+ `docs/superpowers/specs/2026-08-27-regalloc-cache-mapping-design.md`（设计记录）——分配 = 格 → 编码的映射实例（条款 7）；驱逐不变量 = order-free 语义保持；判定单层、算法自由（贪心零证明）
- 执行人：第二维护者（TODO 横向扩展）；验证闭环：DslsDZC
- 事项：
  - 共存关系落定：图活性存活区间相交（复用 RegionCheck cur_seq/exit_seq 机制）；条目版本（IR_STORE 切分）的图表示确认
  - 判定规约：一致性四条（共存互斥 / 读点无陈旧 / 驱逐配对 / 调用失效）写成 .corespec（先规格后实现）
  - 贪心放置策略：版本区间 + 共存检查 + 驱逐写回（`opt.cr` alloc_registers 增量升级；解锁 caller-saved = 调用点失效契约落地）
  - 无配方条目规则：边界 + 图内不可重算必须有 home、驱逐必写回（memory-model 条款 4b 落地）
  - checker：编译期一致性自检（debug 全开，release 可选）
  - 格形态接入：存在区间/共存消费（格形态 v6 落地后，见「格形态 IR 升级」节）
  - （远期）证书层：最优性证书（DP 表重放或 ILP 对偶）——验证「最优」而不只是「一致」

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
- 目标：内核路线（project-book 第五阶段）的汇编级能力——MMIO、特权指令、中断。跨平台统一指令集 + 无限虚拟寄存器 + 平台映射表，寄存器分配按 v4 方向（缓存语义映射实例，`docs/regalloc-cache-mapping.md`——无限虚拟寄存器 + 平台映射表正是映射实例形态；现 `alloc_registers` 线性扫描器为升级起点）
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

- **region_check 误报（B11）**：deref 读出的 int 值被当作指针做区域逃逸检查——`v := *p; return v;` 被拦（预先存在，pts 语义需按类型过滤）

### float 支持实现记录（2026-08-11，对照 IEEE 754 / SysV 标准实现）

- 字面量：decimal → binary64 位模式（纯整数算法，≤18 位有效数字，±1ulp）
- 算术：addsd/subsd/mulsd/divsd（F2 0F 5x C1）；比较：comisd + setcc 无符号标志
- 转换：IR_I2F/IR_F2I（cvtsi2sd/cvttsd2si）+ float 运算 int 操作数隐式转换
- 参数/返回：SysV XMM0-7（int/float 独立编号）+ XMM0 返回 + 栈参数（float 超 8）
- 打印：float_str_bits（位模式 → 十进制，长除 + 去尾零 + 跨位进位舍入）
- 验证：O0/O1/O2 运行全部通过；待办：f32 单精度、printf 风格最短表示

### corelsp 服务器加固 TODO（2026-08-16 终审分流，详见 LSP 任务审查记录）

- ~~json.cr：节点索引无边界防御（-1/过期索引）、重复键取首值（规范为末值）、`\b`/`\f`/`\/` 拒绝、递归深度无上限~~（2026-08-28 已修：节点边界、末值语义、标准转义、128 层深度上限、代理对合并、INT64 边界与溢出检查）
- ~~rpc.cr：Content-Length 数字溢出绕过上限（19+ 位 → 负 n → alloc）、"content-length" 子串可被其他头误匹配、裸 `\n\n` 头终止符不识别（规范强制 CRLF，合规）、逐字节读性能（100KB ≈ 10 万次 syscall）~~（2026-08-28 已修：按 CRLF 行解析、字段起始匹配、数值预检与重复字段拒绝；逐字节读取性能仍为后续优化项）
- ~~analysis.cr：类型节点索引 0 边界（文件首语句为命名类型 fn 时 hover 回退 "int"）、self 参数显示 "int"（impl 解析挂起前不可达）、definition 指向 fn 关键字而非函数名、查询忽略请求 uri（多文档场景悬停 A 返回 B）、多字节字符串按字节列宽匹配（非 UTF-16）~~（2026-08-28 已修：函数名令牌定义位置、请求 URI 快照隔离、UTF-16 code unit 坐标；self/impl 语义仍受前端快照限制）
- analysis.cr：completion/documentSymbol 关键字/@ 表以字面量 if 链镜像（新增关键字时漂移风险——已注释指向真源）、semanticTokens 未闭合字符串以 `\` 结尾 span+1、T_INT_I8.. 死条目（lexer 发 T_INT）、T_LET 死 kind
- test_lsp.py：第七组 read 超时已修（select 5s）；`->` 标记扫描已限定帧间（终审顺手修完成）
- 顺手修遗留：报告文档类笔误（lsp-task-7-report 字节数、lsp-task-6-report §1 表未同步 T_WHILE）——scratch 文件，不阻塞

### 数值类型（dex/apx）迁移遗留 TODO（2026-08-16 终审分流）

- **corearch `--link <so>` 静态路径崩溃**（so_parse_text SIGILL/SIGSEGV，ld.cr:400 附近）：阻塞 extern dex 运行时 FFI 实测（M2 的 IR 层修复已合入并有 cir 断言，运行时验证待此修复）；仓库无 .so 产物、--link 路径零测试覆盖；复现记录 + 备好的 C shim 在 /tmp/dex_ffi_shim.c。**执行注意**：shim 用精确位判等，字面量快路径（str_to_f64_bits 截断 ~2ulp）与计算路径（I2F/1e6）有 1-ulp 差（3.14 → 字面量 4614253070214989086 vs canonical 4614253070214989087）——判等须用 lexer 一致常量或容差
- ~~sizes.cr: IR_APPROX 无显式条目~~（2026-08-29 已补显式 0 字节条目，与其他注解指令对齐）
- 泛型+dex 返回类型：pre-existing（实例化调用点按 int 处理返回类型，与 float 时代逐位一致；bootstrap 侧正确）
- str_to_f64_bits ~2ulp 截断（保留站点文档化限制）：binary64 判别子用 1/3（0.1b+0.2b==0.3 仅 −1ulp 组合恰好落位模式，不可作断言）
- ~~INT_LIT 缺 hex/octal/binary 前缀分支（0x1F 等）；`1_000` 下划线产生 T_INT(-1) 静默值 0~~（2026-08-29 已修：bootstrap 与自举 lexer 支持 `0x`/`0o`/`0b` 及下划线，并拒绝非法数字）
- interp 裸 opcode 数字风格（与既有 op == 26 风格一致，非缺陷）；`_f32/_f64` 宽度透传死路径（EBNF/inventory 争议点 7 已标注，apx 位宽标注需新发射路径）
