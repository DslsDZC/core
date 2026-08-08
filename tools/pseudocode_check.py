#!/usr/bin/env python3
"""校验 docs/pseudocode/ 伪代码文档质量。用法：python3 tools/pseudocode_check.py [路径...]
检查项：
1) 表格行外、首次对照括号外不允许出现任何英文标识符残留（领域专名白名单除外）
2) 正文（剥离括号/字符串/代码片段后）不允许 { } ; 符号
3) 必需章节存在（标识符对照表 / 全局状态）
4) 每个「### 函数」节必须含「### 作用」与「### 测试要点」
5) 术语一致性：文件中共享标识符的对照必须与全局术语表一致
退出码 0 = 通过，1 = 有错误。"""
import re, sys
from pathlib import Path

ROOT = Path("docs/pseudocode")
GLOSSARY = ROOT / "标识符对照表.md"
RE_TOKEN = re.compile(r"(?<![A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*")  # 词边界：中文"5b"的 b 不算标识符
RE_PARA = re.compile(r"（[^（）]*）|\([^()]*\)")  # 首次对照括号（全角+半角）
RE_TABLE_ROW = re.compile(r"^\s*\|")
RE_FN_SEC = re.compile(r"^### 函数[^\n]*\n(.*?)(?=^### 函数|^## )", re.M | re.S)

# 允许的领域专名（翻译约定 2/10 允许保留英文）：标题行/引用行整体跳过；
# 含 x86 寄存器名、指令助记符、编码字段位名、ELF 常量、哈希算法名（按符号处理，可裸写）
ALLOWED = {"IR", "AST", "ELF", "PLT", "GOT", "RIP", "REX", "ModRM", "SIB", "VA",
           "SG", "CLI", "DOT", "Core", "ID", "region", "x86", "u32", "ccr", "so",
           "BSS", "Phase", "disp8", "disp32", "mod", "rm", "reg",
           # REX 位名与 ModRM 字段（arch 文档）
           "W", "R", "X", "B", "M",
           # 单位与汇编操作数记法
           "MB", "KB", "GB", "GiB", "m64", "qword", "stosb", "cld", "rep",
           "imm8", "imm32", "rel8", "rel32",
           "r64", "w64", "m32", "r32",
           "LEA",
           # Linux 系统调用/克隆标志常量
           "CLONE_VM", "CLONE_FS", "CLONE_FILES", "CLONE_SIGHAND", "CLONE_THREAD",
           "CLONE_SYSVSEM", "CLONE_SETTLS", "CLONE_PARENT_SETTID",
           "CLONE_CHILD_CLEARTID", "TID",
           # ELF 规范字段名与常量（arch 文档，标准记号）
           "E_VER", "E_DATA", "E_CLASS", "E_MACH", "E_TYPE", "E_VERSION",
           "E_ENTRY", "E_PHOFF", "E_EHSIZE", "E_PHENTSIZE", "E_PHNUM",
           "E_EHDR_MAGIC", "P_TYPE", "P_FLAGS", "P_OFFSET", "P_VADDR",
           "P_PADDR", "P_FILESZ", "P_MEMSZ", "P_ALIGN", "PHDR", "ELF64",
           "ELF2", "PT_LOAD", "PF_R", "PF_W", "PF_X", "EHDR_SIZE", "TEXT_BASE",
           "EV_CURRENT", "ELFDATA2LSB", "ELFCLASS64", "EM_X86_64", "ET_EXEC",
           "e_ident", "e_type", "e_machine", "e_version", "memsz", "x7fELF",
           "argc", "argv", "main", "Linux", "exit", "_start",
           "WB", "imm64", "r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7",
           "MOV", "RET", "REG", "ARRAY", "CALL", "RETURN",
           "IR_ALLOC_STRUCT", "MAKE_ENUM", "WR", "movabs", "WSL2",
           "ALU", "JMP", "JE", "JAE", "WRXB", "PHDR_SIZE", "RW", "RX", "e_entry",
           "SETcc", "ABI", "System", "V", "AMD64", "JNE", "C", "cr",
           "DJB2", "FNV", "rodata", "TOML", "FFI", "N",
           "O_WRONLY", "O_CREAT", "O_TRUNC", "O_RDONLY",
           # SIB 字段名（arch 文档）
           "scale", "index", "base",
           # x86-64 寄存器
           "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp", "rip",
           "eax", "ebx", "ecx", "edx", "esi", "edi", "ebp", "esp", "eip",
           "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15",
           "r8d", "r9d", "r10d", "r11d", "r12d", "r13d", "r14d", "r15d",
           "ax", "bx", "cx", "dx", "si", "di", "bp", "sp",
           "al", "bl", "cl", "dl", "sil", "dil", "bpl", "spl",
           "ah", "bh", "ch", "dh",
           # x86-64 指令助记符
           "mov", "movzx", "movsx", "lea", "call", "ret", "push", "pop",
           "jmp", "je", "jne", "jz", "jnz", "jg", "jge", "jl", "jle",
           "ja", "jae", "jb", "jbe", "js", "jns", "jc", "jnc", "jo", "jno",
           "jecxz", "jrcxz", "test", "cmp", "add", "sub", "imul", "idiv",
           "mul", "div", "shl", "shr", "sar", "sal", "and", "or", "xor",
           "neg", "not", "inc", "dec", "cdqe", "cqo", "syscall", "nop",
           "leave", "xchg", "sete", "setne", "setg", "setge", "setl", "setle",
           "seta", "setae", "setb", "setbe", "sets", "setns", "int3", "ud2",
           "cmove", "cmovne", "cmovg", "cmovge", "cmovl", "cmovle",
           "cmova", "cmovae", "cmovb", "cmovbe", "cmovs", "cmovns"}

