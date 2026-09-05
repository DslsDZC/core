// === src/arch/hit/hit.cr ===
// 硬件接口表（HIT）：core-x86.toml → 内存表 加载器（M1 Task 1）。
// 设计：docs/superpowers/specs/2026-09-05-hardware-interface-table.md
// 格式：docs/superpowers/plans/2026-09-05-hit-minimal-core-m1.md「表文件格式」节
// 表 = corearch 运行的唯一平台依赖：load_hit_table 把 toml 表文件读成
// 两块紧凑 buffer 表，Task 2 起的表驱动编码器（emit_instr_tabled）直读。
//
// 本文件仅进 corearch 构建清单（build_selfhost_native.py corearch concat），
// corec 不需要。import 行仅为独立 `corec check src/arch/hit/hit.cr` 解析
// （flat concat 构建会剥离 import 行；toml/io/fmt 均已在 corearch 闭包内）。
import io
import toml

// ════════════════════════════════════════════════════════════════
// 内存表布局（Task 2 起直读；LE 存取用 hit_w32/hit_r32）
// ════════════════════════════════════════════════════════════════

// g_hit_events：每事件 32B = 8 × i32
HIT_EVENT_REC : int = 32;
HIT_EV_OFF_ID         : int = 0;   // 最小核事件号（sub=1 nand=2 load=3 store=4）
HIT_EV_OFF_NAME       : int = 4;   // 名字串下标（g_hit_names 表）
HIT_EV_OFF_INPUTS     : int = 8;   // 事件签名（无宽度/寄存器/寻址——最小核抽象）
HIT_EV_OFF_OUTPUTS    : int = 12;
HIT_EV_OFF_SIDE       : int = 16;  // 0 = pure，1 = effect
HIT_EV_OFF_ISA        : int = 20;  // 投影 ISA 码：1 = x86-64（M1 每事件单投影 → 行内复制）
HIT_EV_OFF_STEP_COUNT : int = 24;  // 投影步数（M1 恒 1；多步序列 = M2）
HIT_EV_OFF_STEP_OFF   : int = 28;  // 首步在 g_hit_steps 的字节偏移

// g_hit_steps：每步 20B = 5 × i32
HIT_STEP_REC : int = 20;
HIT_ST_OFF_OP0     : int = 0;   // 指令首字节（无前缀时即 opcode）
HIT_ST_OFF_OP1     : int = 4;   // 第二字节（0 = 无；M1 至多 2 字节 = 前缀+opcode）
HIT_ST_OFF_REG_ROLE : int = 8;  // modrm.reg 角色码：dst=1 src1=2 src2=3 addr=4 val=5
HIT_ST_OFF_RM_ROLE  : int = 12; // modrm.rm 角色码（同上）
HIT_ST_OFF_RM_MODE  : int = 16; // 0 = rm 为寄存器；1 = rm 为 rbp+disp32（槽/常量池寻址）

// 角色/效应/ISA 码
HIT_ROLE_DST  : int = 1;
HIT_ROLE_SRC1 : int = 2;
HIT_ROLE_SRC2 : int = 3;
HIT_ROLE_ADDR : int = 4;
HIT_ROLE_VAL  : int = 5;
HIT_SIDE_PURE : int = 0;
HIT_SIDE_EFFECT : int = 1;
HIT_ISA_X86 : int = 1;

// 表加载全局（hit.cr 仅进 corearch 构建 → 不污染 corec/corelsp；
// 声明放本文件顶部，仿 cir_cache.cr 的 buffer 表惯例）
g_hit_events : string, mut;   g_hit_event_count : int, mut;  g_hit_event_cap : int, mut;
g_hit_steps  : string, mut;   g_hit_step_count : int, mut;   g_hit_step_cap : int, mut;
g_hit_names  : string, mut;   g_hit_name_count : int, mut;   g_hit_name_cap : int, mut;

// ════════════════════════════════════════════════════════════════
// buffer 表小工具（自持：仅用运行时内建 load8/store8/alloc，
// 独立 corec check 亦干净——不依赖 dyn_arr.cr/globals.cr）
// ════════════════════════════════════════════════════════════════

fn hit_copy_bytes(src: string, n: int, dst: string) {
    i : ., mut = 0;
    loop {
        if i >= n { break; }
        store8(dst, i, load8(src, i));
        i = i + 1; }
}

// 4B 小端写/读（仅存非负值——id/字节/码 均非负；字节拆取仿 dyn_arr w32 的
// % 256 惯例——语言无按位 & 运算符）
fn hit_w32(buf: string, pos: int, v: int) {
    store8(buf, pos + 0, v % 256);
    store8(buf, pos + 1, (v / 256) % 256);
    store8(buf, pos + 2, (v / 65536) % 256);
    store8(buf, pos + 3, (v / 16777216) % 256); }

