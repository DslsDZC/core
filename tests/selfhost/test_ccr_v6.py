#!/usr/bin/env python3
"""v6 .ccr 格式 IO 测试——段表架构 + ENT 存在结构段 + SYM 归并/REG 坐标化。

格式真相：docs/superpowers/specs/2026-09-05-lattice-ir-v6-format.md（§2/§3.2/§3.5）
+ ccr_io.cr 头注释（v6 目标形状：SYM 归并 spec §3.2——globals/funcs/str_consts/
structs/enums/opt_meta；REG 坐标化 spec §3.5——kind/parent/enter/exit/first_ent/
last_ent）。
落盘布局（全 LE，offset 相对文件头）：
  [0]   magic u32 = 0x31524343 ("CCR1")
  [4]   version u32 = 6
  [8]   seg_count u32 = 5
  [12]  reserved u32 = 0
  [16]  段表 5 × 12B {tag u32, offset u32, size u32}（规范序 tag 1..5）
  [76]  段体（tag 升序）：STR / SYM / NOD / ENT / REG
  STR(1): str_count + {len u32, data}
  SYM(2): v5 vars/globals 归并——globals 16B（var_idx 槽 → type）前置 +
          函数记录内嵌 var 声明区（v5 vars 表并入，位置即行序）：
    [global_count][globals × {name u32, type u32, init_val i64}]
    [func_count][funcs × {name u32, param_count u32, ret_type u32,
                 root_region i32, first_ent i32, last_ent i32 |
                 param_ents[param_count]×i32（参数 def=-1 条目 id，-1=无）|
                 var_count u32, var_decls[var_count]×{name u32, type u32}}]
    [str_const_count][×4B][structs][enums][opt_meta]
  NOD(3): nod_count + 28B×nod_count（= v5 instrs 内容；NOD id = 文件序）
  ENT(4): ent_count + 28B×ent_count
          {var_id i32, version u32, def_nod i32, live_start u32,
           live_end u32（半开 = 最后使用点+1）, home i32, flags u32}
  REG(5): sg_count + 24B×sg_count {kind u32, parent i32, enter_nod u32,
          exit_nod u32, first_ent i32, last_ent i32}（v5 nstart/ncount 由
          enter/exit 派生；first/last = 区内条目范围——定值点 ∈ [enter, exit)）
"""
import os
import re
import struct
import subprocess
import tempfile

BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COREC = os.path.join(BASE, 'build/corec')
COREARCH = os.path.join(BASE, 'build/corearch')

MAGIC = 0x31524343  # "CCR1"
V6 = 6
SEG_TAGS = [1, 2, 3, 4, 5]  # STR SYM NOD ENT REG
NOD_REC = 28
ENT_REC = 28
REG_REC = 24


