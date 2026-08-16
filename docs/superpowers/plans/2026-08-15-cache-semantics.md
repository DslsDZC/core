# 缓存语义语义定稿实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将五份文档（memory-model.md 重构为核心、pointer-model.md / z-vision.md / project-book.md 更新、execution-model.md 一致性检查）改写为缓存语义表述，完成全仓库术语一致性扫描——零代码改动。

**Architecture:** 语义本体（缓存：值=配方、条目、驱逐/再生、边界公理、赋值=版本化、地址=映射）是范式无关层；区域/arena/字节权限（CompCert v2）降级为经典映射实例。文档层纠偏——实现（HDFG）早已是缓存语义，落后的是文档。

**Tech Stack:** Markdown、grep（验证）、jj（提交，仓库铁律 #2：全面使用 jj，禁止 git）

## Global Constraints

- **零代码改动**：每个任务提交后 `jj status` 必须只显示 `docs/` 下文件
- **版本控制用 jj**，任何一步都不得出现 `git` 命令（铁律 #2）
- **七条条款与术语对照表逐字采用**规格 `docs/superpowers/specs/2026-08-15-cache-semantics-design.md` 第 2、5 节（本计划已内嵌，不得改写）
- **术语契约**（写作用词强制）：语义本体词 = 条目、配方、驱逐、再生、边界、映射实例、条目标识；经典映射词 = 区域、Arena、字节权限、地址、字节序列、偏移。文档中两者身份不可混淆——字节内存永远表述为"映射实例/经典投影"，不得表述为"语义本体/语义面"
- **文件名不变**：memory-model.md、pointer-model.md 等一律不重命名，避免全仓库链接断裂
- **无编译任务**：铁律 #6（CPU 限制）不适用，全程只做文档编辑与 grep 验证

---

### Task 1: memory-model.md 重构（核心交付物）

**Files:**
- Modify: `docs/memory-model.md`（全文结构重构）

**Interfaces:**
- Produces: 文档新增 §一 的标题锚点（`# 存储语义：缓存（Cache Semantics）与经典映射（图锚定区域）`、`## 一、语义本体：缓存语义`、`## 二、经典映射：图锚定区域`、`## 经典映射的权限面：字节权限层`）——Task 3/4 引用的目标

- [ ] **Step 1: 替换文件头部（标题 + 新增 §一 + 概述重命名）**

将第 1–16 行（标题 `# 内存模型：图锚定区域（Graph-Anchored Regions）` 及 `## 概述` 整节）替换为：

```markdown
# 存储语义：缓存（Cache Semantics）与经典映射（图锚定区域）

## 零、术语对照表

"内存"一词在本文件（及全仓库）有三层含义，阅读时先判定语境：

| 术语 | 含义 | 例子 |
|------|------|------|
| 物理内存 | 硬件 | DRAM、寄存器、量子存储 |
| 语义存储 | 缓存（范式无关本体） | 条目、配方、驱逐、再生 |
| 映射 | 实现 | 字节寻址、区域、Arena |

## 一、语义本体：缓存语义

> **2026-08-15 升级说明**：本文件此前将 CompCert v2 字节模型（块 + 字节偏移 + 每字节权限）描述为语义本体。这是文档层的错误——**实现（HDFG）从来就是缓存语义**：节点 = 配方（值的产生方式），边 = 值流，state edges = 顺序约束，驱逐/再生 = 丢令牌/重跑节点。本次改动只纠偏文档，零代码改动。设计依据：`docs/superpowers/specs/2026-08-15-cache-semantics-design.md`。

Core 的存储语义本体是**缓存**——范式无关的存储抽象。以下七条为定义性条款，将来供验证器（翻译桥/CIC 内核）消费：

1. **值 = 配方**。条目的语义 = (产生它的图节点, 输入边)。不存在独立于配方的"存储事实"。
2. **驱逐不变量**。驱逐图内任意条目（丢弃存储物、保留配方）不改变可观测语义——只影响性能，不影响正确性。形式化目标：⟦G ∖ storage(e)⟧ = ⟦G⟧。这是"缓存语义"的定义性质。
3. **再生等价**。重跑配方节点产生的值与原条目可观测等价。这是条款 2 的机制保证，也是"任何范式都能换映射"的语义依据。
4. **边界公理**。图边界输入（MMIO/FFI/输入/测量）是唯一无配方条目，语义上是符号常量。语法层叫 `unsafe`（边界标注），语义层只叫"边界"。边界之外才需要 state，边界之内全是可重算的。
5. **赋值 = 版本化**。`x = x + 1` 在语义上 = "x₁ 诞生、x₀ 作废、绑定移动"，不是修改内存单元。顺序约束由 state edges 表达。"可变"不是内存单元的属性，是绑定可移动的许可。
6. **地址 = 映射**。`&x` = (条目标识, 偏移)，字节地址只是经典投影，不是语义对象。指针算术合法性由条目标识 + 偏移域验证（现有 provenance 三 pass 保留不动）。
7. **映射实例正确性**。区域/arena/字节权限（CompCert v2）是经典映射实例，其正确性标准 = 保持条款 1–6 的可观测语义。

**推论（范式映射表 = 映射正确性定理表）**：经典行 = 证明缓存语义 ⊇ 字节内存实现（CompCert 式语义保鲜）；量子行 = 将来证明缓存语义 ⊇ 量子存储实现。语义保鲜从"编译正确性定理"升级为"映射正确性定理"。

## 二、经典映射：图锚定区域

本部分及以下全部内容**不再是语义本体**——它们是缓存语义（§一）在经典硬件（字节寻址）上的**映射实例**。

Core 采用**图锚定区域**的统一内存管理方案：区域（Region）锚定在HDFG上——**区域是子图节点的字节域**，不是词法作用域的影子。堆内存划分为与 HDFG 子图绑定的独立区域，每个区域内部使用线性指针碰撞分配（bump allocation），回收直接将整个区域游标重置回起始地址（格式化清空）。

本设计是 2026-07-28 多 Arena 模型（`docs/superpowers/specs/2026-07-28-arena-model-design.md`）的**概念升级**：Arena 保留为分配器面实现，语义面升级为图锚定区域。传统区域内存管理（Tofte-Talpin 区域栈、Cyclone、Verona）全部锚定词法作用域（LIFO 嵌套）；Core 的执行模型是HDFG，区域与图同构。

**不可放弃的两个核心价值**（放弃它们的代价）：

1. **无碎片**——静态已知大小的分配路径保持纯 bump，零碎片
2. **动态模式下工程可控的极低碎片**——动态大小分配路径走分档子区域，浪费上界由 size class 表决定

长期运行服务的内存占用上限由并发区域数量决定，天然无 GC 停顿。
```

