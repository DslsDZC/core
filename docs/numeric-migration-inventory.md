# 数值类型迁移盘点——float 站点分类表（迁移契约）

日期：2026-08-16
依据：[2026-08-16-numeric-types-design.md](superpowers/specs/2026-08-16-numeric-types-design.md)（已批准）
用途：Task 5/6 的迁移契约——每个站点按本表逐点执行，**禁止机械替换（sed/全局替换）**。

## 分类规则

| 分类 | 含义 | 判定标准 |
|---|---|---|
| `dex` | 用户可见 float 类型/字面量语义——默认精确（**语义变更**） | 类型常量、类型名/关键字映射、字面量节点、类型规则/错误消息、类型大小、类型名称输出（dump/LSP/IR 类型串） |
| `dex,apx` | 编译器内部浮点路径（运算/打印/指令编码）——保留 binary64 行为（它们是 apx 快路径的实现） | 字面量→binary64 位模式、float 运算 IR 生成、SSE2/XMM 指令编码、float_str_bits 打印、IR_I2F/IR_F2I |
| `保留` | 历史/注释/文档引用 | 注释、docstring、文档、`_f32`/`_f64` 后缀相关令牌/宽度常量 |
| `删除` | 迁移后应移除的残留 | 无迁移后指称的死常量/残留 |
| `_f32`/`_f64` 后缀 | → 保留 | apx 的 CPU 位宽标注（精确标注语法后议） |

注意：代码行内的内联注释随其代码站点一并处理（不单列）；独立注释行单独列出。

## 主分类表（73 站点：dex 38 / dex,apx 16 / 保留 18 / 删除 1）

### src/compiler/ast.cr（10 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| ast.cr:8 `T_FLOAT : int = 3` | 字面量令牌 kind | `dex` | `3.14` 字面量默认语义 → 精确 dex；令牌更名/改义（T_DEX），默认路径不再产 binary64 位模式 |
| ast.cr:84 注释 | 注释 | `保留` | 后缀令牌说明（`_i32/_u64/_f32`），历史注释 |
| ast.cr:93-94 `T_FLOAT_F32/T_FLOAT_F64 = 85/86` | 后缀字面量令牌 | `保留` | `_f32/_f64` 后缀 → apx CPU 位宽标注，令牌保留 |
| ast.cr:99 `T_FLOAT_TYPE : int = 91` | 类型关键字令牌 kind | `删除` | float 关键字消亡；该常量**从未被 lexer 发射**（类型名按 lexeme 匹配，见 parser.cr:84）——死常量残留。删除时勿重编号（保持 LSP 连续区间 90..95 语义，见 analysis.cr:895 说明） |
| ast.cr:108 注释 | 注释 | `保留` | 宽度常量说明（EXPR_INT/EXPR_FLOAT） |
| ast.cr:117-118 `W_F32/W_F64 = 9/10` | 位宽常量 | `保留` | `_f32/_f64` → apx CPU 位宽标注 |
| ast.cr:122 `TY_FLOAT : int = 1` | 核心类型常量 | `dex` | 类型本身更名 TY_DEX，默认精确（语义变更）；设计 §5：float 类型名删除、类型迁为 dex |
| ast.cr:206 `EXPR_FLOAT : int = 27` | 字面量 AST 节点 kind | `dex` | 字面量节点语义 → dex；注释已预示"int_val = value (as scaled int)"（缩放整数 = dex 表示） |
| ast.cr:296 `TI_FLOAT : int = 1` | IR 类型索引 | `dex` | 随类型更名 TI_DEX；单一类型（dex 永远是 dex，apx 只是附注） |
| ast.cr:576-577 `IR_I2F=49 / IR_F2I=50` | 转换 IR 指令 | `dex,apx` | int↔binary64 转换指令（cvtsi2sd/cvttsd2si）——apx 快路径实现，保留 |

### src/compiler/lexer.cr（3 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| lexer.cr:121 `str_to_f64_bits` | 字面量→binary64 位模式 | `dex,apx` | 十进制→IEEE 754 转换是 apx 快路径实现（apx 授权时字面量仍需此转换）；dex 默认路径改走精确解析（Task 5 新增） |
| lexer.cr:328-329 注释 | 注释 | `保留` | 修复历史注释（float 位模式、str_int 截断史） |
| lexer.cr:331 `add_tok_int(T_FLOAT, str_to_f64_bits(...))` | 字面量令牌发射 | `dex,apx` | 发射机制保留为 apx 快路径（binary64 位模式）；令牌 kind 更名 T_DEX 后此处为 apx 授权分支 |

