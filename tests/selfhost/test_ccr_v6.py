#!/usr/bin/env python3
"""v6 .ccr 格式 IO 测试——段表架构 + ENT 存在结构段（v6 计划 Task 4）。

格式真相：docs/superpowers/specs/2026-09-05-lattice-ir-v6-format.md（§2/§3.4）
+ ccr_io.cr 头注释（v6.0 保守路径：v5 语义段装入段表 + 新增 ENT，Task 4 定稿）。
落盘布局（全 LE，offset 相对文件头）：
  [0]   magic u32 = 0x31524343 ("CCR1")
  [4]   version u32 = 6
  [8]   seg_count u32 = 5
  [12]  reserved u32 = 0
  [16]  段表 5 × 12B {tag u32, offset u32, size u32}（规范序 tag 1..5）
  [76]  段体（tag 升序）：STR / SYM / NOD / ENT / REG
  STR(1): str_count + {len u32, data}
  SYM(2): v5 符号面拼接（自描述计数）：func_meta 28B / vars 12B / str_consts 4B /
          structs / enums / globals 16B / opt_meta——v6.0 未归并（后续任务）
  NOD(3): nod_count + 28B×nod_count（= v5 instrs 内容；NOD id = 文件序）
  ENT(4): ent_count + 28B×ent_count
          {var_id i32, version u32, def_nod i32, live_start u32,
           live_end u32（半开 = 最后使用点+1）, home i32, flags u32}
  REG(5): sg_count + 24B×sg_count（v5 sgs 记录，字段序未重排）
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

    def sym_walk(self):
        """Walk the whole SYM body (7 self-counting subsections, mirrors
        load_ccr) and return per-subsection counts. Asserts end == body size."""
        b = self.body(2)
        pos = 0

        def u32():
            nonlocal pos
            v = struct.unpack_from('<I', b, pos)[0]
            pos += 4
            return v

        n = u32()  # func_count
        pos += n * 28
        n = u32()  # var_count
        pos += n * 12
        n = u32()  # str_const_count
        pos += n * 4
        n = u32()  # struct_count
        for _ in range(n):
            u32()
            fc = u32()
            pos += fc * 8
        n = u32()  # enum_count
        for _ in range(n):
            u32()
            vc = u32()
            for _ in range(vc):
                u32()
                tc = u32()
                pos += tc * 4
        n = u32()  # global_count
        pos += n * 16
        n = u32()  # opt_count
        for _ in range(n):
            u32()
            dl = u32()
            pos += dl
        assert pos == len(b), f"SYM walk ended at {pos} of {len(b)}"
        return pos

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
        sym_end = v6.sym_walk()  # validates the full SYM body layout
        assert sym_end == len(v6.body(2))
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
    assert len([e for e in mem_main if e["def"] >= 0]) == 4, \
        f"main should have 4 def'd entries for x, got {mem_main}"
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


if __name__ == '__main__':
    tests = [test_header_segment_table_and_walk,
             test_ent_record_conversion_matches_dump,
             test_loader_rejects_non_v6_version,
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
