# 类型系统方向设计备忘：图本体 + 接口统一（2026-08-30 定稿）

> 摘要（十六字）：**图是本体，接口是契约，类型是推导，编码是映射。**

## 一、定案清单

1. **图本体原则**：图（HDFG）是唯一真相层。类型 = 图节点的标注（投影），接口 = 图上签的契约（行为约束），类型检查 = 图的良构性验证 pass（与 PointerAnalysis / RegionCheck / ProvenanceVerify 同级，不建第二套数据结构）。
2. **接口统一**：用户面 + 检查层只有接口一个概念。int / dex / string / bool = **原生接口条目**（规则内建在编译器、公理引用规约层、**用户不可实现**——公理是编译器领地，防伪造证明）。
3. **实现决策**：一张 interface 注册表（动态表，int = 表头原生条目）；检查器删掉所有类型特判、统一查表验证；**发射层原语映射不动**（`+` → addq 是机器知识，归 hw-map 编码层，不做表驱动化大重构）。
4. **类型检查 = 图验证 pass**：标注一致性 + 操作数兼容性按注册表规则判定，与指针三 pass 同一层级。
5. **where 值约束**：实现内联轻量前置条件。三档语义阶梯：编译期常量约束 → 编译错误/通过；符号约束 → VC 义务（验证管线消费）；动态约束 → 运行时检查（防「证明不了也不静默」）。与 .corespec 前置条件映射（一条语法，两层消费：checker + VC）。
6. **泛型 = 编译期接口具体化**：类型参数即「实现了某接口的具体类型」，声明处接口绑定 + 实例化检查，不做运行期字典。
7. **宽度移出语言**：见 TODO `width-out-of-language`（单标签单范式；机器形状归 hw-map）。
8. **明确不做**：
   - 完整接口一等化（存在类型/运行期字典）——推迟到平台桥/hw-map 落地时做受限接口值
   - 「不需要类型系统」（全动态化）——实证危险（见 §5.3）

## 二、设计推理

- **单范式原则**：一个概念树（接口）贯穿原语到用户类型，无第二标签范式、无第二类型世界。
- **语义保鲜**：图保留一切，类型/接口是从图可推导的投影——标注可以自动算出，用户零标注负担。
- **纯数学叙事**：int 无上限、dex 精确 = 公理化接口 + 原生实现——原语语义也可对照验证（CompCert 精神推广到原语层）。
- **与既有定案咬合**：M1（身份 = 图节点）、无配方 = 标注、授权归治理层、8 项 Graph→Lattice 验证清单——内存模型 v4 已是图本体，类型系统站到同一层补一致性。
- **接口 = 信息 + 规则**：节点上存储的标注（铭牌）+ 解释标注的规则（本体：良构性规则住验证 pass、公理住规约层）。

## 三、损失账本（免费午餐债——必须显式还的债）

| 损失 | 说明 | 偿还方式 |
|------|------|---------|
| 构造期决议鸡生蛋 | 图构造需要类型选操作，类型靠图分析 | 临时标注 → 事后验证 → 重发射（现有管线已是此形态，显式化） |
| 枚举穷尽性 | match 覆盖检查是类型层性质 | 集合论类型补偿（§5.2） |
| 变型/子类型规则 | 接口需显式变型规则，否则静默健全性洞 | 语义子类型可判定化（§5.2） |
| 健全性定理 | 不再继承自标准类型系统 | 变为验证管线证明义务（语义保鲜项目反正要证） |
| 类型级结构信息静默丢失 | 忘记重编码的信息会被静默丢掉（dex 教训的翻版风险） | 显式设计「标注 + 公理」防漏清单 |

## 四、演进顺序（每一步是上一步的顺水推舟）

1. **where 值约束**（验证切片语法入口）
2. **泛型 = 编译期接口**（第 1 层，便宜）
3. **验证切片**（资助主线：规约 → VC → 自动证明）
4. **v6 格形态**（IR 根基革命）
5. **类型概念收敛**（远期，不动根基，且需 v6 之后）

约束：两条根基革命（v6 与类型收敛）不得同时进行——交叉区域是 checker/ir_gen 全部。

## 五、学术支撑（前沿对照）

### 5.1 论文地图