fn hit_r32(buf: string, pos: int) -> int {
    return load8(buf, pos) + load8(buf, pos + 1) * 256 +
           load8(buf, pos + 2) * 65536 + load8(buf, pos + 3) * 16777216; }

fn hit_grow_events(needed: int) {
    if needed < g_hit_event_cap { return; }
    nc : ., mut = g_hit_event_cap * 2;
    if nc < 16 { nc = 16; }
    if nc < needed { nc = needed + 4; }
    nb := alloc(nc * HIT_EVENT_REC);
    hit_copy_bytes(g_hit_events, g_hit_event_cap * HIT_EVENT_REC, nb);
    g_hit_events = nb;
    g_hit_event_cap = nc; }

fn hit_grow_steps(needed: int) {
    if needed < g_hit_step_cap { return; }
    nc : ., mut = g_hit_step_cap * 2;
    if nc < 16 { nc = 16; }
    if nc < needed { nc = needed + 4; }
    nb := alloc(nc * HIT_STEP_REC);
    hit_copy_bytes(g_hit_steps, g_hit_step_cap * HIT_STEP_REC, nb);
    g_hit_steps = nb;
    g_hit_step_cap = nc; }

fn hit_grow_names(needed: int) {
    if needed < g_hit_name_cap { return; }
    nc : ., mut = g_hit_name_cap * 2;
    if nc < 16 { nc = 16; }
    if nc < needed { nc = needed + 4; }
    nb := alloc(nc * 8);
    hit_copy_bytes(g_hit_names, g_hit_name_cap * 8, nb);
    g_hit_names = nb;
    g_hit_name_cap = nc; }

// ════════════════════════════════════════════════════════════════
// toml 文本扫描（表文件结构层；标量值解析复用 stdlib toml.cr）
// ════════════════════════════════════════════════════════════════

// 从 pos 起逐行扫描，返回第一个 tag 匹配的行首偏移；无 → -1。
// 匹配规则：行首（允许前导空白）字节与 tag 完全相等，且 tag 之后只允许
// 行尾 / 空白 / '\r'（CRLF）/ '#'（行尾注释）——容忍手写表的
// "[[event.proj]]   # 注释" 形式；同时避免 "[[event]]" 前缀误配
// "[[event.proj]]"（tag 后必须紧跟界定符）。
fn hit_find_tag(content: string, pos: int, tag: string) -> int {
    slen := str_len(content);
    tlen := str_len(tag);
    p : ., mut = pos;
    loop {
        if p >= slen { break; }
        s : ., mut = p;
        loop {
            if s >= slen { break; }
            c := load8(content, s);
            if c == 32 || c == 9 { s = s + 1; } else { break; }
        }
        e : ., mut = s;
        loop {
            if e >= slen { break; }
            if load8(content, e) == 10 { break; }
            e = e + 1; }
        if s + tlen <= e {
            m : ., mut = 0;
            ok : ., mut = 1;
            loop {
                if m >= tlen { break; }
                if load8(content, s + m) != load8(tag, m) { ok = 0; break; }
                m = m + 1; }
            if ok == 1 {
                if s + tlen == e { return s; }   // tag 到行尾（\n 或 EOF）
                c2 := load8(content, s + tlen);
                if c2 == 13 || c2 == 32 || c2 == 9 || c2 == 35 { return s; }
            }
        }
        p = e + 1; }
    return -1; }

// 事件名 → 角色码（0 = 未知/缺失）
fn hit_role_code(name: string) -> int {
    if str_eq(name, "dst") != 0 { return HIT_ROLE_DST; }
    if str_eq(name, "src1") != 0 { return HIT_ROLE_SRC1; }
    if str_eq(name, "src2") != 0 { return HIT_ROLE_SRC2; }
    if str_eq(name, "addr") != 0 { return HIT_ROLE_ADDR; }
    if str_eq(name, "val") != 0 { return HIT_ROLE_VAL; }
    return 0; }