### src/compiler/parser.cr（2 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| parser.cr:84 `lex == "float"` → TY_FLOAT | 类型名解析 | `dex` | 用户可见类型名；`float` → `dex`（默认精确，语义变更） |
| parser.cr:405-411 `T_FLOAT/T_FLOAT_F32/F64` 字面量解析 | 字面量节点构建 | `dex` | 字面量节点 EXPR_FLOAT 语义 → dex（默认精确）；其中 409-410 的 W_F32/W_F64 宽度传递保留（后缀标注不动，parser 404 行的 T_FLOAT_F32/F64 分支配对保留） |

### src/compiler/checker.cr（12 处，全部 `dex`）

| 站点 | 角色 | 理由 |
|---|---|---|
| checker.cr:22 `alloc_type(TYP_BASE, TY_FLOAT, 0)` | 类型表注册 | TY_FLOAT→TY_DEX，单一类型 |
| checker.cr:368 `res_type_node` TY_FLOAT→TI_FLOAT | 类型解析管道 | 常量更名随类型 |
| checker.cr:474 `get_type_name` 返回 "float" | 类型名输出（错误消息/hover） | 名字改 "dex" |
| checker.cr:672 / 696 | 函数返回类型→TI 管道 | 常量更名随类型（696 为 @hotpatch 签名核对，同规则） |
| checker.cr:748 | extern 返回类型→TI 管道 | 常量更名随类型 |
| checker.cr:877 `res_call_type` | 调用推断 | 常量更名随类型 |
| checker.cr:1143 | 参数类型→TI 管道 | 常量更名随类型 |
| checker.cr:1196 | 返回类型→TI 管道 | 常量更名随类型 |
| checker.cr:1363 `infer_expr` EXPR_FLOAT→TI_FLOAT | 字面量类型推断 | 字面量语义 → dex |
| checker.cr:1416-1420 算术规则 + 消息 | 类型规则/错误消息 | "Arithmetic operation requires int or float" → int or dex；结果类型 TI_DEX（规则本身不变，类型名变） |
| checker.cr:1597 `iface_ret2 == TY_FLOAT` | 接口方法返回类型分派 | 常量更名随类型 |

### src/compiler/ir_gen.cr（10 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| ir_gen.cr:150 `ti == TI_FLOAT`（IR_ALLOC 小值判定） | 逃逸分析判定 | `dex` | TI_FLOAT→TI_DEX（dex 同为寄存器值类） |
| ir_gen.cr:196 调用返回类型 TY_FLOAT→TI_FLOAT | 类型管道 | `dex` | 常量更名随类型 |
| ir_gen.cr:279 `res_type_node` | 类型管道 | `dex` | 常量更名随类型 |
| ir_gen.cr:291 `str_eq(name, "float")` | 类型名解析（EXPR_IDENT） | `dex` | 用户可见类型名；改 "dex" |
| ir_gen.cr:312 / 363 `type_size` TY_FLOAT = 8 | 类型大小 | `dex` | 大小随 dex（默认缩放整数 8 字节，尺寸语义不变）；常量更名 |
| ir_gen.cr:482-483 EXPR_FLOAT→IR_CONST（TI_FLOAT + 位模式） | 字面量常量发射 | `dex,apx` | 现有发射 = binary64 位模式（apx 快路径表示，保留）；dex 默认精确路径需新增缩放整数常量发射；变量名 "float"→"dex" |
| ir_gen.cr:685-696 float 二元运算生成（含隐式 I2F 插入） | 浮点运算 IR 生成 | `dex,apx` | 保留 binary64 运算路径（SSE2 分派 + cvtsi2sd 隐式转换）为 apx 快路径；dex 默认精确运算改走缩放整数序列（新增路径）；"int 操作数隐式转换"仅在 apx 路径成立（设计 §6 显式转换原则下默认精确路径不插入） |
| ir_gen.cr:974 `type_str = "float"`（IR dump 类型串） | 类型名输出 | `dex` | 名字改 "dex" |
| ir_gen.cr:1093 `type_args + "float"`（monomorph 签名串） | 类型名输出 | `dex` | 名字改 "dex" |

