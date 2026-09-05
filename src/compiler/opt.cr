// === opt.cr ===
// AST-level optimization passes.
// Runs after check_all(), before ir_gen_all().
// Only transforms AST nodes (g_ast), never touches IR or backend.


// ------------------------------------------------------------------
// AST constant folding: EXPR_BINARY(int, int) → EXPR_INT
// ------------------------------------------------------------------

fn ast_is_const_int(node: int) -> int {
    if node < 0 { return 0; }
    if ast_kind(node) == EXPR_INT { return 1; }
    return 0;
}

fn ast_const_val(node: int) -> int {
    return ast_int_val(node);
}

fn ast_bool_as_int(value: bool) -> int {
    if value { return 1; }
    return 0;
}

fn ast_fold_binary(node: int) -> int {
    left := ast_a(node);
    right := ast_b(node);
    opc := ast_c(node);
    if !ast_is_const_int(left) || !ast_is_const_int(right) { return 0; }
    v1 := ast_const_val(left);
    v2 := ast_const_val(right);
    rv : ., mut = 0;
    known : ., mut = 1;
    if opc == OP_ADD { rv = v1 + v2; }
    else if opc == OP_SUB { rv = v1 - v2; }
    else if opc == OP_MUL { rv = v1 * v2; }
    else if opc == OP_DIV { if v2 == 0 { return 0; } rv = v1 / v2; }
    else if opc == OP_MOD { if v2 == 0 { return 0; } rv = v1 % v2; }
    else if opc == OP_EQ { rv = ast_bool_as_int(v1 == v2); }
    else if opc == OP_NE { rv = ast_bool_as_int(v1 != v2); }
    else if opc == OP_LT { rv = ast_bool_as_int(v1 < v2); }
    else if opc == OP_GT { rv = ast_bool_as_int(v1 > v2); }
    else if opc == OP_LE { rv = ast_bool_as_int(v1 <= v2); }
    else if opc == OP_GE { rv = ast_bool_as_int(v1 >= v2); }
    else if opc == OP_AND { rv = ast_bool_as_int(v1 != 0 && v2 != 0); }
    else if opc == OP_OR { rv = ast_bool_as_int(v1 != 0 || v2 != 0); }
    else { known = 0; }
    if known == 0 { return 0; }
    // Fold: replace EXPR_BINARY with EXPR_INT
    // Use ast_set_* to modify in-place
    ast_set_kind(node, EXPR_INT);
    ast_set_a(node, 0);
    ast_set_b(node, 0);
    ast_set_c(node, 0);
    ast_set_int_val(node, rv);
    ast_set_type_val(node, TY_INT);
    return 1;
}

// ------------------------------------------------------------------
// Walk a block's statements and fold expressions
// ------------------------------------------------------------------

fn ast_optimize_body(body: int) {
    if body < 0 { return; }
    bk := ast_kind(body);

    // EXPR_BLOCK: optimize each statement recursively
    if bk == EXPR_BLOCK {
        ss := ast_a(body); sc := ast_b(body);
        i : ., mut = 0;
        loop {
            if i >= sc { break; }
            sn := r64(g_block_stmts, (ss + i) * 8);
            ast_optimize_body(sn);
            i = i + 1;
        }
        return;
    }
    // EXPR_RETURN: optimize the return value expression
    if bk == EXPR_RETURN {
        if ast_a(body) >= 0 { ast_optimize_body(ast_a(body)); }
        return;
    }
    // EXPR_IF: optimize condition, then, else
    if bk == EXPR_IF {
        ast_optimize_body(ast_a(body));  // cond
        ast_optimize_body(ast_b(body));  // then
        if ast_c(body) >= 0 { ast_optimize_body(ast_c(body)); }  // else
        // Fold: if const_int(0) → else, if const_int(≠0) → then
        cond := ast_a(body);
        if ast_is_const_int(cond) {
            cv := ast_const_val(cond);
            then_node := ast_b(body);
            else_node := ast_c(body);
            if cv != 0 && then_node >= 0 {
                // Replace if with then body
                // We can't easily clone AST, so just mark as NONE
                // (IR gen will skip)
            } else if cv == 0 && else_node >= 0 {
                // Replace if with else body
            }
        }
        return;
    }
    // EXPR_BINARY: fold constants
    if bk == EXPR_BINARY {
        ast_optimize_body(ast_a(body));
        ast_optimize_body(ast_b(body));
        ast_fold_binary(body);
        return;
    }
    // EXPR_UNARY
    if bk == EXPR_UNARY {
        if ast_a(body) >= 0 { ast_optimize_body(ast_a(body)); }
        return;
    }
    // EXPR_CALL: optimize args
    if bk == EXPR_CALL {
        if ast_a(body) >= 0 { ast_optimize_body(ast_a(body)); }
        an := ast_b(body); ac := ast_c(body);
        ai : ., mut = 0;
        loop { if ai >= ac { break; } if an >= 0 { ast_optimize_body(an); an = an + 1; } ai = ai + 1; }
        return;
    }
    // EXPR_STRUCT: optimize field values
    if bk == EXPR_STRUCT {
        fn2 := ast_b(body); fc := ast_c(body);
        i : ., mut = 0;
        loop { if i >= fc { break; } if fn2 >= 0 { ast_optimize_body(fn2); fn2 = fn2 + 1; } i = i + 1; }
        return;
    }
    // EXPR_LET: optimize value expression
    if bk == EXPR_LET {
        if ast_c(body) >= 0 { ast_optimize_body(ast_c(body)); }
        return;
    }
    // EXPR_GO: optimize spawned body
    if bk == EXPR_GO {
        if ast_b(body) >= 0 { ast_optimize_body(ast_b(body)); }
        return;
    }
    if bk == EXPR_YIELD {
        if ast_a(body) >= 0 { ast_optimize_body(ast_a(body)); }
        return;
    }
    // EXPR_LOOP, EXPR_WHILE: optimize body
    if bk == EXPR_LOOP || bk == EXPR_WHILE {
        if ast_a(body) >= 0 { ast_optimize_body(ast_a(body)); }
        return;
    }
    // EXPR_FOR: optimize iter and body
    if bk == EXPR_FOR {
        if ast_b(body) >= 0 { ast_optimize_body(ast_b(body)); }
        if ast_c(body) >= 0 { ast_optimize_body(ast_c(body)); }
        return;
    }
    // EXPR_MATCH: optimize match expr and arms
    if bk == EXPR_MATCH {
        if ast_a(body) >= 0 { ast_optimize_body(ast_a(body)); }
        an := ast_b(body);
        loop { if an < 0 { break; }
            if ast_a(an) >= 0 { ast_optimize_body(ast_a(an)); }
            if ast_b(an) >= 0 { ast_optimize_body(ast_b(an)); }
            an = ast_c(an); }
        return;
    }
    // EXPR_STMT: unwrap
    if bk == EXPR_STMT {
        if ast_a(body) >= 0 { ast_optimize_body(ast_a(body)); }
        return;
    }
    // EXPR_ARRAY, EXPR_TUPLE: optimize elements
    if bk == EXPR_ARRAY || bk == EXPR_TUPLE {
        an := ast_b(body); ac := ast_c(body);
        i : ., mut = 0;
        loop { if i >= ac { break; } if an >= 0 { ast_optimize_body(an); an = an + 1; } i = i + 1; }
        return;
    }
    // EXPR_AS: optimize both sides
    if bk == EXPR_AS {
        if ast_a(body) >= 0 { ast_optimize_body(ast_a(body)); }
        return;
    }
    // EXPR_BINARY already handled above; fallthrough for EXPR_INDEX etc.
}

// ------------------------------------------------------------------
// v6 数据基础：存在区间推导（指令序 [first_ref, last_ref]）
// ------------------------------------------------------------------
// compute_live_ranges 填充全局 g_ir_live_ranges（表全局声明在 globals.cr），
// alloc_registers 改读本表——与原内联 iv_buf 构建逻辑逐行一致（行为不变）。
// 表布局：每函数一段，段内每「函数内 var」16B（first_ref/last_ref 各 8B，
// 函数内指令序）；func_i 段起始 = Σ var_count[0..func_i)，不乘固定稠密系数
// （live_range_slot 即该前缀累计；16B 记录 + grow 风格同 g_ir_slice_lens）。

