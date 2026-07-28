# Arena 内存模型 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single global bump allocator with a multi-arena system where each subgraph (function/loop/for/unsafe) gets its own arena, allocation automatically uses the current arena, and subgraph exit resets the arena cursor.

**Architecture:** Three layers — (1) stdlib arena lifecycle in Core (`arena.cr`), (2) compiler emits `IR_ARENA_NEW`/`IR_ARENA_RESET` at subgraph boundaries with compile-time size estimation, (3) ELF backend `emit_alloc_body` checks `g_current_arena` and allocates from the arena chunk when set, falling back to global bump when not.

**Tech Stack:** Core language (self-hosted compiler), x86-64 ELF backend, GNU as (rt.s)

## Global Constraints

- No fixed MAX_ARENAS limit — metadata arrays are dynamic (like `g_df_nodes`)
- `alloc()` API unchanged — arena awareness is transparent
- `g_current_arena = -1` preserves existing global bump behavior
- All lifecycle management in Core code (`arena.cr`); only bump path is in assembly
- New IR opcodes: `IR_ARENA_NEW = 30`, `IR_ARENA_RESET = 31`
- ESZ_IRINSTR = 48 bytes (6 fields × 8 bytes). `iri_set_s1(idx, val)` patches instruction field.
- Chain expansion: arena OOM allocates overflow block from global heap

---

### Task 1: BSS Extension (rt.s)

**Files:**
- Modify: `src/runtime/rt.s`

**Interfaces:**
- Produces: `g_current_arena` (BSS, 8B), `g_arena_pool_data` (BSS, 8B), `g_arena_free_list` (BSS, 8B)

- [ ] **Step 1: Add arena BSS variables**

In `src/runtime/rt.s`, find the `.bss` section. Add after `.balign 4096` and before `heap_ptr`:

```asm
.section .bss
.balign 4096
g_current_arena: .space 8       ; -1 = no arena, use global heap_ptr
g_arena_pool_data: .space 8     ; pool base pointer (filled by arena_init)
g_arena_free_list: .space 8     ; -1 = empty
heap_ptr: .space 8              ; existing, fallback
heap_start: .space 1024 * 1024 * 1024
heap_end:
```

- [ ] **Step 2: Initialize new globals in _start**

In `_start`, after the existing `heap_ptr` init (`lea rax, [rip + heap_start]; lea r10, [rip + heap_ptr]; mov [r10], rax`), add:

```asm
    # Initialize g_current_arena = -1 (no arena active)
    mov r10, -1
    lea rax, [rip + g_current_arena]
    mov [rax], r10

    # Initialize g_arena_pool_data = heap_start (default, overwritten by arena_init)
    lea rax, [rip + heap_start]
    lea r10, [rip + g_arena_pool_data]
    mov [r10], rax
```

- [ ] **Step 3: Verify assembly**

Run: `as -o /tmp/rt.o src/runtime/rt.s`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add src/runtime/rt.s
git commit -m "feat: add arena BSS globals (g_current_arena, g_arena_pool_data, g_arena_free_list)"
```

---

### Task 2: New IR Opcodes (ast.cr, dataflow.cr, opt.cr)

**Files:**
- Modify: `src/compiler/ast.cr`
- Modify: `src/compiler/dataflow.cr`
- Modify: `src/compiler/opt.cr`

**Interfaces:**
- Produces: `IR_ARENA_NEW = 30`, `IR_ARENA_RESET = 31`

- [ ] **Step 1: Add opcode constants to ast.cr**

Find the IR opcode section (around line 526-530), add after `IR_YIELD`:

```core
IR_ARENA_NEW   : int = 30;   // dest=arena_var, src1=size_estimate
IR_ARENA_RESET : int = 31;   // src1=arena_id (dest=-1)
```

- [ ] **Step 2: Register in dataflow.cr df_opcode_name**

Find `fn df_opcode_name`, add after the `IR_YIELD` entry (around line 349):

```core
    if opcode == IR_ARENA_NEW { return "arena_new"; }
    if opcode == IR_ARENA_RESET { return "arena_reset"; }
```

- [ ] **Step 3: Register in dataflow.cr df_connect_srcs**

Find `fn df_connect_srcs` (search for `df_connect_srcs` definition). Add at the end, before the function's closing:

```core
    if opcode == IR_ARENA_NEW { df_use_var(nid, s1); return; }
    if opcode == IR_ARENA_RESET { df_use_var(nid, s1); return; }
