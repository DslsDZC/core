// === cir_cache.cr ===
// Incremental compilation cache: per-function .cir snapshot save/load.
// Saves the dataflow graph state (DF nodes, edges, IR instrs, vars, strings)
// for one function. On cache hit, restores the state directly into the
// compiler's global arrays.

// Magic header for .cir cache files
// v5: edges serialized as 4×8B (from/to/next/kind) so cache hits restore
// state edges; v4 cache files are rejected by the version check.
CIR_CACHE_MAGIC : int = 0xC1C1C1C1C1C1C1C1;
CIR_CACHE_VER   : int = 5;

g_cir_write_buf : string, mut;
g_cir_write_pos : int, mut;
g_cir_write_cap : int, mut;

// Save one function's DFG state to a .cir cache file.
// path: full file path (including .core/cache/cir/ prefix)
// func_idx: function index in g_ir_func_*
// Returns 0 on success, -1 on failure.
fn save_cir_cache(path: string, func_idx: int) -> int {
    fd := syscall3(2, path, 577, 420);  // O_WRONLY|O_CREAT|O_TRUNC, 0644
    if fd < 0 { return -1; }

    // Compute fingerprint
    fn_node := fi_ast_node(func_idx);
    fp := func_fingerprint(fn_node);
    sig := sig_fingerprint(fn_node);
    name_ni := r64(g_ir_func_name_idx, func_idx * 8);
    name := istr_get(name_ni);
    name_len := str_len(name);

    var_start := r64(g_ir_func_var_start, func_idx * 8);
    var_count := r64(g_ir_func_var_count, func_idx * 8);
    node_start := r64(g_df_func_node_start, func_idx * 8);
    node_count := r64(g_df_func_node_count, func_idx * 8);
    instr_start := r64(g_ir_func_instr_start, func_idx * 8);
    instr_count := r64(g_ir_func_instr_count, func_idx * 8);

    // Serialize in memory and issue one write. The previous per-field writes
    // made a full self-host build perform millions of syscalls on its cache.
    total_size : ., mut = 40 + name_len;
    total_size = total_size + 8 + var_count * 24;
    total_size = total_size + 8 + node_count * 64;
    total_size = total_size + 8 + g_df_edge_count * 32;  // v5: 4 fields incl. kind
    total_size = total_size + 8 + instr_count * 48;
    total_size = total_size + 8;
    size_si : ., mut = 0;
    loop {
        if size_si >= g_ir_str_const_count { break; }
        size_ni := r64(g_ir_str_consts, size_si * 8);
        total_size = total_size + 8 + str_len(istr_get(size_ni));
        size_si = size_si + 1;
    }
    if total_size > g_cir_write_cap {
        new_cap := g_cir_write_cap * 2;
        if new_cap < 4096 { new_cap = 4096; }
        if new_cap < total_size { new_cap = total_size; }
        g_cir_write_buf = alloc(new_cap);
        g_cir_write_cap = new_cap;
    }
    g_cir_write_pos = 0;

    // Write header
    w64_cir(fd, CIR_CACHE_MAGIC);
    w64_cir(fd, CIR_CACHE_VER);
    w64_cir(fd, fp);
    w64_cir(fd, sig);
    w64_cir(fd, name_len);
    write_fd(fd, name, name_len);

    // Determine var range for this function
    w64_cir(fd, var_count);
    vi : ., mut = 0;
    loop {
        if vi >= var_count { break; }
        v_idx := var_start + vi;
        w64_cir(fd, irv_name(v_idx));
        w64_cir(fd, irv_id(v_idx));
        w64_cir(fd, irv_type(v_idx));
        vi = vi + 1;
    }

    // Write function's node range
    w64_cir(fd, node_count);
    ni2 : ., mut = 0;
    loop {
        if ni2 >= node_count { break; }
        n := node_start + ni2;
        w64_cir(fd, r64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_OPCODE));
        w64_cir(fd, r64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_DEST));
        w64_cir(fd, r64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_S1));
        w64_cir(fd, r64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_S2));
        w64_cir(fd, r64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_S3));
        w64_cir(fd, r64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_TK));
        w64_cir(fd, r64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_FIRST_EDGE));
        w64_cir(fd, r64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_EDGE_COUNT));
        ni2 = ni2 + 1;
    }

    // Write edges (all edges for this function's nodes)
    // For simplicity, write ALL edges (they're few compared to nodes)
    // v5: 4×8B per edge — from/to/next + kind (state edges survive cache hits)
    w64_cir(fd, g_df_edge_count);
    ei : ., mut = 0;
    loop {
        if ei >= g_df_edge_count { break; }
        w64_cir(fd, r64(g_df_edges, ei * ESZ_DFEDGE + OFF_DFE_FROM));
        w64_cir(fd, r64(g_df_edges, ei * ESZ_DFEDGE + OFF_DFE_TO));
        w64_cir(fd, r64(g_df_edges, ei * ESZ_DFEDGE + OFF_DFE_NEXT));
        w64_cir(fd, r64(g_df_edges, ei * ESZ_DFEDGE + OFF_DFE_KIND));
        ei = ei + 1;
    }

    // Write function's instruction range
    w64_cir(fd, instr_count);
    ii : ., mut = 0;
    loop {
        if ii >= instr_count { break; }
        inst := instr_start + ii;
        w64_cir(fd, iri_op(inst));
        w64_cir(fd, iri_dest(inst));
        w64_cir(fd, iri_s1(inst));
        w64_cir(fd, iri_s2(inst));
        w64_cir(fd, iri_s3(inst));
        w64_cir(fd, iri_tk(inst));
        ii = ii + 1;
    }

    // Write string constants used by this function
    w64_cir(fd, g_ir_str_const_count);
    si : ., mut = 0;
    loop {
        if si >= g_ir_str_const_count { break; }
        ni3 := r64(g_ir_str_consts, si * 8);
        s := istr_get(ni3);
        sl := str_len(s);
        w64_cir(fd, sl);
        vi = 0;
        loop { if vi >= sl { break; }
            w8_cir(fd, load8(s, vi));
        vi = vi + 1; }
        si = si + 1;
    }

    written := syscall3(1, fd, g_cir_write_buf, g_cir_write_pos);
    syscall3(3, fd, 0, 0);
    if written != g_cir_write_pos { return -1; }
    return 0;
}

