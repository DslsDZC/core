Core 语言语法

---

## 设计哲学

- `dyn` 动态类型：图全量已知所有分支，编译器自动插转换代码，不需要用户写 cast。
- 裸指针，和 C 一样自由，编译器通过HDFG自动验证安全。
- 编译时执行由HDFG自动推导，无需关键字。`@comptime` 提供"算不了就报错"的保证。
- requires / ensures 规约与函数体并列，可选编写，参与静态检查。
- 同步调用与 go/await 并发构造统一映射为HDFG。
- I/O 是流变换（转导器）：程序 = (输入流) → (输出流)，输入输出是同一数学对象（流）的两端——输出即对世界的输入。I/O 程序语义 = 流变换，规约可描述「输入流性质 → 输出流性质」，是一等公民语义而非验证黑洞。read_file/print/println 等现有 API 保持原样，系统调用等物理实现由后端按平台桥抽象隔离。

---

## 一、词法与注释

```core
// 单行注释
/* 多行注释 */
```

## 关键字

（以 `src/compiler/lexer.cr lookup_keyword()` 的实现为准，共 35 个）

fn mut return if else loop while for break continue
true false struct enum extern impl match import pub
go await unsafe flow yield interface type mod as
auto fileid move in None Some unit

注：`comptime` 不是关键字（`@comptime` 是 @ 内建原语）；`requires/ensures/old/result/self/Self`
亦非词法关键字（规约语法见 `docs/spec-design.md` 与 `corespec.ebnf`，`self` 按标识符解析）。

注意：* 用于解引用指针，-> 仅用于返回类型，& 取地址。指针安全由HDFG自动验证，详见 `docs/pointer-model.md`。

`@` 开头的是编译器内建原语，不通过标准库实现：
- `@typeInfo` `@field` `@hasField` `@fields` `@sizeOf` `@alignOf` — 类型内省
- `@comptime` `@inline` `@unroll` `@section` — 编译控制
- `@no_bounds_check` `@fast` — 安全检查（unsafe 范畴）

---

## 二、模块与导入

Core 使用基于**文件标识符**和**项目标识符**的展平模块系统，不依赖文件物理路径。

### 2.1 文件标识符

默认使用文件名（不含 `.cr` 扩展名）作为标识符，可在文件头部手动覆盖：

```core
// file: lib/helper.cr
fileid "my_helper"
fn greet(name: string) { ... }
```

同一项目内标识符必须唯一，重复会编译报错。

### 2.2 项目标识符

在项目根目录的 `Core.toml` 中声明项目名：

```toml
name = "acme"
```

代码中使用 `@项目名` 前缀引用外部项目。

### 2.3 导入语法

```core
// 导入同一项目的文件（使用文件标识符）
import math                // 之后用 math.符号
import math : m            // 重命名为 m，之后用 m.符号

// 导入外部项目的文件
import @acme math          // 项目 acme 中的 math 文件
import @acme math : m      // 并重命名为 m
```

### 2.4 符号访问

使用点号 `.` 访问导入的符号：

```core
import math : m
result := m.add(3, 5)     // 调用 math 文件中的 add 函数
```

未导入时也可通过完整路径直接使用（不推荐）：`math::add(3,5)`（双冒号为文件内路径分隔符）。

### 2.5 目录级批量导入

每个目录下可放置 `_import.cr` 文件，其中的导入会自动应用于该目录及所有子目录的 `.cr` 文件（除非子目录有自己的 `_import.cr` 覆盖）。

示例 `_import.cr`：

```core
import @acme math : m
import @std io
```

同一目录及子目录下的文件可直接使用 `m.add` 和 `io.println`，无需重复 import。

### 2.6 依赖裁剪

编译时以 `main` 为入口，分析所有被引用的符号（含跨项目），从外部 IR 中提取被引用的函数、类型及其依赖，合并为单一可执行文件，丢弃未使用代码。适用于内核/嵌入式场景。

```core
// 示例项目结构
//
// my_project/
// ├── Core.toml            # name = "myapp"
// ├── _import.cr         # 全局导入
// ├── main.cr
// └── lib/
//     ├── _import.cr     # 可选，子目录覆盖
//     └── helper.cr

// _import.cr（顶层）
import @acme math : m
import @std io

// main.cr（无需重复 import）
fn main() {
    result := m.add(3, 5)
    io.println("result = {result}")
}
```

### 2.7 注意事项