class V6File:
    """Parse a v6 .ccr file into its segments. Raises AssertionError on layout
    violations (mirrors load_ccr's segment-table contract)."""

    def __init__(self, data: bytes):
        self.d = data
        assert len(data) >= 76, f"file too small for v6 header+table: {len(data)}"
        (magic, ver, seg_count, reserved) = struct.unpack_from('<4I', data, 0)
        assert magic == MAGIC, f"bad magic {magic:#x}"
        assert ver == V6, f"expected version {V6}, got {ver}"
        assert seg_count == 5, f"expected 5 segments, got {seg_count}"
        assert reserved == 0, f"reserved != 0: {reserved}"
        # Segment table: canonical order, contiguous layout
        self.segs = {}
        cur = 16 + seg_count * 12  # first body follows the whole table
        for i, tag in enumerate(SEG_TAGS):
            (t, off, size) = struct.unpack_from('<3I', data, 16 + i * 12)
            assert t == tag, f"row {i}: expected tag {tag}, got {t}"
            assert off == cur, f"tag {tag}: expected offset {cur}, got {off}"
            assert off + size <= len(data), f"tag {tag}: body out of file"
            self.segs[tag] = (off, size)
            cur = off + size
        assert cur == len(data), f"segments end at {cur} of {len(data)} bytes"
        self.fsize = len(data)

    def body(self, tag: int):
        off, size = self.segs[tag]
        return self.d[off:off + size]

    # --- segment record walkers (each body starts with its count) ---

    def str_table(self):
        b = self.body(1)
        (n,) = struct.unpack_from('<I', b, 0)
        pos = 4
        strs = []
        for _ in range(n):
            (ln,) = struct.unpack_from('<I', b, pos)
            pos += 4
            strs.append(b[pos:pos + ln].decode('utf-8', 'replace'))
            pos += ln
        assert pos == len(b), f"STR walk ended at {pos} of {len(b)}"
        return strs

    def sym_parse(self):
        """Parse the whole SYM body (target shape: globals → funcs with embedded
        var-decl areas → str_consts → structs → enums → opt_meta). Asserts
        end == body size (mirrors load_ccr). Returns a structured dict."""
        b = self.body(2)
        pos = 0

        def u32():
            nonlocal pos
            v = struct.unpack_from('<I', b, pos)[0]
            pos += 4
            return v

        def i32():
            nonlocal pos
            v = struct.unpack_from('<i', b, pos)[0]
            pos += 4
            return v

        g = u32()  # global_count
        globals_ = []
        for _ in range(g):
            (name, ty, init) = struct.unpack_from('<IIq', b, pos)
            pos += 16
            globals_.append({'name': name, 'type': ty, 'init': init})
        n = u32()  # func_count
        funcs = []
        for _ in range(n):
            (name, pc, rt, root, fe, le) = struct.unpack_from('<IIiiii', b, pos)
            pos += 24
            param_ents = [i32() for _ in range(pc)]
            vc = u32()  # var_count
            decls = []
            for _ in range(vc):
                (vn, vt) = struct.unpack_from('<II', b, pos)
                pos += 8
                decls.append({'name': vn, 'type': vt})
            funcs.append({'name': name, 'param_count': pc, 'ret_type': rt,
                          'root_region': root, 'first_ent': fe, 'last_ent': le,
                          'param_ents': param_ents, 'var_count': vc,
                          'var_decls': decls})
        scn = u32()  # str_const_count
        pos += scn * 4
        stn = u32()  # struct_count
        for _ in range(stn):
            u32()
            fc = u32()
            pos += fc * 8
        en = u32()  # enum_count
        for _ in range(en):
            u32()
            vc2 = u32()
            for _ in range(vc2):
                u32()
                tc = u32()
                pos += tc * 4
        oc = u32()  # opt_count
        for _ in range(oc):
            u32()
            dl = u32()
            pos += dl
        assert pos == len(b), f"SYM walk ended at {pos} of {len(b)}"
        return {'globals': globals_, 'funcs': funcs,
                'str_const_count': scn, 'struct_count': stn,
                'enum_count': en, 'opt_count': oc}

    def nod(self):
        b = self.body(3)
        (n,) = struct.unpack_from('<I', b, 0)
        assert (len(b) - 4) % NOD_REC == 0, "NOD body size not a multiple of 28"
        assert n == (len(b) - 4) // NOD_REC, f"NOD count {n} != bytes/28"
        pos = 4
        out = []
        for _ in range(n):
            (op, dest) = struct.unpack_from('<Ii', b, pos)
            (s1,) = struct.unpack_from('<q', b, pos + 8)
            (s2, s3) = struct.unpack_from('<ii', b, pos + 16)
            (tk,) = struct.unpack_from('<I', b, pos + 24)
            out.append((op, dest, s1, s2, s3, tk))
            pos += NOD_REC
        return out

    def ent(self):
        b = self.body(4)
        (n,) = struct.unpack_from('<I', b, 0)
        assert (len(b) - 4) % ENT_REC == 0, "ENT body size not a multiple of 28"
        assert n == (len(b) - 4) // ENT_REC, f"ENT count {n} != bytes/28"
        pos = 4
        out = []
        for _ in range(n):
            # var_id i32, version u32, def_nod i32, live_start u32,
            # live_end u32 (half-open), home i32, flags u32
            out.append(struct.unpack_from('<iIiIIiI', b, pos))
            pos += ENT_REC
        return out

    def reg(self):
        """REG rows: {kind, parent, enter_nod, exit_nod, first_ent, last_ent}."""
        b = self.body(5)
        (n,) = struct.unpack_from('<I', b, 0)
        assert (len(b) - 4) % REG_REC == 0, "REG body size not a multiple of 24"
        assert n == (len(b) - 4) // REG_REC, f"REG count {n} != bytes/24"
        pos = 4
        out = []
        for _ in range(n):
            out.append(struct.unpack_from('<6i', b, pos))
            pos += REG_REC
        return out