```

- [ ] **Step 4: Skip in opt.cr optimization loops**

Find the main optimization loop in `opt.cr` (search for `if op == IR_` blocks). Add:

```core
    if op == IR_ARENA_NEW { continue; }
    if op == IR_ARENA_RESET { continue; }
```

Also check `resolve.cr` for any opcode switch — add skip cases if found.

- [ ] **Step 5: Commit**

```bash
git add src/compiler/ast.cr src/compiler/dataflow.cr src/compiler/opt.cr
git commit -m "feat: add IR_ARENA_NEW(30) and IR_ARENA_RESET(31) opcodes"
```

---

### Task 3: CCR Serialization (ccr_io.cr)

**Files:**
- Modify: `src/compiler/ccr_io.cr`

- [ ] **Step 1: Add save_ccr handling**

Find `fn save_ccr`. Find the instruction-writing loop (where opcodes are dispatched). Add after the YIELD case:

```core
    if op == IR_ARENA_NEW {
        w64(buf, ip, IR_ARENA_NEW); ip = ip + 8;
        w64(buf, ip, d); ip = ip + 8;         // dest = arena_var
        w64(buf, ip, s1); ip = ip + 8;         // src1 = size estimate
        w64(buf, ip, s2); ip = ip + 8;
        w64(buf, ip, s3); ip = ip + 8;
        w64(buf, ip, tk); ip = ip + 8;         // type_kind (unused, 0)
        ii = ii + 1;
        continue;
    }
    if op == IR_ARENA_RESET {
        w64(buf, ip, IR_ARENA_RESET); ip = ip + 8;
        w64(buf, ip, d); ip = ip + 8;         // dest = -1 (unused)
        w64(buf, ip, s1); ip = ip + 8;         // src1 = arena_id
        w64(buf, ip, s2); ip = ip + 8;
        w64(buf, ip, s3); ip = ip + 8;
        w64(buf, ip, tk); ip = ip + 8;
        ii = ii + 1;
        continue;
    }
```

- [ ] **Step 2: Add load_ccr handling**

Find `fn load_ccr`. Find the instruction-reading loop. Add after the YIELD case:

```core
    if op == IR_ARENA_NEW {
        d := r64(buf, ip); ip = ip + 8;
        s1 := r64(buf, ip); ip = ip + 8;
        s2 := r64(buf, ip); ip = ip + 8;
        s3 := r64(buf, ip); ip = ip + 8;
        tk := r64(buf, ip); ip = ip + 8;
        emit(IR_ARENA_NEW, d, s1, s2, s3, tk);
        ii = ii + 1;
        continue;
    }
    if op == IR_ARENA_RESET {
        d := r64(buf, ip); ip = ip + 8;
        s1 := r64(buf, ip); ip = ip + 8;
        s2 := r64(buf, ip); ip = ip + 8;
        s3 := r64(buf, ip); ip = ip + 8;
        tk := r64(buf, ip); ip = ip + 8;
        emit(IR_ARENA_RESET, d, s1, s2, s3, tk);
        ii = ii + 1;
        continue;
    }
```

- [ ] **Step 3: Commit**

```bash
git add src/compiler/ccr_io.cr
git commit -m "feat: save/load IR_ARENA_NEW and IR_ARENA_RESET in ccr_io"
```

---

### Task 4: Stdlib — arena.cr

**Files:**
- Rewrite: `src/stdlib/arena.cr`

**Interfaces:**
- Globals: `g_current_arena`, `g_arena_cursors`, `g_arena_sizes`, `g_arena_parents`, `g_arena_pool_data`, `g_arena_max_size`, `g_arena_free_list`, `g_arena_count`, `g_arena_cap`
- Functions: `arena_init(pool_size, arena_size)`, `arena_new() -> int`, `arena_reset(ai)`, `arena_avail(ai) -> int`

- [ ] **Step 1: Write arena.cr**

```core
// Arena memory model — per-subgraph bump allocator.
// Each subgraph (function/loop/for/unsafe) gets its own Arena.
// alloc() checks g_current_arena and uses the arena chunk when set.

// ── Globals (accessed by emit_alloc_body ELF code) ──
g_current_arena : int, mut = -1;

// Arena metadata — dynamic arrays (no fixed limit, grows like g_df_nodes)
g_arena_cursors : string, mut;     // int[] — bump cursor offset per arena
g_arena_sizes   : string, mut;     // int[] — chunk capacity per arena
g_arena_parents : string, mut;     // int[] — parent arena ID (for nesting restore)

