import io

// Test extern function declarations at top level
extern fn getchar() -> int;
extern fn putchar(c: int) -> int;

fn main() -> int {
    // Verify that extern fn declarations compiled successfully
    // by testing that we can call main correctly
    println("ALL PASS");
    return 0;
}
