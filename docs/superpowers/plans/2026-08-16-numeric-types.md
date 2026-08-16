# 数值类型实现计划：dex + apx（float 移除，手动迁移）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **执行性质：手动迁移**——每个 float 站点逐点判断语义归宿（dex / dex,apx），**禁止机械替换（sed/全局替换）**。

**Goal:** 实现 dex（精确小数，默认实数语义）+ apx（近似授权标签，后端变换许可），移除 float 类型，全仓库手动迁移。

**Architecture:** dex = 核心类型（定点缩放整数实现，精确运算）；apx = 变量级标签（与 mut/pub 同族）→ IR_APPROX 注解 → 后端兑现（CPU = binary64 快路径——现成浮点指令；他范式忽略 = 精确）。迁移契约 = Task 1 的分类表（人工审）；编译器内部浮点路径保留为 dex,apx（行为不变），用户可见 float 类型迁为 dex（默认精确）。

**Tech Stack:** Core 语言（编译器自身 + stdlib）、ELF 后端（现成 FPU 指令编码 instr.cr）、测试套件（tests/bootstrap + tests/selfhost + tests/suite）。

**Spec:** `docs/superpowers/specs/2026-08-16-numeric-types-design.md`

## Global Constraints

- **禁止 git**，全部用 `jj`；提交信息中文
- 长时间编译/构建必须 `nice -n 19` 或 `cpulimit -l 10`（铁律 #6）
- **手动迁移**：每个 float 站点逐点判断，禁止全局替换；分类表（Task 1 产出）是迁移契约，人工审
- 语义归宿规则：编译器内部浮点路径（运算/打印/指令编码）→ `dex, apx`（保留 binary64 行为 = apx 快路径）；用户可见 `float` 类型 → `dex`（默认精确——**这是语义变更**，非改名）；`_f32`/`_f64` 后缀保留（apx 的 CPU 位宽标注）
- 构建测试：`python3 build_selfhost_native.py`（自举编译是回归底线——编译器自身迁移后必须能自举）
- 现有 API 零变化（print/println/read_file 等）——float 移除是设计定的唯一例外

---

### Task 1: 迁移盘点——分类表（迁移契约）

**Files:**
- Create: `docs/numeric-migration-inventory.md`（分类表——Task 2-7 的契约）

**Interfaces:**
- Produces: 全仓库 float 站点清单，每站点分类：`dex`（精确）/ `dex,apx`（保行为）/ `保留`（历史/注释）/ `删除`（移除）

- [ ] **Step 1: 盘点源码站点**

对以下文件逐处 grep `float`（含 TY_FLOAT、float 关键字、浮点指令助记符、float_str_bits、I2F/F2I 等变体），列出**每个站点**的：文件:行号、上下文、角色（类型声明/运算/指令编码/打印/字面量/关键字/注释）：

- `src/compiler/ast.cr`（TY_FLOAT 常量、IR 指令）、`lexer.cr`（float 关键字、浮点字面量扫描）、`parser.cr`（float 类型解析）、`checker.cr`（float 类型规则、I2F/F2I 检查）、`ir_gen.cr`（float 运算生成、字面量）、`monomorph.cr`、`module.cr`、`dump.cr`、`ccr_io.cr`（序列化）
- `src/stdlib/fmt.cr`（float_str_bits）
- `src/arch/linux/ld/elf.cr`、`instr.cr`（addsd/subsd/mulsd/divsd/comisd/cvtsi2sd/cvttsd2si 编码 + XMM 栈帧）
- `src/lsp/analysis.cr`（semanticTokens 相关——5 处，逐处判断）
- `tests/bootstrap/test_pipeline.py`、`tests/selfhost/test_native_strings.py`、`tests/suite/` 相关
- `grammar/core.ebnf`

- [ ] **Step 2: 逐点分类**

按 Global Constraints 的语义归宿规则，给每个站点标分类，并**写一句判定理由**。编译器内部运算/打印/指令 → `dex,apx`；用户可见类型 → `dex`；`_f32/_f64` → 保留；注释/历史 → 保留。

- [ ] **Step 3: 写分类表文档**