def corec_ccr(src: str, out: str) -> str:
    """Run `corec ccr` on src; returns stdout."""
    with tempfile.NamedTemporaryFile('w', suffix='.cr', delete=False) as f:
        f.write(src)
        path = f.name
    try:
        r = subprocess.run([COREC, 'ccr', path, '-o', out],
                           capture_output=True, text=True, cwd=BASE, timeout=120)
        assert r.returncode == 0, f"corec ccr failed rc={r.returncode}: {r.stderr}"
        return r.stdout
    finally:
        os.unlink(path)


def read_ccr(path: str) -> bytes:
    with open(path, 'rb') as fh:
        return fh.read()


def dump_entries(src: str) -> tuple:
    """cir --dump-entries 通道：(rc, stdout)。内存闭区间表 = 落盘 ENT 的源头。"""
    with tempfile.NamedTemporaryFile('w', suffix='.cr', delete=False) as f:
        f.write(src)
        path = f.name
    try:
        r = subprocess.run([COREC, 'cir', path, '--dump-entries'],
                           capture_output=True, text=True, cwd=BASE, timeout=120)
        return r.returncode, r.stdout
    finally:
        os.unlink(path)


ENTRY_LINE = re.compile(
    r"^e (\d+) var (\d+) name=(\S+) v (\d+) def (-?\d+) kind=(\S+) "
    r"live (\d+)\.\.(\d+) home (-?\d+) flags (\d+)$")
HEADER_LINE = re.compile(r"^== entries func (\d+) \((.*)\): (\d+)$")


def parse_entry_blocks(out: str) -> dict:
    blocks = {}
    cur = None
    for raw in out.splitlines():
        ln = raw.strip()
        m = HEADER_LINE.match(ln)
        if m:
            blocks[m.group(2)] = []
            cur = blocks[m.group(2)]
            continue
        m = ENTRY_LINE.match(ln)
        if m and cur is not None:
            cur.append({
                "e": int(m.group(1)), "var": int(m.group(2)), "name": m.group(3),
                "v": int(m.group(4)), "def": int(m.group(5)), "kind": m.group(6),
                "ls": int(m.group(7)), "le": int(m.group(8)),
                "home": int(m.group(9)), "flags": int(m.group(10)),
            })
    return blocks


def ent_groups(entries: list) -> dict:
    """Group disk ENT records by var_id (order preserved)."""
    groups = {}
    for rec in entries:
        groups.setdefault(rec[0], []).append(rec)
    return groups


# --- tests ---

def test_header_segment_table_and_walk():
    """段表架构：magic/version=6/5 段规范序/offset 连续/走完 == 文件大小。"""
    src = ("fn add(a: int, b: int) -> int { return a + b; }\n"
           "fn main() -> int {\n"
           "    s : ., mut = 0;\n"
           "    for i in 0..4 { s = s + i; }\n"
           "    return s;\n"
           "}\n")
    ccr_path = os.path.join(BASE, 'build/test_v6_layout.ccr')
    try:
        os.unlink(ccr_path)
    except FileNotFoundError:
        pass
    try:
        corec_ccr(src, ccr_path)
        v6 = V6File(read_ccr(ccr_path))
        # every segment body present and non-empty beyond its count
        assert v6.fsize > 76
        strs = v6.str_table()
        assert len(strs) >= 2, f"expected >=2 strings, got {len(strs)}"
        sym = v6.sym_parse()  # validates the full SYM body layout
        assert len(sym['funcs']) >= 1 and len(sym['globals']) >= 1
        n = v6.nod()
        assert len(n) > 4, f"expected nodes, got {len(n)}"
        reg = v6.reg()
        assert len(reg) >= 2, f"expected >=2 regions (func+for), got {len(reg)}"
        e = v6.ent()
        assert len(e) > 0, "expected entries, got none"
    finally:
        try:
            os.unlink(ccr_path)
        except FileNotFoundError:
            pass