- 项目名前的 `@` 前缀不可省略，用于区分本地符号与外部项目符号。
- 文件标识符在当前项目内必须唯一，编译器会检测重复并报错。
- `_import.cr` 本身不生成代码，只起导入声明作用。子目录的 `_import.cr` 会继承父目录的导入（合并，冲突时报错）。
- 依赖裁剪需要 IR 级别的分析器，是 Core 工具链的组成部分。
- 推荐总是先导入再使用，保持代码清晰可读。

---

## 三、变量与基础类型

### 3.1 变量声明

变量使用 `:=` 或 `: Type =` 语法声明（无 `let` 关键字）：

```core
x := 42;           // 不可变，类型推断为 int
y : ., mut = 3.14; // 可变，类型推断为 dex（精确小数）
```

类型标注、标签（mut/pub/apx）可选：

```core
x : int = 42;
name : string = "Core";

count : int, mut = 0;  // 可变 + 显式类型
pub_val : int, pub = 42; // 公开字段
speed : ., apx = 3.14; // apx = 近似授权：授权后端对 dex 运算做语义级变换（CPU 上兑现为 binary64 快路径）

// 批量声明
a, b : int = 1, 2;
```

`auto` 关键字和 `.`（点号）可用于类型推断占位，语义完全相同。既可用于变量声明，也可用作函数返回类型：

```core
// 使用 auto
x : auto = 42;
counter : auto, mut = 0;

// 使用 .（auto 的简写）
y : . = 3.14;
z : ., mut = 20;

// 批量声明
a, b, c : auto, mut = 0;

// 全局公开可变
shared : auto, pub, mut = 42;
```
`.` 更简洁，常用于 `: ., mut` 模式；`auto` 更显式，两者完全等价。
推荐正式代码中使用 `auto` 提高可读性，个人脚本或快速原型可使用 `.` 简写。

`auto` 也可用于函数返回类型，让编译器从函数体推导返回类型：

```core
fn add(a: int, b: int) -> auto {
    return a + b;      // 推导为 int
}

fn pi() -> auto = 3.14159;  // 推导为 dex（精确小数，单行形式）
```

注意：`auto` 是关键字，不可用作变量名或类型名。

### 3.2 基础类型

| 类型 | 说明 |
|------|------|
| int | 整数（精确；i64 实现） |
| dex | 精确小数（默认实数语义，缩放整数/定点实现，精度内置） |
| bool | true / false |
| string | 不可变 UTF-8 字符串 |
| char | Unicode 标量值 |
| dyn | 动态类型——图已知全部分支，边界自动插转换 |

`dyn` 动态类型详见 `docs/dynamic-typing.md`。
| unit | 空值 () |
| never | 发散类型 |

`3.14` 字面量默认产生 dex；近似需显式授权——`apx` 是变量级标签（与 mut/pub 同族）：
`x : ., apx = 3.14` 授权后端把 dex 运算降级为 binary64 FPU 快路径（结果可以变）；
不带 apx 时 dex 恒精确（其他范式忽略 apx 附注即回退到精确缩放整数运算）。
`_f32` / `_f64` 后缀保留，暂作 apx 的 CPU 位宽标注。

显式位宽后缀：

```core
addr := 0x1000_u64;
count := 100_i32;
```

### 3.3 指针

Core 的指针是裸地址，和 C 一样自由，但编译器通过HDFG自动验证安全。

```core
p := &arr[0];      // 取地址，编译器记下 provenance
p = p + n;         // 偏移，随便算
x := *p;           // 解引用，编译器验证 offset ∈ [0, len)
ptr := cast<int*>(addr);  // 显式转换
```

指针安全基于HDFG的 provenance 推导，详见 `docs/pointer-model.md`。

### 3.4 编译时执行

Core 的编译时执行以`HDFG的自动推导为主，`@comptime` 兜底为辅。

```core
// 自动推导——图看见输入全是常量，自动编译期执行
x := fibonacci(40);
cfg := read_file("config.toml");
z := arr[3];            // offset 已知，编译期消错

