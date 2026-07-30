// Goroutine lifecycle — G struct creation and teardown
import arena
import sched

// Goroutine ID counter
g_next_id : int, mut = 1;

fn g_new(entry_fn: int, arg: int, arg_type: int) -> int {
    // Allocate stack (16KB)
    stack := alloc(16384);
    stack_top := stack + 16384 - 8;

    // Create new arena for this goroutine
    aid := arena_new();

    // Initialize fiber
    sp := fiber_init(stack_top, entry_fn);

    // Allocate G struct
    g := alloc(64);
    // G layout: id(8), status(8), sp(8), stack_lo(8), arena_id(8), chan_wait(8), next(8)
    id := g_next_id; g_next_id = g_next_id + 1;
    w64(g, 0, id);           // id
    w64(g, 8, 0);            // _Grunnable
    w64(g, 16, sp);          // stack pointer
    w64(g, 24, stack);       // stack_lo
    w64(g, 32, aid);         // arena_id
    w64(g, 40, -1);          // chan_wait = -1
    w64(g, 48, -1);          // next = -1

    // Enqueue to scheduler
    sched_enqueue(g);

    return g;
}

fn g_free(g: int) {
    // Reset arena
    aid := r64(g, 32);
    arena_reset(aid);
}