g_arena_pool_data : string, mut;   // pool base address (from alloc)
g_arena_max_size : int, mut;       // default chunk size per arena
g_arena_free_list : int, mut = -1; // free list head (-1 = empty)
g_arena_count : int, mut = 0;      // total slots allocated
g_arena_cap : int, mut = 0;        // metadata array capacity

// ── Internal: grow metadata arrays ──
fn _grow_arena_meta(needed: int) {
    if needed < g_arena_cap { return; }
    nc : ., mut = g_arena_cap * 2; if nc < 64 { nc = 64; } if nc < needed { nc = needed + 64; }
    // cursors
    nb := alloc(nc * 8);
    zi : ., mut = 0; loop { if zi >= nc * 8 { break; } store8(nb, zi, 0); zi = zi + 1; }
    if g_arena_cap > 0 { _dyncpy(g_arena_cursors, g_arena_cap * 8, nb); }
    g_arena_cursors = nb;
    // sizes
    nb2 := alloc(nc * 8);
    zi = 0; loop { if zi >= nc * 8 { break; } store8(nb2, zi, 0); zi = zi + 1; }
    if g_arena_cap > 0 { _dyncpy(g_arena_sizes, g_arena_cap * 8, nb2); }
    g_arena_sizes = nb2;
    // parents
    nb3 := alloc(nc * 8);
    zi = 0; loop { if zi >= nc * 8 { break; } store8(nb3, zi, 0); zi = zi + 1; }
    if g_arena_cap > 0 { _dyncpy(g_arena_parents, g_arena_cap * 8, nb3); }
    g_arena_parents = nb3;
    g_arena_cap = nc;
}

// ── Public API ──

fn arena_init(pool_size: int, arena_size: int) {
    g_arena_pool_data = alloc(pool_size);
    g_arena_max_size = arena_size;
    g_arena_free_list = -1;
    g_arena_count = 0;
    g_arena_cap = 0;
    g_current_arena = -1;
}

fn arena_new() -> int {
    ai : ., mut = -1;

    // Try free list first
    if g_arena_free_list >= 0 {
        ai = g_arena_free_list;
        g_arena_free_list = r64(g_arena_parents, ai * 8);  // pop head
    }

    if ai < 0 {
        // Allocate new slot (grow metadata arrays)
        need := g_arena_count + 1;
        _grow_arena_meta(need);
        ai = g_arena_count;
        g_arena_count = need;
    }

    // Initialize slot
    w64(g_arena_cursors, ai * 8, 0);
    w64(g_arena_sizes, ai * 8, g_arena_max_size);
    w64(g_arena_parents, ai * 8, -1);

    // Set parent = previous current arena
    if g_current_arena >= 0 {
        w64(g_arena_parents, ai * 8, g_current_arena);
    }

    // Activate
    g_current_arena = ai;
    return ai;
}

fn arena_reset(ai: int) {
    if ai < 0 || ai >= g_arena_count { return; }

    // Save parent BEFORE free list overwrites g_arena_parents[ai]
    parent := r64(g_arena_parents, ai * 8);

    // Push to free list
    w64(g_arena_parents, ai * 8, g_arena_free_list);
    g_arena_free_list = ai;

    // Restore parent
    if parent >= 0 { g_current_arena = parent; }
    else { g_current_arena = -1; }
}

fn arena_avail(ai: int) -> int {
    if ai < 0 || ai >= g_arena_count { return 0; }
    cursor := r64(g_arena_cursors, ai * 8);
    limit := r64(g_arena_sizes, ai * 8);
    return limit - cursor;
}
```

- [ ] **Step 2: Type-check**

Run: `./build/corec check src/stdlib/arena.cr`
Expected: No compilation errors. (If errors about globals, ensure arena.cr globals are registered — see Known Issues in CLAUDE.md about unregistered globals.)

If there are errors about global registration, add arena globals to the parser's global registration list (similar fix to the tokenizer global registration issue documented in CLAUDE.md).

- [ ] **Step 3: Commit**

```bash
git add src/stdlib/arena.cr
git commit -m "feat: arena lifecycle allocator — init/new/reset with dynamic metadata"
```

---

### Task 5: IR Gen Integration (ir_gen.cr)

**Files:**
- Modify: `src/compiler/ir_gen.cr`

- [ ] **Step 1: Add per-subgraph arena tracking globals**

At the top of `ir_gen.cr` (after the comment block), add:

```core
// Subgraph-level arena tracking for compile-time size estimation
g_sg_alloc_total : string, mut;    // per-sg: cumulative alloc size
g_sg_alloc_cap   : int, mut;
g_sg_arena_var   : string, mut;    // per-sg: IR var for arena ID
g_sg_arena_var_cap : int, mut;