- [ ] **Step 2: 修正"设计动机"论文表 CompCert 行**

在 `## 设计动机` 的论文依据表中，将 CompCert v2 行的"对 Core 的意义"列（原句：`每字节权限层 = 语义面（验证器）的范式`）改为：

```markdown
| Leroy et al., *The CompCert Memory Model, Version 2* (2012) | 块 + (块 ID, 字节偏移) 指针；**每字节权限**（Freeable > Writable > Readable > Nonempty > Empty）；块按构造分离；Coq 机器验证 | 每字节权限层 = **经典映射实例的权限面**（验证器在经典机器上消费的权限视图，见 §一 条款 7） |
```

- [ ] **Step 3: 修正"核心概念"推论 C（字节序列表述加映射注记）**

在 `### 图锚定：区域 = 子图节点的字节域` 的推论 C 末尾（原句：`"控制每一个字节"不是新语法，是图上本来就有的信息。`）追加：

```markdown

> （2026-08-15）在缓存语义下，"字节序列 + 宽度 + 边界"是**经典映射的视图**——语义本体是条目标识 + 偏移（见 §一 条款 6）。
```

- [ ] **Step 4: 修正"语义面：字节权限层"节（标题与首句重述身份）**

将节标题 `## 语义面：字节权限层` 改为 `## 经典映射的权限面：字节权限层`，并将节首句（原句：`内存模型 = 图 + 字节权限层（CompCert v2 范式）：`）改为：

```markdown
经典映射 = 图 + 字节权限层（CompCert v2）：权限层**不是语义本体**，是缓存语义（§一）在字节寻址机器上的权限投影，正确性标准 = 保持 §一 条款 1–6 的可观测语义（条款 7）。
```

- [ ] **Step 5: "设计状态"节追加 2026-08-15 条目**

在 `## 设计状态` 节末尾（`2026-08-13` 条目之后）追加：

```markdown

**2026-08-15**：语义本体定稿为缓存语义（§一，七条条款）——实现早已是缓存语义（HDFG 节点=配方、边=值流、state edges），本文档此前将 CompCert v2 字节模型误作语义本体；本次仅文档纠偏，零代码改动。设计依据：`docs/superpowers/specs/2026-08-15-cache-semantics-design.md`。
```

- [ ] **Step 6: 验证结构完整**

运行：

```bash
grep -n "^# \|^## " docs/memory-model.md
```

预期输出（必须全部出现）：

```
# 存储语义：缓存（Cache Semantics）与经典映射（图锚定区域）
## 零、术语对照表
## 一、语义本体：缓存语义
## 二、经典映射：图锚定区域
## 设计动机
## 核心概念
## 机制总图
## 用户面：零管理负担
## 经典映射的权限面：字节权限层
## 所有权与逃逸
## 与HDFG的集成
## 运行时布局
## 与并发模型的协作
## Rust 风格的对比
## 设计状态
## 待解决问题
```

