# Bare Pointer Model — Full Implementation Design

## Overview

Replace the existing `TYP_REF` (borrow-checked reference) type system with a bare `TYP_PTR` model backed by three dataflow analysis passes, as specified in `docs/pointer-model.md`. The borrow checker is replaced by graph-based verification that requires no user annotations.

## Architecture

```
Source → Parser → Checker(types) → IRGen → DataflowGraph → Passes → Backend
                                          ↑              ↓
                                     PointerAnalysis ← RegionCheck
                                          ↓
                                   ProvenanceVerify
```

The three passes consume the dataflow graph (built during IRGen) and produce verification results. No separate type-level borrow checking is needed — the graph encodes all pointer provenance information.

## Phase 1: Type System — TYP_PTR

### New type kind (ast.cr)

```crystal
TYP_PTR : int = 4;  // data=pointee_type_idx, extra=address_space (0=tracked, 1=external)
```

`TYP_PTR` replaces `TYP_REF` as the single pointer representation. `TYP_REF` is kept during migration but all new code uses `TYP_PTR`.

### Pointer type syntax (parser.cr)

`parse_type()` gets a new branch for `T_STAR`:

```crystal
else if tok_k(t) == T_STAR {
    advance_tok();
    inner := parse_type();
    res = alloc_node(EXPR_PTRTYPE, inner, 0, 0, 0, 0, 0, line, col);
}
```

New AST node:

```crystal
EXPR_PTRTYPE : int = 41;  // a=inner_type (for *T syntax)
```

### Type checker changes (checker.cr)

1. **`UOP_REF` (`&x`)**: Creates `TYP_PTR(inner_type, 0)` instead of `TYP_REF`. Removes borrow checker calls (`check_borrow`, `record_borrow_holder`).

2. **`UOP_DEREF` (`*p`)**: Accepts `TYP_PTR` — unwrap to pointee type. Also keeps `TYP_REF` for migration.

3. **Arithmetic on pointers**: `OP_ADD/OP_SUB` where one operand is `TYP_PTR` and the other is `TI_INT`:
   - Returns `TYP_PTR` (same pointee type)
   - IR gen uses `OP_PTR_ADD`/`OP_PTR_SUB` in `s3` instead of `OP_ADD`/`OP_SUB`
   - `p - q` (both `TYP_PTR`) → `OP_PTR_DIFF`, returns `TI_INT`

4. **`EXPR_AS` cast**: `p as *T` allowed unconditionally (cast safety verified by passes).

5. **`EXPR_UNSAFE`**: `push_unsafe_scope/pop_unsafe_scope` replaces `push_borrow_scope/pop_borrow_scope`. Marks subgraph boundary.

6. **`res_type_node`**: Handles `EXPR_PTRTYPE` → creates `TYP_PTR`.

### IR gen changes (ir_gen.cr)

1. **`UOP_REF`**: Emits `IR_REF` (same opcode, but now the type is `TYP_PTR` not `TYP_REF`).

2. **`EXPR_BINARY` with pointer operands**: When checker marks operand as `TYP_PTR`, emit `IR_BINARY` with `s3 = OP_PTR_ADD`/`OP_PTR_SUB`/`OP_PTR_DIFF` instead of standard opcodes. The checker sets `ast_c(node)` to the new opcode.

3. **`IR_DEREF` / `IR_STORE_PTR`**: Unchanged — the x86 backend already handles these.

### File changes summary

