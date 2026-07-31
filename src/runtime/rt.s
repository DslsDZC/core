# rt.s — x86-64 runtime for Core native binaries
# Provides: __builtin_alloc (bump allocator),
#           __builtin_get_arg (command-line argument access).
# Assemble: as -o rt.o rt.s
# Link: ld -o binary rt.o <other.o>

.intel_syntax noprefix

.section .data
rt_argc: .quad 0
rt_argv: .quad 0

.section .bss
.balign 4096
heap_start:
    .space 1024 * 1024 * 1024
heap_end:
.balign 8
current_g: .space 8  # current goroutine pointer (set via g_set_curg)

.section .data
heap_ptr: .quad 0
empty_str_hdr: .quad 1
empty_str: .byte 0
.balign 8

# Hotpatch SIGHUP sigaction struct — registered in _start
hotpatch_sa:
    .quad _hotpatch_sighup    # sa_handler
    .quad 0                   # sa_flags
    .quad 0                   # sa_mask  (empty sigset_t, 8 bytes on x86-64)

.text

# _start — entry point: saves argc/argv, calls main, exits via syscall.
.globl _start
.type _start, @function
_start:
    # Save argc/argv from stack (Linux process initialization)
    mov rdi, [rsp]
    lea rsi, [rsp + 8]
    lea rax, [rip + rt_argc]
    mov [rax], rdi
    lea rax, [rip + rt_argv]
    mov [rax], rsi

    # Initialize bump allocator heap pointer
    lea rax, [rip + heap_start]
    lea r10, [rip + heap_ptr]
    mov [r10], rax
    call _init_globals

    # Register SIGHUP handler — reloads .hotpatch.toml on SIGHUP
    lea rsi, [rip + hotpatch_sa]
    mov rdi, 1          # SIGHUP = 1
    xor rdx, rdx        # oldact = NULL
    mov r10d, 8         # sigsetsize = sizeof(sigset_t) on x86-64
    mov eax, 13         # rt_sigaction syscall
    syscall

    call main

    mov edi, eax
    mov eax, 60
    syscall

# alloc(size: int) -> string (pointer)
# Allocate size bytes + 8-byte length header.
# Layout: [8-byte size][data...]
# Returns pointer to data (after the header).
# str_len(returned_ptr) = read_header(returned_ptr - 8) - 1 (minus null byte)
.globl alloc
.type alloc, @function
alloc:
    # rdi = requested_size (caller wants rdi usable bytes)
    mov r8, rdi          # save requested size in r8
    add rdi, 15          # size + 8(header) + 7(align)
    and rdi, -8          # align to 8
    lea r10, [rip + heap_ptr]
    mov rax, [r10]
    lea rdx, [rax + rdi]
    lea rcx, [rip + heap_end]
    cmp rdx, rcx
    ja .Lalloc_oom
    mov [r10], rdx

    # Write requested size at header (before data ptr)
    mov [rax], r8

    # Zero-initialize the data portion only (skip header)
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

    lea rax, [rax + 8]    # return ptr to data (after header)
    ret

.Lalloc_oom:
    xor eax, eax
    ret


# get_arg(n: int) -> string
# Returns a copy of the nth command-line argument (0 = program name).
.globl get_arg
.type get_arg, @function
get_arg:
    mov rcx, [rip + rt_argc]
    cmp rdi, rcx
    jge .Larg_oob
    cmp rdi, 0
    jl .Larg_oob

    push r12
    mov rcx, [rip + rt_argv]
    mov r12, [rcx + rdi*8]      # r12 = argv[n]

    # strlen(r12)
    mov rdi, r12
    xor eax, eax
    mov rcx, -1
    repne scasb
    not rcx
    dec rcx                     # rcx = strlen

    # Allocate len + 1
    lea rdi, [rcx + 1]
    push rcx                    # save len
    call alloc
    pop rcx                     # rcx = len
    test rax, rax
    jz .Larg_alloc_fail

    # memcpy(rax, r12, len+1)
    mov rdi, rax
    push rax                    # save buffer start
    mov rsi, r12
    lea rcx, [rcx + 1]          # len+1 (include null)
    rep movsb
    pop rax                     # restore buffer start
    pop r12
    ret

.Larg_alloc_fail:
    xor eax, eax
    pop r12
    ret

.Larg_oob:
    lea rax, [rip + empty_str]
    ret

# load_str_ptr(buf: string, pos: int) -> string
# Load 8-byte string pointer from byte buffer at given offset.
.globl load_str_ptr
.type load_str_ptr, @function
load_str_ptr:
    mov rax, [rdi + rsi]
    ret

# store_str_ptr(buf: string, pos: int, val: string) -> int
# Store 8-byte string pointer into byte buffer at given offset.
.globl store_str_ptr
.type store_str_ptr, @function
store_str_ptr:
    mov [rdi + rsi], rdx
    xor eax, eax
    ret

# load64(buf: string, pos: int) -> int
# Load 8-byte integer from byte buffer at given offset.
.globl load64
.type load64, @function
load64:
    mov rax, [rdi + rsi]
    ret

# _hotpatch_sighup — SIGHUP signal handler
# Reloads .hotpatch.toml via hp_load_config().
# Kernel saves/restores all registers across signal delivery.
.globl _hotpatch_sighup
.type _hotpatch_sighup, @function
_hotpatch_sighup:
    call hp_load_config
    ret