`docs/numeric-migration-inventory.md`：表格（站点 / 分类 / 理由）+ 迁移后目标形态描述。**自检**：无遗漏站点（grep float 再扫一遍对照）；每个分类有理由。

- [ ] **Step 4: 提交**

```bash
cd /home/DslsDZC/core && jj commit -m "docs: 数值类型迁移盘点——float 站点分类表（迁移契约）" docs/numeric-migration-inventory.md
```

---

### Task 2: apx 标签机制（新功能）

**Files:**
- Modify: `src/compiler/lexer.cr`（apx 关键字）、`src/compiler/parser.cr`（变量标签列表加 apx）、`src/compiler/checker.cr`（标签认可 + 类型信息携带）、`src/compiler/ast.cr`（IR_APPROX 指令常量）、`src/compiler/ir_gen.cr`（apx 变量运算处发射 IR_APPROX）、`src/compiler/dataflow.cr`/`dump.cr`/`ccr_io.cr`（IR_APPROX 注册——执行时按现有个别 IR 指令的注册点清单核对）、`src/arch/linux/ld/instr.cr`/`interp.cr`（IR_APPROX 处理：注解，无运算语义）
- Test: `tests/selfhost/test_apx_tag.py`（新）

**Interfaces:**
- Consumes: 分类表（Task 1）
- Produces: `apx` 变量标签（`x : int, apx` 语法合法、checker 认可、类型信息带 apx 位）；`IR_APPROX` 指令（无操作数，附注语义——后端可忽略，interp 跳过）

- [ ] **Step 1: 写失败测试**

`tests/selfhost/test_apx_tag.py`（Python 驱动自举编译器，参照既有 selfhost 测试结构）：
```python
def test_apx_tag_parses():
    # x : int, apx = 42; 应编译通过（check 子命令 exit 0）
    # x : int, bogus_tag = 42; 应报错（非法标签）
def test_apx_tag_no_semantic_change():
    # apx 标签不改变类型检查/IR 生成语义——带与不带 apx 的同一程序
    # 生成的 .ccr 仅在 apx 标记的运算处多 IR_APPROX 指令
```
（完整测试代码在实现时按既有 selfhost 测试模式写——先红：apx 标签解析失败。）

- [ ] **Step 2: 跑测试确认红**

```bash
cd /home/DslsDZC/core && python3 tests/selfhost/test_apx_tag.py
```
Expected: FAIL（apx 未被 parser 认可）。

- [ ] **Step 3: 实现标签机制**

- lexer.cr：`apx` 加入 lookup_keyword（若标签按关键字解析）或按标识符处理（执行时按 mut/pub 的实际实现路径——mut/pub 如何被 parser 识别，apx 走同一条路）
- parser.cr：变量声明的标签解析列表加 apx（与 mut/pub 同槽位）
- checker.cr：apx 标签认可（不报错）；类型信息或变量记录携带 apx 位（执行时按 mut 位的存储方式加 apx 位）
- ir_gen.cr：apx 变量的运算处发射 `IR_APPROX`（无操作数注解——执行时确认 ir_gen 里变量标签的读取点）
- ast.cr：IR_APPROX 常量（执行时按 IR 指令编号段分配——查现有最大 opcode 号）
- dataflow/dump/ccr_io/interp/ELF：IR_APPROX 注册（dump 打印、ccr 序列化、interp 跳过、ELF 无操作——执行时按现有个别 IR 指令的注册点清单逐一核对，**interp 必须跳过不能崩**）

- [ ] **Step 4: 测试转绿 + 回归**

```bash
cd /home/DslsDZC/core && python3 tests/selfhost/test_apx_tag.py && python3 tests/selfhost/test_compile.py && nice -n 19 python3 build_selfhost_native.py
```
Expected: apx 测试全绿；test_compile 回归绿；自举构建成功（编译器自身尚不用 apx，但 IR 新增指令不影响）。

- [ ] **Step 5: 提交**

```bash
cd /home/DslsDZC/core && jj commit -m "core: apx 标签机制——变量标签 + IR_APPROX 注解（新功能，迁移前置）" src/compiler/ tests/selfhost/test_apx_tag.py
```