| File | Changes |
|------|---------|
| `ast.cr` | Add `TYP_PTR:4`, `EXPR_PTRTYPE:41`, `OP_PTR_ADD:14`, `OP_PTR_SUB:15`, `OP_PTR_DIFF:16` |
| `parser.cr` | `parse_type()`: `*T` → `EXPR_PTRTYPE`; `parse_unary()`: `&x` no borrow |
| `checker.cr` | `UOP_REF` → `TYP_PTR`; `UOP_DEREF` handles `TYP_PTR`; binary ops allow ptr arithmetic; `res_type_node` handles `EXPR_PTRTYPE`; `unsafe` → push/pop unsafe scope |
| `ir_gen.cr` | Binary ops: dispatch to `OP_PTR_ADD/SUB/DIFF` for ptr operands |
| `dataflow.cr` | `df_connect_srcs` → edge counting for new opcodes |
| `dump.cr` | Dump `OP_PTR_ADD/SUB/DIFF` names |
| `interp.cr` | Handle `OP_PTR_ADD/SUB/DIFF` in binary dispatch |
| `dataflow.cr` | `df_opcode_name` for new opcodes |

## Phase 2: IR Arithmetic Extension

### New opcode constants

```crystal
OP_PTR_ADD  : int = 14;  // p + n  (p: *T, n: int) → *T, scaled by sizeof(T)
OP_PTR_SUB  : int = 15;  // p - n  (p: *T, n: int) → *T, scaled by sizeof(T)
OP_PTR_DIFF : int = 16;  // p - q  (both *T) → int (element count)
```

### ELF backend (instr.cr)

In `IR_BINARY` handler, add branches:

```crystal
else if s3 == OP_PTR_ADD {
    // imul r11, 8 (element size, hardcoded to 8)
    cp = cp + emit_rex(buf, pos+cp, 1, 11/8, 0, 11/8);
    e2_w8(buf, pos+cp, 107); cp = cp + 1;  // 0x6B IMUL r, r/m, imm8
    cp = cp + emit_modrm(buf, pos+cp, 3, 11%8, 11%8);
    e2_w8(buf, pos+cp, 8); cp = cp + 1;    // *8
    // add r10, r11
    cp = cp + e2_alu(buf, pos+cp, 1);
}
else if s3 == OP_PTR_SUB {
    // imul r11, 8; sub r10, r11
    cp = cp + emit_rex(...); ...  // same MUL sequence
    cp = cp + e2_alu(buf, pos+cp, 41);  // SUB
}
else if s3 == OP_PTR_DIFF {
    // sub r10, r11; sar r10, 3
    cp = cp + e2_alu(buf, pos+cp, 41);  // SUB
    cp = cp + emit_rex(buf, pos+cp, 1, 0, 0, 10/8);
    e2_w8(buf, pos+cp, 193); cp = cp + 1;
    cp = cp + emit_modrm(buf, pos+cp, 3, 7, 10%8);
    e2_w8(buf, pos+cp, 3); cp = cp + 1;  // sar r10, 3
}
```

### Interpreter (interp.cr)

```crystal
if op == 2 {  // IR_BINARY
    lv := r64(g_ir_vals, s1 * 8); rv := r64(g_ir_vals, s2 * 8);
    if s3 == 1  { w64(g_ir_vals, d * 8, lv + rv); }       // OP_ADD
    if s3 == 2  { w64(g_ir_vals, d * 8, lv - rv); }       // OP_SUB
    if s3 == 14 { w64(g_ir_vals, d * 8, lv + rv * 8); }   // OP_PTR_ADD
    if s3 == 15 { w64(g_ir_vals, d * 8, lv - rv * 8); }   // OP_PTR_SUB
    if s3 == 16 { w64(g_ir_vals, d * 8, (lv - rv) / 8); } // OP_PTR_DIFF
    ...
}
```

### Dataflow naming

```crystal
// in dataflow.cr df_opcode_name:
if opcode == IR_BINARY {
    if s3 == OP_PTR_ADD  { return "ptr_add"; }
    if s3 == OP_PTR_SUB  { return "ptr_sub"; }
    if s3 == OP_PTR_DIFF { return "ptr_diff"; }
}
```

## Phase 3: Subgraph Infrastructure

### Subgraph table (new data structures in dyn_arr.cr)

