// === ccr_io.cr ===
// .ccr binary serialization — the interface between corec (frontend)
// and corearch (backend).
//
// v6 format（serialization v3；v6-only——load 校验 version==6，无 v5 兼容/转换）
// 字节真相 = docs/superpowers/specs/2026-09-05-lattice-ir-v6-format.md（设计定稿）
// + coreir-schema.md 家风格（Task 6 并入 schema）。v6.0 保守实施（v6 Task 4）：
// 段表架构 + 新增 ENT 段；SYM/REG 内容暂为 v5 记录装入段表（归并/坐标化 = 后续任务）。
// 全整数 LE；offset 相对文件头：
//   [header 16B]: magic u32 = "CCR1" | version u32 = 6 | seg_count u32 = 5 |
//                 reserved u32 = 0
//   [seg table 5×12B]: {tag u32, offset u32, size u32}——规范序（tag = 行号 1..5，
//                 offset = 上一段尾，段体紧随段表连续排列）
//   [seg bodies]（按段表寻址）:
//     STR(1) 字符串表：  [str_count u32] [× {len u32, data}]（同 v5）
//     SYM(2) 符号面（v6.0 未归并——v5 func_meta/structs/enums/globals + vars/
//              str_consts/opt_meta 自描述拼接，每小节自带计数）:
//       [func_count][func_count×28B name_idx/param_count/ret_type/instr_start/
//                    instr_count/var_start/var_count: u32×7]
//       [var_count][var_count×12B name_idx/id/type_kind: u32×3]  （局部 var 声明
//                    表——v6 目标并入 ENT「存在即声明」，未达）
//       [str_const_count][str_const_count×4B]
//       [struct_count][struct_count×{name u32, field_count u32,
//                      fields[field_count]×{name u32, type u32}}]
//       [enum_count][enum_count×{name u32, variant_count u32,
//                     variants[variant_count]×{name u32, type_count u32,
//                     types[type_count]×u32}}]
//       [global_count][global_count×16B {name_idx u32, var_idx u32, init_val i64}]
//       [opt_count][opt_count×{key u32, len u32, data lenB}]
//     NOD(3) 节点表：    [nod_count u32] [×28B {op i32, dest i32, src1 i64,
//                        src2 i32, src3 i32, tk i32}]——v5 instrs 内容不变；
//                        NOD id = 文件序索引 0..nod_count-1（图坐标 D1；ENT
//                        区间/def 即指此坐标）
//     ENT(4) 条目表：    [ent_count u32] [×28B {var_id i32, version u32,
//                        def_nod i32, live_start u32, live_end u32（半开：
//                        最后使用点+1）, home i32, flags u32}]
//                        内存表 24B/条（闭区间、无 version，opt.cr compute_entries）
//                        → 落盘：version = 同 var 组内定值升序序数（1-based），
//                        live_end_disk = live_end_mem + 1；盘上 7 字段 = 28B
//     REG(5) region 表： [sg_count u32] [×24B kind/enter/exit/parent/nstart/
//                        ncount: i32×6]——v5 SG 内容装入段表（记录重排/区内
//                        条目范围 = 后续坐标任务）
// 载荷约定（corec → corearch）：NOD 段 = v5 instrs 坐标化（字段同布局）——
// corearch 消费路径不变（本任务硬约束）；ENT 由 corearch 加载校验，发射不依赖。
// 与 v5 差异：固定 36B 头 + 定序段 → Header + 段表；entries 段新增。
//   v5 参考：magic/version=5/7 计数在固定偏移，本文件旧注释已废弃。

// --- Byte buffer helpers ---
// No bitwise ops in Core — use arithmetic instead.

CCR_MAGIC : int = 827474755;  // "CCR1" (0x31524343)
CCR_VERSION : int = 6;        // v6-only（load 校验 ==6；拒绝 v5——无转换工具）
CCR_SEG_COUNT : int = 5;      // STR SYM NOD ENT REG（规范序；预留 tag 6+ 不占空间）

// On-disk SG record size: 6 × i32 = 24 bytes (kind/enter/exit/parent/nstart/ncount).
// NOTE: the in-memory SG entry is ESZ_SG (48 bytes, u64 fields) — that is NOT
// the wire format. Always use ESZ_SG_DISK for .ccr size math, never ESZ_SG.
ESZ_SG_DISK : int = 24;

// On-disk ENT record: 7 × 4B = 28 bytes (var_id/version/def_nod/live_start/
// live_end/home/flags; version + 半开 live_end 由内存 24B 表转换，见文件头注释).
// The in-memory entry table is ESZ_ENTRY (24 bytes, no version field — the
// per-var ordinal is derivable from group order); disk record ≠ memory record.
ESZ_ENTRY_DISK : int = 28;

fn bw_byte(val: int, shift: int) -> int {
    if shift == 0 { return val % 256; }
    if shift >= 24 { return (val / 16777216) % 256; }
    if shift >= 16 { return (val / 65536) % 256; }
    if shift >= 8 { return (val / 256) % 256; }
    return 0;
}

fn buf_write_u32(buf: string, pos: int, val: int) {
    w32(buf, pos, val);
}

fn buf_write_i32(buf: string, pos: int, val: int) {
    w32(buf, pos, val);
}

fn buf_write_i64(buf: string, pos: int, val: int) {
    w64(buf, pos, val);
}