def test_ent_record_conversion_matches_dump():
    """ENT 落盘转换 = 内存闭区间表 + version 序数 + live_end 半开 +1：
    cir --dump-entries（内存表，闭区间/组内版本序）↔ .ccr ENT 逐条对照：
    var 相同、disk ls == mem ls、disk le == mem le + 1、disk version == 组内序数。"""
    src = ("fn identity(n: int) -> int { return n; }\n"
           "fn main() -> int {\n"
           "    x := 1;\n"
           "    x = x + 1;\n"
           "    x = x + 2;\n"
           "    return x;\n"
           "}\n")
    # memory side (dump-entries is the same entry table save_ccr serializes)
    rc, out = dump_entries(src)
    assert rc == 0, f"dump-entries rc={rc}\n{out[-500:]}"
    blocks = parse_entry_blocks(out)
    assert "main" in blocks, f"no main block in dump:\n{out}"
    mem_main = blocks["main"]
    # GC 批 2 后 main 的临时 producer 也有 def'd 条目——x 的 4 版本按 name 断言
    x_ent = [e for e in mem_main if e["name"] == "x"]
    assert len(x_ent) == 4 and all(e["def"] >= 0 for e in x_ent), \
        f"main/x should have 4 def'd entries, got {x_ent}"
    # flatten all function blocks: the disk ENT spans every compiled func
    # (res_imports pulls in stdlib funcs, so the file covers > the source funcs)
    mem = [e for blk in blocks.values() for e in blk]
    # disk side
    ccr_path = os.path.join(BASE, 'build/test_v6_ent.ccr')
    try:
        os.unlink(ccr_path)
    except FileNotFoundError:
        pass
    try:
        corec_ccr(src, ccr_path)
        v6 = V6File(read_ccr(ccr_path))
        entries = v6.ent()
        nod_cnt = len(v6.nod())
        # structural invariants first
        for (var_id, ver, df, ls, le, home, flags) in entries:
            assert ver >= 1, f"version must be 1-based: {entries}"
            assert 0 <= ls < le <= nod_cnt, \
                f"bad half-open range {ls}..{le} (nod_count={nod_cnt}): {entries}"
            if df >= 0:
                assert df < nod_cnt, f"def_nod {df} out of range: {entries}"
                assert df == ls, f"def'd entry live_start {ls} != def {df}: {entries}"
            else:
                assert ls >= 0
            assert home == -1, f"home must be -1 pre-allocation: {entries}"
        # per-var groups: ascending defs, adjacent versions meet at def point
        # (disk half-open slicing: le_j == ls_{j+1} == def_{j+1})
        for var_id, group in ent_groups(entries).items():
            if len(group) < 2:
                continue
            for j in range(1, len(group)):
                assert group[j][1] == group[j - 1][1] + 1, \
                    f"versions not sequential for var {var_id}: {group}"
                assert group[j][0] == var_id
                if group[j - 1][3] >= 0:  # prev is def'd → sliced at next def
                    assert group[j - 1][4] == group[j][3], \
                        f"version slice gap for var {var_id}: {group}"
        # map disk entry -> memory entry (same var, same def), compare fields
        mem_by_var_def = {}
        for e in mem:
            mem_by_var_def[(e["var"], e["def"])] = e
        matched = 0
        for (var_id, ver, df, ls, le, home, flags) in entries:
            key = (var_id, df)
            e = mem_by_var_def.get(key)
            assert e is not None, f"disk entry (var {var_id}, def {df}) not in memory table"
            assert ls == e["ls"], \
                f"var {var_id} v{ver}: disk ls {ls} != mem ls {e['ls']}"
            assert le == e["le"] + 1, \
                f"var {var_id} v{ver}: disk half-open le {le} != mem le+1 {e['le'] + 1}"
            assert ver == e["v"], \
                f"var {var_id}: disk version {ver} != mem ordinal {e['v']}"
            matched += 1
        assert matched == len(entries), "not all disk entries matched"
        assert len(entries) == len(mem), \
            f"disk entry count {len(entries)} != memory entry count {len(mem)}"
    finally:
        try:
            os.unlink(ccr_path)
        except FileNotFoundError:
            pass


def test_loader_rejects_non_v6_version():
    """v6-only：version 字段改成 5（或任意非 6）→ corearch 必须拒绝。"""
    src = "fn main() -> int { return 42; }\n"
    ccr_path = os.path.join(BASE, 'build/test_v6_reject.ccr')
    try:
        os.unlink(ccr_path)
    except FileNotFoundError:
        pass
    try:
        corec_ccr(src, ccr_path)
        data = bytearray(read_ccr(ccr_path))
        struct.pack_into('<I', data, 4, 5)  # patch version to 5
        bad_path = ccr_path + '.v5'
        with open(bad_path, 'wb') as fh:
            fh.write(bytes(data))
        r = subprocess.run([COREARCH, bad_path, '--elf', '--static',
                            '-o', os.path.join(BASE, 'build/test_v6_reject.out')],
                           capture_output=True, text=True, cwd=BASE, timeout=60)
        assert r.returncode != 0, \
            f"corearch accepted a v5-patched file: rc={r.returncode} {r.stdout!r}"
        assert 'invalid' in (r.stdout + r.stderr), \
            f"expected invalid-.ccr error, got: {r.stdout!r} {r.stderr!r}"
    finally:
        for p in (ccr_path, ccr_path + '.v5', os.path.join(BASE, 'build/test_v6_reject.out')):
            try:
                os.unlink(p)
            except FileNotFoundError:
                pass