```crystal
// Subgraph entry (48 bytes each)
ESZ_SG   : int = 48;
OFF_SG_KIND   : int = 0;   // 0=func, 1=loop, 2=for, 3=flow, 4=unsafe
OFF_SG_ENTER  : int = 8;   // enter instr seq
OFF_SG_EXIT   : int = 16;  // exit instr seq
OFF_SG_PARENT : int = 24;  // parent subgraph index
OFF_SG_NSTART : int = 32;  // first node index
OFF_SG_NCOUNT : int = 40;  // node count

SG_KINDS:
SG_FUNC   : int = 0;
SG_LOOP   : int = 1;
SG_FOR    : int = 2;
SG_FLOW   : int = 3;
SG_UNSAFE : int = 4;
```

### Subgraph builder functions (dataflow.cr)

```crystal
g_sg_count : int, mut;
g_sgs : string, mut;  // subgraph entries

fn sg_push(kind: int) {
    // Record current subgraph nesting
    // Called at: df_begin_func, IR_LABEL(loop/for start), EXPR_UNSAFE
}

fn sg_pop() {
    // Finalize current subgraph (set exit_seq, node_count)
}
```

### Calling points

| Location | Call | Subgraph kind |
|----------|------|---------------|
| `df_begin_func` | `sg_push(SG_FUNC)` | Function body |
| `df_end_func` | `sg_pop()` | — |
| `ir_gen.cr` loop header | `sg_push(SG_LOOP)` | Loop body |
| `ir_gen.cr` loop exit | `sg_pop()` | — |
| `ir_gen.cr` for header | `sg_push(SG_FOR)` | For body |
| `ir_gen.cr` for exit | `sg_pop()` | — |
| `ir_gen.cr` EXPR_UNSAFE | `sg_push(SG_UNSAFE)` | Unsafe block |
| `ir_gen.cr` after unsafe | `sg_pop()` | — |

### Points-to + offset storage (dyn_arr.cr)

```crystal
// Per-variable points-to bitmap (bits indexed by ALLOC node ID)
g_pts : string, mut;       // flat bitmap: bit i = var points-to alloc_i
g_pts_count : int, mut;    // number of tracked vars

// Per-variable offset from base allocation
g_offsets : string, mut;   // i64 per variable
```

### DFNode extension

```crystal
// New fields (total: 80 bytes from 64)
OFF_DF_PTS      : int = 64;   // points-to bitmap word (lower 64 bits, inline for hot vars)
OFF_DF_OFFSET   : int = 72;   // accumulated offset from base alloc (conservative)
ESZ_DFNODE_NEW  : int = 80;
```

## Phase 4: PointerAnalysis Pass

### File

`src/compiler/ptr_analysis.cr` (~200 lines)

### Interface

```crystal
fn ptr_analysis_func(nstart: int, ncount: int, vstart: int, vcount: int) {
    // Single-function pointer analysis
    // Walks DFNodes in topological order (creation order is valid)
    // For each node, updates pts/offset of destination variable
}
```

### Pseudocode

```
for each node n in [nstart, nstart + ncount):
    op = node.opcode
    d  = node.dest
    if d < 0: continue

    if op == IR_ALLOC || op == IR_ALLOC_STRUCT || op == IR_ALLOC_ARRAY:
        pts[d] = {n}           // points to itself
        offset[d] = 0

    elif op == IR_REF || op == IR_ADDR_INDEX:
        pts[d] = pts[node.s1]  // propagate
        offset[d] = offset[node.s1] + known_offset(node)

    elif op == IR_BINARY && (s3 == OP_PTR_ADD || s3 == OP_PTR_SUB):
        pts[d] = pts[node.s1]
        if node.s2 is constant:
            delta = const_val(node.s2) * 8
            offset[d] = offset[node.s1] + (s3 == PTR_ADD ? delta : -delta)
        else:
            offset[d] = UNKNOWN  // variable offset → runtime check needed

    elif op == IR_LOAD_VAR || op == IR_STORE:
        pts[d] = pts[node.s1]

    else:
        pts[d] = {}              // no pointer provenance
        offset[d] = 0
```

### Orchestration

