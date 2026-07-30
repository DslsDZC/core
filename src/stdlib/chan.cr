// Channel: typed FIFO, goroutine-safe
import sched

fn chan_make(elemsize: int, cap: int) -> int {
    ch := alloc(64);
    buf := alloc(cap * elemsize);
    w64(ch, 0, buf);        // buf
    w64(ch, 8, cap);         // cap
    w64(ch, 16, 0);          // len
    w64(ch, 24, 0);          // head
    w64(ch, 32, elemsize);   // elemsize
    w64(ch, 40, -1);         // send_wait = empty
    w64(ch, 48, -1);         // recv_wait = empty
    w64(ch, 56, 0);          // closed = false
    return ch;
}

fn chan_send(ch: int, val: int) {
    // Copy val into channel buffer
    buf := r64(ch, 0);
    cap := r64(ch, 8);
    len := r64(ch, 16);
    head := r64(ch, 24);
    esize := r64(ch, 32);

    if len < cap {
        // Buffer has space
        tail := (head + len) % cap;
        w64(buf, tail * esize, val);
        w64(ch, 16, len + 1);
    } else {
        // Buffer full: block current goroutine
        // For now: simple blocking wait (yield + retry)
        // In full implementation: add to send_wait list
        loop {
            sched_yield();
            len := r64(ch, 16);
            if len < cap { continue; }
            tail := (head + len) % cap;
            w64(buf, tail * esize, val);
            w64(ch, 16, len + 1);
            break;
        }
    }
}

fn chan_recv(ch: int) -> int {
    buf := r64(ch, 0);
    cap := r64(ch, 8);
    len := r64(ch, 16);
    head := r64(ch, 24);
    esize := r64(ch, 32);

    if len > 0 {
        val := r64(buf, head * esize);
        w64(ch, 24, (head + 1) % cap);
        w64(ch, 16, len - 1);
        return val;
    }

    // Buffer empty: block (yield + retry)
    loop {
        sched_yield();
        len := r64(ch, 16);
        if len > 0 {
            head := r64(ch, 24);
            val := r64(buf, head * esize);
            w64(ch, 24, (head + 1) % cap);
            w64(ch, 16, len - 1);
            return val;
        }
    }
}

fn chan_close(ch: int) {
    w64(ch, 56, 1);  // closed = true
    // Wake up all waiting senders/receivers
    // ... (for now, just mark closed)
}