fn grow_live_ranges(needed: int) {
    if needed < g_live_range_cap { return; }
    nc := g_live_range_cap * 2; if nc < 64 { nc = 64; } if nc < needed { nc = needed + 64; }
    nb := alloc(nc * 16); _dyncpy(g_ir_live_ranges, g_live_range_cap * 16, nb);
    g_ir_live_ranges = nb; g_live_range_cap = nc;
}

fn live_range_slot(func_i: int, var_i: int) -> int {
    // 函数内 var 索引 = var_i − var_start[func_i]；func_i 段起始 = 前缀 var_count 累计
    off : ., mut = 0;
    fi : ., mut = 0;
    loop { if fi >= func_i { break; }
        off = off + r64(g_ir_func_var_count, fi * 8);
        fi = fi + 1; }
    return (off + (var_i - r64(g_ir_func_var_start, func_i * 8))) * 16;
}

fn live_first(func_i: int, var_i: int) -> int {
    if func_i < 0 || var_i < 0 { return -1; }
    return r64(g_ir_live_ranges, live_range_slot(func_i, var_i));
}

fn live_last(func_i: int, var_i: int) -> int {
    if func_i < 0 || var_i < 0 { return -1; }
    return r64(g_ir_live_ranges, live_range_slot(func_i, var_i) + 8);
}

// 存在区间推导：填充 g_ir_live_ranges。语义 = 原 alloc_registers 内联 iv_buf
// 构建（:210-241）：逐函数逐指令扫描，dest/s1/s2 落在 [vs, vs+vc) 内则扩展
// [first_ref,last_ref]（首见写 first，之后推进 last）；未使用 var 两条均为 -1。
fn compute_live_ranges() {
    total : ., mut = 0;
    fi : ., mut = 0;
    loop { if fi >= g_ir_func_count { break; }
        total = total + r64(g_ir_func_var_count, fi * 8);
        fi = fi + 1; }
    grow_live_ranges(total);
    g_live_range_count = total;
    // 首遍写 -1（区间未知 = -1，同 alloc_registers 的 iv_buf 初始化语义）
    zi : ., mut = 0;
    loop { if zi >= total { break; }
        w64(g_ir_live_ranges, zi * 16, -1);
        w64(g_ir_live_ranges, zi * 16 + 8, -1);
        zi = zi + 1; }
    // 逐函数逐指令扫描：段偏移 = 运行中前缀累计（与 live_range_slot 前缀一致）
    seg : ., mut = 0;
    fi = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        ic := r64(g_ir_func_instr_count, fi * 8);
        ist := r64(g_ir_func_instr_start, fi * 8);
        vc := r64(g_ir_func_var_count, fi * 8);
        vs := r64(g_ir_func_var_start, fi * 8);
        if vc > 0 {
            ii : ., mut = 0;
            loop {
                if ii >= ic { break; }
                inst := ist + ii;
                d := iri_dest(inst); s1 := iri_s1(inst); s2 := iri_s2(inst);
                if d >= vs && d < vs + vc {
                    lv := d - vs;
                    st := (seg + lv) * 16;
                    if r64(g_ir_live_ranges, st) < 0 { w64(g_ir_live_ranges, st, ii); }
                    w64(g_ir_live_ranges, st + 8, ii);
                }
                if s1 >= vs && s1 < vs + vc {
                    lv := s1 - vs;
                    st := (seg + lv) * 16;
                    if r64(g_ir_live_ranges, st) < 0 { w64(g_ir_live_ranges, st, ii); }
                    w64(g_ir_live_ranges, st + 8, ii);
                }
                if s2 >= vs && s2 < vs + vc {
                    lv := s2 - vs;
                    st := (seg + lv) * 16;
                    if r64(g_ir_live_ranges, st) < 0 { w64(g_ir_live_ranges, st, ii); }
                    w64(g_ir_live_ranges, st + 8, ii);
                }
                ii = ii + 1;
            }
        }
        seg = seg + vc;
        fi = fi + 1;
    }
    // v6 Task 2：条目版本化——对全部函数切分版本条目（逐函数升序，
    // compute_entries 的 func_i==0 分支负责整表重建；本函数幂等可重跑）。
    // 与 opt 门控解耦：compute_live_ranges 自身在 cir --dump-entries 与
    // alloc_registers（O2）两处被调，条目表随算随新。
    ef : ., mut = 0;
    loop {
        if ef >= g_ir_func_count { break; }
        compute_entries(ef);
        ef = ef + 1;
    }
}

// ------------------------------------------------------------------
// v6 条目版本化：变量 × 定值点切分版本条目
// ------------------------------------------------------------------
// Core IR 非 SSA——变量可多次定值。定值指令 = IR_ALLOC（局部槽初定值，interp
// 置零）与该变量为目标的每次 IR_STORE（IR_STORE 形态 ρ(s1):=ρ(s2)——目标在 s1
// 不在 dest，见 docs/ir-op-semantics.md §2.1）。每个定值切分一个新版本条目。
// 版本存在区间（全局指令序闭区间，与 Task 1 区间表同语义、坐标 +instr_start）：
//   版本 j = [def_j, min(def_{j+1}−1, last_ref)]（末版 = [def_k, last_ref]；
//   last_ref 恒 ≥ 末定值——定值写自身计入引用）。
// 无定值但有引用的变量（函数参数、单次写临时值等）→ 单条目 def_instr=−1、
// 区间 = [first_ref, last_ref]；从未引用（first_ref=−1）跳过。
// 版本号不落盘：同 var 条目按 def_instr 升序（单遍扫描即升序），版本序 = 组内序号。
// 调用前置：compute_live_ranges() 已先行（截断用 last_ref），func_i 升序调用
// （func_i==0 重置全局计数——整表重建，重复调用幂等）。

fn grow_entries(needed: int) {
    if needed < g_entry_cap { return; }
    nc : ., mut = g_entry_cap * 2; if nc < 64 { nc = 64; } if nc < needed { nc = needed + 64; }
    nb := alloc(nc * ESZ_ENTRY); _dyncpy(g_ir_entries, g_entry_cap * ESZ_ENTRY, nb);
    g_ir_entries = nb; g_entry_cap = nc;
}

fn grow_func_entry_meta(needed: int) {
    if needed < g_ir_func_entry_cap { return; }
    nc : ., mut = g_ir_func_entry_cap * 2; if nc < 64 { nc = 64; } if nc < needed { nc = needed + 64; }
    sz := nc * 8;
    n1 := alloc(sz); _dyncpy(g_ir_func_entry_start, g_ir_func_entry_cap * 8, n1); g_ir_func_entry_start = n1;
    n2 := alloc(sz); _dyncpy(g_ir_func_entry_count, g_ir_func_entry_cap * 8, n2); g_ir_func_entry_count = n2;
    g_ir_func_entry_cap = nc;
}

// 条目表字段访问器（24B/条、4B 字段 LE；字段布局注释见 globals.cr）。
// 读统一走 buf_read_i32（ccr_io.cr，真实函数体带符号扩展）——不能调 r32：
// Python bootstrap 的 StackAsmGen 把名为 r32 的调用内联成 `mov eax,[rdi+rsi]`
// （零扩展 32 位读），bootstrap 产物里负值（-1 home/def）会读成 4294967295
// （x86_64_stack_asm.py:242；r32 源码里的符号修正逻辑只在自举产物中生效）。
// 写侧 w32 内联为 `mov [rdi+rsi],edx`（低 32 位存储）——补码语义正确，可用。
fn ent_off(e: int) -> int { return e * ESZ_ENTRY; }
fn ent_var(e: int) -> int { return buf_read_i32(g_ir_entries, ent_off(e) + OFF_ENTRY_VAR); }
fn ent_def(e: int) -> int { return buf_read_i32(g_ir_entries, ent_off(e) + OFF_ENTRY_DEF); }
fn ent_live_start(e: int) -> int { return buf_read_i32(g_ir_entries, ent_off(e) + OFF_ENTRY_LS); }
fn ent_live_end(e: int) -> int { return buf_read_i32(g_ir_entries, ent_off(e) + OFF_ENTRY_LE); }
fn ent_home(e: int) -> int { return buf_read_i32(g_ir_entries, ent_off(e) + OFF_ENTRY_HOME); }
fn ent_flags(e: int) -> int { return buf_read_i32(g_ir_entries, ent_off(e) + OFF_ENTRY_FLAGS); }

