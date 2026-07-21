# TODO

## 已完成

### P0 全量修复（2026-07-23, PR #16, RhineIris）
- **ELF struct/array/enum 寻址修复**：`emit_instr()` 的 disp32 写入补上当前指令基址 `pos`
- **变量数组索引修复**：修正 `IR_LOAD_INDEX_VAR`/`IR_STORE_INDEX_VAR` 的 REX/ModRM/SIB
- **corec2 自举阻塞解除**：corec2 --help、tokenizer/check 和 corec2→corec3 均正常
- **O1 自举稳定性**：corec→corec2→corec3 在 O0/O1 下均成功
- **原生回归测试**：struct、array、enum tag、O1 aggregate ELF

### 本阶段（2025-07-22 自举链修复 + 后端项目化）
- **前端自举贯通**: corec2 → corec10 全线贯通 ✅
- **import/module 修复**: import opt/rt/main，搜索路径加 runtime/compiler
- **project.cr 重构**: 全局变量代替 ProjectConfig 结构体返回
- **checker 强化**: 未定义函数报 EC_N_FUNC；添加 r64 内建
- **后端项目化**: src/arch/linux/ld/ 独立项目（Core.toml + _import.cr + main.cr）

## 剩余工作

### 1. 后端自举
corearch 作为独立项目已可构建（`build src/arch/linux/ld/`），但生成的 corearch 运行时除零崩溃（SIGFPE）。

堆栈信息：
- `build/corearch`（Python 引导版）处理 .ccr 正常工作
- `build/corec build src/arch/linux/ld/` 构建出新 corearch
- 新 corearch 处理 .ccr 时在 Phase 3 完成前 SIGFPE（`idiv r11`，r11=0）
- 地址：`0x420479`，`then_1298+256`
- r11 从 `[rbp-0x128]` 加载，值为 0

尝试过的修复：
- `e2_w32(buf, cp, fo)` → `e2_w32(buf, pos+cp, fo)`：PR #16 已修，struct 对了但除零仍在
- `res_labels()` 调用：SIGSEGV（`r64(NULL, 24)`），堆损坏追不到源头
- scratch buffer 64→256：无效
- `g_x86_is_global` 预分配：无效
- 页面对齐/BSS 改 modulo：治标不治本

可能的方向：
- `res_labels()` 里 `emit_instr(scratch, 0)` 走完整发射路径，期间某些全局数组未分配或已被损坏
- 尝试不用 `scratch` 而是单独写一个纯 sizing 的循环（不调 `emit_instr`）
- 或等更熟悉 ELF 后端的人排查 `then_1286` 处的 `r64(NULL, 24)` 访问

### 2. 解释器局限
- **for 循环**: label/branch 与 dataflow 顺序执行不兼容
- **递归/跨函数调用**: inline 执行不支持 IR_CALL
- **泛型函数**: 类型检查通过但解释器返回 255

### 3. go/flow/yield 并发
- 数据流图不包含 IR_SPAWN/CALL 节点

### 4. 标准库补全
- 字符串操作、JSON 序列化、集合类

## 架构规划

### 指针安全模型
见 `docs/pointer-model.md`。裸指针 + 数据流图 provenance 推导，编译器自动验证，退路 `unsafe`。

### Arena 内存模型
见 `docs/memory-model.md`。堆按数据流子图划分独立 Arena，指针碰撞分配，游标重置回收。Arena 边界对应数据流子图边界，不是独立的概念——由图的推导给出。

### 文档更新
- `docs/pointer-model.md` — 新写，指针安全完整设计
- `docs/language-syntax.md` — 指针语法已更新
- `docs/memory-model.md` — RawRef 已替换为通用 unsafe 引用
- `docs/dataflow-design.md` — 新增指针安全章节
- `docs/project-book.md` — 新增指针安全章节
