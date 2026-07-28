// Low-level runtime globals — used by rt.s (assembly) and ELF backend.
g_rt_argc : int, mut;
g_rt_argv_ptr : string, mut;

// Arena globals (always present, so emit_alloc_body can access them)
g_current_arena : int, mut = -1;
g_arena_pool_data : string, mut;
g_arena_free_list : int, mut = -1;
