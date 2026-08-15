// === analysis.cr ===
// hover + go-to-definition：位置 → 令牌 → 符号表查询（Task 4）。
//
// 查询基于「最后一次成功检查」的快照（g_tokens / g_funcs / g_structs /
// g_enums / g_ast / g_types / g_files / g_seg_starts / g_seg_fileids /
// g_line_fileid / g_source），不触发检查、不修改前端状态。
//
// ── 坐标约定 ──
//   入口 line/col 为 LSP 0-based；g_tokens / AST 节点 / g_line_fileid 均
//   为 1-based，函数内部转换（+1 / -1）。
//
// ── 声明位置反查（执行时确认的路径）──
//   函数    —— fi_ast_node(fi) → EXPR_FN 节点 line/col（fn 关键字位置）。
//   结构体/枚举 —— g_ast 中【没有】声明节点（parser 的 struct/enum 分支只填
//   g_structs/g_enums 表，不 alloc_node）——brief 的「AST 顶层节点按名字
//   反查」路径不存在，改为扫 g_tokens：T_STRUCT/T_ENUM 关键字后紧跟同名
//   T_IDENT 令牌，取其 line/col。
//   局部变量 —— g_syms 在 check_all 后作用域已弹出（只剩顶层符号），改用
//   扫 g_ast：查同名的 EXPR_LET/EXPR_PARAM/EXPR_FOR 节点，取查询位置之前
//   最近的一个（近似块作用域）。
//
// ── 跨文件 ──
//   声明行 → g_line_fileid（拼接坐标行 → file_id）→ g_files 路径表；
//   行号减所在段的行偏移（g_seg_starts 字节偏移 + g_source 换行计数）还原
//   为目标文件自身坐标。主文件段 0 偏移为 0（LSP 文档行号与令牌行号一致——
//   res_imports 末尾会剥除 _import.cr 前导并重新 tokenize）。
//
// 注意（Python bootstrap 地雷）：所有字符串拼接走字面量初始化的累加器；
// 不引入名为 match 的变量（保留字 SIGSEGV）。

// ── 类型名（快照只读，不调 res_type_node——那会分配类型条目）──

// TY_* 常量 → 名字
fn analysis_tyname(ty: int) -> string {
    if ty == TY_INT { return "int"; }
    if ty == TY_FLOAT { return "float"; }
    if ty == TY_BOOL { return "bool"; }
    if ty == TY_STRING { return "string"; }
    if ty == TY_UNIT { return "unit"; }
    if ty == TY_NEVER { return "never"; }
    if ty == TY_CHAR { return "char"; }
    if ty == TI_DYN { return "dyn"; }
    return "?";
}

// 类型表索引 → 名字（TYP_BASE / TYP_NAMED / TYP_REF / TYP_PTR / TYP_SLICE /
// TYP_ARRAY / TYP_GENERIC_APPLY / TYP_GENERIC_PARAM / TYP_TUPLE）
fn analysis_type_name_ti(ti: int) -> string {
    k := get_type_kind(ti);
    if k < 0 { return "?"; }
    if k == TYP_BASE { return analysis_tyname(get_type_data(ti)); }
    if k == TYP_NAMED || k == TYP_GENERIC_PARAM { return istr_get(get_type_data(ti)); }
    if k == TYP_REF {
        out : string, mut = "&";
        if get_type_extra(ti) != 0 { out = out + "mut "; }
        out = out + analysis_type_name_ti(get_type_data(ti));
        return out;
    }
    if k == TYP_PTR {
        out : string, mut = "*";
        out = out + analysis_type_name_ti(get_type_data(ti));
        return out;
    }
    if k == TYP_SLICE {
        out : string, mut = "[]";
        out = out + analysis_type_name_ti(get_type_data(ti));
        return out;
    }
    if k == TYP_ARRAY {
        out : string, mut = analysis_type_name_ti(get_type_data(ti));
        out = out + "[";
        out = out + int_str(get_type_extra(ti));
        out = out + "]";
        return out;
    }
    if k == TYP_GENERIC_APPLY {
        return analysis_type_name_ti(get_type_data(ti));
    }
    if k == TYP_TUPLE {
        cnt := get_type_data(ti);
        out : string, mut = "(";
        e : ., mut = 0;
        loop {
            if e >= cnt { break; }
            if e > 0 { out = out + ", "; }
            out = out + analysis_type_name_ti(r64(g_gen_apply_data, (get_type_extra(ti) + e) * 8));
            e = e + 1;
        }
        out = out + ")";
        return out;
    }
    return "?";
}