并确认无残留旧身份表述：

```bash
grep -n "内存模型 = 图 + 字节权限层\|语义面（验证器）的范式" docs/memory-model.md
```

预期输出：无匹配（grep 退出码 1，无输出行）。

- [ ] **Step 7: 提交**

```bash
jj commit -m "docs: memory-model 重构——语义本体定稿（缓存语义七条款）+ 经典映射重表述"
```

预期输出：`Working copy ... now at:`（新 change id），且：

```bash
jj status
```

只显示 `docs/memory-model.md` 一个变更文件。

---

### Task 2: pointer-model.md——`&` 的所指更新

**Files:**
- Modify: `docs/pointer-model.md`

**Interfaces:**
- Consumes: §一 术语（条目标识、映射实例、经典投影）——来自 Task 1
- Produces: 新节锚点 `## 地址 = 映射（2026-08-15 语义定稿）`、`## 当前状态` 内的 2026-08-15 条目

- [ ] **Step 1: 在"术语"表之后插入"地址 = 映射"节**

在 `## 术语` 表格结束（原第 31 行 `| 图边界 | ... |`）之后、`## 用户可见的语法` 之前，插入：

```markdown
## 地址 = 映射（2026-08-15 语义定稿）

**语义本体**：`&x` = (条目标识, 偏移)——条目由产生它的图节点定义（值 = 配方），偏移是条目内的位移（数组元素、结构体字段）。

**经典映射**：字节地址。编译器和后端把条目标识投影为经典机器上的基地址；在非经典范式（如量子存储）上投影为别的物理表示。

字节地址从来不是语义对象——它只是"缓存"（`docs/memory-model.md` §一）在经典硬件上的映射实例。本文件三个 pass（PointerAnalysis / RegionCheck / ProvenanceVerify）的判定全部在条目标识 + 偏移域上进行，与物理地址表示无关。
```

- [ ] **Step 2: "类型双关"节的字节序列表述加映射注记**

在 `### 类型双关` 第一段（原句：`图的内存模型是"字节序列 + 宽度 + 边界"——provenance`）改为：

```markdown
图的存储语义是条目标识 + 偏移（`docs/memory-model.md` §一 条款 6）；经典映射下表现为"字节序列 + 宽度 + 边界"——provenance
```

（该段后续内容 `（alloc 归属）、offset（字节偏移）、alloc_size（字节大小）全部与类型无关` 保持不变。）

- [ ] **Step 3: "当前状态"节追加 2026-08-15 条目**

在 `## 当前状态` 节末尾（`**更新（2026-08-13）**` 条目之后）追加：

```markdown

**更新（2026-08-15）**：`&` 所指定稿——条目标识 + 偏移是语义，字节地址是经典投影（见上"地址 = 映射"节）。与三个 pass 无行为冲突（判定域本就是条目标识 + 偏移）。
```

- [ ] **Step 4: 验证**

运行：

```bash
grep -n "地址 = 映射\|条目标识" docs/pointer-model.md
```

预期输出：`地址 = 映射（2026-08-15 语义定稿）` 标题行 + 新节内 2 处 `条目标识` 出现。

- [ ] **Step 5: 提交**

```bash
jj commit -m "docs: pointer-model——& 所指更新（条目标识+偏移是语义，字节地址是经典投影）"
```

---

### Task 3: z-vision.md——范式映射表存储半边标注

**Files:**
- Modify: `docs/z-vision.md`

**Interfaces:**
- Consumes: 存储半边挂点 = 缓存语义（Task 1 产物 `docs/memory-model.md` §一）

- [ ] **Step 1: 更新目标一的状态行**

将 `## 目标一` 节的状态行（原句：`**状态**：语义保鲜已实现（HDFG + region/state edge/provenance）；范式映射表未做（设计上每范式一张表）。`）改为：

```markdown
**状态**：语义保鲜已实现（HDFG + region/state edge/provenance）；范式映射表——**存储半边已定稿**（语义本体 = 缓存语义，字节内存 = 经典映射实例，见 `docs/memory-model.md` §一），执行半边设计态（每范式一张表）。
```

- [ ] **Step 2: 验证**

运行：

```bash
grep -n "存储半边" docs/z-vision.md
```

预期输出：状态行出现 `存储半边已定稿`。

- [ ] **Step 3: 提交**

```bash
jj commit -m "docs: z-vision——范式映射表存储半边标注（缓存语义定稿）"
```

---

### Task 4: project-book.md——缓存语义引用（§4.6 / §3.3 一致性）

**Files:**
- Modify: `docs/project-book.md`

