// === provenance_verify.cr ===
// ProvenanceVerify pass — checks DEREF offset against allocation size.
// Runs after PointerAnalysis (ptr_analysis.cr) and RegionCheck (region_check.cr).
// Detects out-of-bounds pointer accesses at compile time.

fn get_alloc_size(alloc_seq: int) -> int {
    // 修复 3：alloc_seq 是 pts 位号（第几个 alloc），经映射表查 DF 节点序号再算大小。
    // 修复前直接当节点序号用 → 查到节点 0 → 恒返回 -1 → 运行时检查永不生成。
    if alloc_seq < 0 || alloc_seq >= g_pa_alloc_count { return -1; }
    an := r64(g_pa_alloc_nodes, alloc_seq * 8);
    op := r64(g_df_nodes, an * ESZ_DFNODE + OFF_DF_OPCODE);
    s1 := r64(g_df_nodes, an * ESZ_DFNODE + OFF_DF_S1);
    s3 := r64(g_df_nodes, an * ESZ_DFNODE + OFF_DF_S3);

    // 修复 12：IR_ALLOC（标量变量槽标记）不是堆分配——不返回 8（修复前把
    // 变量槽当 8 字节堆块，误报/误取 size）
    if op == IR_ALLOC_ARRAY { return s1 * 8; }   // count * 8（元素恒 8 字节，见 instr.cr IR_ALLOC_ARRAY）
    if op == IR_ALLOC_STRUCT {
        // 与 instr.cr IR_ALLOC_STRUCT 一致：fc * 8（field count × 8）
        fi : int = -1; si2 : ., mut = 0;
        loop { if si2 >= g_struct_count { break; }
            if si_name(si2) == s3 { fi = si2; break; }
            si2 = si2 + 1; }
        if fi >= 0 { return si_field_count(fi) * 8; }
        return 8;
    }
    return -1;  // unknown (defer to runtime check)
}

fn pv_is_in_unsafe(node_seq: int) -> int {
    si : ., mut = 0;
    loop { if si >= g_sg_count { break; }
        kind := r64(g_sgs, si * ESZ_SG + OFF_SG_KIND);
        if kind == SG_UNSAFE {
            nstart := r64(g_sgs, si * ESZ_SG + OFF_SG_NSTART);
            ncount := r64(g_sgs, si * ESZ_SG + OFF_SG_NCOUNT);
            if node_seq >= nstart && node_seq < nstart + ncount {
                return 1;
            }
        }
        si = si + 1;
    }
    return 0;
}

fn provenance_verify_func(nstart: int, ncount: int) {
    ni : ., mut = nstart;
    loop { if ni >= nstart + ncount { break; }
        op := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_OPCODE);
        d  := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_DEST);
        s1 := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_S1);

        if op == IR_DEREF && d >= 0 && s1 >= 0 {
            // Skip checks in unsafe blocks
            if pv_is_in_unsafe(ni) != 0 { ni = ni + 1; continue; }

            pts := r64(g_pts, s1 * 8);
            off := r64(g_offsets, s1 * 8);

            // Prov-GC: precise offset check using improved g_offsets
            // If offset is precisely known from constants, check against alloc size
            prec_off := r64(g_offsets, s1 * 8);

            // Check each potential allocation target in the points-to set
            mask : int, mut = 1;
            bi : ., mut = 0;
            loop { if bi >= 64 { break; }
                if (pts / mask) % 2 != 0 {
                    alloc_size := get_alloc_size(bi);
                    if alloc_size >= 0 && off >= 0 {
                        if off >= alloc_size {
                            check_error(EC_TK_INDEX,
                                "pointer out of bounds: offset " + int_str(off) +
                                " >= size " + int_str(alloc_size),
                                0, 0);
                        }
                    } else if alloc_size >= 0 {
                        // Known alloc_size, unknown offset → runtime check
                        // Encode alloc_size in s3 for backend cmp+jae+ud2
                        w64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_S3, alloc_size);
                    } else {
                        // Both unknown → null trap only (s3=0, fast path)
                    }
                }
                mask = mask * 2;
                bi = bi + 1;
            }
        }
        ni = ni + 1;
    }
}

fn provenance_verify_all() {
    // Safety pass — always runs
    fi : ., mut = 0;
    loop { if fi >= g_ir_func_count { break; }
        nstart := r64(g_df_func_node_start, fi * 8);
        ncount := r64(g_df_func_node_count, fi * 8);
        provenance_verify_func(nstart, ncount);
        fi = fi + 1;
    }
}
