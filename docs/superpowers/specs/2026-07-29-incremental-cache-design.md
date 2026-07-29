# 增量缓存设计

## 概述

Core 编译器的函数级增量缓存。默认开启，编译无感知——每次编译自动检查缓存，命中时跳过 tokenize→parse→check→IR gen，直接从数据流图（`.cir`）快照恢复。

## 核心原则

- **无感缓存**：默认开启，不需要 `--incremental` 标志
- **函数级粒度**：缓存 key 是单个函数，不是整个文件
- **存 `.cir`**：缓存 = 数据流图内存状态二进制快照，不发明新格式
- **自动失效**：函数体原文 hash 匹配即命中，不匹配即重编

## 缓存架构

```
.core/cache/cir/
├── <func_id_1>.cir       # 每个函数一个缓存文件
├── <func_id_2>.cir
└── ...
```

`func_id` = 源文件路径（`/` 替换为 `_`）+ `::` + 函数名

### 缓存文件格式（`.cir` 二进制快照）

复用现有的 `w64`/`r64` 序列化原语（与 `.ccr` 风格一致）：

```
[CIR cache entry]
  magic:         int64  = 0xC1C1C1C1C1C1C1C1
  version:       int64  = 1
  fingerprint:   int64  = hash(函数体原文)
  sig_hash:      int64  = hash(函数签名)
  func_id_len:   int64  = 字符串长度
  func_id:       bytes  = 函数 ID 字符串

  // 函数元数据（用于注入 DFG）
  var_count:     int64
  [vars]:        var_count × 12 bytes (name_ni, id, type)
  node_count:    int64
  [nodes]:       node_count × ESZ_DFNODE (64 bytes)
  edge_count:    int64
  [edges]:       edge_count × ESZ_DFEDGE (24 bytes)
  instr_count:   int64
  [instrs]:      instr_count × ESZ_IRINSTR (48 bytes)
  str_count:     int64
  [str_offsets]: str_count × int64 (字符串偏移表)
  [str_data]:    所有字符串数据连续存储
```

## 指纹计算

```core
fn function_fingerprint(func_node: int) -> int {
    // 从 AST 中提取函数体原文区域
    body_node := ast_data(func_node);  // body AST node
    body_start := ast_pos(body_node);  // 函数体在源文件中的起始位置
    body_end := ast_end(body_node);    // 结束位置
    
    // 对原文做 hash
    return hash_source_segment(g_source, body_start, body_end);
}
```

使用现有 `str_hash` 函数（Fowler-Noll-Vo 或类似），已经存在于 `dyn_arr.cr`。

### 签名指纹

```core
fn sig_fingerprint(func_node: int) -> int {
    // 函数名 + 参数类型 + 返回类型
    name_ni := ast_a(func_node);
    hash := str_hash(istr_get(name_ni));
    
    // 遍历参数
    param := ast_b(func_node);
    param_count := ast_c(func_node);
    pi := 0;
    loop {
        if pi >= param_count { break; }
        param_type := ast_type_val(param);
        hash = hash * 31 + param_type;  // 将类型编码入 hash
        pi = pi + 1;
        param = param + 1;
    }
    
    // 返回类型
    ret_type := ast_type_val(func_node);
    hash = hash * 31 + ret_type;
    
    return hash;
}
```

## 编译管线集成（更新后的 `build` 流程）

```
1. tokenize(g_source)
2. res_imports()                  ← 始终运行（确保 import 最新）
3. parse_all()                    ← 始终运行（构建完整 AST）
4. 
5. for each function fi:
   a. func_node := fi_ast_node(fi)
   b. fp := function_fingerprint(func_node)
   c. sig := sig_fingerprint(func_node)
   d. func_id := fi_file_path(fi) + "::" + fi_name(fi)
   e. cache_path := ".core/cache/cir/" + func_id + ".cir"
   
   f. 尝试加载缓存：
      if file_exists(cache_path):
          cached_fp, cached_sig = read_header(cache_path)
          if cached_fp == fp && cached_sig == sig:
              load_cir_cache(cache_path)   ← 命中！跳过 check+IR gen
              continue
   
   g. 缓存未命中：
      check_func(fi)                ← 类型检查这个函数
      ir_gen_func(fi)               ← IR 生成
      save_cir_cache(cache_path, fi) ← 保存缓存

6. 签名变更传播（处理 sig_hash 不匹配的级联失效）：
   if any function has sig_hash changed:
       for each caller of changed function:
           mark caller's cache as stale
           re-check + re-ir-gen the caller

7. lower_to_ccr()                  ← 整体跑
8. backend (ELF gen etc.)
```

## 缓存目录管理

- 缓存目录: `.core/cache/cir/`（自动创建）
- 缓存清理: `./build/corec clean-cache` 命令删除该目录
- `corec` 自动在启动时尝试创建 `.core/cache/cir/`
- `.gitignore` 建议添加 `.core/`

## 序列化/反序列化

参考现有 `save_ccr`/`load_ccr` 模式（`src/compiler/ccr_io.cr`），新增 `src/compiler/cir_cache.cr`：

### save_cir_cache(path, func_idx)

```core
fn save_cir_cache(path: string, func_idx: int) {
    fd := syscall3(2, path, 577, 420);  // O_WRONLY|O_CREAT|O_TRUNC
    if fd < 0 { return; }
    
    w_cir_cache(fd, func_idx);
    syscall3(3, fd, 0, 0);
}
```

### load_cir_cache(path) -> int

```core
fn load_cir_cache(path: string) -> int {
    buf := read_file(path);
    if str_len(buf) < 32 { return -1; }  // 太短，无效
    
    // 验证 magic + version
    // 反序列化到 g_df_nodes/g_ir_instrs 等
    return 0;  // 成功
}
```

## 实现清单

| # | 文件 | 改动 |
|---|------|------|
| 1 | `src/compiler/cir_cache.cr` | 新建：save_cir_cache, load_cir_cache, 指纹计算 |
| 2 | `src/compiler/main.cr` | build 流程中集成缓存检查 |
| 3 | `src/compiler/ast.cr` | 新增 `func_fingerprint` 辅助函数 |
| 4 | `src/compiler/dyn_arr.cr` | 可能新增 hash 辅助 |

## 不包含

- 跨 session 缓存 GC（清理过期缓存文件）
- 并发编译（多线程写缓存）
- 网络缓存（分布式编译）
