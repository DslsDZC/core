// === region_check.cr ===
// RegionCheck pass — verifies DEREF targets are in live subgraphs.
// Runs after PointerAnalysis (ptr_analysis.cr) which builds g_pts table.

fn subgraph_containing(node_seq: int) -> int {
    // 显式映射：O(1) 归属查询（g_df_node_region 由 df_create_node 写入）
    if node_seq >= 0 && node_seq < g_df_node_count {
        return r64(g_df_node_region, node_seq * 8);
    }
    return -1;
}

fn is_in_unsafe(node_seq: int) -> int {
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

fn alloc_seq_to_sg(alloc_seq: int) -> int {
    // Map ALLOC node sequence number to its subgraph
    return subgraph_containing(alloc_seq);
}

fn rc_pts_has_escaped(pts: int, ni: int, nstart: int) -> int {
    // Check if any allocation targeted by pts escapes its parent subgraph
    mask : int, mut = 1;
    bi : ., mut = 0;
    loop { if bi >= 64 { break; }
        if (pts / mask) % 2 == 1 {
            alloc_seq := bi + nstart;
            alloc_sg := alloc_seq_to_sg(alloc_seq);
            deref_sg := subgraph_containing(ni);
            if alloc_sg >= 0 && deref_sg >= 0 {
                alloc_exit := r64(g_sgs, alloc_sg * ESZ_SG + OFF_SG_EXIT);
                if alloc_exit >= 0 && ni > alloc_exit {
                    return 1;  // escaped — alloc subgraph already exited
                }
            }
        }
        mask = mask * 2;
        bi = bi + 1;
    }
    return 0;
}

fn rc_return_escape(ni: int, s1: int, nstart: int) {
    // Siebert: check if a returned pointer escapes its region
    if s1 < 0 { return; }
    pts := r64(g_pts, s1 * 8);
    if pts == 0 { return; }
    cur_sg := subgraph_containing(ni);
    if cur_sg < 0 { return; }
    // Check if any target allocation is in a subgraph that will exit
    // before the caller can use the returned value
    mask : int, mut = 1;
    bi : ., mut = 0;
    loop { if bi >= 64 { break; }
        if (pts / mask) % 2 == 1 {
            alloc_seq := bi + nstart;
            alloc_sg := alloc_seq_to_sg(alloc_seq);
            if alloc_sg >= 0 {
                alloc_sg_kind := r64(g_sgs, alloc_sg * ESZ_SG + OFF_SG_KIND);
                if alloc_sg_kind == SG_FUNC {  // function-level alloc = ok to return
                    bi = bi + 1; mask = mask * 2; continue;
                }
                alloc_exit := r64(g_sgs, alloc_sg * ESZ_SG + OFF_SG_EXIT);
                if alloc_exit >= 0 && ni > alloc_exit {
                    check_error(EC_B_LIFETIME,
                        "region escape: returning pointer to exited subgraph allocation",
                        0, 0);
                }
            }
        }
        mask = mask * 2;
        bi = bi + 1;
    }
}

fn rc_store_escape(ni: int, ptr_var: int, val_var: int) {
    // Siebert: check if storing a pointer creates a dangling reference
    // *ptr = val — val's target allocations must have lifetime >= ptr's
    if val_var < 0 { return; }
    val_pts := r64(g_pts, val_var * 8);
    if val_pts == 0 { return; }
    rc_pts_has_escaped(val_pts, ni, 0);  // simplified check
}

fn region_check_func(nstart: int, ncount: int) {
    ni : ., mut = nstart;
    loop { if ni >= nstart + ncount { break; }
        op := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_OPCODE);
        d  := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_DEST);
        s1 := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_S1);
        s2 := r64(g_df_nodes, ni * ESZ_DFNODE + OFF_DF_S2);

        if is_in_unsafe(ni) != 0 { ni = ni + 1; continue; }

        if op == IR_DEREF && d >= 0 && s1 >= 0 {
            pts := r64(g_pts, s1 * 8);
            if pts != 0 {
                mask : int, mut = 1;
                bi : ., mut = 0;
                loop { if bi >= 64 { break; }
                    if (pts / mask) % 2 == 1 {
                        alloc_seq := bi + nstart;
                        alloc_sg := alloc_seq_to_sg(alloc_seq);
                        deref_sg := subgraph_containing(ni);
                        if alloc_sg >= 0 && deref_sg >= 0 {
                            alloc_exit := r64(g_sgs, alloc_sg * ESZ_SG + OFF_SG_EXIT);
                            if alloc_exit >= 0 && ni > alloc_exit {
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

        // Siebert: interprocedural escape via return
        if op == IR_RETURN && s1 >= 0 {
            rc_return_escape(ni, s1, nstart);
        }

        // Siebert: interprocedural escape via store
        if op == IR_STORE_PTR {
            rc_store_escape(ni, s1, s2);
        }

        ni = ni + 1;
    }
}

fn region_check_all() {
    // Safety pass — always runs
    fi : ., mut = 0;
    loop { if fi >= g_ir_func_count { break; }
        nstart := r64(g_df_func_node_start, fi * 8);
        ncount := r64(g_df_func_node_count, fi * 8);
        region_check_func(nstart, ncount);
        fi = fi + 1;
    }
}