// 函数条目段界（全局条目下标；compute_entries 已跑过才有效）
fn entry_start(func_i: int) -> int {
    if func_i < 0 || func_i >= g_ir_func_count { return 0; }
    return r64(g_ir_func_entry_start, func_i * 8);
}

fn entry_count(func_i: int) -> int {
    if func_i < 0 || func_i >= g_ir_func_count { return 0; }
    return r64(g_ir_func_entry_count, func_i * 8);
}

fn compute_entries(func_i: int) -> int {
    if func_i == 0 { g_entry_count = 0; }
    ic := r64(g_ir_func_instr_count, func_i * 8);
    ist := r64(g_ir_func_instr_start, func_i * 8);
    vc := r64(g_ir_func_var_count, func_i * 8);
    vs := r64(g_ir_func_var_start, func_i * 8);
    cnt : ., mut = 0;
    if ic > 0 && vc > 0 {
        // 每「函数内 var」一条最近打开条目（-1 = 未打开）：定值序列切割 O(1) 收口
        prev : string, mut = alloc(vc * 8);
        pz : ., mut = 0;
        loop {
            if pz >= vc { break; }
            w64(prev, pz * 8, -1);
            pz = pz + 1;
        }
        // 单遍扫描：ALLOC(dest=var) / STORE(s1=var) 命中函数段 → 定值 → 切版本
        ii : ., mut = 0;
        loop {
            if ii >= ic { break; }
            inst := ist + ii;
            op := iri_op(inst);
            dv : ., mut = -1;
            if op == IR_ALLOC {
                d := iri_dest(inst);
                if d >= vs && d < vs + vc { dv = d; }
            } else if op == IR_STORE {
                s1 := iri_s1(inst);
                if s1 >= vs && s1 < vs + vc { dv = s1; }
            }
            if dv >= 0 {
                lv := dv - vs;
                last_global : ., mut = -1;
                ll := live_last(func_i, dv);
                if ll >= 0 { last_global = ist + ll; }
                // 收口上一版本：end = min(def−1, last_ref)（last_ref ≥ 次定值，恒取 def−1）
                pe := r64(prev, lv * 8);
                if pe >= 0 {
                    pend : ., mut = inst - 1;
                    if last_global >= 0 && last_global < pend { pend = last_global; }
                    w32(g_ir_entries, pe * ESZ_ENTRY + OFF_ENTRY_LE, pend);
                }
                // 开新版本：区间端点暂定 = 定值点..last_ref，末版直接成立
                grow_entries(g_entry_count + 1);
                eo := g_entry_count * ESZ_ENTRY;
                w32(g_ir_entries, eo + OFF_ENTRY_VAR, dv);
                w32(g_ir_entries, eo + OFF_ENTRY_DEF, inst);
                w32(g_ir_entries, eo + OFF_ENTRY_LS, inst);
                w32(g_ir_entries, eo + OFF_ENTRY_LE, last_global);
                w32(g_ir_entries, eo + OFF_ENTRY_HOME, -1);
                w32(g_ir_entries, eo + OFF_ENTRY_FLAGS, 0);
                w64(prev, lv * 8, g_entry_count);
                g_entry_count = g_entry_count + 1;
                cnt = cnt + 1;
            }
            ii = ii + 1;
        }
        // 无定值但有引用的 var（参数/单写临时值等）：单条目 def=-1
        lv2 : ., mut = 0;
        loop {
            if lv2 >= vc { break; }
            if r64(prev, lv2 * 8) < 0 {
                gv := vs + lv2;
                ff := live_first(func_i, gv);
                ll := live_last(func_i, gv);
                if ff >= 0 && ll >= 0 {
                    grow_entries(g_entry_count + 1);
                    eo := g_entry_count * ESZ_ENTRY;
                    w32(g_ir_entries, eo + OFF_ENTRY_VAR, gv);
                    w32(g_ir_entries, eo + OFF_ENTRY_DEF, -1);
                    w32(g_ir_entries, eo + OFF_ENTRY_LS, ist + ff);
                    w32(g_ir_entries, eo + OFF_ENTRY_LE, ist + ll);
                    w32(g_ir_entries, eo + OFF_ENTRY_HOME, -1);
                    w32(g_ir_entries, eo + OFF_ENTRY_FLAGS, 0);
                    g_entry_count = g_entry_count + 1;
                    cnt = cnt + 1;
                }
            }
            lv2 = lv2 + 1;
        }
    }
    grow_func_entry_meta(func_i + 1);
    w64(g_ir_func_entry_start, func_i * 8, g_entry_count - cnt);
    w64(g_ir_func_entry_count, func_i * 8, cnt);
    return cnt;
}

// --dump-entries 调试通道输出（cir 命令调用，Task 2 测试载体）：
// 每函数一段、一行一条目；坐标 = 全局指令序/全局变量索引（与表内一致），
// v = 组内版本序（1-based），kind = 定值指令种类（ALLOC/STORE/-）。
fn dump_entries_summary() {
    fi : ., mut = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        es := entry_start(fi);
        ec := entry_count(fi);
        print("== entries func "); print(int_str(fi)); print(" (");
        print(istr_get(r64(g_ir_func_name_idx, fi * 8))); print("): ");
        println(int_str(ec));
        ei : ., mut = 0;
        loop {
            if ei >= ec { break; }
            e := es + ei;
            gv := ent_var(e);
            ord : ., mut = 1;
            ej : ., mut = es;
            loop {
                if ej >= e { break; }
                if ent_var(ej) == gv { ord = ord + 1; }
                ej = ej + 1;
            }
            print(" e "); print(int_str(e));
            print(" var "); print(int_str(gv));
            vn := get_ir_var_name(gv);
            if str_len(vn) > 0 { print(" name="); print(vn); }
            print(" v "); print(int_str(ord));
            print(" def "); print(int_str(ent_def(e)));
            d := ent_def(e);
            if d >= 0 {
                if iri_op(d) == IR_ALLOC { print(" kind=ALLOC"); }
                else { print(" kind=STORE"); }
            } else {
                print(" kind=-");
            }
            print(" live "); print(int_str(ent_live_start(e))); print("..");
            print(int_str(ent_live_end(e)));
            print(" home "); print(int_str(ent_home(e)));
            print(" flags "); println(int_str(ent_flags(e)));
            ei = ei + 1;
        }
        fi = fi + 1;
    }
}

// ===== v6 Task 3：共存推导（存在区间相交；不落盘——D3 判定现算）=====
// 格层语义：共存 = 对称关系（无传递性，最弱理论）。条目的 live 区间为
// 闭区间 [ls, le]（全局指令序坐标——v6 NOD 坐标同源）。

// 单对查询：两条目存在区间相交 ⟺ ls1 ≤ le2 && ls2 ≤ le1（闭区间）。
// e1/e2 = 全局条目索引；func_i 保留兼容调用约定（跨函数指令区间天然
// 不重叠，无需按函数过滤）。判定四条之共存互斥的输入。
fn entries_coexist(func_i: int, e1: int, e2: int) -> int {
    if e1 < 0 || e2 < 0 { return 0; }
    if e1 == e2 { return 0; }
    s1 := ent_live_start(e1); n1 := ent_live_end(e1);
    s2 := ent_live_start(e2); n2 := ent_live_end(e2);
    if s1 < 0 || s2 < 0 { return 0; }
    if s1 <= n2 && s2 <= n1 { return 1; }
    return 0;
}

