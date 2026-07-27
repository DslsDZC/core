# Core 动态类型

## 语法

变量名后的 `.` 标签标记动态类型：

```core
x.int := 42;          // x 是 int，静态
x.dyn := 42;          // x 是动态类型
x.dyn = "hello";      // 可以，类型运行时才确定
x.int = "hello";      // ❌ 编译错误：int 不能赋值 string
```

## 图上的本质

动态类型在图上没有特殊节点——`dyn` 只是一个标签，告诉编译器：**这个变量的类型信息在运行时才完整，边界自动插转换。**

```
// 用户代码
x.dyn := read_file("config.json");
y.int := x.field.timeout;  // 图知道 x.field.timeout 在 JSON 路径上是 int

// 图上的实际表示
read_file ──→ JSON.parse ──→ access(.field.timeout) ──→ auto_to_int ──→ STORE(y)
                                                           ↑
                                                    编译器看图自动插入的转换
```

## 类型检查

### 赋值

```core
x.dyn := 42;           // ✅ 动态变量可以接受任何类型
x.dyn = "hello";       // ✅ 动态变量可以在运行时改变类型

y.int := x;            // 取决于编译器能否推导
                       // → 图知道 x 一定是 int ✅
                       // → 图知道 x 可能不是 int ❌ 编译错误（需显式 cast）
```

### 运算

```core
a.dyn := 42;
b.dyn := "hello";
c.dyn := a + b;        // 编译器看图知道 a 和 b 的类型
                       // int + string → 自动插 int_to_string
                       // string + int → 自动插 int_to_string

d.int := a + 1;        // 图知道 a 的当前值是 int → 编译期决议，零开销
```

## 动态变量上的方法调用

图追踪动态变量的来源。编译器知道每个来源的类型，从而知道有哪些方法可用。

```core
x.dyn := read_file("config.json");
// 图知道 x 当前是 string
x.len();               // ✅ string 有 .len()

x.dyn = [1, 2, 3];
x.push(4);             // ✅ 图知道 x 现在是 array，有 .push()
x.len();               // ✅ 当前路径 x 是 array，array 也有 .len()

// 多路径：
if cond {
    x.dyn = "hello";
} else {
    x.dyn = 42;
}
x.len();               // 编译器：
                       //   路径 1: x 是 string → 有 .len()
                       //   路径 2: x 是 int → 无 .len()
                       //   → 插运行时检查
```

| 图推导结果 | 行为 |
|-----------|------|
| 所有路径都有这个方法 | 编译期决议，零开销 |
| 部分路径有这个方法 | 插运行时 `hasMethod` 检查 |
| 没有任何路径有这个方法 | 编译错误 |

## 与静态变量的交互

```core
x.static := 42;
y.dyn := x;             // static → dyn：自动包装，零开销

a.dyn := 42;
b.static := a;           // dyn → static：编译器看图决定
                         // 图知道 a 当前是 int → ✅
                         // 图不确定 → ❌ 编译错误
```

## 运行时表示

动态变量在运行时是一个 `.tag` + `.value` 的结构：

```
struct DynValue {
    tag: int,       // 当前类型 ID（int=1, string=2, array=3, ...）
    value: u64,     // 数据（8 字节，超出则堆分配）
}
```

边界转换在编译时由编译器插入：

```core
// 用户代码
x.dyn := 42;
y.int := x;

// 编译器生成的代码
x.tag = TYPE_INT;
x.value = 42;
if x.tag != TYPE_INT { panic("type mismatch"); }
y = x.value as int;
```

## 实现位置

| 组件 | 改动 |
|------|------|
| 词法/语法 | `.dyn` `.int` 标签解析 |
| 类型系统 | 新增 `any` 类型 |
| IR | 新增 `TAG_CHECK` `TAG_CONVERT` 指令 |
| PointerAnalysis | 追踪 `any` 变量的类型来源 |
| 代码生成 | 检查 `TAG_CHECK` → 编译期证明或运行时指令 |