| 支柱 | 论文 | 印证/提示 |
|------|------|----------|
| 图本体 IR | [R-HLS（IEEE 2024 / arXiv 2408.08712）](https://ieeexplore.ieee.org/document/11126294)——RVSDG dialect，region + state edges + 内存消歧 | HDFG 设计在硬件综合领域独立平行出现 |
| 接口统一 + 图验证 | [Webs and Flow-Directed Well-Typedness（PLDI 2025）](https://pldi25.sigplan.org/details/pldi-2025-papers/31/Webs-and-Flow-Directed-Well-Typedness-Preserving-Program-Transformations) | 「生产者/消费者必须就接口达成一致 + 统一化类型分析」= 本备忘 §1.2/1.4 的平行印证 |
| 图 IR 形式语义 | [Denotational Semantics of SSA（2024，Lean 机械化）](https://www.emergentmind.com/papers/2411.09347) | 图 IR 获得形式语义基础 = 语义保鲜的学术形态 |
| 精化类型/易用验证 | [Flux（UCSD）](https://comunicaciones.dcc.uchile.cl/events/310-charla-flux-ergonomic-verification-of-rust-programs-with-liquid-types/)（liquid 推断）· [DML index-sensitive（ECOOP 2026）](https://drops.dagstuhl.de/storage/00lipics/lipics-vol372-ecoop2026/LIPIcs.ECOOP.2026/LIPIcs.ECOOP.2026.pdf)（索引敏感嵌套数组 = F11 方向） | where 值约束 + 推断验证路线成熟 |
| 系统级验证 | [Verus（SOSP 2024）](https://dl.acm.org/doi/10.1145/3694715) | 验证管线工程化前沿 |
| 健全性成本 | [Generic Refinement Types（POPL 2025）](https://dl.acm.org/doi/10.1145/3704885) · RefinedRust（Coq 机械化） | 免费午餐债的量化证据 |
| 内存 provenance | [CHERI C 形式化（ASPLOS 2024）](https://www.semanticscholar.org/paper/Formal-Mechanised-Semantics-of-CHERI-C%3A-Undefined-Zaliva-Memarian/606074ae655cbd43468b080e8ae35dde827ff395) · [时态安全（CPP 2025）](https://www.research.ed.ac.uk/en/publications/a-cheri-c-memory-model-for-verified-temporal-safety/) · [ISO TS 6010:2025 provenance-aware memory model](https://www.cl.cam.ac.uk/~pes20/papers/topic.Cerberus.html) | 指针模型与 ISO 标准方向收敛 |
| 整数↔指针 | [双非确定性内存模型（2024，已集成 CompCert）](https://lib.pusan.ac.kr/lawlib/resource/e-article/?db_id=edskci&mod=detail&page_number=1&record_id=edskci.ARTI.10554258) | asp=1（整数转指针标记）的同题前沿解 |

### 5.2 缺口补偿图

| 缺口 | 补偿 | 怎么补 |
|------|------|--------|
| 枚举穷尽性 | **语义子类型/集合论类型**（[Frisch-Castagna-Benzaken, JACM 2008](https://www.lri.fr/~benzaken/papers/semantic_subtyping.pdf)）：类型 = 值的集合，union/intersection/negation，子类型 = 集合包含，**可判定** | 穷尽性 = 集合运算；match 覆盖可判定（CDuce typecase 先例） |
| 变型/子类型 | 同上（子类型可判定）+ [行多态（Rose POPL 2019 泛化；POPL 2026 行多态+type classes+Lean 4 机械化）](https://dl.acm.org/doi/full/10.1145/3776662) | 结构 + 约束 + 机械化健全性的完整形态 |
| 健全性债 | [Gradually Typed Languages Should Be Vigilant!（OOPSLA 2024）](https://dl.acm.org/doi/full/10.1145/3649842) | 「静态系统真的被强制执行」的精确语义判据（vigilance） |
| 无类型系统幻想 | [Typed and Confused（ASE 2024）](https://conf.researchr.org/details/ase-2024/ase-2024-research/149/Typed-and-Confused-Studying-the-Unexpected-Dangers-of-Gradual-Typing)：3 万仓库实证 | 无检查集成 → type confusion 攻击的实证证据 |
| 决议机制 | [POPL 2026 elaboration 健全性](https://dl.acm.org/doi/full/10.1145/3776662)（源 → 目标演算，Lean 机械化） | 约束决议编译有机械化样板 |
| 子类型表达力边界 | [Structural Subtyping as Parametric Polymorphism（OOPSLA 2023）](https://scirate.com/arxiv/cs.PL?date=2023-05-07&range=31#3) | 全子类型不可编码为多态——接口系统子类型需自备机制 |

### 5.3 战略定位

- **PLDI 2025 Webs** = 「接口统一 + 图验证」的独立平行印证——方向是当前编译研究前沿，非空想。
- **语义子类型 = 完整解**：「类型 = 值的集合」与本备忘「类型 = 图上约束信息」**同构**——标注的语义解释有现成数学，且顺带解决穷尽性、子类型、报错质量（非空反例给具体值）。
- **ISO TS 6010**：provenance 已进 C 标准路线——「指针模型与标准方向收敛」是资助材料的硬话。
- **ASE 2024**：对「不需要类型系统」的最直接实证反驳。

## 六、关联

- TODO.md：`width-out-of-language`（宽度移出语言定案）、`dex-precision`、`apx-degrade`
- docs：`memory-model.md`（能力+格 v4）、`pointer-model.md`、`docs/superpowers/specs/2026-08-27-lattice-form-ir-design.md`（格形态 v6）
- 本备忘落点：类型系统增强总纲——后续实现以本备忘 + TODO 挂账为准