fn grow_sg_alloc(needed: int) {
    if needed < g_sg_alloc_cap { return; }
    nc := g_sg_alloc_cap * 2; if nc < 64 { nc = 64; } if nc < needed { nc = needed + 64; }
    nb := alloc(nc * 8); _dyncpy(g_sg_alloc_total, g_sg_alloc_cap * 8, nb); g_sg_alloc_total = nb; g_sg_alloc_cap = nc; }

fn grow_sg_arena_var(needed: int) {
    if needed < g_sg_arena_var_cap { return; }
    nc := g_sg_arena_var_cap * 2; if nc < 64 { nc = 64; } if nc < needed { nc = needed + 64; }
    nb := alloc(nc * 8); _dyncpy(g_sg_arena_var, g_sg_arena_var_cap * 8, nb); g_sg_arena_var = nb; g_sg_arena_var_cap = nc; }
```

- [ ] **Step 2: Add sg_alloc_push/pop and track_alloc_size**

```core
fn sg_alloc_push(kind: int) {
    grow_sg_alloc(g_sg_count + 1);
    grow_sg_arena_var(g_sg_count + 1);
    w64(g_sg_alloc_total, g_sg_count * 8, 0);
    sg_push(kind);
}

fn sg_alloc_pop() {
    total := r64(g_sg_alloc_total, (g_sg_count - 1) * 8);
    arena_var := r64(g_sg_arena_var, (g_sg_count - 1) * 8);
    sg_pop();
    emit(IR_ARENA_RESET, -1, arena_var, 0, 0, 0);
}

fn track_alloc_size(size: int) {
    if g_sg_count > 0 {
        old := r64(g_sg_alloc_total, (g_sg_count - 1) * 8);
        w64(g_sg_alloc_total, (g_sg_count - 1) * 8, old + size);
    }
}
```

- [ ] **Step 3: Wire arena at function entry/exit in ir_gen_func**

In `ir_gen_func`, find the start of body generation. Replace `sg_push(kind)` call pattern. The function currently doesn't call `sg_push` directly — `df_begin_func` does that. But we need to add arena lifecycle around the function body.

Find `if body >= 0 { gen_expr(body); }`. Replace with:

```core
    // Function-level arena
    sg_alloc_push(SG_FUNC);
    arena_var := new_ir_var("_arena", TI_INT);
    w64(g_sg_arena_var, (g_sg_count - 1) * 8, arena_var);
    emit(IR_ARENA_NEW, arena_var, total, 0, 0, 0);

    if body >= 0 { gen_expr(body); }

    sg_alloc_pop();
```

Wait, this has an ordering issue — we need the total before we create IR_ARENA_NEW, but we need the arena_var before body gen. Let me restructure:

```core
    // Function-level arena
    sg_alloc_push(SG_FUNC);
    arena_var := new_ir_var("_arena", TI_INT);
    w64(g_sg_arena_var, (g_sg_count - 1) * 8, arena_var);
    // Emit placeholder IR_ARENA_NEW (size patched at sg_alloc_pop)
    emit(IR_ARENA_NEW, arena_var, 0, 0, 0, 0);
    // Store instruction index for size patching
    arena_instr := g_ir_instr_count - 1;

    if body >= 0 { gen_expr(body); }

    // Patch size estimate
    total := r64(g_sg_alloc_total, g_sg_count - 1);
    if total > 0 { iri_set_s1(arena_instr, total); }

    sg_alloc_pop();
```

- [ ] **Step 4: Wire arena at loop/for/unsafe boundaries**

Find the existing `sg_push`/`sg_pop` calls in ir_gen.cr:

For **LOOP** (around line 659):
```core
    sg_alloc_push(SG_LOOP);
    arena_var := new_ir_var("_arena", TI_INT);
    w64(g_sg_arena_var, (g_sg_count - 1) * 8, arena_var);
    emit(IR_ARENA_NEW, arena_var, 0, 0, 0, 0);
    arena_instr := g_ir_instr_count - 1;
    // ... loop body gen ...
    total := r64(g_sg_alloc_total, g_sg_count - 1);
    if total > 0 { iri_set_s1(arena_instr, total); }
    sg_alloc_pop();