### src/compiler/monomorph.cr（3 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| monomorph.cr:101 `s == "float"` → TY_FLOAT | 泛型基类型名解析 | `dex` | 用户可见类型名；改 "dex" |
| monomorph.cr:192 注释 "(int, float, etc.)" | 注释 | `保留` | 注释 |
| monomorph.cr:220 `k == EXPR_FLOAT` 克隆分支 | 泛型 AST 克隆 | `dex` | 节点 kind 更名随字面量语义（EXPR_FLOAT→EXPR_DEX 或保持 kind 号） |

### src/compiler/module.cr（3 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| module.cr:361 注释 "int=0, string=1, float=2..." | 注释 | `保留` | 编码表注释（注意：注释与代码已有出入——注释写 float=2，代码 L366 写 `ptype_code = 3`，既有 bug，Task 5 顺带修正注释即可，勿动编码） |
| module.cr:366 `pname == "float"` → code 3 | extern 参数类型名编码 | `dex` | 用户可见类型名（extern 声明里的类型字符串）；改 "dex"。ABI 语义：dex 跨 C 边界按 binary64 传递属 apx 授权行为，编码 3 保留给 apx 场景 |
| module.cr:380 `ret_type == "float"` → code 3 | extern 返回类型名编码 | `dex` | 同上 |

### src/compiler/dump.cr（1 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| dump.cr:52 `type_kind_name` tk==1 → "float" | 类型名输出（dump） | `dex` | 名字改 "dex" |

### src/compiler/ccr_io.cr（1 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| ccr_io.cr:210-211 注释（修复 14：IR_CONST float 位模式 64 位化） | 注释 | `保留` | 修复历史注释；序列化本身无 float 分支（裸 i64），无需改动 |

### src/stdlib/fmt.cr（2 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| fmt.cr:194 注释 "float 打印（IEEE 754 double → 十进制）" | 注释 | `保留` | 注释 |
| fmt.cr:203 `float_str_bits(bits)` | 打印（binary64 位模式→十进制） | `dex,apx` | 设计 §5 明示："float_str_bits → dex 打印，保留为 apx 路径实现"——binary64 打印保留为 apx 快路径；dex 默认打印 = 缩放整数→十进制（新增） |

### src/arch/linux/ld/instr.cr（10 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| instr.cr:298 注释（SSE2 段头 "float 支持"）+ 323 注释（movsd SysV float 参数） | 注释 | `保留` | 注释 |
| instr.cr:336-340 `e2_store_ret`（TI_FLOAT → movsd [slot], xmm0） | 指令编码（返回值存放） | `dex,apx` | SysV XMM0 返回路径保留为 apx 快路径；TI_FLOAT→TI_DEX 更名后按附注分派 |
| instr.cr:344-346 `e2_push_xmm0`（sub rsp,8 + movsd [rsp],xmm0） | 指令编码（float 参数压栈） | `dex,apx` | apx 参数栈传递路径，保留 |
| instr.cr:352-360 `e2_sd_cvt`（cvtsi2sd） | 指令编码（int→float 转换） | `dex,apx` | cvtsi2sd = apx 快路径转换，保留 |
| instr.cr:418-425 IR_I2F 发射（cvtsi2sd + movsd 存回） | 指令编码 | `dex,apx` | IR_I2F 是 apx 路径指令，保留 binary64 行为 |
| instr.cr:426-432 IR_F2I 发射（movsd + cvttsd2si + 存回） | 指令编码 | `dex,apx` | 同上（cvttsd2si 截断语义 = binary64 行为，保留） |
| instr.cr:456-475 IR_BINARY TI_FLOAT（addsd/subsd/mulsd/divsd/comisd） | 指令编码（浮点运算/比较） | `dex,apx` | SSE2 double 运算 = apx 快路径核心实现（IEEE 754 标准答案），逐位保留；内联注释（456/459/467）随行 |
| instr.cr:584-625 IR_CALL SysV 分派（XMM0-7 参数、fr_cnt、9+ float 栈参数） | 指令编码（调用约定） | `dex,apx` | SysV float 参数传递保留为 apx 快路径；内联注释（584/605）随行 |
| instr.cr:784 注释（"int 超 6 + float 超 8" 压栈数） | 注释 | `保留` | 注释 |
| instr.cr:860-862 IR_RETURN（TI_FLOAT → movsd xmm0） | 指令编码（返回值） | `dex,apx` | XMM0 返回路径保留（apx 快路径）；内联注释（861）随行 |