// 强制——算不了就报错
@comptime {
    x := fibonacci(40);
    cfg := read_file("config.toml");
}
```

详见 `docs/comptime.md`。

### 3.5 @ 内建原语

`@` 开头的标识符是编译器内建的能力入口，不通过标准库实现。分三类：

**元数据查询**——编译期查询类型信息，零运行时开销：

```core
@sizeOf(T)            // 类型大小
@alignOf(T)           // 类型对齐
@fields(T)            // 字段名列表
@field(T, name)       // 字段偏移和类型
@hasField(T, name)    // 字段是否存在
@typeInfo(T)          // 完整类型结构
```

**编译控制**——不改变语义，只改变编译方式：

```core
@inline(fn)           // 提示内联
@unroll(n)            // 展开循环
@section(name)        // 指定代码段
@comptime(expr)       // 强制编译期执行
```

**安全检查**——unsafe 范畴，调用方自己保证：

```core
@no_bounds_check      // 跳过边界检查
```

详见 `docs/at-intrinsics.md`。

### 3.6 可选类型

```core
maybe: int? = Some(5);
nothing: int? = None;
```

---

## 四、复合类型

### 4.1 元组

```core
pair := (42, true);
(n, b) := pair;   // 解构
```

### 4.2 数组与切片

```core
arr := [1, 2, 3];
zeros : [int; 16] = [0; 16];
slice : [int] = arr[0..2];   // 切片，引用原数组
```

### 4.3 结构体

```core
struct Point {
    x: dex,
    y: dex,
}

p := Point { x = 1.0, y = 2.0 };
println(p.x);
```

### 4.4 枚举

```core
enum IpAddr {
    V4(u8, u8, u8, u8),
    V6(u16, u16, u16, u16, u16, u16, u16, u16),
}

enum Option[T] {
    Some(T),
    None,
}
```

---

## 五、函数

### 5.1 定义

```core
fn add(a: int, b: int) -> int {
    return a + b;
}

// 单行形式
fn add(a: int, b: int) -> int = a + b;
```

### 5.2 方法

```core
impl Point {
    fn norm(&self) -> dex {
        (self.x * self.x + self.y * self.y).sqrt()
    }

    fn move_by(&mut self, dx: dex, dy: dex) {
        self.x += dx;
        self.y += dy;
    }
}
```

### 5.3 泛型

```core
fn first[T](list: &[T]) -> T? {
    if list.len() > 0 {
        return Some(list[0]);
    }
    None
}
```

### 5.4 形式规约

```core
fn divide(a: int, b: int) -> int?
    requires b != 0
    ensures result.is_some() implies (a / b) == result.unwrap()
{
    if b == 0 {
        return None;
    }
    return Some(a / b);
}
```

- requires —— 调用方必须满足的前提条件
- ensures —— 保证的后置条件，result 指返回值，old(expr) 指函数入口时表达式的值

规约参与静态检查，不影响运行时性能。

---

## 六、控制流

### 6.1 条件

```core
if x > 0 {
    println("positive");
} else if x < 0 {
    println("negative");
} else {
    println("zero");
}

category := if x > 0 { "positive" } else { "not positive" };
```

### 6.2 循环

```core
for i in 0..10 {
    println(i);
}

for item in items {
    println(item);
}

loop {
    if done { break; }
}

while condition {
    // ...
}
```

### 6.3 模式匹配

```core
match opt {
    Some(x) => println("got {x}"),
    None => println("nothing"),
}
```

匹配必须穷尽所有情况。

当 match 的 scrutinee 是字符串表达式且所有分支都是字符串常量时，编译器自动生成基于哈希的跳转表——计算一次哈希值，与各分支的预计算哈希比较，冲突时再检查相等。无需逐个分支线性比较。

```core
match cmd {
    "start"   => start_server(),
    "stop"    => stop_server(),
    "restart" => restart_server(),
    _         => println("unknown command"),
}
// 编译器优化为跳转表，而非逐个字符串比较
```

---

## 七、所有权与借用

- 默认借用：函数传参、赋值等不移动所有权，编译器自动插入借用。
- 显式移动：使用 move 关键字转移所有权。

```core
a := vec![1, 2, 3];
b := move a;          // a 失效

fn consume(v: Vec<int>) { ... }
consume(move b);         // b 移动进去
```

- 复制类型：整数、精确小数（dex）、布尔、小元组等实现 Copy 接口，赋值时自动复制。

无生命周期标注，编译器全权推断引用有效性。

---

## 八、接口

```core
interface Hash {
    fn hash(&self) -> u64;
}