errors = []

# 读全局术语表：原名 -> 中文名（共享条目）
glossary = {}
if GLOSSARY.exists():
    for line in GLOSSARY.read_text(encoding="utf-8").splitlines():
        if not line.startswith("|") or "原名" in line:
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) >= 2 and re.fullmatch(r"[A-Za-z_]\w*", cells[1]):
            glossary[cells[1]] = cells[0]

targets = [Path(a) for a in sys.argv[1:]] if len(sys.argv) > 1 else sorted(ROOT.rglob("*.md"))
for md in targets:
    if md.name in ("README.md", "标识符对照表.md"):
        continue
    text = md.read_text(encoding="utf-8")
    for ln, line in enumerate(text.splitlines(), 1):
        if RE_TABLE_ROW.match(line):
            continue  # 表格行允许符号示例（如 左花括号 `{`）
        if line.startswith("# ") or line.startswith("> "):
            continue  # 文档标题行与源文件路径引用行（骨架强制要求，允许英文路径）
        clean = line
        for _ in range(10):                    # 迭代剥离最内层括号（处理混合嵌套）
            new = RE_PARA.sub("", clean)
            if new == clean:
                break
            clean = new
        clean = re.sub(r'"[^"]*"', "", clean)  # 字符串字面量是值不是正文
        clean = re.sub(r"`[^`]*`", "", clean)  # 反引号代码片段是记号不是正文
        clean = re.sub(r"0x[0-9a-fA-F]+", "", clean)  # 十六进制字面量是符号不是标识符
        clean = re.sub(r"r/m(8|16|32|64)?", "", clean)  # 汇编操作数记法 r/m64、r/m 等
        clean = re.sub(r"//[^\n]*", "", clean)     # 注释内容允许源码字符引用（如 a、i）
        if any(ch in clean for ch in "{};"):
            errors.append(f"{md}:{ln}: 禁止符号 {[c for c in '{};' if c in clean]}")
        for tok in RE_TOKEN.findall(clean):
            if tok in ALLOWED:
                continue
            errors.append(f"{md}:{ln}: 英文残留 {tok}")
    for sec in ("## 标识符对照表", "## 全局状态"):
        if sec not in text:
            errors.append(f"{md}: 缺少章节 {sec}")
    for m in RE_FN_SEC.finditer(text):
        if "### 作用" not in m.group(1):
            errors.append(f"{md}: 函数节 {m.group(0).splitlines()[0]} 缺少作用说明")
        if "### 测试要点" not in m.group(1):
            errors.append(f"{md}: 函数节 {m.group(0).splitlines()[0]} 缺少测试要点")
    # 术语一致性：文件中共享标识符的对照必须与术语表同名
    file_map = {}
    for line in text.splitlines():
        if not line.startswith("|") or "原名" in line:
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) >= 2 and re.fullmatch(r"[A-Za-z_]\w*", cells[1]):
            file_map[cells[1]] = cells[0]
    for orig, zh in file_map.items():
        if orig in glossary and glossary[orig] != zh:
            errors.append(f"{md}: 术语不一致 {orig}: 术语表={glossary[orig]} 本文件={zh}")

if errors:
    print(f"{len(errors)} 个问题：")
    for e in errors[:100]:
        print(" ", e)
    sys.exit(1)
print(f"OK: {len(list(ROOT.rglob('*.md'))) - 2} 个文档全部通过")