// AST 类型节点 → 名字（快照只读；depth 防深链失控）
fn analysis_type_node_name(node: int, depth: int) -> string {
    if node < 0 || node >= g_ast_count || depth > 8 { return "?"; }
    k := ast_kind(node);
    if k == 0 { return analysis_tyname(ast_type_val(node)); }
    if k == EXPR_IDENT { return istr_get(ast_int_val(node)); }
    if k == EXPR_REFTYPE {
        out : string, mut = "&";
        if ast_data(node) != 0 { out = out + "mut "; }
        out = out + analysis_type_node_name(ast_a(node), depth + 1);
        return out;
    }
    if k == EXPR_PTRTYPE {
        out : string, mut = "*";
        out = out + analysis_type_node_name(ast_a(node), depth + 1);
        return out;
    }
    if k == EXPR_ARRAY {
        out : string, mut = "[";
        out = out + analysis_type_node_name(ast_a(node), depth + 1);
        if ast_int_val(node) != 0 {
            out = out + ";";
            out = out + int_str(ast_int_val(node));
        }
        out = out + "]";
        return out;
    }
    if k == EXPR_GENERIC_APPLY {
        out : string, mut = istr_get(ast_a(node));
        out = out + "<";
        ac : ., mut = 0;
        an : ., mut = ast_b(node);
        loop {
            if ac >= ast_c(node) { break; }
            if ac > 0 { out = out + ", "; }
            out = out + analysis_type_node_name(an, depth + 1);
            ac = ac + 1;
            an = an + 1;
        }
        out = out + ">";
        return out;
    }
    return "?";
}

// ── 令牌定位 ──

// 扫 g_tokens 找覆盖 (line, col)（0-based）的令牌，返回令牌索引；无则 -1。
// 匹配：令牌所在行 == line，且 col ∈ [令牌起点, 起点 + lexeme 长度)。
fn analysis_token_at(line: int, col: int) -> int {
    tl : ., mut = line + 1;
    tc : ., mut = col + 1;
    i : ., mut = 0;
    loop {
        if i >= g_token_count { return -1; }
        if r64(g_tokens, i * ESZ_TOKEN + OFF_TK_KIND) == T_EOF { return -1; }
        if r64(g_tokens, i * ESZ_TOKEN + OFF_TK_LINE) == tl {
            cl := r64(g_tokens, i * ESZ_TOKEN + OFF_TK_COL);
            lex := r64(g_tokens, i * ESZ_TOKEN + OFF_TK_LEXEME);
            w : ., mut = 1;
            if lex >= 0 { w = str_len(istr_get(lex)); }
            if tc >= cl && tc < cl + w { return i; }
        }
        i = i + 1;
    }
}

// ── 函数 hover ──

// EXPR_PARAM 节点 → 参数类型名
fn analysis_param_type_name(pn: int) -> string {
    tn := ast_data(pn);
    if tn > 0 && ast_kind(tn) != 0 { return analysis_type_node_name(tn, 0); }
    return analysis_tyname(ast_type_val(pn));
}

// 函数返回类型名（EXPR_FN type_val 槽 = 返回类型节点；0 = 无 -> 声明）
fn analysis_fn_ret_name(fi: int) -> string {
    fn_node := fi_ast_node(fi);
    if fn_node >= 0 && fn_node < g_ast_count {
        tn := ast_type_val(fn_node);
        if tn > 0 && tn < g_ast_count {
            if ast_kind(tn) != 0 { return analysis_type_node_name(tn, 0); }
            return analysis_tyname(ast_type_val(tn));
        }
    }
    return analysis_tyname(fi_return_type(fi));
}