fn buf_read_u32(buf: string, pos: int) -> int {
    b0 := load8(buf, pos);
    b1 := load8(buf, pos + 1);
    b2 := load8(buf, pos + 2);
    b3 := load8(buf, pos + 3);
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

fn buf_read_i32(buf: string, pos: int) -> int {
    b0 := load8(buf, pos);
    b1 := load8(buf, pos + 1);
    b2 := load8(buf, pos + 2);
    b3 := load8(buf, pos + 3);
    val := b0 + b1 * 256 + b2 * 65536;
    if b3 >= 128 { return val + (b3 - 256) * 16777216; }
    return val + b3 * 16777216;
}

fn buf_read_i64(buf: string, pos: int) -> int {
    // Little-endian signed 64-bit. The low dword must be read UNSIGNED:
    // reading it signed (buf_read_i32) would double-subtract for negatives
    // (e.g. -7 = lo -7 + hi -1 → -7 + -2^32, not -7).
    b0 := load8(buf, pos);
    b1 := load8(buf, pos + 1);
    b2 := load8(buf, pos + 2);
    b3 := load8(buf, pos + 3);
    lo := b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
    h0 := load8(buf, pos + 4);
    h1 := load8(buf, pos + 5);
    h2 := load8(buf, pos + 6);
    h3 := load8(buf, pos + 7);
    hi : ., mut = h0 + h1 * 256 + h2 * 65536;
    if h3 >= 128 { hi = hi + (h3 - 256) * 16777216; }
    else { hi = hi + h3 * 16777216; }   // 修复 15：h3 < 128 时漏加 h3×2^24 → bit 56-62 丢失
    // Keep the factor within the parser's supported integer-literal range.
    hi_part := hi * 65536;
    hi_part = hi_part * 65536;
    return lo + hi_part;
}

// Check a byte range without forming an overflowing end position. CCR counts
// come from the file, so every variable-length section must use this helper
// before reading or growing an array from its count.
fn ccr_has_bytes(pos: int, need: int, fsize: int) -> int {
    if pos < 0 || need < 0 || pos > fsize { return 0; }
    if need > fsize - pos { return 0; }
    return 1;
}

fn ccr_i32_fits(val: int) -> int {
    if val < -2147483648 || val > 2147483647 { return 0; }
    return 1;
}

fn ccr_validate_i32_fields() -> int {
    ii : ., mut = 0;
    loop {
        if ii >= g_ir_instr_count { break; }
        if ccr_i32_fits(iri_dest(ii)) == 0 ||
           ccr_i32_fits(iri_s2(ii)) == 0 ||
           ccr_i32_fits(iri_s3(ii)) == 0 { return 0; }
        ii = ii + 1;
    }
    si : ., mut = 0;
    loop {
        if si >= g_sg_count { break; }
        f := si * ESZ_SG;
        if ccr_i32_fits(r64(g_sgs, f + OFF_SG_KIND)) == 0 ||
           ccr_i32_fits(r64(g_sgs, f + OFF_SG_ENTER)) == 0 ||
           ccr_i32_fits(r64(g_sgs, f + OFF_SG_EXIT)) == 0 ||
           ccr_i32_fits(r64(g_sgs, f + OFF_SG_PARENT)) == 0 ||
           ccr_i32_fits(r64(g_sgs, f + OFF_SG_NSTART)) == 0 ||
           ccr_i32_fits(r64(g_sgs, f + OFF_SG_NCOUNT)) == 0 { return 0; }
        si = si + 1;
    }
    return 1;
}

// --- Segment size calculation（段体大小；Header+段表 = 16 + 12×5 = 76）---
// 每段自带计数 u32；写侧与 calc 侧逐字节一致（v6 测试 walk 校验 end==fsize）。

fn ccr_str_seg_size() -> int {
    sz : ., mut = 4;  // str_count
    si : ., mut = 0;
    loop {
        if si >= g_str_count { break; }
        sz = sz + 4 + istr_len(si);
        si = si + 1;
    }
    return sz;
}

fn ccr_sym_seg_size() -> int {
    sz : ., mut = 4;  // func_count
    sz = sz + g_ir_func_count * 28;
    sz = sz + 4 + g_ir_var_count * 12;          // var_count + vars
    sz = sz + 4 + g_ir_str_const_count * 4;     // str_const_count + str_consts
    // structs: struct_count + {name, field_count, fields×8B}
    sz = sz + 4;
    sti : ., mut = 0;
    loop {
        if sti >= g_struct_count { break; }
        sz = sz + 8 + si_field_count(sti) * 8;
        sti = sti + 1;
    }
    // enums: enum_count + {name, variant_count, variants×{name, tc, types×4B}}
    sz = sz + 4;
    ei : ., mut = 0;
    loop {
        if ei >= g_enum_count { break; }
        vc := ei_variant_count(ei);
        sz = sz + 8;  // name + variant_count
        vi : ., mut = 0;
        loop {
            if vi >= vc { break; }
            tc := ei_variant_type_count(ei, vi);
            sz = sz + 8 + tc * 4;  // variant name + tc + types
            vi = vi + 1;
        }
        ei = ei + 1;
    }
    // globals: global_count + 16B each (name_idx, var_idx, init_val i64)
    sz = sz + 4 + g_ir_global_count * 16;
    // opt_meta: opt_count + {key, len, data}
    sz = sz + 4;
    mi : ., mut = 0;
    loop {
        if mi >= g_opt_meta_count { break; }
        sz = sz + 8 + r32(g_opt_meta, mi * OPT_META_STRIDE + 4);
        mi = mi + 1;
    }
    return sz;
}

fn ccr_nod_seg_size() -> int {
    return 4 + g_ir_instr_count * 28;
}

fn ccr_ent_seg_size() -> int {
    return 4 + g_entry_count * ESZ_ENTRY_DISK;
}

fn ccr_reg_seg_size() -> int {
    return 4 + g_sg_count * ESZ_SG_DISK;
}

// --- Size calculation（v6：16B header + 5×12B seg table + 各段体）---

fn calc_ccr_size() -> int {
    sz : ., mut = 16 + CCR_SEG_COUNT * 12;
    sz = sz + ccr_str_seg_size();
    sz = sz + ccr_sym_seg_size();
    sz = sz + ccr_nod_seg_size();
    sz = sz + ccr_ent_seg_size();
    sz = sz + ccr_reg_seg_size();
    return sz;
}

// --- Entry-table accessors（内存 24B 表读；不能调 opt.cr 的 ent_var——corearch
// 二进制不含 opt.cr，本文件为双端共享。写侧 w32/读侧 buf_read_i32（符号扩展），
// 与 opt.cr ent_* 一致（r32 在 bootstrap 产物中零扩展，见 opt.cr 注记））---
fn ccr_ent_var(e: int) -> int { return buf_read_i32(g_ir_entries, e * ESZ_ENTRY + OFF_ENTRY_VAR); }
fn ccr_ent_def(e: int) -> int { return buf_read_i32(g_ir_entries, e * ESZ_ENTRY + OFF_ENTRY_DEF); }
fn ccr_ent_ls(e: int) -> int { return buf_read_i32(g_ir_entries, e * ESZ_ENTRY + OFF_ENTRY_LS); }
fn ccr_ent_le(e: int) -> int { return buf_read_i32(g_ir_entries, e * ESZ_ENTRY + OFF_ENTRY_LE); }
fn ccr_ent_home(e: int) -> int { return buf_read_i32(g_ir_entries, e * ESZ_ENTRY + OFF_ENTRY_HOME); }
fn ccr_ent_flags(e: int) -> int { return buf_read_i32(g_ir_entries, e * ESZ_ENTRY + OFF_ENTRY_FLAGS); }

// grow 副本（corearch 无 opt.cr；语义同 opt.cr grow_entries/grow_func_entry_meta）
fn ccr_grow_entries(needed: int) {
    if needed < g_entry_cap { return; }
    nc : ., mut = g_entry_cap * 2; if nc < 64 { nc = 64; } if nc < needed { nc = needed + 64; }
    nb := alloc(nc * ESZ_ENTRY); _dyncpy(g_ir_entries, g_entry_cap * ESZ_ENTRY, nb);
    g_ir_entries = nb; g_entry_cap = nc;
}

fn ccr_grow_func_entry_meta(needed: int) {
    if needed < g_ir_func_entry_cap { return; }
    nc : ., mut = g_ir_func_entry_cap * 2; if nc < 64 { nc = 64; } if nc < needed { nc = needed + 64; }
    sz := nc * 8;
    n1 := alloc(sz); _dyncpy(g_ir_func_entry_start, g_ir_func_entry_cap * 8, n1); g_ir_func_entry_start = n1;
    n2 := alloc(sz); _dyncpy(g_ir_func_entry_count, g_ir_func_entry_cap * 8, n2); g_ir_func_entry_count = n2;
    g_ir_func_entry_cap = nc;
}

// --- Save（写侧与 calc 侧一致；段表规范序、段体连续）---

fn save_ccr(path: string) -> int {
    // The v5 wire format stores these fields as signed i32. Refuse to emit a
    // lossy file instead of letting w32 silently keep only the low bits.
    if ccr_validate_i32_fields() == 0 { return -1; }

    // Entries must be computed before save（lower_to_ccr 尾部无条件计算）——
    // 内存表 24B/条闭区间；落盘转换在此做（version 序数、live_end 半开 +1）。
    // 拒发损坏表：var 越界 / 区间反序（le < ls 或 ls < 0）都是内部错误。
    ei : ., mut = 0;
    loop {
        if ei >= g_entry_count { break; }
        ev := ccr_ent_var(ei);
        els := ccr_ent_ls(ei);
        ele := ccr_ent_le(ei);
        if ev < 0 || ev >= g_ir_var_count { return -1; }
        if els < 0 || ele < els { return -1; }
        ei = ei + 1;
    }

    tsz := calc_ccr_size();
    buf := alloc(tsz);
    pos : ., mut = 0;

    // Header（16B）
    buf_write_u32(buf, pos, CCR_MAGIC); pos = pos + 4;
    buf_write_u32(buf, pos, CCR_VERSION); pos = pos + 4;
    buf_write_u32(buf, pos, CCR_SEG_COUNT); pos = pos + 4;
    buf_write_u32(buf, pos, 0); pos = pos + 4;  // reserved

    // 段体大小（与 calc_ccr_size 同一来源逐段一致）
    s1 := ccr_str_seg_size();
    s2 := ccr_sym_seg_size();
    s3 := ccr_nod_seg_size();
    s4 := ccr_ent_seg_size();
    s5 := ccr_reg_seg_size();

    // Seg table（5 × 12B；offset = 前段尾，从段表后起）
    o1 : ., mut = 16 + CCR_SEG_COUNT * 12;
    o2 : ., mut = o1 + s1;
    o3 : ., mut = o2 + s2;
    o4 : ., mut = o3 + s3;
    o5 : ., mut = o4 + s4;

    buf_write_u32(buf, pos, 1); buf_write_u32(buf, pos + 4, o1); buf_write_u32(buf, pos + 8, s1); pos = pos + 12;
    buf_write_u32(buf, pos, 2); buf_write_u32(buf, pos + 4, o2); buf_write_u32(buf, pos + 8, s2); pos = pos + 12;
    buf_write_u32(buf, pos, 3); buf_write_u32(buf, pos + 4, o3); buf_write_u32(buf, pos + 8, s3); pos = pos + 12;
    buf_write_u32(buf, pos, 4); buf_write_u32(buf, pos + 4, o4); buf_write_u32(buf, pos + 8, s4); pos = pos + 12;
    buf_write_u32(buf, pos, 5); buf_write_u32(buf, pos + 4, o5); buf_write_u32(buf, pos + 8, s5); pos = pos + 12;

    // === STR: strings ===
    buf_write_u32(buf, pos, g_str_count); pos = pos + 4;
    si : ., mut = 0;
    loop {
        if si >= g_str_count { break; }
        sl := istr_len(si);
        buf_write_u32(buf, pos, sl); pos = pos + 4;
        ci : ., mut = 0;
        loop {
            if ci >= sl { break; }
            store8(buf, pos, str_load8(si, ci));
            pos = pos + 1;
            ci = ci + 1;
        }
        si = si + 1;
    }

    // === SYM: func meta ===
    buf_write_u32(buf, pos, g_ir_func_count); pos = pos + 4;
    fi : ., mut = 0;
    loop {
        if fi >= g_ir_func_count { break; }
        buf_write_u32(buf, pos, r64(g_ir_func_name_idx, fi * 8)); pos = pos + 4;
        buf_write_u32(buf, pos, r64(g_ir_func_param_count, fi * 8)); pos = pos + 4;
        buf_write_u32(buf, pos, r64(g_ir_func_ret_type, fi * 8)); pos = pos + 4;
        buf_write_u32(buf, pos, r64(g_ir_func_instr_start, fi * 8)); pos = pos + 4;
        buf_write_u32(buf, pos, r64(g_ir_func_instr_count, fi * 8)); pos = pos + 4;
        buf_write_u32(buf, pos, r64(g_ir_func_var_start, fi * 8)); pos = pos + 4;
        buf_write_u32(buf, pos, r64(g_ir_func_var_count, fi * 8)); pos = pos + 4;
        fi = fi + 1;
    }

    // === SYM: IR variables ===
    buf_write_u32(buf, pos, g_ir_var_count); pos = pos + 4;
    vi : ., mut = 0;
    loop {
        if vi >= g_ir_var_count { break; }
        buf_write_u32(buf, pos, irv_name(vi)); pos = pos + 4;
        buf_write_u32(buf, pos, irv_id(vi)); pos = pos + 4;
        buf_write_u32(buf, pos, irv_type(vi)); pos = pos + 4;
        vi = vi + 1;
    }

    // === SYM: string constants ===
    buf_write_u32(buf, pos, g_ir_str_const_count); pos = pos + 4;
    sci : ., mut = 0;
    loop {
        if sci >= g_ir_str_const_count { break; }
        buf_write_u32(buf, pos, r64(g_ir_str_consts, sci * 8)); pos = pos + 4;
        sci = sci + 1;
    }

    // === SYM: structs ===
    buf_write_u32(buf, pos, g_struct_count); pos = pos + 4;
    sti : ., mut = 0;
    loop {
        if sti >= g_struct_count { break; }
        fc := si_field_count(sti);
        buf_write_u32(buf, pos, si_name(sti)); pos = pos + 4;
        buf_write_u32(buf, pos, fc); pos = pos + 4;
        fii : ., mut = 0;
        loop {
            if fii >= fc { break; }
            buf_write_u32(buf, pos, si_field_name(sti, fii)); pos = pos + 4;
            buf_write_u32(buf, pos, si_field_type(sti, fii)); pos = pos + 4;
            fii = fii + 1;
        }
        sti = sti + 1;
    }

    // === SYM: enums ===
    buf_write_u32(buf, pos, g_enum_count); pos = pos + 4;
    ei2 : ., mut = 0;
    loop {
        if ei2 >= g_enum_count { break; }
        vc := ei_variant_count(ei2);
        buf_write_u32(buf, pos, ei_name(ei2)); pos = pos + 4;
        buf_write_u32(buf, pos, vc); pos = pos + 4;
        vi2 : ., mut = 0;
        loop {
            if vi2 >= vc { break; }
            tcnt := ei_variant_type_count(ei2, vi2);
            buf_write_u32(buf, pos, ei_variant_name(ei2, vi2)); pos = pos + 4;
            buf_write_u32(buf, pos, tcnt); pos = pos + 4;
            tf : ., mut = 0;
            loop {
                if tf >= tcnt { break; }
                buf_write_u32(buf, pos, ei_variant_type(ei2, vi2, tf)); pos = pos + 4;
                tf = tf + 1;
            }
            vi2 = vi2 + 1;
        }
        ei2 = ei2 + 1;
    }

    // === SYM: globals（16B each: name_idx u32, var_idx u32, init_val i64）===
    buf_write_u32(buf, pos, g_ir_global_count); pos = pos + 4;
    gi : ., mut = 0;
    loop {
        if gi >= g_ir_global_count { break; }
        buf_write_u32(buf, pos, r64(g_ir_globals, gi * 24)); pos = pos + 4;     // name_idx
        buf_write_u32(buf, pos, r64(g_ir_globals, gi * 24 + 8)); pos = pos + 4; // var_idx
        buf_write_i64(buf, pos, r64(g_ir_globals, gi * 24 + 16)); pos = pos + 8; // init_val
        gi = gi + 1;
    }

    // === SYM: opt_meta ===
    buf_write_u32(buf, pos, g_opt_meta_count); pos = pos + 4;
    mi : ., mut = 0;
    loop {
        if mi >= g_opt_meta_count { break; }
        mo := mi * OPT_META_STRIDE;
        mk := r32(g_opt_meta, mo);       // key (u8 padded to u64)
        md_len := r32(g_opt_meta, mo + 4); // data length
        buf_write_u32(buf, pos, mk); pos = pos + 4;
        buf_write_u32(buf, pos, md_len); pos = pos + 4;
        di : ., mut = 0;
        loop { if di >= md_len { break; }
            store8(buf, pos, load8(g_opt_meta, mo + 8 + di));
            pos = pos + 1;
            di = di + 1;
        }
        mi = mi + 1;
    }

    // === NOD: instructions（28B each；NOD id = 文件序 = 全局指令序）===
    buf_write_u32(buf, pos, g_ir_instr_count); pos = pos + 4;
    ii : ., mut = 0;
    loop {
        if ii >= g_ir_instr_count { break; }
        buf_write_u32(buf, pos, iri_op(ii)); pos = pos + 4;
        buf_write_i32(buf, pos, iri_dest(ii)); pos = pos + 4;
        // 修复 14：s1 改 64 位——IR_CONST 的大 int 常量 / float 位模式
        // 之前被截断成 32 位（float 常量静默损坏）
        buf_write_i64(buf, pos, iri_s1(ii)); pos = pos + 8;
        buf_write_i32(buf, pos, iri_s2(ii)); pos = pos + 4;
        buf_write_i32(buf, pos, iri_s3(ii)); pos = pos + 4;
        buf_write_u32(buf, pos, iri_tk(ii)); pos = pos + 4;
        ii = ii + 1;
    }

    // === ENT: entries（28B each；内存闭区间 → 盘上：version 组内序数、live_end+1 半开）===
    // 版本序数：每 var 一张计数槽（var 全局槽 id 唯一属一个函数——组内序 = 全局序）
    buf_write_u32(buf, pos, g_entry_count); pos = pos + 4;
    vcnt : string, mut = alloc((g_ir_var_count + 8) * 8);
    vz : ., mut = 0;
    loop {
        if vz >= g_ir_var_count + 8 { break; }
        w64(vcnt, vz * 8, 0);
        vz = vz + 1;
    }
    ej : ., mut = 0;
    loop {
        if ej >= g_entry_count { break; }
        ev := ccr_ent_var(ej);
        ed := ccr_ent_def(ej);
        els := ccr_ent_ls(ej);
        ele := ccr_ent_le(ej);
        eho := ccr_ent_home(ej);
        efl := ccr_ent_flags(ej);
        ord := r64(vcnt, ev * 8) + 1;
        w64(vcnt, ev * 8, ord);
        buf_write_i32(buf, pos, ev); pos = pos + 4;      // var_id
        buf_write_u32(buf, pos, ord); pos = pos + 4;     // version（1-based）
        buf_write_i32(buf, pos, ed); pos = pos + 4;      // def_nod（-1 = 无定值）
        buf_write_u32(buf, pos, els); pos = pos + 4;     // live_start（含定值）
        buf_write_u32(buf, pos, ele + 1); pos = pos + 4; // live_end（半开 = 内存闭区间 +1）
        buf_write_i32(buf, pos, eho); pos = pos + 4;     // home（-1 = 未分配）
        buf_write_u32(buf, pos, efl); pos = pos + 4;     // flags
        ej = ej + 1;
    }

    // === REG: sgs（24B each）===
    buf_write_u32(buf, pos, g_sg_count); pos = pos + 4;
    si2 : ., mut = 0;
    loop {
        if si2 >= g_sg_count { break; }
        f := si2 * ESZ_SG;
        buf_write_i32(buf, pos, r64(g_sgs, f + OFF_SG_KIND)); pos = pos + 4;
        buf_write_i32(buf, pos, r64(g_sgs, f + OFF_SG_ENTER)); pos = pos + 4;
        buf_write_i32(buf, pos, r64(g_sgs, f + OFF_SG_EXIT)); pos = pos + 4;
        buf_write_i32(buf, pos, r64(g_sgs, f + OFF_SG_PARENT)); pos = pos + 4;
        buf_write_i32(buf, pos, r64(g_sgs, f + OFF_SG_NSTART)); pos = pos + 4;
        buf_write_i32(buf, pos, r64(g_sgs, f + OFF_SG_NCOUNT)); pos = pos + 4;
        si2 = si2 + 1;
    }

    // Use syscall directly (write_file uses str_len which stops at null)
    fd := syscall3(2, path, 577, 420);  // open(O_WRONLY|O_CREAT|O_TRUNC, 0644)
    if fd < 0 { return -1; }
    written : ., mut = 0;
    written = syscall3(1, fd, buf, tsz);  // write(fd, buf, tsz)
    r2 := syscall3(3, fd, 0, 0);  // close(fd)
    if written != tsz { return -1; }
    return 0;
}

// --- Load（v6-only：校验 Header + 段表规范布局 + 逐段越界拒绝）---
// 段体内容 = 对应 v5 段记录（STR/SYM/NOD/REG），解析逻辑与 v5 load 逐行一致；
// ENT 盘上 28B → 内存 24B 表（去掉 version、live_end 半开转回闭区间 −1）。

fn load_ccr(data: string, fsize: int) -> int {
    if fsize < 16 { return -1; }  // header

    pos : ., mut = 0;

    // Magic
    magic := buf_read_u32(data, pos); pos = pos + 4;
    if magic != CCR_MAGIC { return -1; }

    // Version — v6-only（无 v5 兼容/转换工具）
    ver := buf_read_u32(data, pos); pos = pos + 4;
    if ver != CCR_VERSION { return -1; }

    // Seg count + reserved
    seg_cnt := buf_read_u32(data, pos); pos = pos + 4;
    rsv := buf_read_u32(data, pos); pos = pos + 4;
    if seg_cnt > (fsize - 16) / 12 { return -1; }

    // 段表：规范布局——tag 必须 = 行号（1..），offset 必须 = 前段尾，段不越界。
    // （段表 {tag, offset, size} 结构本身允段序自由，v6.0 writer 只用规范序——
    // loader 按规范序校验，非规范布局一律拒绝。）
    seg_off1 : ., mut = 0; seg_off2 : ., mut = 0; seg_off3 : ., mut = 0;
    seg_off4 : ., mut = 0; seg_off5 : ., mut = 0;
    seg_end1 : ., mut = 0; seg_end2 : ., mut = 0; seg_end3 : ., mut = 0;
    seg_end4 : ., mut = 0; seg_end5 : ., mut = 0;
    have1 : ., mut = 0; have2 : ., mut = 0; have3 : ., mut = 0;
    have4 : ., mut = 0; have5 : ., mut = 0;
    cursor : ., mut = 16 + seg_cnt * 12;
    ri : ., mut = 0;
    loop {
        if ri >= seg_cnt { break; }
        if !ccr_has_bytes(pos, 12, fsize) { return -1; }
        tg := buf_read_u32(data, pos); pos = pos + 4;
        soff := buf_read_u32(data, pos); pos = pos + 4;
        ssz := buf_read_u32(data, pos); pos = pos + 4;
        if tg < 1 || tg > 5 { return -1; }
        if tg != ri + 1 { return -1; }              // 规范 tag 序
        if soff != cursor { return -1; }            // 段体连续
        if ssz > fsize - cursor { return -1; }      // 越界拒绝
        // 重复 tag 防御（规范序下不可能，双保险）
        if tg == 1 { if have1 != 0 { return -1; } seg_off1 = soff; seg_end1 = soff + ssz; have1 = 1; }
        if tg == 2 { if have2 != 0 { return -1; } seg_off2 = soff; seg_end2 = soff + ssz; have2 = 1; }
        if tg == 3 { if have3 != 0 { return -1; } seg_off3 = soff; seg_end3 = soff + ssz; have3 = 1; }
        if tg == 4 { if have4 != 0 { return -1; } seg_off4 = soff; seg_end4 = soff + ssz; have4 = 1; }
        if tg == 5 { if have5 != 0 { return -1; } seg_off5 = soff; seg_end5 = soff + ssz; have5 = 1; }
        cursor = soff + ssz;
        ri = ri + 1;
    }

    // STR/SYM/NOD 必备；ENT/REG 可缺（v5 兼容精神：旧段缺失 = 空）
    if have1 == 0 || have2 == 0 || have3 == 0 { return -1; }
    if have4 == 0 { seg_off4 = 0; seg_end4 = 0; }
    if have5 == 0 { seg_off5 = 0; seg_end5 = 0; }

    // 状态重置（corearch 单次加载；保持可重入）
    g_str_count = 0;
    g_ir_var_count = 0;
    g_ir_instr_count = 0;
    g_ir_func_count = 0;
    g_ir_str_const_count = 0;
    g_struct_count = 0;
    g_enum_count = 0;
    g_sg_count = 0;
    g_ir_global_count = 0;
    g_opt_meta_count = 0;
    g_entry_count = 0;

    // === STR: strings ===
    pos = seg_off1;
    if !ccr_has_bytes(pos, 4, seg_end1) { return -1; }
    str_cnt := buf_read_u32(data, pos); pos = pos + 4;
    si : ., mut = 0;
    loop {
        if si >= str_cnt { break; }
        if !ccr_has_bytes(pos, 4, seg_end1) { return -1; }
        sl := buf_read_u32(data, pos); pos = pos + 4;
        if !ccr_has_bytes(pos, sl, seg_end1) { return -1; }
        // Allocate buffer for string content
        s := alloc(sl + 1);
        ci : ., mut = 0;
        loop {
            if ci >= sl { break; }
            store8(s, ci, load8(data, pos));
            pos = pos + 1;
            ci = ci + 1;
        }
        store8(s, sl, 0);
        str_intern(s);
        si = si + 1;
    }

    // === SYM: func meta（28B each）===
    pos = seg_off2;
    if !ccr_has_bytes(pos, 4, seg_end2) { return -1; }
    func_cnt := buf_read_u32(data, pos); pos = pos + 4;
    if func_cnt > (seg_end2 - seg_off2) / 28 { return -1; }
    grow_ir_func_meta(func_cnt);
    fi : ., mut = 0;
    loop {
        if fi >= func_cnt { break; }
        if !ccr_has_bytes(pos, 28, seg_end2) { return -1; }
        fv0 := buf_read_u32(data, pos); pos = pos + 4; w64(g_ir_func_name_idx, fi * 8, fv0);
        fv1 := buf_read_u32(data, pos); pos = pos + 4; w64(g_ir_func_param_count, fi * 8, fv1);
        fv2 := buf_read_u32(data, pos); pos = pos + 4; w64(g_ir_func_ret_type, fi * 8, fv2);
        fv3 := buf_read_u32(data, pos); pos = pos + 4; w64(g_ir_func_instr_start, fi * 8, fv3);
        fv4 := buf_read_u32(data, pos); pos = pos + 4; w64(g_ir_func_instr_count, fi * 8, fv4);
        fv5 := buf_read_u32(data, pos); pos = pos + 4; w64(g_ir_func_var_start, fi * 8, fv5);
        fv6 := buf_read_u32(data, pos); pos = pos + 4; w64(g_ir_func_var_count, fi * 8, fv6);
        g_ir_func_count = fi + 1;
        fi = fi + 1;
    }

    // === SYM: IR variables（12B each）===
    if !ccr_has_bytes(pos, 4, seg_end2) { return -1; }
    var_cnt := buf_read_u32(data, pos); pos = pos + 4;
    if var_cnt > (seg_end2 - seg_off2) / 12 { return -1; }
    grow_ir_vars(var_cnt);
    vi : ., mut = 0;
    loop {
        if vi >= var_cnt { break; }
        if !ccr_has_bytes(pos, 12, seg_end2) { return -1; }
        name_ni := buf_read_u32(data, pos); pos = pos + 4;
        id := buf_read_u32(data, pos); pos = pos + 4;
        tk := buf_read_u32(data, pos); pos = pos + 4;
        irv_set_name(vi, name_ni);
        irv_set_id(vi, id);
        irv_set_type(vi, tk);
        g_ir_var_count = vi + 1;
        vi = vi + 1;
    }

    // === SYM: string constants（4B each）===
    if !ccr_has_bytes(pos, 4, seg_end2) { return -1; }
    str_const_cnt := buf_read_u32(data, pos); pos = pos + 4;
    if str_const_cnt > (seg_end2 - seg_off2) / 4 { return -1; }
    grow_ir_str_consts(str_const_cnt);
    sci : ., mut = 0;
    loop {
        if sci >= str_const_cnt { break; }
        if !ccr_has_bytes(pos, 4, seg_end2) { return -1; }
        scv := buf_read_u32(data, pos); pos = pos + 4; w64(g_ir_str_consts, sci * 8, scv);
        g_ir_str_const_count = sci + 1;
        sci = sci + 1;
    }

    // === SYM: structs ===
    if !ccr_has_bytes(pos, 4, seg_end2) { return -1; }
    struct_cnt := buf_read_u32(data, pos); pos = pos + 4;
    if struct_cnt > (seg_end2 - seg_off2) / 8 { return -1; }
    grow_structs(struct_cnt);
    g_struct_count = struct_cnt;
    sti : ., mut = 0;
    loop {
        if sti >= struct_cnt { break; }
        if !ccr_has_bytes(pos, 8, seg_end2) { return -1; }
        sname_ni := buf_read_u32(data, pos); pos = pos + 4;
        fc := buf_read_u32(data, pos); pos = pos + 4;
        if fc > MAX_STRUCT_FIELDS { println("error: .ccr struct field count exceeds max"); return 1; }
        if fc > (seg_end2 - pos) / 8 { return -1; }
        w64(g_structs, sti * ESZ_STRUCTINFO + OFF_SI_NAME, sname_ni);
        w64(g_structs, sti * ESZ_STRUCTINFO + OFF_SI_FIELD_COUNT, fc);
        // Zero out all field slots and type nodes
        zfi : ., mut = 0;
        loop {
            if zfi >= 16 { break; }
            w64(g_structs, sti * ESZ_STRUCTINFO + OFF_SI_FIELD_NAMES + zfi * 8, 0);
            w64(g_structs, sti * ESZ_STRUCTINFO + OFF_SI_FIELD_TYPES + zfi * 8, 0);
            w64(g_structs, sti * ESZ_STRUCTINFO + OFF_SI_FIELD_TYPE_NODES + zfi * 8, 0);
            zfi = zfi + 1;
        }
        // Zero generic slots
        w64(g_structs, sti * ESZ_STRUCTINFO + OFF_SI_GENERIC_COUNT, 0);
        zgi : ., mut = 0;
        loop { if zgi >= 4 { break; } w64(g_structs, sti * ESZ_STRUCTINFO + OFF_SI_GENERIC_NAMES + zgi * 8, 0); zgi = zgi + 1; }
        // Write field data
        fi2 : ., mut = 0;
        loop {
            if fi2 >= fc { break; }
            fn_ni := buf_read_u32(data, pos); pos = pos + 4;
            ft := buf_read_u32(data, pos); pos = pos + 4;
            w64(g_structs, sti * ESZ_STRUCTINFO + OFF_SI_FIELD_NAMES + fi2 * 8, fn_ni);
            w64(g_structs, sti * ESZ_STRUCTINFO + OFF_SI_FIELD_TYPES + fi2 * 8, ft);
            fi2 = fi2 + 1;
        }
        sti = sti + 1;
    }

    // === SYM: enums ===
    if !ccr_has_bytes(pos, 4, seg_end2) { return -1; }
    enum_cnt := buf_read_u32(data, pos); pos = pos + 4;
    if enum_cnt > (seg_end2 - seg_off2) / 8 { return -1; }
    grow_enums(enum_cnt);
    g_enum_count = enum_cnt;
    ei : ., mut = 0;
    loop {
        if ei >= enum_cnt { break; }
        if !ccr_has_bytes(pos, 8, seg_end2) { return -1; }
        ename_ni := buf_read_u32(data, pos); pos = pos + 4;
        vc := buf_read_u32(data, pos); pos = pos + 4;
        if vc > MAX_ENUM_VARIANTS { println("error: .ccr enum variant count exceeds max"); return 1; }
        if vc > (seg_end2 - pos) / 8 { return -1; }
        w64(g_enums, ei * ESZ_ENUMINFO + OFF_EI_NAME, ename_ni);
        w64(g_enums, ei * ESZ_ENUMINFO + OFF_EI_VARIANT_COUNT, vc);
        // Zero all variant slots
        zvi : ., mut = 0;
        loop {
            if zvi >= 16 { break; }
            w64(g_enums, ei * ESZ_ENUMINFO + OFF_EI_VARIANTS + zvi * OFF_EV_SIZE + OFF_EV_NAME, 0);
            w64(g_enums, ei * ESZ_ENUMINFO + OFF_EI_VARIANTS + zvi * OFF_EV_SIZE + OFF_EV_TYPE_COUNT, 0);
            ztj : ., mut = 0;
            loop { if ztj >= 16 { break; } w64(g_enums, ei * ESZ_ENUMINFO + OFF_EI_VARIANTS + zvi * OFF_EV_SIZE + OFF_EV_TYPES + ztj * 8, 0); ztj = ztj + 1; }
            zvi = zvi + 1;
        }
        w64(g_enums, ei * ESZ_ENUMINFO + OFF_EI_GENERIC_COUNT, 0);
        zgi2 : ., mut = 0;
        loop { if zgi2 >= 4 { break; } w64(g_enums, ei * ESZ_ENUMINFO + OFF_EI_GENERIC_NAMES + zgi2 * 8, 0); zgi2 = zgi2 + 1; }
        // Write variant data
        vi3 : ., mut = 0;
        loop {
            if vi3 >= vc { break; }
            vni := buf_read_u32(data, pos); pos = pos + 4;
            tc := buf_read_u32(data, pos); pos = pos + 4;
            if tc > MAX_VARIANT_TYPES { println("error: .ccr variant type count exceeds max"); return 1; }
            if tc > (seg_end2 - pos) / 4 { return -1; }
            w64(g_enums, ei * ESZ_ENUMINFO + OFF_EI_VARIANTS + vi3 * OFF_EV_SIZE + OFF_EV_NAME, vni);
            w64(g_enums, ei * ESZ_ENUMINFO + OFF_EI_VARIANTS + vi3 * OFF_EV_SIZE + OFF_EV_TYPE_COUNT, tc);
            tf : ., mut = 0;
            loop {
                if tf >= tc { break; }
                tval := buf_read_u32(data, pos); pos = pos + 4;
                w64(g_enums, ei * ESZ_ENUMINFO + OFF_EI_VARIANTS + vi3 * OFF_EV_SIZE + OFF_EV_TYPES + tf * 8, tval);
                tf = tf + 1;
            }
            vi3 = vi3 + 1;
        }
        ei = ei + 1;
    }

    // === SYM: globals（16B each: name_idx, var_idx, init_val i64）===
    if !ccr_has_bytes(pos, 4, seg_end2) { return -1; }
    gc := buf_read_u32(data, pos); pos = pos + 4;
    if gc > (seg_end2 - seg_off2) / 16 { return -1; }
    grow_ir_globals(gc);
    gi : ., mut = 0;
    loop {
        if gi >= gc { break; }
        gname_ni := buf_read_u32(data, pos); pos = pos + 4;
        gvar_idx := buf_read_u32(data, pos); pos = pos + 4;
        ginit_val := buf_read_i64(data, pos); pos = pos + 8;
        w64(g_ir_globals, gi * 24, gname_ni);
        w64(g_ir_globals, gi * 24 + 8, gvar_idx);
        w64(g_ir_globals, gi * 24 + 16, ginit_val);
        g_ir_global_count = gi + 1;
        gi = gi + 1;
    }

    // === SYM: opt_meta ===
    if !ccr_has_bytes(pos, 4, seg_end2) { return -1; }
    mc := buf_read_u32(data, pos); pos = pos + 4;
    mi : ., mut = 0;
    loop {
        if mi >= mc { break; }
        if !ccr_has_bytes(pos, 8, seg_end2) { return -1; }
        mk := buf_read_u32(data, pos); pos = pos + 4;
        md_len := buf_read_u32(data, pos); pos = pos + 4;
        if md_len > OPT_META_STRIDE - 8 || !ccr_has_bytes(pos, md_len, seg_end2) { return -1; }
        // Allocate and store entry
        grow_opt_meta(mi + 1);
        mo := mi * OPT_META_STRIDE;
        w32(g_opt_meta, mo, mk);
        w32(g_opt_meta, mo + 4, md_len);
        di : ., mut = 0;
        loop { if di >= md_len { break; }
            store8(g_opt_meta, mo + 8 + di, load8(data, pos));
            pos = pos + 1;
            di = di + 1;
        }
        g_opt_meta_count = mi + 1;
        mi = mi + 1;
    }

    // === NOD: instructions（28B each）===
    pos = seg_off3;
    if !ccr_has_bytes(pos, 4, seg_end3) { return -1; }
    instr_cnt := buf_read_u32(data, pos); pos = pos + 4;
    if instr_cnt > (seg_end3 - seg_off3) / 28 { return -1; }
    grow_ir_instrs(instr_cnt);
    ii : ., mut = 0;
    loop {
        if ii >= instr_cnt { break; }
        if !ccr_has_bytes(pos, 28, seg_end3) { return -1; }
        opcode := buf_read_u32(data, pos); pos = pos + 4;
        dest := buf_read_i32(data, pos); pos = pos + 4;
        s1 := buf_read_i64(data, pos); pos = pos + 8;   // 修复 14：s1 64 位
        s2 := buf_read_i32(data, pos); pos = pos + 4;
        s3 := buf_read_i32(data, pos); pos = pos + 4;
        tk := buf_read_u32(data, pos); pos = pos + 4;
        iri_set_op(ii, opcode);
        iri_set_dest(ii, dest);
        iri_set_s1(ii, s1);
        iri_set_s2(ii, s2);
        iri_set_s3(ii, s3);
        iri_set_tk(ii, tk);
        g_ir_instr_count = ii + 1;
        ii = ii + 1;
    }

    // === ENT: entries（28B each → 内存 24B 表）===
    // 盘上半开 live_end → 内存闭区间 −1；version 字段不入内存（组内序可推）。
    if have4 != 0 {
        pos = seg_off4;
        if !ccr_has_bytes(pos, 4, seg_end4) { return -1; }
        ent_cnt := buf_read_u32(data, pos); pos = pos + 4;
        if ent_cnt > (seg_end4 - seg_off4) / ESZ_ENTRY_DISK { return -1; }
        ccr_grow_entries(ent_cnt);
        eii : ., mut = 0;
        loop {
            if eii >= ent_cnt { break; }
            if !ccr_has_bytes(pos, ESZ_ENTRY_DISK, seg_end4) { return -1; }
            ev := buf_read_i32(data, pos); pos = pos + 4;   // var_id
            evr := buf_read_u32(data, pos); pos = pos + 4;  // version（盘上仅校验用）
            ed := buf_read_i32(data, pos); pos = pos + 4;   // def_nod
            els := buf_read_u32(data, pos); pos = pos + 4;  // live_start（含定值）
            ele := buf_read_u32(data, pos); pos = pos + 4;  // live_end（半开）
            eho := buf_read_i32(data, pos); pos = pos + 4;  // home
            efl := buf_read_u32(data, pos); pos = pos + 4;  // flags
            // 语义校验（越界拒绝，先例 ccr 校验风格）
            if evr < 1 { return -1; }
            if ev < 0 || ev >= var_cnt { return -1; }
            if els >= ele || ele > instr_cnt { return -1; }
            if ed >= 0 {
                if ed >= instr_cnt { return -1; }
                if ed != els { return -1; }   // 定值条目 live_start == def
            }
            // 内存闭区间表
            mo2 := eii * ESZ_ENTRY;
            w32(g_ir_entries, mo2 + OFF_ENTRY_VAR, ev);
            w32(g_ir_entries, mo2 + OFF_ENTRY_DEF, ed);
            w32(g_ir_entries, mo2 + OFF_ENTRY_LS, els);
            w32(g_ir_entries, mo2 + OFF_ENTRY_LE, ele - 1);
            w32(g_ir_entries, mo2 + OFF_ENTRY_HOME, eho);
            w32(g_ir_entries, mo2 + OFF_ENTRY_FLAGS, efl);
            g_entry_count = eii + 1;
            eii = eii + 1;
        }
        // 函数条目段界重建：条目按函数升序成块落盘（compute_entries func_i 升序），
        // 每函数一段 [start, count)——块判定 = var 槽 ∈ 该函数 var 区间（var 槽
        // 全属唯一函数，段序与函数序一致）。重建失败 = 格式不一致。
        ccr_grow_func_entry_meta(func_cnt);
        pf : ., mut = 0;
        pe : ., mut = 0;
        loop {
            if pf >= func_cnt { break; }
            fvs := r64(g_ir_func_var_start, pf * 8);
            fvc := r64(g_ir_func_var_count, pf * 8);
            w64(g_ir_func_entry_start, pf * 8, pe);
            loop {
                if pe >= g_entry_count { break; }
                pv := buf_read_i32(g_ir_entries, pe * ESZ_ENTRY + OFF_ENTRY_VAR);
                if fvc <= 0 || pv < fvs || pv >= fvs + fvc { break; }
                pe = pe + 1;
            }
            w64(g_ir_func_entry_count, pf * 8, pe - r64(g_ir_func_entry_start, pf * 8));
            pf = pf + 1;
        }
        if pe != g_entry_count { return -1; }
    }

    // === REG: sgs（24B each；v5 SG 内容装入段表，记录序不变）===
    if have5 != 0 {
        pos = seg_off5;
        if !ccr_has_bytes(pos, 4, seg_end5) { return -1; }
        sg_n := buf_read_u32(data, pos); pos = pos + 4;
        if sg_n > (seg_end5 - seg_off5) / ESZ_SG_DISK { return -1; }
        sg_i : ., mut = 0;
        loop {
            if sg_i >= sg_n { break; }
            grow_sg(sg_i + 1);
            f := sg_i * ESZ_SG;
            w64(g_sgs, f + OFF_SG_KIND, buf_read_i32(data, pos)); pos = pos + 4;
            w64(g_sgs, f + OFF_SG_ENTER, buf_read_i32(data, pos)); pos = pos + 4;
            w64(g_sgs, f + OFF_SG_EXIT, buf_read_i32(data, pos)); pos = pos + 4;
            w64(g_sgs, f + OFF_SG_PARENT, buf_read_i32(data, pos)); pos = pos + 4;
            w64(g_sgs, f + OFF_SG_NSTART, buf_read_i32(data, pos)); pos = pos + 4;
            w64(g_sgs, f + OFF_SG_NCOUNT, buf_read_i32(data, pos)); pos = pos + 4;
            sg_i = sg_i + 1;
        }
        g_sg_count = sg_n;
    }

    return 0;
}