```

For **FOR** (around line 724):
```core
    sg_alloc_push(SG_FOR);
    arena_var := new_ir_var("_arena", TI_INT);
    w64(g_sg_arena_var, (g_sg_count - 1) * 8, arena_var);
    emit(IR_ARENA_NEW, arena_var, 0, 0, 0, 0);
    arena_instr := g_ir_instr_count - 1;
    // ... for body gen ...
    total := r64(g_sg_alloc_total, g_sg_count - 1);
    if total > 0 { iri_set_s1(arena_instr, total); }
    sg_alloc_pop();
```

For **UNSAFE** (around line 1005):
```core
    sg_alloc_push(SG_UNSAFE);
    arena_var := new_ir_var("_arena", TI_INT);
    w64(g_sg_arena_var, (g_sg_count - 1) * 8, arena_var);
    emit(IR_ARENA_NEW, arena_var, 0, 0, 0, 0);
    arena_instr := g_ir_instr_count - 1;
    ret := gen_expr(ast_a(node));
    total := r64(g_sg_alloc_total, g_sg_count - 1);
    if total > 0 { iri_set_s1(arena_instr, total); }
    sg_alloc_pop();
```

- [ ] **Step 5: Wire track_alloc_size into ALLOC instruction emission**

In `emit()` or at each ALLOC emit site, call `track_alloc_size`. The cleanest location: in `emit()` itself, after writing the instruction, check if opcode is an ALLOC variant and track the size.

At the end of `emit()` (after `g_ir_instr_count = idx + 1;` and `df_create_node(...);`), add:

```core
    // Track allocation size for subgraph arena size estimation
    if opcode == IR_ALLOC && src1 > 0 { track_alloc_size(src1); }
    if opcode == IR_ALLOC_STRUCT {
        // struct size = field_count * 8 (from name_ni in s3)
        // For now, just track as default — refined in future passes
        track_alloc_size(64);
    }
    if opcode == IR_ALLOC_ARRAY && src1 > 0 { track_alloc_size(src1 * 8); }
```

- [ ] **Step 6: Commit**

```bash
git add src/compiler/ir_gen.cr
git commit -m "feat: ir_gen arena lifecycle — sg_alloc_push/pop, size estimation, subgraph binding"
```

---

### Task 6: ELF Backend — emit_alloc_body Dual Path (elf.cr)

**Files:**
- Modify: `src/arch/linux/ld/elf.cr`

- [ ] **Step 1: Read current emit_alloc_body**

Read the current `emit_alloc_body` function (around line 23-84 in elf.cr) and understand its structure:
- It emits `_start` initialization code
- Has bounds check (cmp rdi, 64MB)
- Bumps `heap_ptr` from BSS
- Zeroes memory with `rep stosb`
- Stores length header, returns data ptr

- [ ] **Step 2: Modify emit_alloc_body for dual-path**

Replace the body of `emit_alloc_body` to check `g_current_arena` at entry. New logic:

```asm
emit_alloc_body:
    ; Entry: rdi = size
    ; Save original size for header
    mov r9, rdi

    ; Check g_current_arena
    lea r10, [rip + g_current_arena]
    mov r10d, [r10]           ; 32-bit load (arena ID fits in int32)
    test r10d, r10d
    js .Lglobal_alloc          ; if < 0, use global bump

    ; ── Arena allocation path ──
    ; r10d = ai (arena index)

    ; Load arena_cursors[ai]
    lea r11, [rip + g_arena_cursors]
    mov r11, [r11]             ; load cursor array pointer
    mov rcx, [r11 + r10*8]     ; rcx = cursors[ai] = old_cursor

    ; Load arena_sizes[ai]
    lea r11, [rip + g_arena_sizes]
    mov r11, [r11]             ; load sizes array pointer
    mov r8, [r11 + r10*8]      ; r8 = sizes[ai] = chunk max

    ; Load g_arena_pool_data
    lea r11, [rip + g_arena_pool_data]
    mov r11, [r11]             ; r11 = pool_base address

    ; Compute chunk start: pool_base + ai * g_arena_max_size
    ; g_arena_max_size is stored in BSS
    lea rdx, [rip + g_arena_max_size]
    mov rax, [rdx]             ; rax = g_arena_max_size
    mul r10d                   ; rax = ai * arena_max_size (low 64 bits)
    add r11, rax               ; r11 = pool_base + ai * arena_max_size (= chunk start)

    ; Align size
    mov rdi, r9                ; reload original size
    add rdi, 15
    and rdi, -8

    ; Bump
    mov rax, rcx               ; rax = old_cursor
    add rcx, rdi               ; rcx = new_cursor
    cmp rcx, r8                ; new_cursor > chunk_size?
    ja .Lchain_expand

    ; Update cursor
    lea rdx, [rip + g_arena_cursors]
    mov rdx, [rdx]
    mov [rdx + r10*8], rcx     ; cursors[ai] = new_cursor

    ; Return chunk_start + old_cursor
    add rax, r11               ; rax = chunk_start + old_cursor
    ; Store length header (hidden 8 bytes before data ptr)
    mov [rax], r9
    lea rax, [rax + 8]         ; return data ptr after header
    ret

