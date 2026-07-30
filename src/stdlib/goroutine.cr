// Goroutine lifecycle — G struct creation and teardown
import arena
import sched

// Goroutine ID counter
g_next_id : int, mut = 1;

// G struct layout (80 bytes):
//   0: id
//   8: status (0=runnable, 1=running, 2=waiting)
//  16: sp (stack pointer for fiber)
//  24: stack_lo (lowest address of stack)
//  32: arena_id
//  40: result_ch (result channel, set by sched_go)
//  48: next (linked list for run queue / send_wait / recv_wait)
//  56: saved_fn (entry function ptr, for wrapper dispatch)
//  64: saved_arg (saved argument, for wrapper dispatch)
//  72: temp_val (temp value for wait queue handoff)

fn g_new(entry_fn: int, arg: int, arg_type: int) -> int {
    // Allocate stack (16KB)
    stack := alloc(16384);
    stack_top := stack + 16384 - 8;

    // Create new arena for this goroutine
    aid := arena_new();

    // Initialize fiber
    sp := fiber_init(stack_top, entry_fn);

    // Allocate G struct (80 bytes)
    g := alloc(80);
    id := g_next_id; g_next_id = g_next_id + 1;
    w64(g, 0, id);           // id
    w64(g, 8, 0);            // _Grunnable
    w64(g, 16, sp);          // stack pointer
    w64(g, 24, stack);       // stack_lo
    w64(g, 32, aid);         // arena_id
    w64(g, 40, 0);           // result_ch = 0 (default)
    w64(g, 48, -1);          // next = -1
    w64(g, 56, entry_fn);    // saved_fn = entry function ptr
    w64(g, 64, arg);         // saved_arg
    w64(g, 72, 0);           // temp_val = 0

    return g;
}

fn g_free(g: int) {
    // Reset arena
    aid := r64(g, 32);
    arena_reset(aid);
}
