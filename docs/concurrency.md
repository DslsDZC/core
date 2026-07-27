# Core 并发原语

## 设计原则

- **只有一张图。** go/flow/yield/await 都是图上的节点和边，不是额外的运行时概念。
- **有 OS 用 OS 线程，无 OS 抢占式时间片。** 没有 actor、没有 CSP、没有 async/await 关键字。

## 原语

### flow

声明一个可激活的命名子图。

```core
flow counter() -> int {
    i := 0;
    loop {
        yield i;
        i = i + 1;
        if i >= 5 { break; }
    }
}
```

`flow` 在图上创建一个子图模板。每次 `go` 将子图实例化一次。

### go

激活一个 flow 实例，产生一个新的图节点，与调用者并行。

```core
c := go counter();
// 图上：counter 子图被实例化，新节点加入图
// 有 OS：新线程
// 无 OS：新节点加入就绪队列
```

`go` 返回一个指向 flow 实例的句柄。调用者通过 `await` 获取 flow 的输出。

### yield

暂停当前 flow，输出一个值。

```core
flow numbers() {
    yield 1;   // 暂停，输出 1
    yield 2;   // 恢复，暂停，输出 2
    yield 3;   // 恢复，暂停，输出 3
}
```

`yield` 在图上是一个暂停点：当前节点的执行暂停，值沿输出边传递给消费者。消费者通过 `await` 接收。

多个 `yield` 的 flow 类似生成器——每次 `yield` 后可以继续执行到下一个 `yield`。

### await

等待一个 flow 实例的输出。

```core
c := go counter();
v := await c;       // 等待 counter 输出一个值
// v = 0
v = await c;        // 等待 counter 输出下一个值
// v = 1
```

`await` 在图上是一个同步点：当前节点等待目标子图的输出边就绪。

### 组合使用

```core
flow worker(id: int) -> int {
    loop {
        result := compute(id);
        yield result;
    }
}

fn main() {
    w1 := go worker(1);
    w2 := go worker(2);

    v1 := await w1;
    v2 := await w2;
    println(v1 + v2);
}
```

### 与静态类型的边界

```core
flow producer() -> int {
    yield 42;
}

c := go producer();
x : int := await c;    // ✅ 类型匹配
y : string := await c; // 编译错误：int 不能赋给 string
```

```core
flow producer() -> dyn {
    if cond { yield 42; }
    else    { yield "hello"; }
}

c := go producer();
x := await c;           // x 是 dyn，运行时确定
```

## 图上的表示

```
go counter() → 新节点，子图实例化，独立上下文

yield val    → 暂停当前节点，值沿输出边传递
               接收边就绪 → 节点恢复

await c      → 等待目标节点的输出边有值
               边就绪 → 节点继续
```

```
                         ┌──────┐
        go counter() ───→│  ctx │──→ yield 1 ───→ await
                         │  ctx │──→ yield 2 ───→ await
                         │  ctx │──→ yield 3 ───→ await
                         └──────┘
每个 go 创建独立上下文
每个 yield 产生一个输出值
```

## 与其它模型的对应

| Core | OS 线程 | Go goroutine | Python generator |
|------|---------|-------------|-----------------|
| `flow` | 函数 | `func` | `def` |
| `go` | `pthread_create` | `go` | — |
| `yield` | — | 无直接对应 | `yield` |
| `await` | `pthread_join` | `wg.Wait` | — |

## 当前状态

词法和解析器已支持 `flow`、`go`、`yield`、`await` 关键字。图上的子图实例化、节点暂停/恢复尚未完全实现。