.Lchain_expand:
    ; Arena OOM — chain expand: allocate from global heap
    ; Save current arena ID
    push r10
    ; Temporarily disable arena mode
    mov qword [rip + g_current_arena], -1
    ; Fall through to global alloc path

.Lglobal_alloc:
    ; ── Global bump path (existing logic, slightly adapted) ──
    ; (Original emit_alloc_body code goes here)
    mov r8, r9                 ; r8 = original size (for header)
    add rdi, 15
    and rdi, -8
    lea r10, [rip + heap_ptr]
    mov rax, [r10]
    lea rdx, [rax + rdi]
    lea rcx, [rip + heap_end]
    cmp rdx, rcx
    ja .Loom
    mov [r10], rdx
    mov [rax], r8
    ; zero-init
    push rax
    push rdx
    lea rdi, [rax + 8]
    xor eax, eax
    sub rdx, rdi
    mov rcx, rdx
    cld
    rep stosb
    pop rdx
    pop rax
    lea rax, [rax + 8]
    ; If we came from chain_expand, restore arena
    ; Check if stack has saved arena ID
    ; (Simplification: chain expand just returns this global alloc ptr)
    ret

.Loom:
    xor eax, eax
    ret
```

Note: The assembly above is a sketch. The actual implementation needs to be precise x86-64 machine code emission compatible with the existing `emit_alloc_body` interface. Key points:
1. Function entry is the same (`rdi = size`)
2. Function exit is the same (`rax = pointer` or 0)
3. The arena path loads globals via RIP-relative addressing
4. Chain expansion falls through to global bump path

The actual code emission uses `w8(buf, pos+cp, byte)` etc. — follow the existing pattern.

- [ ] **Step 3: Update emit_alloc_body return signature in phase 2 sizing**

In the `elf_gen` function where `emit_alloc_body` size is pre-calculated (currently hardcoded as 84 bytes), update the estimated size to accommodate the expanded function (approximately double, ~160-180 bytes).

```core
    total_code = total_code + 180;  // arena-aware alloc body
```

- [ ] **Step 4: Commit**

```bash
git add src/arch/linux/ld/elf.cr
git commit -m "feat: emit_alloc_body dual-path arena alloc + chain expansion fallback"
```

---

### Task 7: ELF Backend — Arena NEW/RESET Encoding (instr.cr, resolve.cr)

**Files:**
- Modify: `src/arch/linux/ld/instr.cr`
- Modify: `src/arch/linux/ld/elf.cr` (add arena_new_impl / arena_reset_impl emit)
- Modify: `src/arch/linux/ld/resolve.cr`

- [ ] **Step 1: Add IR_ARENA_NEW encoding to instr.cr**

Find the main instruction encoding function in `instr.cr` (where IR opcodes are dispatched, around the `if op == IR_ALLOC` section). Add before the `return cp` at the end:

```core
    if op == IR_ARENA_NEW {
        // dest = arena_var (IR var that receives the arena ID)
        // src1 = size_estimate (currently advisory, 0 = use default)
        // Emit: call arena_new_impl
        // After call, store the result (arena ID) to dest slot
        do2 := g2_slot(d);
        grow_alloc_patch(g_x86_alloc_patch_count + 1);
        w64(g_x86_alloc_patch_pos, g_x86_alloc_patch_count * 8, pos + cp);
        g_x86_alloc_patch_count = g_x86_alloc_patch_count + 1;
        e2_w8(buf, pos+cp, 232); e2_w32(buf, pos+cp+1, 0); cp = cp + 5;  // call placeholder
        // Store returned arena ID to dest variable
        cp = cp + e2_st(buf, pos+cp, 0, do2);
        return cp;
    }
