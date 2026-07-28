// === region_check.cr ===
// RegionCheck pass — verifies DEREF targets are in live subgraphs.
// Runs after PointerAnalysis (ptr_analysis.cr) which builds g_pts table.

fn subgraph_containing(node_seq: int) -> int {
    // Search subgraph table for innermost subgraph containing node_seq
    best := -1;
    si : ., mut = 0;
    loop { if si >= g_sg_count { break; }
        nstart := r64(g_sgs, si * ESZ_SG + OFF_SG_NSTART);
        ncount := r64(g_sgs, si * ESZ_SG + OFF_SG_NCOUNT);
        if node_seq >= nstart && node_seq < nstart + ncount {
            best = si;
        }
        si = si + 1;
    }
    return best;
}

fn region_check_func(nstart: int, ncount: int) {
    ni : ., mut = nstart;
    loop { if ni >= nstart + ncount { break; }
        op := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_OPCODE);
        d  := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_DEST);
        s1 := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_S1);

        if op == IR_DEREF && d >= 0 && s1 >= 0 {
            // Get the pointer variable's points-to set
            pts := r64(g_pts, s1 * 8);
            if pts != 0 {
                // Check each bit in points-to set using running mask (>> not available)
                // Use arithmetic instead of bitwise & (not available in bootstrap backend)
                mask : int, mut = 1;
                bi : ., mut = 0;
                loop { if bi >= 64 { break; }  // limited to first 64 ALLOCs
                    if (pts / mask) % 2 == 1 {
                        // Find ALLOC node that created this allocation
                        alloc_seq := bi + nstart;  // simplified: ALLOC ID = bit position
                        alloc_sg := subgraph_containing(alloc_seq);
                        deref_sg := subgraph_containing(ni);
                        if alloc_sg >= 0 && deref_sg >= 0 {
                            alloc_exit := r64(g_sgs, alloc_sg * ESZ_SG + OFF_SG_EXIT);
                            if alloc_exit >= 0 && ni > alloc_exit {
                                // Deref after alloc subgraph exited — dangling pointer
                                check_error(EC_B_LIFETIME,
                                    "dangling pointer: allocation subgraph exited before deref",
                                    0, 0);
                            }
                        }
                    }
                    mask = mask * 2;
                    bi = bi + 1;
                }
            }
        }
        ni = ni + 1;
    }
}

fn region_check_all() {
    if g_opt_level < 1 { return; }  // only at opt>=1 for now
    fi : ., mut = 0;
    loop { if fi >= g_ir_func_count { break; }
        nstart := r64(g_df_func_node_start, fi * 8);
        ncount := r64(g_df_func_node_count, fi * 8);
        region_check_func(nstart, ncount);
        fi = fi + 1;
    }
}
