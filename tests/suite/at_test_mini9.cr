import io

struct Point { x: int, y: int }

fn test_fields_basic() -> int {
    flds := @fields(Point);
    // check flds contains field names
    if str_len(flds) < 4 { return 1; }
    return 0;
}

fn main() -> int {
    r7 := test_fields_basic();  if r7 != 0 { print("FAIL fields: "); println(int_str(r7)); return r7; }
    println("ALL PASS");
    return 0;
}