def test_ccr_v6_roundtrip_elf():
    """v6 落盘 → corec build 全链路（corec save v6 → corearch load v6 → ELF）：
    程序计算 0+1+2+3+4+5 = 15，ELF 运行时以 main 返回值为退出码。"""
    src = ("fn main() -> int {\n"
           "    s : ., mut = 0;\n"
           "    for i in 0..6 { s = s + i; }\n"
           "    return s;\n"
           "}\n")
    ccr_path = os.path.join(BASE, 'build/test_v6_rt.ccr')
    out = os.path.join(BASE, 'build/test_v6_rt')
    try:
        os.unlink(ccr_path)
    except FileNotFoundError:
        pass
    try:
        os.unlink(out)
    except FileNotFoundError:
        pass
    try:
        with tempfile.NamedTemporaryFile('w', suffix='.cr', delete=False) as f:
            f.write(src)
            path = f.name
        # 1) corec build (its own corearch invocation) round-trips v6
        r = subprocess.run([COREC, 'build', path, '-o', out, '--static'],
                           capture_output=True, text=True, cwd=BASE, timeout=120)
        assert r.returncode == 0, f"corec build failed: {r.stderr}"
        os.chmod(out, 0o755)
        run = subprocess.run([out], capture_output=True, text=True, timeout=10)
        assert run.returncode == 15, \
            f"expected exit 15 (sum 0..5), got {run.returncode} stdout={run.stdout!r}"
        assert os.path.exists(ccr_path), "corec build did not save .ccr alongside output"
        v6 = V6File(read_ccr(ccr_path))  # the built artifact is v6
        assert v6.ent(), "built .ccr carries no ENT segment"
        # 2) direct corearch invocation on the same .ccr
        out2 = os.path.join(BASE, 'build/test_v6_rt2')
        try:
            os.unlink(out2)
        except FileNotFoundError:
            pass
        r = subprocess.run([COREARCH, ccr_path, '--elf', '--static', '-o', out2],
                           capture_output=True, text=True, cwd=BASE, timeout=120)
        assert r.returncode == 0, f"corearch load v6 failed: {r.stdout} {r.stderr}"
        os.chmod(out2, 0o755)
        run2 = subprocess.run([out2], capture_output=True, text=True, timeout=10)
        assert run2.returncode == 15, \
            f"corearch-only run expected 15, got {run2.returncode} stdout={run2.stdout!r}"
        try:
            os.unlink(out2)
        except FileNotFoundError:
            pass
    finally:
        os.unlink(path)
        for p in (ccr_path, out):
            try:
                os.unlink(p)
            except FileNotFoundError:
                pass


