// === ptr_analysis.cr ===
// PointerAnalysis pass — builds points-to relations from dataflow graph.
// Flow-sensitive, single-function analysis.
// Used by downstream safety passes (RegionCheck, etc.).

fn pa_in_unsafe(node_seq: int) -> int {
    si : ., mut = 0;
    loop { if si >= g_sg_count { break; }
        kind := r64(g_sgs, si * ESZ_SG + OFF_SG_KIND);
        if kind == SG_UNSAFE {
            nstart := r64(g_sgs, si * ESZ_SG + OFF_SG_NSTART);
            ncount := r64(g_sgs, si * ESZ_SG + OFF_SG_NCOUNT);
            if node_seq >= nstart && node_seq < nstart + ncount { return 1; }
        }
        si = si + 1;
    }
    return 0;
}

fn ptr_analysis_func(nstart: int, ncount: int, vstart: int, vcount: int) {
    // Initialize pts/offset for this function's variables
    vi : ., mut = 0;
    loop { if vi >= vcount { break; }
        var_idx := vstart + vi;
        grow_pts(var_idx + 1);
        w64(g_pts, var_idx * 8, 0);        // empty points-to set
        grow_offsets(var_idx + 1);
        w64(g_offsets, var_idx * 8, 0);     // offset = 0
        vi = vi + 1;
    }

    ni : ., mut = nstart;
    loop { if ni >= nstart + ncount { break; }
        op := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_OPCODE);
        d  := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_DEST);
        s1 := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_S1);
        s2 := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_S2);
        s3 := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_S3);

        // In unsafe blocks: suppress pointer tracking (pts stays 0)
        if d >= 0 && pa_in_unsafe(ni) != 0 { ni = ni + 1; continue; }

        if d >= 0 {
            // ALLOC creates a new allocation -- it points to itself
            if op == IR_ALLOC || op == IR_ALLOC_STRUCT || op == IR_ALLOC_ARRAY {
                w64(g_pts, d * 8, 1);  // single bit for self
                w64(g_offsets, d * 8, 0);
            }

            // REF propagates points-to from source
            if op == IR_REF && s1 >= 0 {
                w64(g_pts, d * 8, r64(g_pts, s1 * 8));
                w64(g_offsets, d * 8, r64(g_offsets, s1 * 8));
            }

            // ADDR_INDEX: propagate with offset
            if op == IR_ADDR_INDEX && s1 >= 0 {
                w64(g_pts, d * 8, r64(g_pts, s1 * 8));
                scale := s3;  // element size
                idx := -1;    // try to find constant index
                // If s2 is a CONST, get its value
                // Simplified: propagate offset symbolically
                w64(g_offsets, d * 8, r64(g_offsets, s1 * 8));  // + idx*scale at runtime
            }

            // BINARY with PTR ops: propagate with offset adjustment
            if op == IR_BINARY && (s3 == OP_PTR_ADD || s3 == OP_PTR_SUB) && s1 >= 0 {
                w64(g_pts, d * 8, r64(g_pts, s1 * 8));
                delta := r64(g_offsets, s1 * 8);
                if s3 == OP_PTR_ADD { w64(g_offsets, d * 8, delta); }  // + n*8 at runtime
                else { w64(g_offsets, d * 8, delta); }                  // - n*8 at runtime
            }

            // LOAD_VAR and STORE propagate
            if op == IR_LOAD || op == IR_STORE {
                if s1 >= 0 {
                    w64(g_pts, d * 8, r64(g_pts, s1 * 8));
                    w64(g_offsets, d * 8, r64(g_offsets, s1 * 8));
                }
            }

            // CALL: conservative — leave pts=0 (untrackable).
            // Passes will not report errors for CALL results since
            // pts==0 means "no provenance info available".
            // Future: interprocedural pointer analysis for known callees.
            if op == IR_CALL {
                // pts stays 0 (initialized above) = unknown/top
                w64(g_offsets, d * 8, 0);
            }
        }
        ni = ni + 1;
    }
}

fn ptr_analysis_all() {
    fi : ., mut = 0;
    loop { if fi >= g_ir_func_count { break; }
        nstart := r64(g_df_func_node_start, fi * 8);
        ncount := r64(g_df_func_node_count, fi * 8);
        vstart := r64(g_ir_func_var_start, fi * 8);
        vcount := r64(g_ir_func_var_count, fi * 8);
        ptr_analysis_func(nstart, ncount, vstart, vcount);
        fi = fi + 1;
    }
}