// 解析一个 [[event.proj]] 块并追加一条 20B 步记录。
// Returns ISA 码（成功，≥1）或 0（失败——错误已打印）。
fn hit_parse_proj_chunk(pc: string, event_id: int) -> int {
    ia := toml_get_str(pc, "isa");
    isa_code : ., mut = 0;
    if str_eq(ia, "x86-64") != 0 { isa_code = HIT_ISA_X86; }
    if isa_code == 0 {
        print("error: HIT table: event "); print_i(event_id); println(" unknown isa");
        return 0; }
    reg_role := hit_role_code(toml_get_str(pc, "modrm_reg_role"));
    rm_role := hit_role_code(toml_get_str(pc, "modrm_rm_role"));
    if reg_role == 0 || rm_role == 0 {
        print("error: HIT table: event "); print_i(event_id); println(" unknown modrm role");
        return 0; }
    rm_mode := toml_get_int(pc, "rm_mode");  // 缺省 0 = rm 为寄存器
    if rm_mode < 0 || rm_mode > 1 {
        print("error: HIT table: event "); print_i(event_id); println(" bad rm_mode");
        return 0; }
    // opcode = [..]：≤2 字节（M1 单步形态：前缀 + opcode）；超出 = M1 形态未实现
    opc := alloc(16);   // 至多 4 项暂存（2 项上限由 n > 2 校验兜底）
    n := toml_get_int_list(pc, "opcode", opc, 4);
    if n < 1 {
        print("error: HIT table: event "); print_i(event_id); println(" opcode missing/malformed");
        return 0; }
    if n > 2 {
        print("error: HIT table: event "); print_i(event_id); println(" opcode >2 bytes (M1 single-step)");
        return 0; }
    // 值域校验：每项须 0..255（字节）——防 >255 静默截断（发射端按字节写）。
    // toml 无负号解析 → 负值不可达，仅查上限。
    j : ., mut = 0;
    loop {
        if j >= n { break; }
        if hit_r32(opc, j * 4) > 255 {
            print("error: HIT table: event "); print_i(event_id);
            println(" opcode byte >255 (not a byte)");
            return 0; }
        j = j + 1; }
    hit_grow_steps(g_hit_step_count + 1);
    sb := g_hit_step_count * HIT_STEP_REC;
    g_hit_step_count = g_hit_step_count + 1;
    hit_w32(g_hit_steps, sb + HIT_ST_OFF_OP0, hit_r32(opc, 0));
    op1 : ., mut = 0;
    if n == 2 { op1 = hit_r32(opc, 4); }
    hit_w32(g_hit_steps, sb + HIT_ST_OFF_OP1, op1);
    hit_w32(g_hit_steps, sb + HIT_ST_OFF_REG_ROLE, reg_role);
    hit_w32(g_hit_steps, sb + HIT_ST_OFF_RM_ROLE, rm_role);
    hit_w32(g_hit_steps, sb + HIT_ST_OFF_RM_MODE, rm_mode);
    return isa_code; }

// 解析一个 [[event]] 块（含其投影块），追加一条 32B 事件记录。
// Returns 0 = 成功；1 = 失败（错误已打印）。
fn hit_parse_event_chunk(chunk: string) -> int {
    id := toml_get_int(chunk, "id");
    if id <= 0 {
        println("error: HIT table: event missing or invalid id");
        return 1; }
    // 重复 id 检测
    k : ., mut = 0;
    loop {
        if k >= g_hit_event_count { break; }
        if hit_r32(g_hit_events, k * HIT_EVENT_REC + HIT_EV_OFF_ID) == id {
            print("error: HIT table: duplicate event id "); print_i(id); println("");
            return 1; }
        k = k + 1; }
    name := toml_get_str(chunk, "name");
    if str_len(name) == 0 {
        print("error: HIT table: event "); print_i(id); println(" missing name");
        return 1; }
    inputs := toml_get_int(chunk, "inputs");
    outputs := toml_get_int(chunk, "outputs");
    se := toml_get_str(chunk, "side_effect");
    side : ., mut = -1;
    if str_eq(se, "pure") != 0 { side = HIT_SIDE_PURE; }
    if str_eq(se, "effect") != 0 { side = HIT_SIDE_EFFECT; }
    if side < 0 {
        print("error: HIT table: event "); print_i(id); println(" bad side_effect");
        return 1; }
    // 名字入本表名字表（g_hit_names 8B/项存串指针；名字 str_sub 副本 arena 存活）
    hit_grow_names(g_hit_name_count + 1);
    name_ni : ., mut = g_hit_name_count;
    g_hit_name_count = name_ni + 1;
    store_str_ptr(g_hit_names, name_ni * 8, name);
    // 事件行追加（isa/步数/步偏移在投影解析后回填）
    hit_grow_events(g_hit_event_count + 1);
    slot := g_hit_event_count;
    g_hit_event_count = slot + 1;
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_ID, id);
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_NAME, name_ni);
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_INPUTS, inputs);
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_OUTPUTS, outputs);
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_SIDE, side);
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_ISA, 0);
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_STEP_COUNT, 0);
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_STEP_OFF, 0);
    // 投影步：M1 每事件恰一个 [[event.proj]]（多步序列投影 = M2）
    first_off := g_hit_step_count * HIT_STEP_REC;
    isa_code : ., mut = 0;
    cnt : ., mut = 0;
    hpos : ., mut = 0;
    loop {
        hdr := hit_find_tag(chunk, hpos, "[[event.proj]]");
        if hdr < 0 { break; }
        cnt = cnt + 1;
        if cnt > 1 {
            print("error: HIT table: event "); print_i(id); println(" has >1 projection step (M2)");
            return 1; }
        nxt := hit_find_tag(chunk, hdr + 1, "[[event.proj]]");
        blk_end : ., mut = str_len(chunk);
        if nxt >= 0 { blk_end = nxt; }
        pc := str_sub(chunk, hdr, blk_end - hdr);
        isa_code = hit_parse_proj_chunk(pc, id);
        if isa_code == 0 { return 1; }
        hpos = blk_end; }
    if cnt == 0 {
        print("error: HIT table: event "); print_i(id); println(" missing [[event.proj]]");
        return 1; }
    // 回填（M1 单投影：步数 = 1；isa 取自该投影行）
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_ISA, isa_code);
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_STEP_COUNT, cnt);
    hit_w32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_STEP_OFF, first_off);
    return 0; }