// 同 var 跨版本冲突数（数据自检）：版本按定值点切割，构造保证
// 版本 j 区间终点 = 版本 j+1 定值点 −1 < 其起点 → 相邻版本必不交。
// 返回 0 = 版本化正确（任何 >0 = 版本切割 bug）。O(n) 每 var 组。
fn coexist_version_conflicts(func_i: int) -> int {
    es := entry_start(func_i);
    ec := entry_count(func_i);
    conflicts : ., mut = 0;
    ei : ., mut = 0;
    loop {
        if ei >= ec { break; }
        e := es + ei;
        gv := ent_var(e);
        // 找同 var 的下一版本条目（版本按定值序相邻）
        ej : ., mut = ei + 1;
        loop {
            if ej >= ec { break; }
            if ent_var(es + ej) == gv {
                if entries_coexist(func_i, e, es + ej) != 0 {
                    conflicts = conflicts + 1;
                }
                break;
            }
            ej = ej + 1;
        }
        ei = ei + 1;
    }
    return conflicts;
}

// 同 home 组内冲突数（判定输入雏形——共存互斥：同槽条目不共存）。
// home = -1（未分配）不参与。真实成本注记（评审 I-2）：home ≥ 0 时对每函数
// 做 O(E²) 相等探测（与组大小 k 无关；当前无回填路径 = 内层不进入 = O(E)）。
// 触发点 = 判定进入消费端（分配器/自检回填 home 后）——届时须按 v6 格式定稿
// §4.2 per-group sweep O(k log k) 重写，不得直接复用本函数（ledger 门禁注记）。
fn coexist_home_conflicts(func_i: int) -> int {
    es := entry_start(func_i);
    ec := entry_count(func_i);
    conflicts : ., mut = 0;
    ei : ., mut = 0;
    loop {
        if ei >= ec { break; }
        e1 := es + ei;
        h1 := ent_home(e1);
        if h1 >= 0 {
            ej : ., mut = ei + 1;
            loop {
                if ej >= ec { break; }
                e2 := es + ej;
                if ent_home(e2) == h1 {
                    if entries_coexist(func_i, e1, e2) != 0 {
                        conflicts = conflicts + 1;
                    }
                }
                ej = ej + 1;
            }
        }
        ei = ei + 1;
    }
    return conflicts;
}

// --dump-coexist 调试通道（cir 命令调用，Task 3 测试载体）：
// 每函数输出版本冲突数（应 0）与同 home 组内冲突数（未分配时应 0）。
fn dump_coexist_summary() {
    fi : ., mut = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        print("== coexist func "); print(int_str(fi)); print(" (");
        print(istr_get(r64(g_ir_func_name_idx, fi * 8))); print("):");
        print(" ver_conf "); print(int_str(coexist_version_conflicts(fi)));
        print(" home_conf "); println(int_str(coexist_home_conflicts(fi)));
        fi = fi + 1;
    }
}

// ===== v6 Task 5：判定消费最小闭环（一致性自检——共 specs/
// regalloc-consistency.corespec 规约）=====
// 分配结果真相源 = g_opt_meta 的 OPT_KEY_REG_ASSIGN 对（var_idx → x86 寄存器号）：
// 后端 instr.cr 的 g2_slot/get_reg_for_var 在发射时按此把 var 落寄存器（corec 与
// corearch 共享同一 .ccr 传输这份 meta）——判定消费它就是消费「实际编码的分配」。
// （注：opt.cr:575 区头注释「IR 操作数改写为负编码」是过时设计残留——实现已改为
// 元数据表 + 后端 g2_slot 查询，判定按实现走。）
// 版本级 vs 变量级对齐（衔接决策 b）：alloc_registers 是变量级单区间分配，条目是
// 版本级。判定把分配结果按「条目所属 var」投影到版本条目上——同 var 多版本 = 同
// 位置组内多条（版本按定值切割互不共存，sweep 自然校验）；两条目同位置且共存 =
// 违反。变量级表述（同寄存器两 var 的 [first_ref,last_ref] 相交）与条目级表述在
// 变量级分配下等价（一 var 的版本区间并 = 其整活跃窗口），但条目级表述在分配器
// 升级为条目级（CAG，docs/regalloc-cache-mapping.md §五）后无需改动——版本条目
// 各自落位置，判定原样消费。③④（驱逐配对/调用点失效）按 brief 范围控制留 TODO：
// 现分配器无驱逐、只用 callee-saved（调用点平凡满足）——随 CAG 同批落地，判定
// 规约先行落文档（spec/regalloc-consistency.corespec R3/R4）。

LOC_HOME_BASE : int = 1000000;  // 位置编码：寄存器号直用（0..15）；home 槽偏移本常量
RPT_MAX : int = 8;              // 规则违反诊断每函数每规则打印上限（计数不封顶）

// 分配结果镜像解析（mirror instr.cr get_reg_for_var——corec 不含后端文件；
// 两处解析同一 g_opt_meta 布局，分配器升级统一 seam 时收敛）。
fn meta_reg_for_var(var_idx: int) -> int {
    mi : ., mut = 0;
    loop {
        if mi >= g_opt_meta_count { break; }
        mo := mi * OPT_META_STRIDE;
        mk := r32(g_opt_meta, mo);
        if mk == OPT_KEY_REG_ASSIGN {
            data_len := r32(g_opt_meta, mo + 4);
            di : ., mut = 4;  // skip count u32, pairs start at +4
            loop {
                if di >= data_len { break; }
                vi := r32(g_opt_meta, mo + 8 + di);
                if vi == var_idx {
                    return r32(g_opt_meta, mo + 8 + di + 4);
                }
                di = di + 8;
            }
        }
        mi = mi + 1;
    }
    return -1;
}

// 16B 记录比较（归并用）：key = (loc, entry 的 live_start)，均升序
fn rl_rec_lt(buf: string, a: int, b: int) -> int {
    la := r64(buf, a * 16); lb := r64(buf, b * 16);
    if la != lb { if la < lb { return 1; } return 0; }
    ea := r64(buf, a * 16 + 8); eb := r64(buf, b * 16 + 8);
    if ent_live_start(ea) < ent_live_start(eb) { return 1; }
    return 0;
}

// 自底向上归并排序（16B 记录 {loc:8, entry:8}）——O(k log k)，
// v6 格式定稿 §4.2 sweep 门禁（同位置组内检查不得逐对 O(E²)）。
fn rl_merge_sort(buf: string, n: int) {
    if n <= 1 { return; }
    tmp := alloc(n * 16);
    width : ., mut = 1;
    loop {
        if width >= n { break; }
        left : ., mut = 0;
        loop {
            if left >= n { break; }
            mid : ., mut = left + width; if mid > n { mid = n; }
            right : ., mut = left + width * 2; if right > n { right = n; }
            i : ., mut = left; j : ., mut = mid; k : ., mut = left;
            loop {
                if i >= mid || j >= right { break; }
                if rl_rec_lt(buf, i, j) != 0 {
                    w64(tmp, k * 16, r64(buf, i * 16));
                    w64(tmp, k * 16 + 8, r64(buf, i * 16 + 8));
                    i = i + 1;
                } else {
                    w64(tmp, k * 16, r64(buf, j * 16));
                    w64(tmp, k * 16 + 8, r64(buf, j * 16 + 8));
                    j = j + 1;
                }
                k = k + 1;
            }
            loop {
                if i >= mid { break; }
                w64(tmp, k * 16, r64(buf, i * 16));
                w64(tmp, k * 16 + 8, r64(buf, i * 16 + 8));
                i = i + 1; k = k + 1;
            }
            loop {
                if j >= right { break; }
                w64(tmp, k * 16, r64(buf, j * 16));
                w64(tmp, k * 16 + 8, r64(buf, j * 16 + 8));
                j = j + 1; k = k + 1;
            }
            left = right;
        }
        zi : ., mut = 0;
        loop {
            if zi >= n { break; }
            w64(buf, zi * 16, r64(tmp, zi * 16));
            w64(buf, zi * 16 + 8, r64(tmp, zi * 16 + 8));
            zi = zi + 1;
        }
        width = width * 2;
    }
}