```

- [ ] **Step 2: Add IR_ARENA_RESET encoding to instr.cr**

```core
    if op == IR_ARENA_RESET {
        // src1 = arena_id (IR variable)
        // Load arena_id into edi, call arena_reset_impl
        cp = cp + e2_load_var(buf, pos+cp, 7, s1);  // mov edi, arena_id
        grow_alloc_patch(g_x86_alloc_patch_count + 1);
        w64(g_x86_alloc_patch_pos, g_x86_alloc_patch_count * 8, pos + cp);
        g_x86_alloc_patch_count = g_x86_alloc_patch_count + 1;
        e2_w8(buf, pos+cp, 232); e2_w32(buf, pos+cp+1, 0); cp = cp + 5;  // call placeholder
        return cp;
    }
```

Note: `e2_load_var(buf, pos+cp, 7, s1)` loads the IR variable `s1` into register rdi (= 7 for `edi`). Check the register numbering convention in `instr.cr` — the emitted code needs to match the calling convention (`rdi` = first arg).

- [ ] **Step 3: Add label size estimation for new opcodes in sizes.cr**

Find the instruction size function in `src/arch/linux/ld/sizes.cr`. Add size cases:

```core
    if op == IR_ARENA_NEW {
        // call(5) + store(4) = 9 bytes
        return 9;
    }
    if op == IR_ARENA_RESET {
        // load_var edi(4) + call(5) = 9 bytes
        return 9;
    }
```

- [ ] **Step 4: Add arena_new_impl / arena_reset_impl to elf.cr**

In `elf.cr` (after `emit_alloc_body`), add two new emitter functions:

```core
// Emit arena_new_impl — creates a new arena slot.
// Called from IR_ARENA_NEW. Returns arena ID in rax.
// For initial implementation: just call the Core arena_new() function.
// This is a placeholder that expands into:
//   call arena_new   (via PLT if available, or direct reloc)
// We emit a call instruction that gets patched similarly to alloc calls.
fn emit_arena_new_impl(buf: string, pos: int) -> int {
    // mov edi, 0 (no size hint for now)
    e2_w8(buf, pos, 191); e2_w32(buf, pos+1, 0);  // mov edi, 0
    // call arena_new — placeholder, patched at link time
    grow_alloc_patch(g_x86_alloc_patch_count + 1);
    w64(g_x86_alloc_patch_pos, g_x86_alloc_patch_count * 8, pos + 5);
    g_x86_alloc_patch_count = g_x86_alloc_patch_count + 1;
    e2_w8(buf, pos+5, 232); e2_w32(buf, pos+6, 0);  // call placeholder
    // ret
    e2_w8(buf, pos+10, 195);  // ret
    return 11;
}

// Emit arena_reset_impl — resets an arena slot.
// Called from IR_ARENA_RESET. Takes arena ID in edi, void return.
fn emit_arena_reset_impl(buf: string, pos: int) -> int {
    // edi already contains arena_id from caller
    // call arena_reset — placeholder, patched at link time
    grow_alloc_patch(g_x86_alloc_patch_count + 1);
    w64(g_x86_alloc_patch_pos, g_x86_alloc_patch_count * 8, pos);
    g_x86_alloc_patch_count = g_x86_alloc_patch_count + 1;
    e2_w8(buf, pos, 232); e2_w32(buf, pos+1, 0);  // call placeholder
    // ret
    e2_w8(buf, pos+5, 195);  // ret
    return 6;
}
```

- [ ] **Step 5: Register arena_new_impl/arena_reset_impl in elf_gen**

In `elf_gen`, after emitting the alloc body and its offset registration, add:

```core
    // arena_new_impl
    grow_func_offsets(g_x86_func_off_count * 2 + 2);
    w64(g_x86_func_offsets, g_x86_func_off_count * 16, str_intern("arena_new_impl"));
    w64(g_x86_func_offsets, g_x86_func_off_count * 16 + 8, total_code);
    g_x86_func_off_count = g_x86_func_off_count + 1;
    total_code = total_code + 11;  // emit_arena_new_impl size

    // arena_reset_impl
    grow_func_offsets(g_x86_func_off_count * 2 + 2);
    w64(g_x86_func_offsets, g_x86_func_off_count * 16, str_intern("arena_reset_impl"));
    w64(g_x86_func_offsets, g_x86_func_off_count * 16 + 8, total_code);
    g_x86_func_off_count = g_x86_func_off_count + 1;
    total_code = total_code + 6;  // emit_arena_reset_impl size
