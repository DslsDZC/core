// M:N scheduler — M OS threads, N goroutines
import goroutine
import chan
import arena

g_machines : string, mut;    // M array
g_machine_count : int, mut;

g_global_runq_head : int, mut = -1;  // global run queue
g_global_runq_tail : int, mut = -1;

g_num_workers : int, mut = 0;        // number of worker threads
g_sched_inited : int, mut = 0;       // 0 = not initialized, 1 = initialized

fn sched_init() {
    if g_sched_inited != 0 { return; }

    // Initialize arena system (required by goroutine/chan)
    arena_init(1048576, 65536);  // 1MB pool, 64KB chunks

    // Initialize M workers (one per CPU)
    // For now: single-threaded (1 M, cooperative)
    m := alloc(32);
    w64(m, 0, 0);     // id = 0
    w64(m, 8, -1);     // cur_g = none
    w64(m, 16, -1);    // runq_head = empty
    w64(m, 24, -1);    // runq_tail = empty
    g_machines = m;
    g_machine_count = 1;
    g_set_curg(-1);    // current_g = none (mirrors M[0].cur_g)
    g_sched_inited = 1;
}

fn sched_enqueue(g: int) {
    // Add to global run queue
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

fn sched_get_curg() -> int {
    return g_get_curg();
}

fn sched_yield() {
    // Current goroutine yields
    cur_g := sched_get_curg();

    // Re-enqueue current G
    if cur_g >= 0 {
        w64(cur_g, 8, 0);  // _Grunnable
        sched_enqueue(cur_g);
    }

    // Schedule next
    sched_schedule(0);
}

fn sched_schedule(m_idx: int) {
    next_g := sched_dequeue();
    if next_g >= 0 {
        old_g := r64(g_machines, m_idx * 32 + 8);
        w64(g_machines, m_idx * 32 + 8, next_g);
        g_set_curg(next_g);
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

// sched_worker_run: main loop for worker threads.
// Each worker dequeues and runs goroutines in a loop.
fn sched_worker_run(m_idx: int) {
    // Store this worker's index in its M struct
    w64(g_machines, m_idx * 32, m_idx);  // m.id = m_idx

    loop {
        next_g := sched_dequeue();
        if next_g >= 0 {
            old_g := r64(g_machines, m_idx * 32 + 8);
            w64(g_machines, m_idx * 32 + 8, next_g);
            g_set_curg(next_g);
            w64(next_g, 8, 1);  // _Grunning

            if old_g >= 0 {
                old_sp_addr := old_g + 16;
                next_sp := r64(next_g, 16);
                fiber_switch(old_sp_addr, next_sp);
            }
            // else: first goroutine on this M, start it
        }
        // If no work, yield to OS
        // For now: spin-wait (will add proper blocking later)
        // yield(); // sched_yield_to_os() — future
    }
}

// sched_go: spawn a goroutine that calls fn_ptr(arg), return a channel for the result.
// fn_ptr is the function's address (resolved by the backend at link time).
// arg is the single argument passed to the spawned function.
fn sched_go(fn_ptr: int, arg: int) -> int {
    // Create a 1-element channel for collecting the result
    ch := chan_make(8, 1);

    // Create a new goroutine via g_new
    g := g_new(fn_ptr, arg, 0);

    // Store result channel in G struct (offset 40)
    w64(g, 40, ch);

    // Enqueue goroutine to the scheduler
    sched_enqueue(g);

    // Return the channel so the caller can await the result
    return ch;
}

// sched_spawn_workers: create n worker threads via m_start_workers (rt.s)
fn sched_spawn_workers(n: int) {
    if n <= 1 { return; }
    total_ms := alloc(n * 32);
    mi : ., mut = 0;
    loop {
        if mi >= n { break; }
        w64(total_ms, mi * 32, mi);          // m.id
        w64(total_ms, mi * 32 + 8, -1);      // m.cur_g = none
        w64(total_ms, mi * 32 + 16, -1);     // runq_head
        w64(total_ms, mi * 32 + 24, -1);     // runq_tail
        mi = mi + 1;
    }
    g_machines = total_ms;
    g_machine_count = n;
    g_num_workers = n - 1;
    m_start_workers(n);  // launch workers (assembly in rt.s)
}