// 打印位置描述（loc < LOC_HOME_BASE = 寄存器号；否则 home 槽）
fn rl_print_loc(loc: int) {
    if loc >= LOC_HOME_BASE {
        print("home slot "); print(int_str(loc - LOC_HOME_BASE));
    } else {
        print("reg "); print(int_str(loc));  // x86 寄存器枚举号（3=rbx, 12-15=r12-r15）
    }
}

fn rl_func_name(fi: int) {
    print("func "); print(int_str(fi)); print(" (");
    print(istr_get(r64(g_ir_func_name_idx, fi * 8))); print(")");
}

// 规则 ① 违反诊断（打印上限 RPT_MAX 防病理刷屏，计数不封顶）
fn rl_report_rule1(func_i: int, loc: int, e1: int, e2: int) {
    print("regalloc-consistency: "); rl_func_name(func_i);
    print(": rule 1 violation: entries "); print(int_str(e1));
    print(" (var "); print(int_str(ent_var(e1))); print(") and "); print(int_str(e2));
    print(" (var "); print(int_str(ent_var(e2))); print(") both at ");
    rl_print_loc(loc);
    print(", coexist ["); print(int_str(ent_live_start(e1))); print("..");
    print(int_str(ent_live_end(e1))); print("] x ["); print(int_str(ent_live_start(e2)));
    print(".."); print(int_str(ent_live_end(e2))); println("]");
}

// 规则 ② 违反诊断
fn rl_report_rule2(func_i: int, gv: int, inst: int) {
    print("regalloc-consistency: "); rl_func_name(func_i);
    print(": rule 2 violation: read of var "); print(int_str(gv));
    vn := get_ir_var_name(gv);
    if str_len(vn) > 0 { print(" name="); print(vn); }
    print(" at instr "); print(int_str(inst));
    println(" not covered by any active version entry");
}

// 规则 ②（框架）：寄存器驻留变量的读点必须有活跃版本覆盖。
// 读点 = 指令 i 以 v 为源操作数（IR_STORE 的 s1 是写目标，排除；dest 从不读）。
// 覆盖义务边界 = 首个版本化定值（IR_ALLOC/IR_STORE）之后——版本区间自定值点起
// 连续覆盖至 last_ref，义务内读点恒有版本（构造不变量）；义务前读窗口（ALLOC_
// ARRAY/ALLOC_STRUCT 等非版本化定值供给）待 compute_entries 按格式定稿 §4.1
// 「dest ≥ 0 = 定值点」升级后自动纳入——本检查零改动（TODO 注记同 plan Task 2）。
fn rl_rule2_func(func_i: int, vs: int, vc: int, ist: int, ic: int, es: int, ec: int) -> int {
    violations : ., mut = 0;
    lv : ., mut = 0;
    loop {
        if lv >= vc { break; }
        gv := vs + lv;
        if meta_reg_for_var(gv) < 0 { lv = lv + 1; continue; }
        // 收集该 var 的版本条目（def ≥ 0；表内按定值点升序）——先数再收集
        m : ., mut = 0;
        ei : ., mut = 0;
        loop {
            if ei >= ec { break; }
            e := es + ei;
            if ent_var(e) == gv && ent_def(e) >= 0 { m = m + 1; }
            ei = ei + 1;
        }
        if m <= 0 { lv = lv + 1; continue; }  // 无版本化定值：义务范围为空
        vers : string, mut = alloc(m * 8);
        vj : ., mut = 0;
        ei = 0;
        loop {
            if ei >= ec { break; }
            e := es + ei;
            if ent_var(e) == gv && ent_def(e) >= 0 {
                w64(vers, vj * 8, e);
                vj = vj + 1;
            }
            ei = ei + 1;
        }
        // 逐指令升序扫读点；版本游标单调推进（版本区间自 def 起无缝相接）。
        // 坐标注意（评审 F1 修复）：ent_def/ent_live_end 存全局指令坐标（ist+局部，
        // compute_entries 写入 inst = ist + ii）——比较必须用 inst 不得用局部 ii；
        // func 0 上 ist=0 使 ii == inst 掩盖该错配，非 func 0 函数上规则 ② 会失明
        // （只漏报不误报；回归 = test_live_ranges check_regalloc_read_gap_nonfunc0）。
        cursor : ., mut = 0;
        first_def := r64(vers, 0 * 8);
        ii : ., mut = 0;
        loop {
            if ii >= ic { break; }
            inst := ist + ii;
            op := iri_op(inst);
            rd : ., mut = 0;
            s1 := iri_s1(inst);
            s2 := iri_s2(inst);
            if s1 == gv && op != IR_STORE { rd = 1; }
            if s2 == gv { rd = 1; }
            if rd != 0 && inst >= ent_def(first_def) {
                // 推进游标至最后一个 def ≤ inst 的版本
                loop {
                    if cursor + 1 >= m { break; }
                    nx := r64(vers, (cursor + 1) * 8);
                    if ent_def(nx) > inst { break; }
                    cursor = cursor + 1;
                }
                cv := r64(vers, cursor * 8);
                if ent_live_end(cv) < inst {
                    if violations < RPT_MAX { rl_report_rule2(func_i, gv, inst); }
                    violations = violations + 1;
                }
            }
            ii = ii + 1;
        }
        lv = lv + 1;
    }
    return violations;
}

// 判定实现（0 = 一致 1 = 违反）——消费条目表（存在区间/home）+ 分配结果
// （g_opt_meta 投影）。precondition：alloc_registers() 已跑（条目表随算随新）。
fn verify_regalloc_consistency(func_i: int) -> int {
    if func_i < 0 || func_i >= g_ir_func_count { return 0; }
    es := entry_start(func_i);
    ec := entry_count(func_i);
    if ec <= 0 { return 0; }
    ic := r64(g_ir_func_instr_count, func_i * 8);
    ist := r64(g_ir_func_instr_start, func_i * 8);
    vc := r64(g_ir_func_var_count, func_i * 8);
    vs := r64(g_ir_func_var_start, func_i * 8);

    // 规则 ①：位置组 = 寄存器（meta 投影，loc = 寄存器号）∪ home（回填 seam，
    // loc = LOC_HOME_BASE + home）。收集有位置条目 → 按 (loc, live_start) 归并
    // 排序 → 同 loc 段内 ls 升序单遍维持最大 live_end：max_end ≥ 当前 ls ⟹ 相交。
    cnt : ., mut = 0;
    ei : ., mut = 0;
    loop {
        if ei >= ec { break; }
        e := es + ei;
        if ent_live_start(e) >= 0 && ent_live_end(e) >= 0 {
            v := ent_var(e);
            if meta_reg_for_var(v) >= 0 { cnt = cnt + 1; }
            else if ent_home(e) >= 0 { cnt = cnt + 1; }
        }
        ei = ei + 1;
    }
    rule1_viol : ., mut = 0;
    if cnt > 1 {
        rec : string, mut = alloc(cnt * 16);
        ci : ., mut = 0;
        ei = 0;
        loop {
            if ei >= ec { break; }
            e := es + ei;
            if ent_live_start(e) >= 0 && ent_live_end(e) >= 0 {
                v := ent_var(e);
                loc : ., mut = -1;
                rn := meta_reg_for_var(v);
                if rn >= 0 { loc = rn; }
                else if ent_home(e) >= 0 { loc = LOC_HOME_BASE + ent_home(e); }
                if loc >= 0 {
                    w64(rec, ci * 16, loc);
                    w64(rec, ci * 16 + 8, e);
                    ci = ci + 1;
                }
            }
            ei = ei + 1;
        }
        rl_merge_sort(rec, cnt);
        run_start : ., mut = 0;
        loop {
            if run_start >= cnt { break; }
            run_end : ., mut = run_start + 1;
            loop {
                if run_end >= cnt { break; }
                if r64(rec, run_end * 16) != r64(rec, run_start * 16) { break; }
                run_end = run_end + 1;
            }
            maxj : ., mut = -1;
            zi : ., mut = run_start;
            loop {
                if zi >= run_end { break; }
                e := r64(rec, zi * 16 + 8);
                if maxj >= 0 {
                    mej := r64(rec, maxj * 16 + 8);
                    if ent_live_end(mej) >= ent_live_start(e) {
                        if rule1_viol < RPT_MAX {
                            rl_report_rule1(func_i, r64(rec, zi * 16), mej, e);
                        }
                        rule1_viol = rule1_viol + 1;
                    }
                }
                if maxj < 0 || ent_live_end(e) > ent_live_end(r64(rec, maxj * 16 + 8)) {
                    maxj = zi;
                }
                zi = zi + 1;
            }
            run_start = run_end;
        }
    }

    // 规则 ②（框架）：寄存器驻留变量的读点活跃版本覆盖
    rule2_viol : ., mut = 0;
    if vc > 0 && ic > 0 {
        rule2_viol = rl_rule2_func(func_i, vs, vc, ist, ic, es, ec);
    }

    if rule1_viol > 0 || rule2_viol > 0 { return 1; }
    return 0;
}