```

And in Phase 3 (emit), after calling `emit_alloc_body`, call the new emitters:

```core
    // arena_new_impl
    cp = cp + emit_arena_new_impl(buf, cp);
    // arena_reset_impl
    cp = cp + emit_arena_reset_impl(buf, cp);
```

- [ ] **Step 6: Handle new opcodes in resolve.cr label resolution**

In `resolve.cr`, ensure any label-related passes skip new opcodes (they don't use labels).

- [ ] **Step 7: Commit**

```bash
git add src/arch/linux/ld/instr.cr src/arch/linux/ld/elf.cr src/arch/linux/ld/sizes.cr src/arch/linux/ld/resolve.cr
git commit -m "feat: ELF backend arena_new/reset opcode encoding + impl stubs"
```

---

### Task 8: Tests

**Files:**
- Create: `tests/suite/arena_test.cr`

- [ ] **Step 1: Write arena lifecycle test**

```core
// Arena memory model test suite
// Tests basic arena lifecycle, nesting, and alloc integration

fn test_arena_basic() -> int {
    arena_init(1048576, 65536);  // 1MB pool, 64KB chunks

    // Create arena
    a1 := arena_new();
    if a1 < 0 { return 1; }       // arena_new failed
    if g_current_arena != a1 { return 2; }  // not activated

    // Alloc should now use arena
    p := alloc(64);
    if p == 0 { return 3; }       // alloc failed

    // Reset
    arena_reset(a1);
    if g_current_arena >= 0 { return 4; }  // should be -1 after reset

    // Re-use arena from free list
    a2 := arena_new();
    if a2 != a1 { return 5; }     // should reuse same ID

    arena_reset(a2);
    return 0;  // pass
}

fn test_arena_nesting() -> int {
    arena_init(1048576, 65536);

    a1 := arena_new();    // parent
    p1 := alloc(32);
    if p1 == 0 { return 1; }

    a2 := arena_new();    // child (arena in loop)
    if g_current_arena != a2 { return 2; }
    p2 := alloc(64);
    if p2 == 0 { return 3; }

    // Child reset should restore parent
    arena_reset(a2);
    if g_current_arena != a1 { return 4; }

    // Parent still works
    p3 := alloc(16);
    if p3 == 0 { return 5; }

    arena_reset(a1);
    return 0;
}

fn test_arena_free_list_reuse() -> int {
    arena_init(1048576, 65536);

    // Allocate multiple arenas
    a1 := arena_new(); arena_reset(a1);
    a2 := arena_new(); arena_reset(a2);
    a3 := arena_new(); arena_reset(a3);

    // Next new should reuse a3 (LIFO free list)
    a4 := arena_new();
    if a4 != a3 { return 1; }  // should reuse most recently freed

    arena_reset(a4);
    return 0;
}

fn main() -> int {
    r1 := test_arena_basic();
    if r1 != 0 { print("FAIL basic: "); println(int_str(r1)); return r1; }

    r2 := test_arena_nesting();
    if r2 != 0 { print("FAIL nesting: "); println(int_str(r2)); return r2; }

    r3 := test_arena_free_list_reuse();
    if r3 != 0 { print("FAIL freelist: "); println(int_str(r3)); return r3; }

    println("ALL PASS");
    return 0;
}
```

- [ ] **Step 2: Run test via interpreter**

```bash
./build/corec run -f tests/suite/arena_test.cr
```

(Note: `-f` flag may not exist — use `run` subcommand with file path or inline. Check `./build/corec --help` for the correct syntax.)

If the `run` command doesn't support importing stdlib files, try:
```bash
./build/corec build tests/suite/arena_test.cr -o /tmp/arena_test --static
/tmp/arena_test
echo $?
```

Or inline the arena code directly in the test file without the `import` and test with the interpreter directly.

- [ ] **Step 3: Run existing tests to verify no regression**

```bash
python3 tests/bootstrap/test_pipeline.py
python3 tests/selfhost/test_compile.py
```

Expected: All existing tests pass (arena code path not triggered for non-arena tests).

- [ ] **Step 4: Commit**

```bash
git add tests/suite/arena_test.cr
git commit -m "test: arena lifecycle, nesting, and free-list reuse"
```