### src/arch/linux/ld/elf.cr（2 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| elf.cr:1250-1251 注释（"float 参数在 XMM"） | 注释 | `保留` | 注释 |
| elf.cr:1252-1262 TI_FLOAT 参数 XMM 落槽（movsd [rbp+po2], xmm{frn}；9+ float 栈参数边缘路径） | 指令编码（函数序言参数搬移） | `dex,apx` | SysV XMM 参数搬移保留为 apx 快路径 |

### src/lsp/analysis.cr（8 处；预扫报"5 处"为字面量 "float" 命中：36/312/848/865/908，本表补 T_FLOAT 变体 3 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| analysis.cr:36 `analysis_tyname` TY_FLOAT → "float" | 类型名输出（hover/documentSymbol 显示） | `dex` | 名字改 "dex" |
| analysis.cr:312 `analysis_type_of_expr` EXPR_FLOAT → "float" | 字面量类型显示 | `dex` | 字面量语义 → dex，显示 "dex" |
| analysis.cr:848 注释（"运算符与 int/float 字面量令牌的 lexeme = -1"） | 注释 | `保留` | 注释（令牌跨度扫描说明） |
| analysis.cr:864-881 注释块（tokenType 映射表：864 含 T_FLOAT_F64、865 内置类型名 int/float/…、881 "number (7): T_INT T_FLOAT"） | 注释 | `保留` | 映射表注释；legend 结构本身不改（number 类保留） |
| analysis.cr:895 `(k >= T_INT_I8 && k <= T_FLOAT_F64)` 区间 | semanticTokens legend 分派 | `保留` | 区间含 T_FLOAT_F32/F64（后缀令牌保留 → 区间保持有效，无需改动）；另含 T_INT_TYPE..T_AUTO_TYPE 区间——若 T_FLOAT_TYPE 删除但不重编号，区间仍正确（见 ast.cr:99 行理由） |
| analysis.cr:900 `k == T_FLOAT` → number legend(7) | 令牌→legend 分派 | `dex` | T_FLOAT 令牌更名 T_DEX 后同步（仍映射 number） |
| analysis.cr:908 `str_eq(s, "float")` 内置类型名判定 | 内置类型名清单 | `dex` | 名字改 "dex"（与 parser.cr:84 同源清单） |
| analysis.cr:955 `k == T_FLOAT` 令牌跨度扫描 | 令牌长度计算（镜像 lexer） | `dex` | 随令牌更名同步；后缀令牌分支（956 起小数扫描）保留 |

### 测试（4 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| tests/bootstrap/test_pipeline.py:46 docstring "non-int return types (string, float)" | 注释 | `保留` | docstring |
| tests/bootstrap/test_pipeline.py:187-190 'Float Add'（`fn main() -> float`，3.14+2.86=6.0） | 用户可见类型用例 | `dex` | 测精确语义：dex 精确算术 3.14+2.86=6.0 精确成立，用例改为 dex 后仍通过（期望值不变）；注意该用例跑在 Python bootstrap 解释器上——bootstrap 需先认识 dex（见范围外附录） |
| tests/bootstrap/test_pipeline.py:196-199 'Int Float Mix'（`fn main() -> float`，2+3.5=5.5） | 用户可见类型用例 | `dex` | 同上：2+3.5=5.5 精确成立；混合 int+dex 在 dex 世界无隐式转换问题（缩放整数对齐） |
| tests/selfhost/test_native_strings.py:47-52 float_str_bits 位模式断言（3.14/2/10/1/100/-2 的 binary64 位→十进制串） | 打印快路径用例 | `dex,apx` | 测 binary64 行为 → 保留为 apx 打印路径的回归用例（float_str_bits 保留） |

### grammar/core.ebnf（1 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| core.ebnf:29-31 注释（"'float' 类型名已移除（2026-08-16 数值类型设计）；旧 float 语义 = 'dex' + 'apx'"） | 注释 | `保留` | 设计决策注释；文法本体已迁移（BaseType 已含 'dex'），无残留语法 |

### docs/（1 条汇总，21 文件 86 处）

| 站点 | 角色 | 分类 | 理由 |
|---|---|---|---|
| docs/ 21 个文件 84 处 "float" 字面量（compcert-reference 8、error-codes 2、pseudocode 10 文件 22、superpowers specs 5 文件 13、superpowers plans 4 文件 39）；另有 3 个 pseudocode 文件（checker-4/checker-5/parser-2）含 TY_FLOAT/TI_FLOAT/EXPR_FLOAT 变体 | 文档引用 | `保留` | 文档/历史引用（含本设计 spec 本身与 Task 计划）——按规则保留为历史；后续文档刷新属独立任务 |

