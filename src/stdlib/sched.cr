// M:N scheduler — M OS threads, N goroutines

g_machines : string, mut;    // M array
g_machine_count : int, mut;

g_global_runq_head : int, mut = -1;  // global run queue
g_global_runq_tail : int, mut = -1;

fn sched_init() {
    // Initialize M workers (one per CPU)
    // For now: single-threaded (1 M, cooperative)
    m := alloc(32);
    w64(m, 0, 0);     // id = 0
    w64(m, 8, -1);     // cur_g = none
    w64(m, 16, -1);    // runq_head = empty
    w64(m, 24, -1);    // runq_tail = empty
    g_machine_count = 1;
}

fn sched_enqueue(g: int) {
    // Add to global run queue (simple for now)
    if g_global_runq_head < 0 {
        g_global_runq_head = g;
        g_global_runq_tail = g;
    } else {
        w64(g_global_runq_tail, 48, g);  // next = g
        g_global_runq_tail = g;
    }
}

fn sched_dequeue() -> int {
    g := g_global_runq_head;
    if g >= 0 {
        g_global_runq_head = r64(g, 48);  // g.next
        if g_global_runq_head < 0 { g_global_runq_tail = -1; }
        w64(g, 48, -1);  // clear next
    }
    return g;
}

fn sched_yield() {
    // Current goroutine yields
    m_idx := 0;  // single M
    cur_g := r64(g_machines, m_idx * 32 + 8);

    // Re-enqueue current G
    if cur_g >= 0 {
        w64(cur_g, 8, 0);  // _Grunnable
        sched_enqueue(cur_g);
    }

    // Schedule next
    sched_schedule();
}

fn sched_schedule() {
    m_idx := 0;
    next_g := sched_dequeue();
    if next_g >= 0 {
        old_g := r64(g_machines, m_idx * 32 + 8);
        w64(g_machines, m_idx * 32 + 8, next_g);
        w64(next_g, 8, 1);  // _Grunning

        if old_g >= 0 {
            // Save old_g's sp, switch to next_g's sp
            old_sp_addr := old_g + 16;  // &g.stack_ptr
            next_sp := r64(next_g, 16);  // g.stack_ptr
            fiber_switch(old_sp_addr, next_sp);
        }
        // else: first goroutine, just start it
    }
}
