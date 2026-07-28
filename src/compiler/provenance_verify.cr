// === provenance_verify.cr ===
// ProvenanceVerify pass — checks DEREF offset against allocation size.
// Runs after PointerAnalysis (ptr_analysis.cr) and RegionCheck (region_check.cr).
// Detects out-of-bounds pointer accesses at compile time.

fn get_alloc_size(alloc_node_seq: int) -> int {
    op := r64(g_df_nodes, alloc_node_seq * ESZ_DFNODE + OFF_DF_OPCODE);
    s1 := r64(g_df_nodes, alloc_node_seq * ESZ_DFNODE + OFF_DF_S1);
    s2 := r64(g_df_nodes, alloc_node_seq * ESZ_DFNODE + OFF_DF_S2);
    s3 := r64(g_df_nodes, alloc_node_seq * ESZ_DFNODE + OFF_DF_S3);

    if op == IR_ALLOC { return 8; }              // scalar = 8 bytes
    if op == IR_ALLOC_STRUCT { return 8 + s2 * 8; }  // struct size
    if op == IR_ALLOC_ARRAY { return s1 * s2; }       // count * element_size
    return -1;  // unknown (defer to runtime check)
}

fn provenance_verify_func(nstart: int, ncount: int) {
    ni : ., mut = nstart;
    loop { if ni >= nstart + ncount { break; }
        op := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_OPCODE);
        d  := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_DEST);
        s1 := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_S1);

        if op == IR_DEREF && d >= 0 && s1 >= 0 {
            pts := r64(g_pts, s1 * 8);
            off := r64(g_offsets, s1 * 8);

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
                    }
                    // if alloc_size < 0: runtime check needed (not yet implemented)
                }
                mask = mask * 2;
                bi = bi + 1;
            }
        }
        ni = ni + 1;
    }
}

fn provenance_verify_all() {
    if g_opt_level < 1 { return; }
    fi : ., mut = 0;
    loop { if fi >= g_ir_func_count { break; }
        nstart := r64(g_df_func_node_start, fi * 8);
        ncount := r64(g_df_func_node_count, fi * 8);
        provenance_verify_func(nstart, ncount);
        fi = fi + 1;
    }
}
