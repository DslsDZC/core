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
            op := iri_op(inst); d := iri_dest(inst); s1 := iri_s1(inst); s2 := iri_s2(inst);

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