零站点文件（预扫范围内确认无 float）：`tests/suite/`（30 个 .cr 全部无 float 字面量/类型）、`src/compiler/{dataflow,opt,pass,diag,interp,globals,entry,main,corearch,project,dyn_arr,_import}.cr`、`src/arch/linux/ld/{ld,resolve,sizes}.cr`、`src/runtime/`、`src/lsp/`（除 analysis.cr 外的 rpc.cr 等）、`examples/`、`vscode-core/`、`spec/`、`grammar/{tokens,corespec}.ebnf`、`legacy_asm_backend/`。
注：interp.cr 值存储为裸 64 位（无 float 分支），TI_FLOAT→TI_DEX 更名不触及；dex 精确运算的解释执行属 Task 5 新增。

## 迁移后目标形态（dex/apx 双语义落点）

| 层 | dex（默认精确，语义变更） | apx（授权近似，binary64 快路径保留） | 涉及站点 |
|---|---|---|---|
| 字面量 | `3.14` → 缩放整数常量（精确解析，新路径） | `3.14` → binary64 位模式（str_to_f64_bits 保留） | lexer:121/331、ir_gen:482-483、parser:405-411、ast:8/206 |
| 词法令牌 | T_FLOAT → T_DEX（字面量令牌） | T_FLOAT_F32/F64 保留（apx CPU 位宽标注） | ast:8/93-94 |
| 类型系统 | TY_FLOAT→TY_DEX、TI_FLOAT→TI_DEX（单一类型，dex 永远是 dex） | —（apx 是变量级标签，不进类型） | ast:122/296、checker:22 |
| 类型名解析 | "float"→"dex"（parser/monomorph/ir_gen/module/LSP 清单同源改） | — | parser:84、monomorph:101、ir_gen:291、module:366/380、lsp:908 |
| 检查器 | 算术规则 int\|dex、消息更新、推断 TI_DEX；apx 标签透传零规则 | — | checker 12 处 |
| IR | dex 运算 = 缩放整数指令序列（新后端路径）；IR_APPROX 附注（非语义） | IR_I2F/IR_F2I 保留；TI_FLOAT 分派 SSE2 | ir_gen:685-696、ast:576-577 |
| 后端 | 默认 dex → 整数指令序列（新增） | SSE2/XMM/SysV 全路径保留（addsd…comisd、cvtsi2sd/cvttsd2si、XMM0-7 参数/返回） | instr.cr 8 处代码、elf.cr:1252-1262 |
| 打印 | dex → 十进制（缩放整数长除，新路径） | float_str_bits 保留为 apx 打印实现 | fmt.cr:203 |
| 名称输出 | "float"→"dex"（dump/IR 类型串/LSP 显示） | — | dump:52、ir_gen:974/1093、lsp:36/312 |
| FFI | extern 类型名字符串 "float"→"dex" | 跨 C 边界 binary64 ABI 属 apx 授权行为（编码 3 保留） | module:366/380 |
| 测试 | float 用例 → dex（3.14+2.86、2+3.5 精确成立） | float_str_bits 位模式用例保留 | test_pipeline:187-199、test_native_strings:47-52 |
| EBNF/文档 | 文法已迁移（dex 入 BaseType） | — | core.ebnf:29-31（注释保留） |

执行顺序提示（与计划一致）：**先加 dex（Task 2-4）再移 float（Task 5-6）**，保持编译器自举；每个 `dex,apx` 站点只改名不改行为（binary64 路径不变）。

## 范围外附录：bootstrap/corec（Python 自举编译器，预扫范围外但构建关键）

`build_selfhost_native.py` 用 bootstrap 编译 src/compiler——**bootstrap 目前不认识 `dex`**（无任何 dex 支持），且保留完整 float 实现（7 文件 ~14 处）：

- `bootstrap/corec/frontend/lexer.py:81/94/107`（is_float 字面量扫描）
- `bootstrap/corec/frontend/parser.py:24`（type_name lexeme）、`327`（base_types 集合）、`509`（float 字面量）
- `bootstrap/corec/frontend/type_checker.py:199`（kind_map）、`220-222`（float 算术 + 提升规则）
- `bootstrap/corec/frontend/ir_gen.py:165`（float 字面量）、`629/637`（kind_map）
- `bootstrap/corec/ir/cir.py:42`（docstring）
- `bootstrap/corec/backend/interpreter.py:28`（float 默认值 0.0）、`91-92`（float 常量）
- `bootstrap/corec/backend/x86_64_stack_asm.py:145`（float 常量发射）