def test_sym_reg_target_shape():
    """SYM 归并/REG 坐标化目标形状（spec §3.2/§3.5 落地）：
    - SYM func 记录 = {name/param_count/ret_type/root_region/first_ent/last_ent}
      + param_ents + var 声明区（v5 vars 表并入）；globals 记录带 type；
    - REG 记录 = {kind, parent, enter_nod, exit_nod, first_ent, last_ent}；
    - 根 region（SG_FUNC）行与 func 记录 1:1，span 连续铺满 NOD 空间，
      first/last = 本函数条目块；嵌套 region 条目范围 = 定值点 ∈ [enter, exit)
      （文件条目序连续一段）；变量命名空间行数覆盖 ENT/NOD 引用。"""
    src = ("fn main() -> int {\n"
           "    s : ., mut = 0;\n"
           "    for i in 0..4 { s = s + i; }\n"
           "    return s;\n"
           "}\n")
    ccr_path = os.path.join(BASE, 'build/test_v6_symreg.ccr')
    try:
        os.unlink(ccr_path)
    except FileNotFoundError:
        pass
    try:
        corec_ccr(src, ccr_path)
        v6 = V6File(read_ccr(ccr_path))
        sym = v6.sym_parse()
        globs = sym['globals']
        funcs = sym['funcs']
        strs = v6.str_table()
        nod_cnt = len(v6.nod())
        ents = v6.ent()
        regs = v6.reg()
        # func 记录
        assert len(funcs) >= 1
        f = funcs[0]
        assert strs[f['name']] == 'main', f"func0 is {strs[f['name']]!r}"
        assert f['param_count'] == 0
        assert f['var_count'] >= f['param_count']
        decl_names = [strs[d['name']] for d in f['var_decls']]
        assert len(decl_names) == f['var_count']
        # 局部变量声明随函数记录落盘（for 循环变量内部名 = for_i）
        for want in ('s', 'for_i'):
            assert want in decl_names, \
                f"local {want} missing from func var decls: {decl_names}"
        # 全局记录：有数据（>=1 条），全局行数 = var 行序前缀（func0 var 基准）
        assert len(globs) >= 1
        g_base = len(globs)
        # REG: 根行（kind=0）与 func 1:1；span 连续铺满 NOD 空间
        roots = [(i, r) for i, r in enumerate(regs) if r[0] == 0]
        assert len(roots) == len(funcs), \
            f"SG_FUNC rows {len(roots)} != func records {len(funcs)}"
        prev_end = 0
        for k, (rid, r) in enumerate(roots):
            assert funcs[k]['root_region'] == rid, \
                f"func {k} root_region {funcs[k]['root_region']} != row {rid}"
            assert r[2] == prev_end, \
                f"root {k} enter {r[2]} != previous end {prev_end}"
            prev_end = r[3]
            # 根 region 条目范围 == 函数条目块（SYM func 记录同值）
            assert funcs[k]['first_ent'] == r[4] and funcs[k]['last_ent'] == r[5]
            assert (r[4] == -1) == (r[5] == -1)
        assert prev_end == nod_cnt, \
            f"root spans end at {prev_end}, nod_count {nod_cnt}"
        # 嵌套 region：first/last = def_nod ∈ [enter, exit) 的文件序连续段
        for rid, r in enumerate(regs):
            if r[0] == 0:
                assert r[1] == -1, f"root {rid} parent != -1: {r}"
                continue
            if r[1] >= 0:
                p = regs[r[1]]
                assert r[2] >= p[2] and r[3] <= p[3], \
                    f"region {rid} escapes parent span: {r} vs {p}"
            exp = {ei for ei, en in enumerate(ents)
                   if en[2] >= 0 and r[2] <= en[2] < r[3]}
            if not exp:
                assert r[4] == -1 and r[5] == -1, \
                    f"empty region {rid} has range {r[4]}..{r[5]}"
            else:
                assert r[4] == min(exp) and r[5] == max(exp), \
                    f"region {rid} range {r[4]}..{r[5]} != expected {min(exp)}..{max(exp)}"
                got = set(range(r[4], r[5] + 1))
                assert got == exp, \
                    f"region {rid} run not exactly the def'd-in-range set"
        # 变量命名空间（globals + 各 func var_count）覆盖 ENT var id / NOD dest
        total_vars = len(globs) + sum(fn['var_count'] for fn in funcs)
        for en in ents:
            assert 0 <= en[0] < total_vars, \
                f"ENT var_id {en[0]} outside var namespace 0..{total_vars - 1}"
        for (op, dest, s1, s2, s3, tk) in v6.nod():
            if dest >= 0:
                assert dest < total_vars, f"NOD dest {dest} outside var namespace"
    finally:
        try:
            os.unlink(ccr_path)
        except FileNotFoundError:
            pass