// 全函数自检（O2 构建路径调用点）：0 = 全部一致；违反时打印诊断并返回违反
// 函数数。成功静默（自检通过 = 不打扰构建输出）。
fn regalloc_verify_all() -> int {
    bad : ., mut = 0;
    fi : ., mut = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        bad = bad + verify_regalloc_consistency(fi);
        fi = fi + 1;
    }
    return bad;
}

// ===== Task 5 测试钩子（cir --check-regalloc 载体专用注入；真实构建路径
// 永不调用——注入只存在于 cir debug 分支，不触碰生产分配器行为）=====
// 各注入在全部函数范围找目标（不假设 func 0 = 被测 main——按 cwd 解析差异，
// 标准库函数可能并入 IR 使 func 序移位；找「首个满足形状的函数」保证确定性）。

// 注入 ①-home 组冲突：取两条不同 var 的共存条目，home 置同一槽 7。
// 约束：两 var 均须 meta 未分配（寄存器驻留条目的位置 = 寄存器，位置判定优先；
// home 组是栈/驱逐槽 seam——与真实分配器行为同构：寄存器驻留条目不落 home）。
fn try_inject_home_conflict(func_i: int) -> int {
    es := entry_start(func_i);
    ec := entry_count(func_i);
    if ec < 2 { return 0; }
    e1i : ., mut = 0;
    loop {
        if e1i >= ec { break; }
        e1 := es + e1i;
        v1 := ent_var(e1);
        if meta_reg_for_var(v1) >= 0 { e1i = e1i + 1; continue; }
        e2i : ., mut = e1i + 1;
        loop {
            if e2i >= ec { break; }
            e2 := es + e2i;
            v2 := ent_var(e2);
            if v1 != v2 && meta_reg_for_var(v2) < 0 &&
               entries_coexist(func_i, e1, e2) != 0 {
                w32(g_ir_entries, e1 * ESZ_ENTRY + OFF_ENTRY_HOME, 7);
                w32(g_ir_entries, e2 * ESZ_ENTRY + OFF_ENTRY_HOME, 7);
                return 1;
            }
            e2i = e2i + 1;
        }
        e1i = e1i + 1;
    }
    return 0;
}

fn inject_home_conflict() -> int {
    fi : ., mut = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        if try_inject_home_conflict(fi) != 0 { return 1; }
        fi = fi + 1;
    }
    return 0;
}

// 追加一条 OPT_KEY_REG_ASSIGN 记录（格式同 alloc_registers 写侧；首个匹配即
// 生效——故伪造目标须是真实分配未覆盖的 var，后端 get_reg_for_var 同语义）
fn meta_append_reg_assign(var_idx: int, reg: int) {
    grow_opt_meta(g_opt_meta_count + 1);
    eo := g_opt_meta_count * OPT_META_STRIDE;
    store8(g_opt_meta, eo, 0); store8(g_opt_meta, eo + 1, 0);
    store8(g_opt_meta, eo + 2, 0); store8(g_opt_meta, eo + 3, 0);  // OPT_KEY_REG_ASSIGN=0
    dl : ., mut = 4 + 8;
    store8(g_opt_meta, eo + 4, dl % 256); store8(g_opt_meta, eo + 5, (dl / 256) % 256);
    store8(g_opt_meta, eo + 6, (dl / 65536) % 256); store8(g_opt_meta, eo + 7, (dl / 16777216) % 256);
    store8(g_opt_meta, eo + 8, 1); store8(g_opt_meta, eo + 9, 0);
    store8(g_opt_meta, eo + 10, 0); store8(g_opt_meta, eo + 11, 0);  // count = 1
    store8(g_opt_meta, eo + 12, var_idx % 256); store8(g_opt_meta, eo + 13, (var_idx / 256) % 256);
    store8(g_opt_meta, eo + 14, (var_idx / 65536) % 256); store8(g_opt_meta, eo + 15, (var_idx / 16777216) % 256);
    store8(g_opt_meta, eo + 16, reg % 256); store8(g_opt_meta, eo + 17, (reg / 256) % 256);
    store8(g_opt_meta, eo + 18, (reg / 65536) % 256); store8(g_opt_meta, eo + 19, (reg / 16777216) % 256);
    g_opt_meta_count = g_opt_meta_count + 1;
}

// 注入 ①-寄存器组冲突：找一对不同 var 的共存条目 (e1, e2)，向 g_opt_meta 追加
// 两个伪造 REG_ASSIGN 对：var(e1)→reg 3、var(e2)→reg 3 → 两 var 版本条目同组
// 同寄存器且共存 → 规则 ① 寄存器组违反。
// 注：不依赖真实分配器输出（2026-09-06 实测 alloc_registers 现分配结果恒为空——
// 见 opt.cr alloc 注记），自造 meta 保证注入确定；首个匹配语义 = 无冲突（新块
// 对未出现过对 var 生效）。注入仅存在于 cir debug 分支。
fn try_inject_reg_conflict(func_i: int) -> int {
    es := entry_start(func_i);
    ec := entry_count(func_i);
    if ec < 2 { return 0; }
    e1i : ., mut = 0;
    loop {
        if e1i >= ec { break; }
        e1 := es + e1i;
        v1 := ent_var(e1);
        e2i : ., mut = e1i + 1;
        loop {
            if e2i >= ec { break; }
            e2 := es + e2i;
            v2 := ent_var(e2);
            if v1 != v2 && entries_coexist(func_i, e1, e2) != 0 {
                meta_append_reg_assign(v1, 3);
                meta_append_reg_assign(v2, 3);
                return 1;
            }
            e2i = e2i + 1;
        }
        e1i = e1i + 1;
    }
    return 0;
}

fn inject_reg_conflict() -> int {
    fi : ., mut = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        if try_inject_reg_conflict(fi) != 0 { return 1; }
        fi = fi + 1;
    }
    return 0;
}

// 注入 ②-读点空洞：找 var——其最后一个版本条目（def ≥ 0 中 def 最大）
// live_end > def（定值后仍有读）——把该 var 置为寄存器驻留（伪造 meta 对
// var→reg 3，独立于真实分配输出）并把该版本 live_end 截断为 def → 其后的
// 读点无活跃版本覆盖 → 规则 ② 违反（规则 ① 不受扰：该 reg 组内只有此 var
// 自己的版本条目，版本间不共存）。
fn try_inject_read_gap(func_i: int) -> int {
    vc := r64(g_ir_func_var_count, func_i * 8);
    vs := r64(g_ir_func_var_start, func_i * 8);
    es := entry_start(func_i);
    ec := entry_count(func_i);
    lv : ., mut = 0;
    loop {
        if lv >= vc { break; }
        gv := vs + lv;
        // 该 var 最后一条 def ≥ 0 条目（表内定值点升序 → 末条即 def 最大）
        last : ., mut = -1;
        ei : ., mut = 0;
        loop {
            if ei >= ec { break; }
            e := es + ei;
            if ent_var(e) == gv && ent_def(e) >= 0 { last = e; }
            ei = ei + 1;
        }
        if last >= 0 && ent_live_end(last) > ent_def(last) {
            meta_append_reg_assign(gv, 3);
            w32(g_ir_entries, last * ESZ_ENTRY + OFF_ENTRY_LE, ent_def(last));
            return 1;
        }
        lv = lv + 1;
    }
    return 0;
}