// 函数签名："fn 名(参数类型, ...) -> 返回类型"
fn analysis_hover_fn(fi: int) -> string {
    out : string, mut = "fn ";
    out = out + istr_get(fi_name(fi));
    out = out + "(";
    first_param : ., mut = -1;
    param_count : ., mut = 0;
    fn_node := fi_ast_node(fi);
    if fn_node >= 0 && fn_node < g_ast_count {
        first_param = ast_b(fn_node);
        param_count = ast_c(fn_node);
    }
    pi : ., mut = 0;
    pn : ., mut = first_param;
    loop {
        if pi >= param_count { break; }
        if pn < 0 || pn >= g_ast_count { break; }
        if pi > 0 { out = out + ", "; }
        if ast_kind(pn) == EXPR_PARAM { out = out + analysis_param_type_name(pn); }
        pi = pi + 1;
        pn = pn + 1;
        // 参数节点不连续（类型节点插在中间）——顺延找下一个 EXPR_PARAM
        loop {
            if pn >= g_ast_count { break; }
            if ast_kind(pn) == EXPR_PARAM { break; }
            pn = pn + 1;
        }
    }
    out = out + ") -> ";
    out = out + analysis_fn_ret_name(fi);
    return out;
}

// 结构体 hover："struct 名 { 字段: 类型, ... }"
fn analysis_hover_struct(si: int) -> string {
    out : string, mut = "struct ";
    out = out + istr_get(si_name(si));
    out = out + " {";
    f : ., mut = 0;
    loop {
        if f >= si_field_count(si) { break; }
        out = out + " ";
        out = out + istr_get(si_field_name(si, f));
        out = out + ": ";
        tn := si_field_type_node(si, f);
        if tn > 0 && ast_kind(tn) != 0 { out = out + analysis_type_node_name(tn, 0); }
        else { out = out + analysis_tyname(si_field_type(si, f)); }
        out = out + ",";
        f = f + 1;
    }
    out = out + " }";
    return out;
}

// 枚举 hover："enum 名 { 变体, ... }"
fn analysis_hover_enum(ei: int) -> string {
    out : string, mut = "enum ";
    out = out + istr_get(ei_name(ei));
    out = out + " {";
    v : ., mut = 0;
    loop {
        if v >= ei_variant_count(ei) { break; }
        out = out + " ";
        out = out + istr_get(ei_variant_name(ei, v));
        out = out + ",";
        v = v + 1;
    }
    out = out + " }";
    return out;
}

// ── 局部变量（AST 反查）──

// 查声明 name_ni 的 AST 节点：EXPR_LET（a=名）/ EXPR_PARAM（a=名）/
// EXPR_FOR（a=变量名）；取 (line, col) <= 查询位置（0-based 转 1-based）
// 中最近的一个（近似作用域）。无则 -1。
fn analysis_var_decl(name_ni: int, line: int, col: int) -> int {
    tl : ., mut = line + 1;
    tc : ., mut = col + 1;
    best : ., mut = -1;
    bl : ., mut = -1;
    bc : ., mut = -1;
    i : ., mut = 0;
    loop {
        if i >= g_ast_count { break; }
        k := ast_kind(i);
        if k == EXPR_LET || k == EXPR_PARAM || k == EXPR_FOR {
            if ast_a(i) == name_ni {
                ln := ast_line(i);
                cl := ast_col(i);
                if ln < tl || (ln == tl && cl <= tc) {
                    if ln > bl || (ln == bl && cl > bc) {
                        best = i;
                        bl = ln;
                        bc = cl;
                    }
                }
            }
        }
        i = i + 1;
    }
    return best;
}

