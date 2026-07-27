# Core 指针模型

## 问题

C 风格的裸指针表达能力极强，但完全没有安全保障。Rust 用 borrow checker 和生命周期标注来保障安全，代价是陡峭的学习曲线和表达力的损失。

Core 的目标：**指针和 C 一样自由，安全保障不依赖用户标注。**

## 方案

Core 的编译器内部维护一张完整的数据流图（dataflow graph）。图中每个值的出生节点记录了它的来源（provenance），每个解引用操作记录在 DEREF 节点中。编译器通过分析图上的路径自动验证指针安全，不需要类型系统层面的 borrow 规则。

验证逻辑由三个编译期 pass 完成，全部是图上的稀疏分析：

| Pass | 功能 | 输入 | 输出 |
|------|------|------|------|
| PointerAnalysis | 建 points-to 关系 | 数据流图 | pointer-induced flow 的边 |
| RegionCheck | 子图存活检查 | 数据流图 + 子图边界 | 每个 DEREF 的存活判定 |
| ProvenanceVerify | 越界检查 | 数据流图 + points-to | 每个 DEREF 的偏移判定 |

## 术语

| 术语 | 含义 |
|------|------|
| provenance | 指针的来源——它来自哪个分配操作（ALLOC、ALLOC_STRUCT 等） |
| points-to | 指针可能指向哪些内存位置 |
| direct flow | 值通过赋值直接传递：`a = b` |
| pointer-induced flow | 值通过指针间接传递：`*p = x`，需要 points-to 才能追踪 |
| 子图 | 数据流图上与一个执行上下文（函数、loop、flow）对应的连通子图 |
| DEREF 节点 | 表示一次指针解引用操作的图节点 |
| 图边界 | 编译器无法追踪 provenance 的入口点（外部地址、FFI 返回值等） |

## 用户可见的语法

```core
p := &arr[0];      // 取地址
p = p + n;         // 偏移
x := *p;           // 解引用
p = p - 1;         // 往回偏移
casted := cast<int*>(p);  // 类型转换

unsafe {
    mmio := 0x7fff0000 as *int;  // 外部地址，编译器没有 provenance
    *mmio = 42;
}
```

用户不需要学习 borrow lifetime、RawRef、Arena tag 等概念，不需要 `@ptrFromInt` 之类的内置函数。指针的操作和 C 一样自由。动态类型（`dyn`）作为类型标注时，指针的行为也由图自动管理。

## Pass 1: PointerAnalysis

### 解决的问题

数据流图天然记录了 direct flow。`a = b`、`a = &x`、`a = a + n` 这些操作在图上有直接的边。但 pointer-induced flow（`*p = x`）需要通过 points-to 关系才能追踪：编译器必须先知道 `*p` 可能指向哪些分配块，才能建立 p→target 的边。

### 算法

PointerAnalysis 遍历数据流图，收集每个指针变量的 points-to 信息。分析是流敏感的，按图上的拓扑序进行。

```
输入: 数据流图
处理:
  1. 对每个 ADDR 节点 (p = &x):
     record points-to(p) ∪= {x}

  2. 对每个 COPY 节点 (q = p):
     record points-to(q) ∪= points-to(p)

  3. 对每个 ADD/SUB 节点 (p = p + n):
     points-to(p) 不变（偏移不影响 points-to 集）
     record offset(p) += n

  4. 对每个 STORE 节点 (*p = x):
     对每个 t ∈ points-to(p):
       record store(t, x)
       在图上添加一条从 x 到 t 的边（pointer-induced flow）

  5. 对每个 LOAD 节点 (x = *p):
     对每个 t ∈ points-to(p):
       record x ∈ points-to(t 的成员)
       在图上添加一条从 t 到 x 的边

  6. 对每个 CALL 节点 (f(args)):
     保守处理：假设函数可能修改任何通过参数可达的内存
     （内联后可精确化）

输出: 补充了 pointer-induced flow 边的数据流图
```

### 复杂度

O(N × P)，其中 N 为指针变量数，P 为 points-to 集平均大小。Core 的图是 flat array，可以按子图独立分析，不需要全程序统一求解。

## Pass 2: RegionCheck

### 解决的问题

跨子图引用：子图 A 分配的内存被子图 B 引用。当子图 A 退出后，B 中的指针变成悬垂指针。

### 算法

RegionCheck 为每个子图分配递增的序号（由控制流决定，不是运行时值）。每个 ALLOC 节点标记它所属的子图 ID。每个 DEREF 节点检查目标子图是否存活。