---

### Task 3: dex 类型核心（TY_DEX + 字面量）

**Files:**
- Modify: `src/compiler/ast.cr`（TY_FLOAT → TY_DEX 常量；TYP 相关）、`src/compiler/lexer.cr`（`dex` 关键字 + 浮点字面量 → dex 字面量）、`src/compiler/parser.cr`（dex 类型解析）、`src/compiler/checker.cr`（dex 类型规则——执行时按 float 规则改名 + 语义微调）
- Test: `tests/selfhost/test_dex_type.py`（新）

**Interfaces:**
- Consumes: 分类表（Task 1）
- Produces: `dex` 类型（TY_DEX，精确小数语义标记）；`3.14` 字面量解析为 dex 类型；`x : dex` 合法；float 关键字在 lexer/parser 移除（迁移站点按分类表处理——**注意顺序**：先加 dex 再移 float，保持编译器可自举）

- [ ] **Step 1: 写失败测试**

`tests/selfhost/test_dex_type.py`：
```python
def test_dex_type_declares():
    # x : dex = 3.14; 编译通过（check exit 0）
    # fn f() -> dex { return 3.14; } 编译通过
def test_dex_literal_type():
    # fn main() -> int { x := 3.14; return 1; } —— 3.14 推断为 dex（不报错）
```

- [ ] **Step 2: 跑测试确认红**

Expected: FAIL（dex 未知类型/3.14 无 dex 归宿）。

- [ ] **Step 3: 实现 dex 类型**

- ast.cr：TY_FLOAT 改 TY_DEX（或新增 TY_DEX 并逐步迁移引用——执行时按 TY_FLOAT 的引用点数判断：引用少则直接改名，多则分步）
- lexer.cr：`dex` 加入关键字；浮点字面量扫描产出 dex 字面量 token（保留现有字面量解析逻辑——位模式/±1ulp 那套是 apx 快路径的字面量，**先保留**，dex 精确字面量的解析在 Task 4）
- parser.cr：dex 类型名解析（float 的解析路径改为 dex）
- checker.cr：dex 类型规则（float 规则改名；dex 默认精确语义的规则差异在 Task 4 的运算实现中体现，此处类型层面先通）

- [ ] **Step 4: 测试转绿 + 自举回归**

```bash
cd /home/DslsDZC/core && python3 tests/selfhost/test_dex_type.py && python3 tests/selfhost/test_compile.py && nice -n 19 python3 build_selfhost_native.py
```
Expected: dex 测试绿；自举构建成功（编译器自身代码里的 float 站点尚未迁移——**float 关键字还在**，两型并存期）。

- [ ] **Step 5: 提交**

```bash
cd /home/DslsDZC/core && jj commit -m "core: dex 类型——TY_DEX + 字面量 + 类型规则（与 float 并存期）" src/compiler/ tests/selfhost/test_dex_type.py
```

---

### Task 4: dex 精确运算（定点缩放实现——新代码）

**Files:**
- Modify: `src/compiler/ir_gen.cr`（dex 运算生成：无 apx = 定点缩放整数指令序列；有 apx = 现成浮点路径）、`src/compiler/checker.cr`（dex 运算类型规则——精确语义）
- Create: `src/stdlib/dex.cr`（定点缩放运算：表示 = 缩放整数 + 精度；加减乘除/比较/打印——**执行时设计定点方案**：固定缩放（如 10^9 内部精度）起步，溢出/舍入规则文档化）
- Test: `tests/suite/dex_test.cr` + `tests/selfhost/test_dex_arith.py`

**Interfaces:**
- Consumes: dex 类型（Task 3）
- Produces: dex 精确运算（字面量精确解析、加减乘除比较、打印）；无 apx 的 dex 运算编译为定点整数指令序列；`dex.cr` 提供打印/转换辅助（模块函数）

- [ ] **Step 1: 写失败测试**

`tests/suite/dex_test.cr`（Core 程序，编译执行断言）：
```core
// 3.14 + 2.86 == 6.0（精确）
// 0.1 + 0.2 == 0.3（精确——浮点做不到的）
// 1/10 打印为 "0.1"
```
（完整用例在实现时按 tests/suite 既有模式写；期望值 = 精确十进制。）