```crystal
fn ptr_analysis_all() {
    fi := 0;
    loop { if fi >= g_ir_func_count { break; }
        nstart = r64(g_df_func_node_start, fi * 8);
        ncount = r64(g_df_func_node_count, fi * 8);
        vstart = r64(g_ir_func_var_start, fi * 8);
        vcount = r64(g_ir_func_var_count, fi * 8);
        ptr_analysis_func(nstart, ncount, vstart, vcount);
        fi = fi + 1;
    }
}
```

## Phase 5: RegionCheck Pass

### File

`src/compiler/region_check.cr` (~150 lines)

### Pseudocode

```
for each DEREF node:
    ptr_var = node.s1
    allocs = pts[ptr_var]        // set of possible ALLOC targets
    
    for each alloc_id in allocs:
        alloc_node = get_node(alloc_id)
        sg_alloc = subgraph_containing(alloc_node)
        cur_seq = node_seq(deref_node)
        
        if cur_seq > sg_alloc.exit_seq:
            error("dangling pointer: alloc exits at ", sg_alloc.exit_seq,
                  " deref at ", cur_seq)
```

### Subgraph containment query

```crystal
fn subgraph_containing(node_id: int) -> int {
    // Linear scan subgraph table for node_id in [nstart, nstart + ncount)
    // Returns innermost subgraph index
}
```

## Phase 6: ProvenanceVerify Pass

### File

`src/compiler/provenance_verify.cr` (~200 lines)

### Pseudocode

```
for each DEREF node:
    ptr_var = node.s1
    allocs = pts[ptr_var]
    off = offset[ptr_var]
    
    for each alloc_id in allocs:
        alloc_node = get_node(alloc_id)
        alloc_size = get_alloc_size(alloc_node)
        
        if alloc_size == UNKNOWN_SIZE:
            emit_bounds_check(node, off, alloc_size)
        else:
            if off < 0 || off >= alloc_size:
                error("out of bounds: offset ", off, " >= size ", alloc_size)
```

### Runtime bounds check emission

When `alloc_size` is runtime-determined (variable-length array), emit `IR_BOUNDS_CHECK` before the DEREF:

```crystal
fn emit_bounds_check(deref_instr: int, offset_var: int, size_var: int) {
    // Insert IR_BOUNDS_CHECK(deref_instr - 1) — before the DEREF
}
```

The ELF backend for `IR_BOUNDS_CHECK` (currently a no-op) needs implementation:

```crystal
if op == IR_BOUNDS_CHECK && s2 >= 0 {
    // cmp s1, s2
    // jae .panic
    // .panic: ud2
}
```

## Migration: Borrow Checker → Passes

The borrow checker (`checker.cr` lines 258-343, 1186-1210) is replaced incrementally:

1. Phase 1: `UOP_REF` stops calling `check_borrow()`. No error is emitted for multiple references to the same variable.
2. Phases 4-6: The three passes run after IRGen. Any proven unsound access is caught there.
3. The borrow scope functions (`push_borrow_scope/pop_borrow_scope`) are replaced by `push_unsafe_scope/pop_unsafe_scope` during Phase 1, as they're no longer needed for borrow tracking.

Error codes `EC_B_BORROW_*` are not removed — they're deprecated and may fire in migration warnings.

## Phase Order and Dependencies

```
Phase 1 (Types) ─────────────────────────────────────┐
                                                       │
Phase 2 (IR Arith) ── depends on P1 ──────────────────┤
                                                       │
Phase 3 (Subgraph) ── independent of P1/P2 ───────────┤
                                                       │
Phase 4 (PtrAnalysis) ── depends on P1 + P2 + P3 ─────┤
                                                       │
Phase 5 (RegionCheck) ── depends on P3 + P4 ──────────┤
                                                       │
Phase 6 (ProvenanceVerify) ── depends on P4 ──────────┤
```

Phases 1 and 3 can be developed in parallel. Phases 2 builds on 1. Phases 4-6 build on all prior phases.