**处理建议**：Task 2（加 dex）必须同步在 bootstrap 落 dex 类型支持，否则自举断裂；bootstrap 自身实现 binary64 语义（Python float），按 `dex,apx` 同类处理（认识 dex 类型名、保留 binary64 实现 = apx 快路径参考实现）最贴契约——**需维护者确认后再纳入 Task 5 范围**。

## 完整性自检

复查 grep（全仓库，2026-08-16）：

```bash
grep -rn "float" src/ tests/ grammar/            # 命中文件与主表 13+3+1 个源码文件一一对应
grep -rn "TY_FLOAT" src/                          # 6 文件：ast/checker/ir_gen/monomorph/parser/analysis ✓
grep -rn "TI_FLOAT" src/                          # 41 处，5 文件：ast/ir_gen/checker/instr/elf ✓（均入表）
grep -rn "T_FLOAT\b\|T_FLOAT_TYPE" src/           # ast:8/99、lexer:331、lsp:881(注)/900/955、parser:405 ✓
grep -rn "EXPR_FLOAT" src/                        # ast:206、parser:411、checker:1363、ir_gen:481、monomorph:220、lsp:312 ✓
grep -rn "IR_I2F\|IR_F2I" src/                    # ast:576-577、ir_gen:691/696、instr:418/426 ✓
grep -rn "T_FLOAT_F32\|T_FLOAT_F64" src/          # ast:93-94、parser:405/409-410、lsp:864(注)/895 ✓
grep -rn "W_F32\|W_F64" src/                      # ast:117-118、parser:409-410 ✓
grep -rn "_f32\|_f64" src/ tests/ grammar/        # 仅 ast.cr:84 注释 ✓
grep -rn "float" tests/suite/ examples/ vscode-core/ spec/ src/runtime/   # 0 命中 ✓
grep -rln "float" docs/                           # 21 文件 84 处 → docs 汇总行 ✓（另 3 个 pseudocode 文件仅含 TY_FLOAT 等变体）
```

计数核对：主表 73 行 = dex 38 + dex,apx 16 + 保留 18 + 删除 1；docs 汇总 1 行；范围外附录 14 处（未计入主表）。无未列入的 float 站点。

## 分类争议点

1. **parser.cr:405-411（字面量节点）标 `dex`**：该行同时含后缀宽度传递（W_F32/W_F64，保留）与 T_FLOAT 分支（dex 语义）。按"节点语义归属"标 dex，后缀部分在理由中注明不动。
2. **ir_gen.cr:482-483（字面量→IR_CONST）标 `dex,apx`**：发射的 binary64 位模式是 apx 表示（保留），但 TI_FLOAT→TI_DEX 更名属 dex 侧。若执行时希望整体按语义层处理可改 `dex`——建议以"位模式保留 = 快路径"为准标 dex,apx。
3. **ast.cr:99 T_FLOAT_TYPE 标 `删除`**：从未被发射的死常量（float 关键字实际按 lexeme 匹配）。唯一风险是 LSP 连续区间 `T_INT_TYPE..T_AUTO_TYPE`（90..95）——删除不重编号则区间语义不变，故删除安全。若保守处理可标保留，但契约建议删除。
4. **计划文件 Task 5 的括号示例把 monomorph/module/dump/ccr_io/parser/lexer 列为 `dex,apx` 站点**：本表按 Global Constraints 逐点判定——这些文件的**类型名/常量更名**站点属用户可见类型语义（`dex`），仅其**binary64 机制**部分（lexer 位转换、ir_gen 运算生成）为 `dex,apx`。计划原文"按分类表逐点执行"，以本表为准。
5. **module.cr:361/366 编码表注释与代码不符**（注释 float=2、代码 =3）：既有 bug，非本任务修复项；Task 5 改注释时需核对实际 ABI 编码。
6. **bootstrap 范围外但构建关键**（见附录）：若 Task 5 按表迁移 src/compiler 而 bootstrap 未先支持 dex，`build_selfhost_native.py` 自举失败——需在计划层面确认 bootstrap 的 dex 落地任务归属。