- [ ] **Step 2: 跑测试确认红**

Expected: FAIL（dex 运算未实现——编译错误或结果错）。

- [ ] **Step 3: 实现定点运算**

- 定点表示：缩放整数（内部精度常量，执行时定——建议 10^9，文档化溢出规则）
- ir_gen：dex 运算（无 apx）→ 定点指令序列（缩放乘法/加法——执行时按现有整数运算指令组合）；dex 运算（有 apx）→ 现有浮点路径（binary64）
- checker：dex 运算类型规则（dex op dex → dex；int 参与时的转换规则——执行时按现 float 的 int 隐式转换模式改）
- dex 打印：`dex.cr` 或 fmt.cr（定点 → 十进制字符串，去尾零）
- 字面量精确解析：`3.14` → 定点整数（十进制 → 缩放整数，非二进制近似）

- [ ] **Step 4: 测试转绿 + 回归**

```bash
cd /home/DslsDZC/core && ./build/corec build tests/suite/dex_test.cr -o /tmp/dex_test --static && /tmp/dex_test && python3 tests/selfhost/test_dex_arith.py && python3 tests/selfhost/test_compile.py
```
Expected: dex 精确语义全绿（0.1+0.2==0.3）；回归绿。

- [ ] **Step 5: 提交**

```bash
cd /home/DslsDZC/core && jj commit -m "core: dex 精确运算——定点缩放实现（无 apx 走定点，有 apx 走 binary64）" src/compiler/ src/stdlib/dex.cr tests/suite/dex_test.cr tests/selfhost/test_dex_arith.py
```

---

### Task 5: 编译器内部迁移（按分类表逐点执行）

**Files:**
- Modify: 分类表中所有 `dex,apx` 站点（`src/stdlib/fmt.cr` float_str_bits、`src/arch/linux/ld/instr.cr` 浮点指令、`src/arch/linux/ld/elf.cr`、`src/compiler/ir_gen.cr` I2F/F2I、`monomorph.cr`、`module.cr`、`dump.cr`、`ccr_io.cr`、`parser.cr`、`lexer.cr`）——按分类表逐个站点改

**Interfaces:**
- Consumes: 分类表（Task 1）+ dex/apx（Task 2-4）
- Produces: 编译器自身全部 float 站点迁移完毕——**编译器代码里不再有 float**（除历史注释）；自举构建成功

- [ ] **Step 1: 按分类表逐站点迁移**

按 `docs/numeric-migration-inventory.md` 的分类逐站点执行（**手动、逐点**——每个站点：读上下文 → 按分类改 → 记录）：
- `dex,apx` 站点：类型/常量名 float→dex，语义保持（binary64 路径不变——它们就是 apx 快路径）
- `保留` 站点：不动
- `删除` 站点：移除
- 每改完一个文件：`./build/corec check`（单文件语法/类型）

- [ ] **Step 2: 编译器自举迁移**

编译器自身的 float 用法（如 float_str_bits 的调用、浮点测试代码）迁移为 dex/apx 写法（编译器代码 = dex,apx——它是 apx 快路径的消费者）。

- [ ] **Step 3: 自举全绿**

```bash
cd /home/DslsDZC/core && python3 tests/selfhost/test_compile.py && nice -n 19 python3 build_selfhost_native.py && ./build/corec check src/compiler/main.cr
```
Expected: 自举构建成功——编译器用 dex/apx 编译自己；corec2 路径照常（若可行）。

- [ ] **Step 4: 提交**

```bash
cd /home/DslsDZC/core && jj commit -m "core: 编译器内部 float→dex,apx 迁移（按分类表逐点，自举通过）" src/compiler/ src/stdlib/ src/arch/
```

---

### Task 6: float 移除 + 测试迁移

**Files:**
- Modify: 分类表中 `删除` 站点（用户可见 float 关键字/类型的残留）；`tests/bootstrap/test_pipeline.py`、`tests/selfhost/test_native_strings.py`、`tests/suite/` 的 float 用例（逐点：测精确 → dex；测 binary64 行为 → dex,apx）
- Test: 全测试套件

