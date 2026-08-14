// @ builtins test suite
import io

fn test_sizeof_int() -> int {
    sz := @sizeOf(int);
    // @sizeOf(int) should return 8 on x86-64
    if sz != 8 { return 1; }
    return 0;
}

fn test_sizeof_bool() -> int {
    sz := @sizeOf(bool);
    if sz != 1 { return 1; }
    return 0;
}

fn test_alignof_int() -> int {
    al := @alignOf(int);
    if al != 8 { return 1; }
    return 0;
}

// Struct type for field tests
struct Point { x: int, y: int }

fn test_sizeof_struct() -> int {
    sz := @sizeOf(Point);
    if sz < 8 { return 1; }  // at least 2 ints
    return 0;
}

fn test_no_bounds_check() -> int {
    @no_bounds_check;
    return 0;  // just verifies it compiles
}

fn add(a: int, b: int) -> int { return a + b; }

fn test_inline_hint() -> int {
    result := @inline(add)(3, 4);
    if result != 7 { return 1; }
    return 0;
}

fn test_fields_basic() -> int {
    flds := @fields(Point);
    if str_len(flds) < 3 { return 1; }  // "x,y"
    return 0;
}

fn main() -> int {
    r1 := test_sizeof_int();  if r1 != 0 { print("FAIL sizeof_int: "); println(int_str(r1)); return r1; }
    r2 := test_sizeof_bool();  if r2 != 0 { print("FAIL sizeof_bool: "); println(int_str(r2)); return r2; }
    r3 := test_alignof_int();  if r3 != 0 { print("FAIL alignof_int: "); println(int_str(r3)); return r3; }
    r4 := test_sizeof_struct();  if r4 != 0 { print("FAIL sizeof_struct: "); println(int_str(r4)); return r4; }
    r5 := test_no_bounds_check();  if r5 != 0 { print("FAIL no_bounds_check: "); println(int_str(r5)); return r5; }
    r6 := test_inline_hint();  if r6 != 0 { print("FAIL inline: "); println(int_str(r6)); return r6; }
    r7 := test_fields_basic();  if r7 != 0 { print("FAIL fields: "); println(int_str(r7)); return r7; }
    println("ALL PASS");
    return 0;
}