interface Eq {
    fn eq(&self, other: &Self) -> bool;
}
```

实现：

```core
impl Hash for Point {
    fn hash(&self) -> u64 {
        ...
    }
}
```

标准库为常用类型提供 Hash 实现——哈希的语义是散列函数（数学：同一输入必得同一输出），具体算法是后端实现细节、可替换（平台桥提供 hash_bytes/hash_str 语义接口，现有 str_hash 保持）：

| 类型 | Hash 实现 |
|------|----------|
| `int` | 整数值直接作为哈希 |
| `string` | 基于内容的哈希 |
| `bool` | true/false 映射为固定值 |
| `dex` | 按位表示的哈希 |
| `(T1, T2)` | 组合哈希 |

用户也可为自定义类型手动实现或通过 derive 自动生成。

### 8.1 HashMap / HashSet

标准库提供基于 Hash + Eq 的泛型集合类型：

```core
import std::collections;

map : collections::HashMap[string, int] = .{};
map["key"] = 42;

set : collections::HashSet[int] = .{};
set.insert(7);
```

类型约束由编译器自动推导：`HashMap[K, V]` 要求 `K: Hash + Eq`，`HashSet[T]` 要求 `T: Hash + Eq`。

---

## 九、并发

### 9.1 异步启动

```core
handle := go some_work(arg1, arg2);  // handle: Flow<T>
```

### 9.2 等待结果

```core
result := await handle;   // 阻塞直到完成
```

属性：当需要值时自动等待

```core
val := go fetch(url) + go fetch(other);  // 自动等待
```

### 9.3 长期执行流

```core
flow counter(start: int) -> int {
    n : ., mut = start;
    loop {
        yield n;      // 产出数据
        n += 1;
    }
}

f := go counter(0);
for i in 0..5 {
    v := f.recv();  // 接收一个值
    println(v);
}
```

### 9.4 通道（标准库）

```core
import std::chan;
(tx, rx) := chan::new();
go producer(tx);
go consumer(rx);
```

---

## 十、错误处理

```core
enum Result[T, E] {
    Ok(T),
    Err(E),
}

fn fetch() -> Result<string, IoError> {
    data := read_file("config.txt")?;   // 出错则立刻返回 Err
    Ok(data)
}
```

? 只能用于返回 Result 的函数中。

---

## 十一、不安全区域

```core
unsafe {
    reg := 0xFEED_0000 as RawRef<u64>;
    reg.write(0x42);
}
```

unsafe 块内允许：

- 使用 RawRef<T>
- 调用外部 C 函数
- 编译器固有

RawRef<T> 无法逃逸到安全代码。

---

## 十二、HDFG视图（设计）

编写顺序代码时，后台自动构建HDFG：

- 每个 flow / go 映射为图节点
- yield / recv 定义连续的数据边
- 并行例程形成动态扇出/扇入结构
- 集成 select 可以表达汇合点

整张图可被静态分析和形式化验证。

---

## 十三、示例：并行计算 π

```core
mod examples::pi;

fn leibniz_partial(start: int, n: int) -> dex {
    sum : ., mut = 0.0;
    sign : ., mut = if start % 4 == 1 { 1.0 } else { -1.0 };
    for i in 0..n {
        sum += sign / ((start + 2 * i) as dex);
        sign = -sign;
    }
    return sum;
}

flow worker(id: int, base: int, chunk: int) -> dex {
    offset : ., mut = base;
    loop {
        partial := leibniz_partial(offset, chunk);
        yield partial;
        offset += chunk * num_workers();
    }
}

flow orchestrator(workers: int, chunk_size: int) {
    flows : ., mut = [];
    for i in 0..workers {
        flows.push(go worker(i, 1 + 2 * i * chunk_size, chunk_size));
    }

    pi : ., mut = 0.0;
    loop {
        for f in &flows {
            pi += 4.0 * f.recv();
        }
        println("π ≈ {pi}");
    }
}

fn main() {
    worker_count := 8;
    chunk := 10_000;
    go orchestrator(worker_count, chunk);
}
```

输出：持续逼近 π 的近似值，如

```
π ≈ 3.1415926...
π ≈ 3.141592653...
...
```

此程序展示了：只用 go、flow、yield、recv，就能构建并行的数据流网络。

---

## 设计要点

1. 无指针操作符（*, ->）和地址运算
2. 类型自动推导，减少显式类型标注
3. 默认借用语义，显式 move 转移所有权
4. 并发构造仅 go 和 await 两个关键字
5. 控制流结构（if、for、match）保持直观
6. 可选规约标注参与静态检查，不影响运行时
7. unsafe 块清晰隔离不安全操作