**Interfaces:**
- Consumes: 分类表 + Task 2-5
- Produces: 语言里 float 完全移除；测试套件全绿

- [ ] **Step 1: 移除 float 关键字/类型**

lexer/parser/checker 的 float 关键字与 TY_FLOAT 引用全部移除（分类表 `删除` 站点；确认无编译器内部残留——编译器自身已迁 dex,apx）。

- [ ] **Step 2: 测试逐点迁移**

- 测浮点行为的用例 → 按语义：精确断言 → dex；binary64 行为断言（位模式/舍入）→ dex,apx
- 新增 dex 精确断言（0.1+0.2==0.3 类）与 apx 行为断言（binary64 结果）

- [ ] **Step 3: 全套件回归**

```bash
cd /home/DslsDZC/core && python3 tests/bootstrap/test_pipeline.py && python3 tests/selfhost/test_compile.py && python3 tests/selfhost/test_apx_tag.py && python3 tests/selfhost/test_dex_type.py && python3 tests/selfhost/test_dex_arith.py && python3 tests/selfhost/test_lsp.py && nice -n 19 python3 build_selfhost_native.py
```
Expected: 全绿 + 自举成功。

- [ ] **Step 4: 提交**

```bash
cd /home/DslsDZC/core && jj commit -m "core: float 移除——用户可见类型删除 + 测试逐点迁移（dex/apx 双语义）" src/compiler/ tests/
```

---

### Task 7: grammar/EBNF + 收尾验证

**Files:**
- Modify: `grammar/core.ebnf`（float 移除、dex 类型、apx 标签、字面量产生式）

**Interfaces:**
- Consumes: Task 1-6
- Produces: EBNF 与实现一致；全链路验证完成

- [ ] **Step 1: EBNF 同步**

`grammar/core.ebnf`：float 产生式移除 → dex；标签产生式加 apx；字面量产生式（3.14 → dex 字面量）。对照 lexer.cr/parser.cr 实际实现。

- [ ] **Step 2: 全链路终验**

```bash
cd /home/DslsDZC/core && python3 tests/bootstrap/test_pipeline.py && python3 tests/selfhost/test_compile.py && python3 tests/selfhost/test_lsp.py && nice -n 19 python3 build_selfhost_native.py
```

- [ ] **Step 3: 验收清单**

- [ ] 分类表所有站点已迁移（grep float 仅剩历史注释/文档引用）
- [ ] dex 精确语义测试绿（0.1+0.2==0.3、打印 "0.1"）
- [ ] apx 行为测试绿（binary64 结果）
- [ ] 自举构建成功（编译器 = dex,apx 编译自己）
- [ ] LSP/内核测试不回归

- [ ] **Step 4: 提交**

```bash
cd /home/DslsDZC/core && jj commit -m "docs: EBNF 同步 + 数值类型迁移终验" grammar/core.ebnf
```

---

## Self-Review 记录

- **Spec 覆盖**：§二 dex 类型 → Task 3/4；§三 apx 标签 → Task 2；§四 落点（字面量/检查器/IR/后端）→ Task 3/4/5；§五 float 移除迁移 → Task 1/5/6；§七 命名 → Task 3/6；EBNF → Task 7。**YAGNI**（§六）：隐式转换/字面量重载/扩展类型注册不做——计划未含。
- **占位符**：Task 4 的定点实现细节（内部精度常量、溢出规则）标注「执行时定」——这是设计决策点不是占位（计划给出建议值 10^9 与文档化要求）；各任务的「执行时按现有模式」标注 = 现有代码的具体行号需执行者读码确认（与 LSP 计划同惯例）。
- **类型一致性**：TY_FLOAT → TY_DEX 在 Task 3 定义、Task 5/6 消费；apx 标签/IR_APPROX 在 Task 2 定义、Task 5 消费；分类表（Task 1）是 Task 5/6 的逐点契约。
- **手动迁移性质**：计划无 sed/全局替换步骤——每个站点单独列/单独判定；编译器自举（Task 5 Step 3）是迁移正确性的硬验收。