# fiber_switch(current_sp_addr, next_sp) -> int
# Save current context, load next context
.globl fiber_switch
.type fiber_switch, @function
fiber_switch:
    # rdi = &current_g.stack_ptr (address to save RSP to)
    # rsi = next_g.stack_ptr (RSP to restore)

    # Save callee-saved registers
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    # Save RSP
    mov qword [rdi], rsp

    # Restore next RSP
    mov rsp, rsi

    # Restore callee-saved registers
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    ret

# fiber_init(stack_bottom, entry_fn) -> int
# Initialize a new fiber's stack and return its initial SP
.globl fiber_init
.type fiber_init, @function
fiber_init:
    # rdi = stack_bottom (highest address of the 16KB stack)
    # rsi = entry_fn (function to call when fiber starts)

    # Set up a fake stack frame so fiber_switch will jump to entry_fn
    # Stack layout (from top):
    #   [return address] = entry_fn
    #   [saved rbp] = 0
    #   [saved r15-r12, rbx] = 0
    # RSP after fiber_switch pops these will be at entry_fn

    mov rax, rdi        # rax = stack_bottom
    sub rax, 48         # Reserve space for callee-saved regs (6*8)
    mov qword [rax], rsi      # Return address = entry_fn

    # Clear registers for clean start
    sub rax, 8          # Fake return address for when entry_fn returns
    xor ecx, ecx
    mov [rax], rcx      # entry_fn returns to 0 = crash (intentional)

    ret

# g_set_curg(ptr) — set current goroutine pointer
# Core-side bridge: rt.s cannot reference Core globals directly
# (they are managed by the ELF backend), so the current G lives here.
.globl g_set_curg
.type g_set_curg, @function
g_set_curg:
    lea rax, [rip + current_g]
    mov [rax], rdi
    ret

# g_get_curg() — get current goroutine pointer
.globl g_get_curg
.type g_get_curg, @function
g_get_curg:
    lea rax, [rip + current_g]
    mov rax, [rax]
    ret

# m_start_workers(n: int) — launch N worker threads via clone
# Each worker runs the scheduler loop (sched_worker_run).
# clone flags: CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD
# = 0x10F00
# syscall 56: clone(flags, child_stack, parent_tid, child_tls, child_tid)
#
# Register usage:
#   rbx = n (total workers to start)
#   r12 = current worker index (0 = main thread, 1..n-1 = workers)
#   r15 = child stack top (scratch)
.globl m_start_workers
.type m_start_workers, @function
m_start_workers:
    push rbx
    push r12
    push r13
    push r15
    mov rbx, rdi         # rbx = n (number of workers)
    xor r12d, r12d       # r12 = 0 (start from index 0; skip 0 = main thread)
.Lworker_loop:
    inc r12              # increment to next worker index (start at 1)
    cmp r12, rbx
    jg .Ldone            # if r12 > n, done

    # Allocate 64KB stack for worker
    push r12
    mov rdi, 65536
    call alloc
    pop r12
    test rax, rax
    jz .Lnext_worker     # skip if alloc fails

    # rax = stack_base, stack_top = base + 65536
    mov r15, rax
    add r15, 65536

    # Set up child stack:
    #   child_stack_top - 8  = worker index (popped by worker_entry)
    #   child_stack_top - 16 = return address (worker_entry)
    lea r13, [rip + worker_entry]
    mov [r15 - 16], r13
    mov [r15 - 8], r12

    # clone(flags=0x10F00, child_stack=r15-16, parent_tid=0, child_tls=0, child_tid=0)
    mov edi, 0x10F00
    lea rsi, [r15 - 16]
    xor edx, edx
    xor r10d, r10d
    xor r8d, r8d
    mov eax, 56          # sys_clone
    syscall

    test rax, rax
    jz .Lchild

.Lnext_worker:
    inc r12
    jmp .Lworker_loop

.Lchild:
    # Child thread: RSP = child_stack = r15 - 16
    # Pop return address (worker_entry) and jump there via ret
    xor ebp, ebp
    ret

.Ldone:
    pop r15
    pop r13
    pop r12
    pop rbx
    ret

# worker_entry: entry point for worker threads spawned by m_start_workers.
# The worker index is at [RSP] (pushed before clone on child stack).
# We pop it and call sched_worker_run(m_idx) — never returns.
worker_entry:
    pop rdi              # rdi = worker index (first arg to sched_worker_run)
    call sched_worker_run
    # Should never return, but just in case:
    mov eax, 60          # exit syscall
    xor edi, edi
    syscall

# goroutine_entry_wrapper: entry point for goroutines spawned via go.
# Called via fiber_init as the fiber entry.
# Reads the current G via g_get_curg(),
# loads saved_fn and saved_arg from G, calls saved_fn(saved_arg),
# sends rax to result_ch, then yields forever.
.globl goroutine_entry_wrapper
.type goroutine_entry_wrapper, @function
goroutine_entry_wrapper:
    call g_get_curg       # rax = current G pointer
    mov rdi, [rax + 56]   # rdi = saved_fn
    mov rsi, [rax + 64]   # rsi = saved_arg
    call rdi              # call saved_fn(saved_arg)
    # rax = return value
    push rax
    call g_get_curg
    mov rdi, [rax + 40]   # rdi = result_ch
    pop rsi               # rsi = return value
    call chan_send        # chan_send(result_ch, return_value)
.Lyield_loop:
    call sched_yield
    jmp .Lyield_loop
