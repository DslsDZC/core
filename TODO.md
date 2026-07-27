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

### 本阶段（2025-07-22 自举链修复 + 后端项目化）
- **前端自举贯通**: corec2 → corec10 全线贯通 ✅
- **import/module 修复**: import opt/rt/main，搜索路径加 runtime/compiler
- **project.cr 重构**: 全局变量代替 ProjectConfig 结构体返回
- **checker 强化**: 未定义函数报 EC_N_FUNC；添加 r64 内建
- **后端项目化**: src/arch/linux/ld/ 独立项目（Core.toml + _import.cr + main.cr）

## 剩余工作

### 1. 解释器局限
- **for 循环**: label/branch 与 dataflow 顺序执行不兼容
- **递归/跨函数调用**: inline 执行不支持 IR_CALL
- **泛型函数**: 类型检查通过但解释器返回 255

### 2. go/flow/yield 并发
- 数据流图不包含 IR_SPAWN/CALL 节点

### 3. 标准库补全
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