**Interfaces:**
- Consumes: 缓存语义术语（Task 1 产物）

- [ ] **Step 1: §4.6 指针安全追加一句引用**

在 `### 4.6 指针安全` 节末尾（原句：`Core 的指针安全完全建立在HDFG上，不引入 borrow checker、Arena tag、RawRef 等独立概念层。编译器从图中推导每个指针的来源（provenance）和偏移，在解引用点自动验证。详见 `docs/pointer-model.md`。`）末尾追加：

```markdown

存储语义本体为**缓存语义**（值 = 配方、条目可驱逐可再生、图边界为唯一不可再生来源）；字节内存是其在经典硬件上的映射实例——见 `docs/memory-model.md`。
```

- [ ] **Step 2: §3.3 执行模型追加一句引用**

在 `### 3.3 单一执行模型` 节中"图是执行语义的载体，**不是执行方式的决定者**"段落的末尾（原句：`图只约束语义（依赖、迭代、并发结构），不决定物理执行。`）末尾追加：

```markdown
同样，图也是存储语义的载体——值即条目（配方可重算），存储即缓存（范式无关），内存只是经典映射（见 `docs/memory-model.md`）。
```

- [ ] **Step 3: 验证**

运行：

```bash
grep -n "缓存语义\|范式无关" docs/project-book.md
```

预期输出：§4.6 一句、§3.3 一句（共 2 处新增命中，加上原有无关命中可忽略）。

- [ ] **Step 4: 提交**

```bash
jj commit -m "docs: project-book——缓存语义引用（§4.6/§3.3 一致性）"
```

---

### Task 5: execution-model.md 一致性检查（预期无改动）

**Files:**
- Check: `docs/execution-model.md`（规格第 4 项："一致性检查，有冲突才改"）

- [ ] **Step 1: 检查文档是否存在字节内存语义本体表述**

运行：

```bash
grep -n "字节\|地址\|内存模型\|语义面" docs/execution-model.md
```

预期输出：命中的仅为物理约束表述（`内存是否可动态分配`、`内存上限`、`内存配额`——部署配置语境，属"物理内存"层，不冲突）。若出现任何把字节寻址当作语义本体的表述，将其改写为映射语境（如 `存储语义 = 缓存（docs/memory-model.md §一）；"内存是否可动态分配"是物理内存层的部署约束`）并提交：

```bash
jj commit -m "docs: execution-model——缓存语义一致性修正"
```

- [ ] **Step 2: 无冲突则跳过提交，记录验证结果**

预期输出：无冲突 → 本任务无提交，验证结论写入 Task 6 的提交说明。

---

### Task 6: 全仓库术语一致性扫描

**Files:**
- Check: `docs/**/*.md`（全仓库文档）
- Modify: 扫描发现的残留冲突表述所在文件（如有）

**Interfaces:**
- Consumes: Task 1–5 全部产物

- [ ] **Step 1: 扫描残留"字节模型 = 语义本体"表述**

运行：

```bash
grep -rn "内存模型 = 图 + 字节权限层\|语义面（验证器）的范式\|字节序列 + 宽度 + 边界" docs/ --include="*.md" | grep -v "superpowers/specs\|superpowers/plans\|术语对照表\|经典映射"
```

预期输出：无命中（退出码 1）。若有命中，逐处判定语境：属于历史规格（specs/ 下设计记录）→ 保留不改（历史原样惯例）；属于现行文档且为语义本体表述 → 改写为映射语境后列入 Step 3 提交。

- [ ] **Step 2: 扫描新术语落地情况**

运行：

```bash
grep -rln "缓存语义\|条目标识" docs/*.md
```

预期输出（必须全部包含）：

```
docs/memory-model.md
docs/pointer-model.md
docs/project-book.md
docs/z-vision.md
```

- [ ] **Step 3: 链接检查（规格 §8 验收：无断链）**

运行：

```bash
for f in docs/memory-model.md docs/pointer-model.md docs/project-book.md docs/z-vision.md docs/execution-model.md docs/superpowers/specs/2026-08-15-cache-semantics-design.md; do test -f "$f" && echo "OK $f" || echo "MISSING $f"; done
```

预期输出：全部 `OK`，无 `MISSING`。

- [ ] **Step 4: 提交扫描修复（如有）与扫描本身**

若 Step 1 有修复，先提交修复；无论有无修复，最后确认零代码改动：

```bash
jj status
```

预期输出：仅 `docs/` 下文件；随后提交：

```bash
jj commit -m "docs: 全仓库术语一致性扫描（缓存语义定稿收尾，零代码改动）"
```

若没有可提交内容（Step 1 零命中、Step 5 无改动且此前任务已各自提交），则本任务无提交，验证即完成——在最终汇报中说明扫描结果。
