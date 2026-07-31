// go_e2e_test.cr — end-to-end goroutine test.
//
// Spawns square(21) via `go`, waits on the result channel, and checks 441.
//
// Status: COMPILE-VERIFICATION ONLY. The full runtime path (goroutine fiber
// execution through goroutine_entry_wrapper) requires two pieces that do not
// exist yet:
//   1. a function-address mechanism (`&fn` currently emits an unresolved
//      dummy — see ir_gen.cr EXPR_IDENT "Could be a function name being
//      used as a value"), and
//   2. a runtime that links rt.s (fiber_switch/fiber_init/g_set_curg/
//      g_get_curg/m_start_workers) into user binaries (currently only
//      core_rt.so-based linking does, and no such .so is built by the
//      self-hosted pipeline).
// Until then this test verifies the full frontend + backend pipeline:
// sched_init → sched_go(fn_ni, arg) → chan_recv → result check.
import io
import sched

fn square(n: int) -> int {
    return n * n;
}

fn main() -> int {
    sched_init();
    ch := go square(21);
    result := chan_recv(ch);
    if result != 441 { return 1; }
    println("ALL PASS");
    return 0;
}