fn inject_read_gap() -> int {
    fi : ., mut = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        if try_inject_read_gap(fi) != 0 { return 1; }
        fi = fi + 1;
    }
    return 0;
}

// ------------------------------------------------------------------
// Register allocation: rewrite IR operands to encode physical regs
// ------------------------------------------------------------------
// Rewrites g_ir_instrs operand fields: operands pointing to IR vars
// that should go in registers are replaced with negative register
// encodings (-1=rax, -2=rcx, -3=rdx, ...).
// Backend g2_slot() checks v < 0 and returns v directly as reg num.
// No backend decision-making needed — pure mechanical translation.

fn alloc_registers() {
    if g_opt_level < 1 { return; }
    // v6 数据基础：存在区间表先行（原内联 iv_buf 构建已提取为 compute_live_ranges）
    compute_live_ranges();
    fi : ., mut = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        ic := r64(g_ir_func_instr_count, fi * 8);
        ist := r64(g_ir_func_instr_start, fi * 8);
        vc := r64(g_ir_func_var_count, fi * 8);
        vs := r64(g_ir_func_var_start, fi * 8);
        if vc <= 0 { fi = fi + 1; continue; }

        // Use only callee-saved registers (preserved across function calls)
        // rbx(3), r12(12), r13(13), r14(14), r15(15) = 5 registers
        // (rsp/rbp excluded; caller-saved regs get clobbered by function calls)
        MAX_REGS : int = 5;
        reg_idx : ., mut = 0;
        reg_phys : string, mut = alloc(5 * 8);
        w64(reg_phys, 0, 3); w64(reg_phys, 8, 12);
        w64(reg_phys, 16, 13); w64(reg_phys, 24, 14); w64(reg_phys, 32, 15);

        // Map local var index → physical register (-1 = stack)
        var_reg : string, mut;    var_reg_cap : int, mut;
        vrc : ., mut = 64; if vc * 2 > vrc { vrc = vc * 2; }
        var_reg = alloc(vrc * 8); var_reg_cap = vrc;
        vr_clear : ., mut = 0;
        loop { if vr_clear >= vrc { break; } w64(var_reg, vr_clear * 8, -1); vr_clear = vr_clear + 1; }

        // Simple linear scan: for each instruction, allocate regs for dest
        vi : ., mut = 0;
        ii : ., mut = 0;
        loop {
            if ii >= ic { break; }
            inst := ist + ii;
            // 只读 dest——op/s1/s2 在本循环未用（评审 Minor：已清除的死赋值）
            d := iri_dest(inst);

            // Free regs for vars that end before this instruction
            vi = 0;
            loop { if vi >= vc { break; }
                if r64(var_reg, vi * 8) >= 0 {
                    last_ref := live_last(fi, vs + vi);
                    if last_ref < ii {
                        // Return reg to pool
                        w64(var_reg, vi * 8, -1);
                    }
                }
                vi = vi + 1; }

            // Allocate reg for dest if it has a live range
            if d >= vs && d < vs + vc {
                lvi := d - vs;
                if r64(var_reg, lvi * 8) < 0 {
                    first_ref := live_first(fi, d);
                    last_ref := live_last(fi, d);
                    if first_ref >= 0 && last_ref >= 0 && reg_idx < MAX_REGS {
                        w64(var_reg, lvi * 8, r64(reg_phys, reg_idx * 8));
                        reg_idx = reg_idx + 1;
                    }
                }
            }
            // (operands NOT rewritten — metadata stored separately)
            // Register assignments collected into g_opt_meta below.
            ii = ii + 1;
        }

        // Write register assignments to g_opt_meta (flat array of var_idx+reg_num pairs)
        // Store register assignments in g_opt_meta (simple format: var_idx,reg pairs)
        // ⚠️ 已知（2026-09-06 实测注记；措辞经评审 M2 收敛）：实测语料（tests/suite
        // 与自举构建语料）上 rc 恒为 0——instr 循环每步对 last_ref < ii 的已分配 var
        // 复位 var_reg（「归还」），循环末只保留末指令仍活跃的 var，实际无 var 存活
        // → g_opt_meta 无 REG_ASSIGN 对 → 后端全栈发射（正确但无寄存器加速）。
        // 「恒为 0」仅为上述语料的观测，非形式保证——防回退挂账（v6 Task 6 / CAG
        // 前）：分配器改动后须跑 --check-regalloc 载体核对 rc 汇总（g_opt_meta
        // REG_ASSIGN 对数 > 0）或加看门狗计数（全函数 rc==0 时告警），防止回归。
        // 本函数语义本轮不动（v6 Task 5 范围控制）；寄存器复用/回池修复随 CAG
        // 分配器升级（docs/regalloc-cache-mapping.md §五）同批——判定消费 seam
        // 已就绪（meta_reg_for_var/verify 按分配输出消费，届时自动接管）。
        rc : ., mut = 0;
        vi = 0;
        loop { if vi >= vc { break; }
            if r64(var_reg, vi * 8) >= 0 { rc = rc + 1; }
        vi = vi + 1; }
        if rc > 0 {
            ei : ., mut = g_opt_meta_count;
            grow_opt_meta(ei + 1);
            // Write key(u32) + data_len(u32) header using store8
            eo := ei * OPT_META_STRIDE;
            store8(g_opt_meta, eo, 0); store8(g_opt_meta, eo+1, 0);
            store8(g_opt_meta, eo+2, 0); store8(g_opt_meta, eo+3, 0);  // OPT_KEY_REG_ASSIGN=0
            dl : ., mut = 4 + rc * 8;
            store8(g_opt_meta, eo+4, dl%256); store8(g_opt_meta, eo+5, (dl/256)%256);
            store8(g_opt_meta, eo+6, (dl/65536)%256); store8(g_opt_meta, eo+7, (dl/16777216)%256);
            // Write count
            store8(g_opt_meta, eo+8, rc%256); store8(g_opt_meta, eo+9, (rc/256)%256);
            store8(g_opt_meta, eo+10, (rc/65536)%256); store8(g_opt_meta, eo+11, (rc/16777216)%256);
            // Write pairs: [var_idx(u32), reg(u32)]...
            di : ., mut = 12;  // after header(8) + count(4)
            vi = 0;
            loop { if vi >= vc { break; }
                rn := r64(var_reg, vi * 8);
                if rn >= 0 {
                    vw := vs + vi;
                    store8(g_opt_meta, eo+di, vw%256); store8(g_opt_meta, eo+di+1, (vw/256)%256);
                    store8(g_opt_meta, eo+di+2, (vw/65536)%256); store8(g_opt_meta, eo+di+3, (vw/16777216)%256);
                    store8(g_opt_meta, eo+di+4, rn%256); store8(g_opt_meta, eo+di+5, (rn/256)%256);
                    store8(g_opt_meta, eo+di+6, (rn/65536)%256); store8(g_opt_meta, eo+di+7, (rn/16777216)%256);
                    di = di + 8;
                }
            vi = vi + 1; }
            g_opt_meta_count = ei + 1;
        }
        fi = fi + 1;
    }
}