// ════════════════════════════════════════════════════════════════
// 公共接口（M1 Task 1 契约）
// ════════════════════════════════════════════════════════════════

// 加载 HIT 表文件并填充 g_hit_events/g_hit_steps（计数式重置——重复调用
// 覆盖旧表）。Returns 0 = 成功；1 = 失败（错误已打印，表不可用）。
fn load_hit_table(path: string) -> int {
    content := read_file(path);
    if str_len(content) == 0 {
        print("error: cannot open HIT table: "); println(path);
        return 1; }
    g_hit_event_count = 0;
    g_hit_step_count = 0;
    g_hit_name_count = 0;
    expected := toml_get_int(content, "events");  // [table] events（缺省 0 → 尾部校验兜底）
    pos : ., mut = 0;
    loop {
        hdr := hit_find_tag(content, pos, "[[event]]");
        if hdr < 0 { break; }
        end := hit_find_tag(content, hdr + 1, "[[event]]");
        if end < 0 { end = str_len(content); }
        chunk := str_sub(content, hdr, end - hdr);
        if hit_parse_event_chunk(chunk) != 0 { return 1; }
        pos = end; }
    if g_hit_event_count == 0 {
        println("error: HIT table: no [[event]] sections");
        return 1; }
    if g_hit_event_count != expected {
        print("error: HIT table: [table] events="); print_i(expected);
        print(" parsed="); print_i(g_hit_event_count); println(" mismatch");
        return 1; }
    return 0; }

// 表模式激活态：加载成功（g_hit_event_count > 0）= 发射循环启用表优先
fn hit_table_active() -> int {
    if g_hit_event_count > 0 { return 1; }
    return 0; }

// 事件 id → 事件槽（记录下标）；-1 = 无
fn hit_event_lookup(id: int) -> int {
    i : ., mut = 0;
    loop {
        if i >= g_hit_event_count { break; }
        if hit_r32(g_hit_events, i * HIT_EVENT_REC + HIT_EV_OFF_ID) == id { return i; }
        i = i + 1; }
    return -1; }

// 事件名（诊断用；g_hit_names 表取串）
fn hit_event_name(slot: int) -> string {
    if slot < 0 || slot >= g_hit_event_count { return ""; }
    ni := hit_r32(g_hit_events, slot * HIT_EVENT_REC + HIT_EV_OFF_NAME);
    if ni < 0 || ni >= g_hit_name_count { return ""; }
    return load_str_ptr(g_hit_names, ni * 8); }

// 取事件投影步：把该步 20B 记录原样复制到 out（调用方保证 ≥20B）。
// Returns 0 = 成功；-1 = 事件槽/步号非法。
fn hit_proj_step(event_slot: int, step_i: int, out: string) -> int {
    if event_slot < 0 || event_slot >= g_hit_event_count { return -1; }
    sc := hit_r32(g_hit_events, event_slot * HIT_EVENT_REC + HIT_EV_OFF_STEP_COUNT);
    if step_i < 0 || step_i >= sc { return -1; }
    off := hit_r32(g_hit_events, event_slot * HIT_EVENT_REC + HIT_EV_OFF_STEP_OFF);
    j : ., mut = 0;
    loop {
        if j >= HIT_STEP_REC { break; }
        store8(out, j, load8(g_hit_steps, off + step_i * HIT_STEP_REC + j));
        j = j + 1; }
    return 0; }