// Write helpers for the in-memory cache serializer.
fn w64_cir(fd: int, val: int) {
    w64(g_cir_write_buf, g_cir_write_pos, val);
    g_cir_write_pos = g_cir_write_pos + 8;
}

fn w8_cir(fd: int, val: int) {
    store8(g_cir_write_buf, g_cir_write_pos, val);
    g_cir_write_pos = g_cir_write_pos + 1;
}

fn write_fd(fd: int, data: string, len: int) {
    write_pos : ., mut = 0;
    loop {
        if write_pos >= len { break; }
        store8(g_cir_write_buf, g_cir_write_pos, load8(data, write_pos));
        g_cir_write_pos = g_cir_write_pos + 1;
        write_pos = write_pos + 1;
    }
}

// Load a .cir cache file and restore DFG state.
// func_idx is the function index used to verify the cached fingerprints
// against the current AST. Returns 0 on success, -1 on failure (cache miss).
fn load_cir_cache(path: string, func_idx: int) -> int {
    data := read_file(path);
    if str_len(data) < 48 { return -1; }
    pos : ., mut = 0;

    // Validate header
    magic := r64(data, pos); pos = pos + 8;
    if magic != CIR_CACHE_MAGIC { return -1; }
    ver := r64(data, pos); pos = pos + 8;
    if ver != CIR_CACHE_VER { return -1; }

    fp := r64(data, pos); pos = pos + 8;
    sig := r64(data, pos); pos = pos + 8;

    // Verify fingerprints against current AST.
    // If the function body or signature changed, the cache is stale.
    fn_node := fi_ast_node(func_idx);
    current_fp := func_fingerprint(fn_node);
    if fp != current_fp { return -1; }
    current_sig := sig_fingerprint(fn_node);
    if sig != current_sig { return -1; }

    // Verify function identity (name)
    name_len := r64(data, pos); pos = pos + 8;
    // Skip name string (we already know which function we tried to load)
    pos = pos + name_len;

    // Restore vars
    var_count := r64(data, pos); pos = pos + 8;
    vi : ., mut = 0;
    loop {
        if vi >= var_count { break; }
        name_ni := r64(data, pos); pos = pos + 8;
        v_id := r64(data, pos); pos = pos + 8;
        v_type := r64(data, pos); pos = pos + 8;
        // Ensure var array is large enough
        if v_id >= g_ir_var_count {
            grow_ir_vars(v_id + 1);
            g_ir_var_count = v_id + 1;
        }
        irv_set_name(v_id, name_ni);
        irv_set_id(v_id, v_id);
        irv_set_type(v_id, v_type);
        vi = vi + 1;
    }

    // Restore nodes
    node_count := r64(data, pos); pos = pos + 8;
    base_node := g_df_node_count;
    grow_df_nodes(g_df_node_count + node_count);
    // RegionCheck 显式映射：恢复的节点没有经过 df_create_node，须在此同步写入
    // node→region 映射，否则 subgraph_containing 在缓存命中路径读到未初始化
    // 的 g_df_node_region（null → SIGSEGV）。缓存不保存内层 region（Minor #4），
    // 以当前 open 的 func region（df_begin_func 已 sg_push）为归属——与旧的
    // 线性扫 g_sgs 在缓存命中路径得到的结果一致。
    grow_df_node_region(base_node + node_count);
    ni : ., mut = 0;
    loop {
        if ni >= node_count { break; }
        n := base_node + ni;
        w64(g_df_node_region, n * 8, g_cur_sg);
        w64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_OPCODE, r64(data, pos)); pos = pos + 8;
        w64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_DEST, r64(data, pos)); pos = pos + 8;
        w64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_S1, r64(data, pos)); pos = pos + 8;
        w64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_S2, r64(data, pos)); pos = pos + 8;
        w64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_S3, r64(data, pos)); pos = pos + 8;
        w64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_TK, r64(data, pos)); pos = pos + 8;
        w64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_FIRST_EDGE, r64(data, pos)); pos = pos + 8;
        w64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_EDGE_COUNT, r64(data, pos)); pos = pos + 8;
        // Record var producer
        dest := r64(g_df_nodes, n * ESZ_DFNODE + OFF_DF_DEST);
        if dest >= 0 {
            grow_df_arrays(dest + 1);
            w64(g_df_var_producer, dest * 8, n);
        }
        ni = ni + 1;
    }
    g_df_node_count = base_node + node_count;

    // Restore edges (v5: 4×8B per edge — from/to/next/kind)
    edge_count := r64(data, pos); pos = pos + 8;
    grow_df_edges(edge_count);
    g_df_edge_count = edge_count;
    ei : ., mut = 0;
    loop {
        if ei >= edge_count { break; }
        e_from := r64(data, pos); pos = pos + 8;
        e_to := r64(data, pos); pos = pos + 8;
        e_next := r64(data, pos); pos = pos + 8;
        e_kind := r64(data, pos); pos = pos + 8;
        w64(g_df_edges, ei * ESZ_DFEDGE + OFF_DFE_FROM, e_from);
        w64(g_df_edges, ei * ESZ_DFEDGE + OFF_DFE_TO, e_to);
        w64(g_df_edges, ei * ESZ_DFEDGE + OFF_DFE_NEXT, e_next);
        w64(g_df_edges, ei * ESZ_DFEDGE + OFF_DFE_KIND, e_kind);
        ei = ei + 1;
    }

    // Restore instructions
    instr_count := r64(data, pos); pos = pos + 8;
    base_instr := g_ir_instr_count;
    grow_ir_instrs(g_ir_instr_count + instr_count);
    ii : ., mut = 0;
    loop {
        if ii >= instr_count { break; }
        inst := base_instr + ii;
        iri_set_op(inst, r64(data, pos)); pos = pos + 8;
        iri_set_dest(inst, r64(data, pos)); pos = pos + 8;
        iri_set_s1(inst, r64(data, pos)); pos = pos + 8;
        iri_set_s2(inst, r64(data, pos)); pos = pos + 8;
        iri_set_s3(inst, r64(data, pos)); pos = pos + 8;
        iri_set_tk(inst, r64(data, pos)); pos = pos + 8;
        ii = ii + 1;
    }
    g_ir_instr_count = base_instr + instr_count;

    // Restore string constants (used by nodes/instrs)
    str_count := r64(data, pos); pos = pos + 8;
    si : ., mut = 0;
    loop {
        if si >= str_count { break; }
        sl := r64(data, pos); pos = pos + 8;
        s := str_sub(data, pos, sl);
        pos = pos + sl;
        track_str(str_intern(s));
        si = si + 1;
    }

    return 0;
}

// Ensure cache directory exists.
fn make_cir_cache_dir() {
    // Create .core/ directory hierarchy for cache.
    // mkdir syscall = 83 on x86-64 Linux: mkdir(path, mode)
    // Ignore EEXIST errors (directory may already exist).
    syscall3(83, ".core", 448, 0);
    syscall3(83, ".core/cache", 448, 0);
    syscall3(83, ".core/cache/cir", 448, 0);
}
