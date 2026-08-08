# Core 源码伪代码文档

> 将 src/ 下全部 Core 语言源码（56 个 .cr 文件，19,749 行）翻译为无编程语言关键字的
> 汉语伪代码。用途：TDD 测试要点推导 + 远期完全形式化基础。

## 范围
- 已译：src/compiler/（29 文件）、src/stdlib/（18）、src/runtime/（2）、src/arch/linux/ld/（7）
- 排除：rt.s（汇编）、rt.ccr（编译产物）、bootstrap.c / compiler_rt.c（C 代码）、tests/、examples/
- 本目录结构镜像 src/，每源文件一个或多个 .md（≥800 行的源文件拆分为多个部分，命名 <源名>-<序号>.md）

## 约定速查
（完整约定见实现计划 Global Constraints G2，此处为速查）
| 源码 | 伪代码 |
|------|--------|
| if / else | 如果…那么： / 否则： |
| while / for | 循环（当…成立时）： / 对…遍历： |
| return | 返回 |
| fn / struct / enum | 函数 / 结构 / 枚举 |
| 声明 := | 令 名字 = 值 |
| true/false/None | 真 / 假 / 无值（None） |
| and/or/not | 且 / 或 / 非 |
| 比较运算符 | 等于/不等于/小于/小于等于/大于/大于等于 |
| + - * / % 位运算 | 保留符号 |

- 标识符：首次出现写作 中文名（原名），共享标识符必须用《标识符对照表.md》的名字
- 伪代码正文禁止英文关键字、裸英文标识符、花括号与分号符号；禁止模糊词（"适当地"等）
- 每个函数节含「作用」（职责/输入输出语义）+「逻辑」（缩进式逐语句伪代码）+「测试要点」（编号列表）
- 详细程度：全量逐语句，不做概括；仅空文件与纯引入文件可简述

## 文件索引

### compiler/（29 个源文件 → 39 个文档）
- [lexer.md](compiler/lexer.md)（源 393 行）
- [parser-1.md](compiler/parser-1.md) ~ [parser-4.md](compiler/parser-4.md)（源 1,691 行，4 部分）
- [checker-1.md](compiler/checker-1.md) ~ [checker-5.md](compiler/checker-5.md)（源 2,404 行，5 部分）
- [ast.md](compiler/ast.md)（源 629 行）
- [ir_gen-1.md](compiler/ir_gen-1.md) ~ [ir_gen-4.md](compiler/ir_gen-4.md)（源 2,032 行，4 部分）
- [dataflow.md](compiler/dataflow.md)（源 521 行）
- [ccr_io.md](compiler/ccr_io.md)（源 594 行）
- [cir_cache.md](compiler/cir_cache.md)（源 314 行）
- [opt.md](compiler/opt.md)（源 525 行）
- [pass.md](compiler/pass.md)（源 24 行）
- [dyn_arr.md](compiler/dyn_arr.md)（源 786 行）
- [interp.md](compiler/interp.md)（源 384 行）
- [dump.md](compiler/dump.md)（源 334 行）
- [main.md](compiler/main.md)（源 587 行）
- [corearch.md](compiler/corearch.md)（源 149 行）
- [module.md](compiler/module.md)（源 552 行）
- [project.md](compiler/project.md)（源 56 行）
- [diag.md](compiler/diag.md)（源 154 行）
- [globals.md](compiler/globals.md)（源 182 行）
- [entry.md](compiler/entry.md)（源 2 行）
- [_import.md](compiler/_import.md)（源 34 行）
- [elf.md](compiler/elf.md)（源 566 行）
- [linker.md](compiler/linker.md)（源 0 行）
- [ext_mgr.md](compiler/ext_mgr.md)（源 93 行）
- [ext_safety.md](compiler/ext_safety.md)（源 37 行）
- [monomorph.md](compiler/monomorph.md)（源 438 行）
- [provenance_verify.md](compiler/provenance_verify.md)（源 90 行）
- [ptr_analysis.md](compiler/ptr_analysis.md)（源 283 行）
- [region_check.md](compiler/region_check.md)（源 156 行）

### stdlib/（18 个源文件 → 18 个文档）
- [_import.md](stdlib/_import.md)（源 3 行）· [arena.md](stdlib/arena.md)（99 行）· [assert.md](stdlib/assert.md)（125 行）· [chan.md](stdlib/chan.md)（181 行）· [cli.md](stdlib/cli.md)（373 行）· [collections.md](stdlib/collections.md)（126 行）· [fmt.md](stdlib/fmt.md)（192 行）· [goroutine.md](stdlib/goroutine.md)（70 行）· [hotpatch.md](stdlib/hotpatch.md)（47 行）· [io.md](stdlib/io.md)（52 行）· [math.md](stdlib/math.md)（77 行）· [os.md](stdlib/os.md)（104 行）· [panic.md](stdlib/panic.md)（48 行）· [sched.md](stdlib/sched.md)（205 行）· [scheduler.md](stdlib/scheduler.md)（154 行）· [toml.md](stdlib/toml.md)（168 行）· [trace.md](stdlib/trace.md)（23 行）· [variadic.md](stdlib/variadic.md)（34 行）

### runtime/（2 个源文件 → 2 个文档）
- [rt.md](runtime/rt.md)（源 14 行）· [arena_globals.md](runtime/arena_globals.md)（源 4 行）

### arch/linux/ld/（7 个源文件 → 12 个文档）
- [elf-1.md](arch/linux/ld/elf-1.md) ~ [elf-4.md](arch/linux/ld/elf-4.md)（源 1,643 行，4 部分）
- [instr-1.md](arch/linux/ld/instr-1.md) ~ [instr-3.md](arch/linux/ld/instr-3.md)（源 1,203 行，3 部分）
- [ld.md](arch/linux/ld/ld.md)（源 477 行）· [main.md](arch/linux/ld/main.md)（136 行）· [resolve.md](arch/linux/ld/resolve.md)（91 行）· [sizes.md](arch/linux/ld/sizes.md)（75 行）· [_import.md](arch/linux/ld/_import.md)（15 行）