def test_sym_func_params_blocks():
    """函数记录 param_ents（参数 def=-1 条目 id）+ 条目块序（文件序 = 函数序）：
    参数变量 = 函数 var 声明区前 param_count 个（行序 = 参数序，类型 int）；
    add 全条目 def=-1；main 的 x 重定值切 4 个定值条目（dump-entries 同源）。"""
    src = ("fn add(a: int, b: int) -> int { return a + b; }\n"
           "fn main() -> int {\n"
           "    x := 1;\n"
           "    x = x + 1;\n"
           "    x = x + 2;\n"
           "    return x;\n"
           "}\n")
    ccr_path = os.path.join(BASE, 'build/test_v6_symparams.ccr')
    try:
        os.unlink(ccr_path)
    except FileNotFoundError:
        pass
    try:
        corec_ccr(src, ccr_path)
        v6 = V6File(read_ccr(ccr_path))
        sym = v6.sym_parse()
        funcs = sym['funcs']
        strs = v6.str_table()
        ents = v6.ent()
        regs = v6.reg()
        assert strs[funcs[0]['name']] == 'add'
        assert strs[funcs[1]['name']] == 'main'
        g_base = len(sym['globals'])
        # add: 参数声明 = var 声明区前 2 个（a, b, TI_INT=0）
        add = funcs[0]
        assert add['param_count'] == 2
        assert add['var_count'] >= 3
        pdecls = add['var_decls'][:2]
        assert [strs[d['name']] for d in pdecls] == ['a', 'b']
        assert [d['type'] for d in pdecls] == [0, 0], "int param type != TI_INT"
        nod = v6.nod()
        a_block = ents[add['first_ent']:add['last_ent'] + 1]
        # GC 批 2（dest≥0 全定值）：add 的 producer 临时值（_arena/binary 组）有
        # def'd 版本条目；a/b 参数无定值 → def=-1 单条目（块内扫描定位——参数
        # def=-1 条目不再占据块首，位置式断言已不可用）
        defd_add = [en for en in a_block if en[2] >= 0]
        assert len(defd_add) >= 1, f"add has no def'd producer entries: {a_block}"
        excluded = {16, 26, 44}  # STORE_INDEX_VAR/STORE_PTR/DYN_DISPATCH dest 非定值
        assert not ({nod[en[2]][0] for en in defd_add} & excluded), \
            f"add def'd entry from excluded op: {a_block}"
        # param_ents 指向 a/b 的 def=-1 入参条目（var 扫描）；a/b 各恰一条
        for pi, pvar in enumerate((g_base, g_base + 1)):
            pid = add['param_ents'][pi]
            assert pid >= 0, f"param {pi} entry missing: {add['param_ents']}"
            assert ents[pid][0] == pvar and ents[pid][2] == -1, \
                f"param {pi} entry wrong var/def: {ents[pid]}"
            no_defs = [en for en in a_block if en[0] == pvar and en[2] == -1]
            assert len(no_defs) == 1, f"param {pi}: def=-1 entries != 1: {no_defs}"
        # 文件条目块 = 函数序（main 块紧接 add 块——add 块非空）
        main_f = funcs[1]
        assert main_f['first_ent'] == add['last_ent'] + 1
        # 根 region（kind=0）行序 = 函数序 1:1（含目录 _import 拉入的 stdlib 函数）
        roots = [(i, r) for i, r in enumerate(regs) if r[0] == 0]
        assert len(roots) == len(funcs)
        assert funcs[0]['root_region'] == roots[0][0]
        assert funcs[1]['root_region'] == roots[1][0]
        assert roots[0][1][4] == add['first_ent'] and roots[0][1][5] == add['last_ent']
        assert roots[1][1][4] == main_f['first_ent'] and roots[1][1][5] == main_f['last_ent']
        # main: x 重定值 → ALLOC+3×STORE = 4 个版本条目（def_nod ops [6,9,9,9]；
        # GC 批 2 后 main 还有 producer 组（CONST/BINARY/ARENA_NEW）——按组断言：
        # ops 组合 [6,9,9,9] 的 4 版本组即 x）
        main_block = ents[main_f['first_ent']:main_f['last_ent'] + 1]
        groups = ent_groups(main_block)
        x_group = [g for g in groups.values()
                   if len(g) == 4 and [nod[en[2]][0] for en in g] == [6, 9, 9, 9]]
        assert len(x_group) == 1, \
            f"main: no x group (4 versions, ALLOC+3 STORE): {main_block}"
        assert [en[1] for en in x_group[0]] == [1, 2, 3, 4], \
            f"x versions not sequential: {x_group[0]}"
        # GC 批 2 扩权实证：main 的 def'd 条目数 > 4（临时 producer 组入条目）
        defd_main = [en for en in main_block if en[2] >= 0]
        assert len(defd_main) > 4, \
            f"main should have producer temp def'd entries beyond x: {main_block}"
    finally:
        try:
            os.unlink(ccr_path)
        except FileNotFoundError:
            pass