// 声明节点 → 变量类型名
fn analysis_var_type(vd: int, depth: int) -> string {
    if vd < 0 || depth > 8 { return "?"; }
    k := ast_kind(vd);
    if k == EXPR_PARAM {
        return analysis_param_type_name(vd);
    }
    if k == EXPR_FOR { return "int"; }
    if k == EXPR_LET {
        tn := ast_b(vd);
        if tn > 0 {
            if ast_kind(tn) != 0 { return analysis_type_node_name(tn, 0); }
            return analysis_tyname(ast_type_val(tn));
        }
        return analysis_type_of_expr(ast_c(vd), depth + 1);
    }
    return "?";
}

// 表达式 → 类型名（轻量恢复：字面量/调用/标识符转发/引用；depth 防环）
fn analysis_type_of_expr(node: int, depth: int) -> string {
    if node < 0 || depth > 8 { return "?"; }
    k := ast_kind(node);
    if k == EXPR_INT { return "int"; }
    if k == EXPR_FLOAT { return "float"; }
    if k == EXPR_BOOL { return "bool"; }
    if k == EXPR_STRING { return "string"; }
    if k == EXPR_CHAR { return "char"; }
    if k == EXPR_CALL {
        f := ast_a(node);
        if f >= 0 && ast_kind(f) == EXPR_IDENT {
            fi := find_func(ast_int_val(f));
            if fi >= 0 { return analysis_fn_ret_name(fi); }
        }
        return "?";
    }
    if k == EXPR_IDENT {
        vd := analysis_var_decl(ast_int_val(node), ast_line(node) - 1, ast_col(node) - 1);
        if vd >= 0 { return analysis_var_type(vd, depth + 1); }
        return "?";
    }
    if k == EXPR_UNARY && ast_c(node) == UOP_REF {
        out : string, mut = "&";
        out = out + analysis_type_of_expr(ast_a(node), depth + 1);
        return out;
    }
    return "?";
}

// ── hover ──

// 位置 → hover 内容：函数签名 / 变量类型 / 结构体字段 / 枚举变体；无结果空串
fn analysis_hover(line: int, col: int) -> string {
    ti := analysis_token_at(line, col);
    if ti < 0 { return ""; }
    if r64(g_tokens, ti * ESZ_TOKEN + OFF_TK_KIND) != T_IDENT { return ""; }
    name_ni := r64(g_tokens, ti * ESZ_TOKEN + OFF_TK_LEXEME);
    // 局部变量/参数优先（遮蔽函数/类型名）
    vd := analysis_var_decl(name_ni, line, col);
    if vd >= 0 {
        t := analysis_var_type(vd, 0);
        if str_len(t) > 0 { return t; }
    }
    // 函数
    fi := find_func(name_ni);
    if fi >= 0 { return analysis_hover_fn(fi); }
    // 结构体
    si := find_struct_by_name(name_ni);
    if si >= 0 { return analysis_hover_struct(si); }
    // 枚举
    ei := find_enum(name_ni);
    if ei >= 0 { return analysis_hover_enum(ei); }
    return "";
}

// ── definition ──

// 扫 g_tokens 找声明关键字（T_STRUCT/T_ENUM）后紧跟同名 T_IDENT 的令牌；
// 返回该名字令牌索引，无则 -1（g_ast 无结构体/枚举声明节点，见文件头注）
fn analysis_decl_tok(kw: int, name_ni: int) -> int {
    i : ., mut = 0;
    loop {
        if i + 1 >= g_token_count { return -1; }
        if r64(g_tokens, i * ESZ_TOKEN + OFF_TK_KIND) == kw {
            if r64(g_tokens, (i + 1) * ESZ_TOKEN + OFF_TK_KIND) == T_IDENT &&
               r64(g_tokens, (i + 1) * ESZ_TOKEN + OFF_TK_LEXEME) == name_ni {
                return i + 1;
            }
        }
        i = i + 1;
    }
}