fn pass_stack_share() {
    if g_ir_func_count <= 0 { return; }

    // Allocate g_stack_map with -1 for all IR vars
    g_stack_map = alloc(g_ir_var_count * 8);
    svi : ., mut = 0;
    loop { if svi >= g_ir_var_count { break; } w64(g_stack_map, svi * 8, -1); svi = svi + 1; }

    fi : ., mut = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        ic := r64(g_ir_func_instr_count, fi * 8);
        ist := r64(g_ir_func_instr_start, fi * 8);
        vc := r64(g_ir_func_var_count, fi * 8);
        vs := r64(g_ir_func_var_start, fi * 8);
        if vc <= 0 || ic <= 0 { fi = fi + 1; continue; }

        // Build intervals for all vars (as in reg alloc)
        iv := alloc(vc * 16);
        zz : ., mut = 0;
        loop { if zz >= vc { break; } w64(iv, zz*16, -1); w64(iv, zz*16+8, -1); zz = zz + 1; }
        ii : ., mut = 0;
        loop {
            if ii >= ic { break; }
            inst := ist + ii;
            d := iri_dest(inst); s1 := iri_s1(inst); s2 := iri_s2(inst);
            vn : ., mut = 0;
            va : string, mut = alloc(24);    va_cap : int, mut = 3;
            if va_cap == 0 { va = alloc(24); va_cap = 3; }
            if d >= vs && d < vs+vc { if vn < va_cap { w64(va, vn * 8, d-vs); vn=vn+1; } }
            if s1 >= vs && s1 < vs+vc { if vn < va_cap { w64(va, vn * 8, s1-vs); vn=vn+1; } }
            if s2 >= vs && s2 < vs+vc { if vn < va_cap { w64(va, vn * 8, s2-vs); vn=vn+1; } }
            vi2 : ., mut = 0;
            loop { if vi2 >= vn { break; }
                lv := r64(va, vi2 * 8);
                if r64(iv, lv*16) < 0 { w64(iv, lv*16, ii); }
                w64(iv, lv*16+8, ii);
                vi2 = vi2 + 1; }
            ii = ii + 1; }

        // For each stack var, try to find another to share with
        vj1 : ., mut = 0;
        loop { if vj1 >= vc { break; }
            global_v1 := vs + vj1;
            // Skip if this var is in a register (negative encoding in IR means register)
            is_reg : ., mut = 0;
            // Check first instruction that uses this var
            first_ref := r64(iv, vj1*16);
            if first_ref >= 0 {
                inst_chk := ist + first_ref;
                if iri_dest(inst_chk) == global_v1 {
                    if iri_dest(inst_chk) < 0 { is_reg = 1; }
                } else if iri_s1(inst_chk) == global_v1 {
                    if iri_s1(inst_chk) < 0 { is_reg = 1; }
                } else if iri_s2(inst_chk) == global_v1 {
                    if iri_s2(inst_chk) < 0 { is_reg = 1; }
                }
            }
            if is_reg != 0 { vj1 = vj1 + 1; continue; }

            s1_start := r64(iv, vj1*16);
            s1_end := r64(iv, vj1*16+8);
            vj2 : ., mut = 0;
            loop { if vj2 >= vj1 { break; }
                s2_start := r64(iv, vj2*16);
                s2_end := r64(iv, vj2*16+8);
                // Check disjoint: s1 ends before s2 starts, or s2 ends before s1 starts
                if (s1_end < s2_start || s2_end < s1_start) && s1_start >= 0 && s2_start >= 0 {
                    // Map vj1 to use vj2's slot
                    w64(g_stack_map, (vs+vj1)*8, vs+vj2);
                    break;
                }
                vj2 = vj2 + 1; }
        vj1 = vj1 + 1; }
        fi = fi + 1; }
}

// ------------------------------------------------------------------
// Common subexpression elimination (CFIR)
// ------------------------------------------------------------------
fn pass_cse() {
    if g_ir_func_count <= 0 { return; }
    fi : ., mut = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        ic := r64(g_ir_func_instr_count, fi * 8);
        ist := r64(g_ir_func_instr_start, fi * 8);
        if ic <= 0 { fi = fi + 1; continue; }

        // CSE: track seen (op, s1, s2) → dest_var mapping
        // Simple linear scan — sufficient for O1
        seen_count : ., mut = 0;
        // Flat array: each entry = (op:8, s1:8, s2:8, dest:8) = 32 bytes
        seen : string, mut = alloc(ic * 32);
        // Replacement map: var → canonical var (8 bytes each)
        replace_map : string, mut = alloc(ic * 8);
        replace_count : ., mut = 0;

        ii : ., mut = 0;
        loop {
            if ii >= ic { break; }
            inst := ist + ii;
            op := iri_op(inst);
            d := iri_dest(inst);
            s1 := iri_s1(inst);
            s2 := iri_s2(inst);

            // Skip arena opcodes — side-effecting, not optimizable
            if op == IR_ARENA_NEW { ii = ii + 1; continue; }
            if op == IR_ARENA_RESET { ii = ii + 1; continue; }
            if op == IR_INLINE { ii = ii + 1; continue; }
            if op == IR_NO_BOUNDS_CHECK { ii = ii + 1; continue; }
            if op == IR_FAST { ii = ii + 1; continue; }
            if op == IR_UNROLL { ii = ii + 1; continue; }
            if op == IR_APPROX { ii = ii + 1; continue; }
            if op == IR_SECTION { ii = ii + 1; continue; }
            if op == IR_HOTPATCH_ROUTE { ii = ii + 1; continue; }
            if op == IR_DYN_TAG { ii = ii + 1; continue; }
            if op == IR_DYN_VAL { ii = ii + 1; continue; }
            if op == IR_DYN_PACK { ii = ii + 1; continue; }
            if op == IR_DYN_DISPATCH { ii = ii + 1; continue; }
            if op == IR_CALL_EXTERN { ii = ii + 1; continue; }
            if op == IR_LAZY_THUNK { ii = ii + 1; continue; }
            if op == IR_LAZY_FORCE { ii = ii + 1; continue; }
            if op == IR_FNADDR { ii = ii + 1; continue; }

            // Only CSE for pure computations: BINARY, UNARY
            if (op == IR_BINARY || op == IR_UNARY) && d >= 0 {
                // Check if we've seen this expression
                found : ., mut = -1;
                sj : ., mut = 0;
                loop {
                    if sj >= seen_count { break; }
                    so := sj * 32;
                    if r64(seen, so) == op && r64(seen, so+8) == s1 && r64(seen, so+16) == s2 {
                        found = sj; break;
                    }
                    sj = sj + 1;
                }
                if found >= 0 {
                    // Duplicate — record replacement: d → canonical dest
                    canonical := r64(seen, found * 32 + 24);
                    w64(replace_map, replace_count * 8, d);
                    w64(replace_map, replace_count * 8 + 8, canonical);
                    replace_count = replace_count + 1;
                    // NOP this instruction
                    iri_set_op(inst, IR_NOP);
                } else {
                    // New expression — record it
                    so := seen_count * 32;
                    w64(seen, so, op);
                    w64(seen, so+8, s1);
                    w64(seen, so+16, s2);
                    w64(seen, so+24, d);
                    seen_count = seen_count + 1;
                }
            }

            // Apply replacements to operands of ALL instructions
            if replace_count > 0 {
                rj : ., mut = 0;
                loop {
                    if rj >= replace_count { break; }
                    old_v := r64(replace_map, rj * 8);
                    new_v := r64(replace_map, rj * 8 + 8);
                    if iri_s1(inst) == old_v { iri_set_s1(inst, new_v); }
                    if iri_s2(inst) == old_v { iri_set_s2(inst, new_v); }
                    if iri_s3(inst) == old_v { iri_set_s3(inst, new_v); }
                    rj = rj + 1;
                }
            }

            ii = ii + 1;
        }
        fi = fi + 1;
    }
}

fn optimize_all() {
    // Pointer analysis (always runs, even at opt_level 0)
    ptr_analysis_all();
    // RegionCheck: verify DEREF targets are in live subgraphs
    region_check_all();
    // ProvenanceVerify: check DEREF offsets against allocation sizes
    provenance_verify_all();
    if g_opt_level < 1 { return; }
    fi : ., mut = 0;
    loop {
        if fi >= g_func_count { break; }
        fn_node := fi_ast_node(fi);
        body := ast_data(fn_node);  // function body
        ast_optimize_body(body);
        fi = fi + 1;
    }
    // pass_cse skipped — causes GPF in self-compiled binary
    if g_opt_level >= 2 {
        pass_cse();
        alloc_registers();
        pass_stack_share();
    }
}