def test_loader_rejects_root_span_beyond_nod_space():
    """GC-3（SYM 评审 M1）：REG root span 对 NOD 空间上界校验。

    loader 解析序 REG → NOD：root region（SG_FUNC 行）的 enter/exit 在 REG
    段解析时就回填成函数指令边界，但 instr_cnt 直到 NOD 段才可知——彼时
    无上界校验（ENT 有 ele > instr_cnt 拒绝先例）。损坏文件把末函数 root
    region 的 exit_nod 推出 NOD 空间（exit == instr_cnt + 1）→ corearch 必须
    拒绝（'invalid .ccr'）。守卫缺失时 loader 静默接受并在缓冲外读指令
    发射（GC-1 同族数据面缺陷）。"""
    src = ("fn main() -> int {\n"
           "    s : ., mut = 0;\n"
           "    for i in 0..4 { s = s + i; }\n"
           "    return s;\n"
           "}\n")
    ccr_path = os.path.join(BASE, 'build/test_v6_rootspan.ccr')
    try:
        os.unlink(ccr_path)
    except FileNotFoundError:
        pass
    try:
        corec_ccr(src, ccr_path)
        data = bytearray(read_ccr(ccr_path))
        v6 = V6File(bytes(data))
        regs = v6.reg()
        nod_cnt = len(v6.nod())
        # 末函数 root region（最后一个 kind==0 行）：span 末 = NOD 空间末
        # （根行 span 连续铺满 NOD 空间的不变量），exit_nod += 1 → 越界
        roots = [i for i, r in enumerate(regs) if r[0] == 0]
        assert roots, f"no SG_FUNC rows in REG: {regs}"
        rid = roots[-1]
        assert regs[rid][3] == nod_cnt, \
            f"last root exit {regs[rid][3]} != nod_count {nod_cnt}: {regs[rid]}"
        reg_off, _ = v6.segs[5]
        patch_at = reg_off + 4 + rid * REG_REC + 12  # exit_nod field (+12 in row)
        struct.pack_into('<i', data, patch_at, regs[rid][3] + 1)
        bad_path = ccr_path + '.oob'
        with open(bad_path, 'wb') as fh:
            fh.write(bytes(data))
        r = subprocess.run([COREARCH, bad_path, '--elf', '--static',
                            '-o', os.path.join(BASE, 'build/test_v6_rootspan.out')],
                           capture_output=True, text=True, cwd=BASE, timeout=60)
        assert r.returncode != 0, \
            f"corearch accepted root span beyond NOD space: rc={r.returncode} {r.stdout!r}"
        assert 'invalid' in (r.stdout + r.stderr), \
            f"expected invalid-.ccr error, got: {r.stdout!r} {r.stderr!r}"
    finally:
        for p in (ccr_path, ccr_path + '.oob',
                  os.path.join(BASE, 'build/test_v6_rootspan.out')):
            try:
                os.unlink(p)
            except FileNotFoundError:
                pass


def test_save_rejects_var_block_misalignment():
    """GC-4（SYM 评审 M2）：save var 行序位置级守卫。

    计数级守卫（Σ func var_count == var_count + var_idx==gi）总量守恒时察觉
    不到块错位——func0 声明区起点左移 1（--inject-var-shift 测试钩子，真实
    构建路径永不注入）后 Σ 不变，旧实现静默落盘行序错位的文件（声明区/
    var 命名空间漂移）。位置级守卫（vs == 前缀累计）必须拒绝：rc != 0、
    不落盘。"""
    src = ("fn add(a: int, b: int) -> int { return a + b; }\n"
           "fn main() -> int {\n"
           "    x := 1;\n"
           "    return x + 1;\n"
           "}\n")
    ccr_path = os.path.join(BASE, 'build/test_v6_varshift.ccr')
    with tempfile.NamedTemporaryFile('w', suffix='.cr', delete=False) as f:
        f.write(src)
        path = f.name
    try:
        os.unlink(ccr_path)
    except FileNotFoundError:
        pass
    try:
        r = subprocess.run([COREC, 'ccr', path, '-o', ccr_path,
                            '--inject-var-shift'],
                           capture_output=True, text=True, cwd=BASE, timeout=120)
        out = r.stdout + r.stderr
        assert r.returncode != 0, \
            f"save accepted misaligned var block (rc=0):\n{out}"
        assert 'inject-var-shift: precondition' not in out, \
            f"hook precondition failed — test not exercising the guard:\n{out}"
        assert not os.path.exists(ccr_path), \
            "save wrote a .ccr file despite rejecting"
    finally:
        os.unlink(path)
        try:
            os.unlink(ccr_path)
        except FileNotFoundError:
            pass


if __name__ == '__main__':
    tests = [test_header_segment_table_and_walk,
             test_ent_record_conversion_matches_dump,
             test_sym_reg_target_shape,
             test_sym_func_params_blocks,
             test_loader_rejects_non_v6_version,
             test_loader_rejects_root_span_beyond_nod_space,
             test_save_rejects_var_block_misalignment,
             test_ccr_v6_roundtrip_elf]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"FAIL {t.__name__}: {e}")
        except Exception as e:
            failed += 1
            print(f"ERROR {t.__name__}: {e!r}")
    print(f"{len(tests) - failed}/{len(tests)} passed")
    raise SystemExit(1 if failed else 0)
