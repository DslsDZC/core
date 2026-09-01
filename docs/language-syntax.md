# Core 语言语法

本文档描述 Core 语言**本体**的语法：词法、类型标注、声明、表达式、控制流、接口与泛型、规约、并发。语法形式以 `grammar/core.ebnf` 与 `src/compiler/` 源码为准（冲突时以源码为准）；语义以格形态为标准框架解释。

---

## 一、设计要点

Core 的语义保鲜（semantic preservation）由三层映射承载：

| 层 | 形态 | 格式 | 职责 |
|----|------|------|------|
| 图 | 结构表达（关系空间） | `.cir` | 程序的结构：节点、边、region |
| 格 | 存在表达（状态空间） | `.ccr` | 存在：状态、条目、共存、驱逐 |
| 编码 | 机器形状 | ELF | 目标实现细节，由 hw-map 领域决定 |

编译把图降为格的线性投影（`lower_to_ccr()`），格的线性投影承载全部类型与语义信息，形式验证直接消费——这就是语义保鲜：正确性陈述对全部可能执行成立，不按控制流路径陈述。详见 `docs/memory-model-capability-lattice.md`（三层映射 v4 §四）与 `docs/superpowers/specs/2026-08-27-lattice-form-ir-design.md`（格形态 IR）。

语言层面的设计要点：

- **无独立类型系统**：类型 = 图上的标注，接口 = 图上的契约，类型检查 = 图的良构性验证（与指针三 pass 同级）。本文档只描写类型标注的**语法**。
- **无 `let` 关键字**：变量用 `:=` 或 `: Type =` 声明。
- **无生命周期标注**：引用有效性由编译器全权推断。
- **默认借用**：传参、赋值默认借用，显式 `move` 转移所有权。
- **编译时执行自动推导**：格/图看到全常量输入即自动编译期执行，`@comptime` 兜底（"算不了就报错"）。
- **指针自由 + 自动验证**：裸地址与 C 同级自由，编译器通过格/图自动验证安全。
- **并发 = 流的构造**：`go` / `await` / `flow` / `yield` 构成数据流网络。

---

## 二、词法

### 2.1 注释

```core
// 单行注释
/* 多行注释 */
```

多行注释可以嵌套（`/* /* */ */`）。

### 2.2 标识符

```
IDENT = LETTER { LETTER | DIGIT | '_' | '\'' }
```

字母（a-z / A-Z / `_`）开头，后续可含字母、数字、下划线与单引号。`_` 本身是通配符（match 分支、占位）。

### 2.3 关键字

共 37 个（以 `src/compiler/lexer.cr lookup_keyword()` 为准）：

```
fn mut return if else loop while for break continue
true false struct enum extern impl match import pub
go await unsafe flow yield interface type mod as
auto fileid move self in None Some unit
```

- `self` 是词法关键字，用于方法接收者（`self` / `&self` / `&mut self`）。
- `Self` 不是词法关键字——它是接口/方法签名中的上下文类型名，按标识符解析，由 checker 按上下文处理。
- `comptime` 不是关键字（`@comptime` 是 @ 内建原语）。
- `requires` / `ensures` / `old` / `result` 不是词法关键字——它们是规约层的语法（见第 10 章与 `grammar/corespec.ebnf`）。

### 2.4 字面量

| 字面量 | 示例 | 说明 |
|--------|------|------|
| 整数 | `42` `0` `-7` | 十进制。无进制前缀、无 `_` 分隔符、无宽度后缀；机器位宽由编码层按目标决定 |
| 小数 | `3.14` `.5` | 精确小数，默认 `dex` 语义（`3.` 不是合法小数） |
| 字符串 | `"Core"` `"a\nb"` | 不可变 UTF-8 |
| 字符 | `'x'` `'\n'` `'\x41'` | Unicode 标量值 |
| 布尔 | `true` `false` | |
| 单元 | `()` | `unit` 类型的唯一值 |
| 可选 | `None` `Some(expr)` | 可选类型构造器（见 4.3） |

转义序列：`\n` `\t` `\r` `\0` `\\` `\"` `\'` `\xHH`（两位十六进制）。

### 2.5 运算符记号

| 记号 | 含义 |
|------|------|
| `:=` | 变量声明（无 `let`） |
| `=` | 赋值（含声明初始化 `: T =`） |
| `->` | 返回类型（仅此用途） |
| `*` | 乘 / 解引用 |
| `&` `&mut` | 取地址（引用） |
| `+ - / %` | 算术 |
| `== != < > <= >=` | 比较 |
| `&& \|\| !` | 逻辑 |
| `.` | 字段访问 / 类型推断占位 |
| `::` | 路径分隔符（文件内路径） |
| `,` | 分隔 |
| `;` | 语句结束（可省略） |
| `?` | 可选标记 / 错误传播 |
| `..` | 范围 |
| `@` | 内建原语前缀 |
| `_` | 通配符 |

---

## 三、模块与导入

模块系统基于**文件标识符**与**项目标识符**，不使用文件物理路径。

### 3.1 文件标识符

默认使用文件名（不含 `.cr`）作为标识符，可在文件头部覆盖：

```core
fileid "my_helper";

fn greet(name: string) -> string = "hi " + name;
```

同一项目内标识符必须唯一，重复报错。

### 3.2 模块声明

```core
mod examples::pi;
```

`mod` 声明路径（`Path = IDENT { '::' IDENT }`），`::` 是文件内路径分隔符。

### 3.3 导入

```core
import math;              // 同一项目的文件（文件标识符）
import math : m;          // 重命名，之后用 m.符号
import @acme math;        // 外部项目 acme 中的 math 文件
import @acme math : m;    // 并重命名
```

`@项目名` 前缀区分本地符号与外部项目符号，不可省略。项目名在项目根的 `Core.toml` 中声明（`name = "acme"`）。

### 3.4 符号访问

```core
import math : m;

result := m.add(3, 5);    // 点号访问导入符号
```

未导入时可用完整路径 `math::add(3, 5)` 直接访问（不推荐）。

### 3.5 目录级批量导入

目录下的 `_import.cr` 自动应用于该目录及子目录（子目录自己的 `_import.cr` 覆盖；继承合并，冲突报错）：

```core
// _import.cr
import @acme math : m;
import @std io;
```

```core
// main.cr——无需重复 import
fn main() {
    result := m.add(3, 5);
    io.println("result = {result}");
}
```

`_import.cr` 本身不生成代码，只起导入声明作用。

<!-- TODO task2: 第 4-7 章 -->
<!-- TODO task3: 第 8-10 章 -->
<!-- TODO task4: 第 11-13 章 -->