```
输入: 带有子图边界标记的数据流图

处理:
  为每个子图分配范围 [enter_seq, exit_seq]

  对每个 DEREF 节点:
    1. 从 DEREF 沿指针来源倒推 ALLOC 节点
    2. 获取 ALLOC 所在的子图 ID
    3. 获取该子图的 exit_seq
    4. 获取当前指令的序号 cur_seq

    if cur_seq < exit_seq:
      → 目标子图存活，安全
    else:
      → 目标子图已退出，编译错误
```

### 子图确定

| 结构 | 子图范围 |
|------|---------|
| 函数 | [函数入口, 函数返回] |
| loop | [loop 开始, loop 退出] |
| for | [for 开始, for 结束] |
| flow/go | [创建, 回收] |

子图的入口和出口节点在 IR 生成时已存在（df_begin_func / df_end_func 等）。RegionCheck 只是消费这些信息。

## Pass 3: ProvenanceVerify

### 解决的问题

指针算术后的解引用是否越界。`p = &arr[0]; p = p + 100; *p`——编译器需要知道 `arr` 的长度是否大于 100。

### 算法

ProvenanceVerify 从每个 DEREF 节点出发，沿指针来源倒推，找到最初的 ALLOC 节点，比较偏移量。

```
输入: 带有 points-to 信息的完整数据流图

处理:
  对每个 DEREF 节点:
    1. 沿 pointer 的 def 链倒推到 ALLOC 节点
       (经过 COPY、ADD、SUB、LOAD 等中间节点)

    2. 累计偏移量：
       - ADD n:    offset += n
       - SUB n:    offset -= n
       - LOAD:     偏移重置（解引用一个指针，取其指向的成员的偏移）
       - COPY:     偏移不变，沿来源继续

    3. 获取 ALLOC 节点的大小 alloc_size

    if alloc_size 是编译期已知的:
      if 0 <= offset < alloc_size:
        → 安全（编译期证明，零运行时开销）
      else:
        → 编译错误
    else:
      → 插入运行时边界检查（由后端 emit）
```

### 运行时边界检查

当 ALLOC 的大小不是编译期可知时（如运行时决定的数组大小），编译器在 DEREF 之前插入一条条件指令：

```
check offset >= 0 && offset < alloc_size
fail → panic
```

后端将其编译为 `cmp` + `jae` + `ud2` 序列，约 10 字节，无其他运行时开销。

## unsafe 边界

`unsafe` 是编译器无法追踪 provenance 时的唯一退路。发生在图边界：

| 场景 | 原因 |
|------|------|
| 外部硬件地址 | `0x7fff0000 as *int` 没有 ALLOC 节点 |
| FFI 返回值 | 外部函数返回的指针没有 Core 的 provenance |
| inline assembly | 汇编的输出指针没有来源 |
| `unsafe` 类型双关 | 违反类型系统假设，编译器无法推导 |

`unsafe` 块内部的指针操作仍然被三点 pass 追踪。`unsafe` 不是"关掉验证"——是"标注图边界入口"。一旦进入 safe 代码，编译器重新获得追踪权。

```core
unsafe {
    p := 0x7fff0000 as *int;  // 入口，编译器接受用户保证
}
// 之后编译器可以追踪 p 的 provenance
```

## 与其它语言的对比

| | C | Rust | Zig | Core |
|--|---|------|-----|------|
| 指针算术 | 随便 | `*T` 不行 | `[*]T` 可以 | 裸指针随便 |
| 越界检查 | 无 | bounds check | bounds check | 编译期证明或运行时 check |
| 生命周期验证 | 无 | borrow checker | 编译时 | RegionCheck |
| 别名分析 | 无 | 独占&共享引用 | 编译时 | PointerAnalysis |
| 验证时机 | 无 | 类型检查 | 编译时 | 图 pass |
| 用户需标注 | 无 | lifetimes | 有时 | 无 |
| unsafe | 整个语言 | 关键字 | 关键字 | 关键字 |

## 当前状态

Core 编译器已有数据流图（`src/compiler/dataflow.cr`）和线性扫描寄存器分配器（`src/compiler/opt.cr`）。三个 pass 均未实现。图的子节点结构已包含 opcode、dest、src1、src2、src3 字段，可以承载 pointer analysis 需要的元数据（points-to 集、偏移量等）。

## 参考

- **SVF** (SVF-tools): LLVM 上的值流图框架，自动检测 use-after-free、double-free、buffer overflow。Core 的数据流图是更统一的形式——同一张图同时做 regalloc、调度、验证。
- **Fridtjof Siebert** (2006): 全程序 context-sensitive flow-sensitive 指针分析，静态检测区域内存中的悬垂指针。RegionCheck 的直接参考。
- **Prov-GC** (Banerjee 2020): 动态 pointer provenance 追踪，实现 C 的声浪 GC。ProvenanceVerify 的 provenance 追踪概念来源。