// 1-based 行 → 文件路径（g_line_fileid → file_id → g_files）；兜底主文件
fn analysis_path_for_line(ln1: int) -> string {
    fid : ., mut = -1;
    if ln1 >= 1 && ln1 - 1 < g_line_count { fid = r64(g_line_fileid, (ln1 - 1) * 8); }
    if fid < 0 && g_file_count > 0 { fid = r64(g_files, 0); }
    i : ., mut = 0;
    loop {
        if i >= g_file_count { break; }
        if r64(g_files, i * 16) == fid {
            p := load_str_ptr(g_files, i * 16 + 8);
            if str_len(p) > 0 { return p; }
        }
        i = i + 1;
    }
    return "";
}

// 1-based 行 → 所在段在主文件后的行偏移（拼接坐标 → 目标文件自身坐标）
fn analysis_line_offset(ln1: int) -> int {
    fid : ., mut = -1;
    if ln1 >= 1 && ln1 - 1 < g_line_count { fid = r64(g_line_fileid, (ln1 - 1) * 8); }
    if fid < 0 { return 0; }
    i : ., mut = 1;
    loop {
        if i >= g_seg_count { break; }
        if r64(g_seg_fileids, i * 8) == fid {
            limit := r64(g_seg_starts, i * 8);
            off_lines : ., mut = 0;
            pos : ., mut = 0;
            loop {
                if pos >= limit { break; }
                if load8(g_source, pos) == 10 { off_lines = off_lines + 1; }
                pos = pos + 1;
            }
            return off_lines;
        }
        i = i + 1;
    }
    return 0;   // 主文件（段 0）：偏移 0
}

// 声明位置（1-based 拼接坐标）→ Location JSON；行/列转 0-based + 段偏移还原。
// uri 经 lsp_json_escape_str 转义（lsp.cr，同翻译单元——concat 顺序无关）。
fn analysis_def_json(ln1: int, cl1: int) -> string {
    off := analysis_line_offset(ln1);
    line0 : ., mut = ln1 - 1 - off;
    col0 : ., mut = cl1 - 1;
    uri : string, mut = "file://";
    uri = uri + analysis_path_for_line(ln1);
    out : string, mut = "{\"uri\":";
    out = out + lsp_json_escape_str(uri);
    out = out + ",\"range\":{\"start\":{\"line\":";
    out = out + int_str(line0);
    out = out + ",\"character\":";
    out = out + int_str(col0);
    out = out + "},\"end\":{\"line\":";
    out = out + int_str(line0);
    out = out + ",\"character\":";
    out = out + int_str(col0 + 1);
    out = out + "}}}";
    return out;
}

// 位置 → Location JSON（{"uri","range"}）；无结果空串
fn analysis_definition(line: int, col: int) -> string {
    ti := analysis_token_at(line, col);
    if ti < 0 { return ""; }
    if r64(g_tokens, ti * ESZ_TOKEN + OFF_TK_KIND) != T_IDENT { return ""; }
    name_ni := r64(g_tokens, ti * ESZ_TOKEN + OFF_TK_LEXEME);
    // 局部变量/参数
    vd := analysis_var_decl(name_ni, line, col);
    if vd >= 0 { return analysis_def_json(ast_line(vd), ast_col(vd)); }
    // 函数
    fi := find_func(name_ni);
    if fi >= 0 {
        fn_node := fi_ast_node(fi);
        if fn_node >= 0 && fn_node < g_ast_count {
            return analysis_def_json(ast_line(fn_node), ast_col(fn_node));
        }
        return "";
    }
    // 结构体 / 枚举（令牌反查声明）
    if find_struct_by_name(name_ni) >= 0 {
        d := analysis_decl_tok(T_STRUCT, name_ni);
        if d >= 0 {
            return analysis_def_json(r64(g_tokens, d * ESZ_TOKEN + OFF_TK_LINE),
                                     r64(g_tokens, d * ESZ_TOKEN + OFF_TK_COL));
        }
    }
    if find_enum(name_ni) >= 0 {
        d := analysis_decl_tok(T_ENUM, name_ni);
        if d >= 0 {
            return analysis_def_json(r64(g_tokens, d * ESZ_TOKEN + OFF_TK_LINE),
                                     r64(g_tokens, d * ESZ_TOKEN + OFF_TK_COL));
        }
    }
    return "";
}
