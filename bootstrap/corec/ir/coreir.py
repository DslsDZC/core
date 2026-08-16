from dataclasses import dataclass, field
from typing import Optional, List, Any
from corec.ir.base import IRNode, IRVar

# dex 定点缩放精度（与自举侧一致：S = 10^6，6 位小数）
DEX_SCALE = 10 ** 6


class Dex(int):
    """dex 定点缩放值（S = 10^6）——精确十进制语义的解释器表示（数值迁移 Task 4）。

    与 int 的差异：
    - 解释器以 isinstance(operand, Dex) 判定 dex 运算（缩放整数算术）
    - 测试比较：与 float 期望值按缩放语义换算（3.14 → 3140000/10^6 == 3.14）
    """

    def __eq__(self, other):
        if isinstance(other, float):
            return float(self) / DEX_SCALE == other
        return int.__eq__(self, other)

    __hash__ = int.__hash__


@dataclass
class Instr(IRNode): pass

@dataclass
class ConstInstr(Instr):
    value: object
    type: str
    dest: IRVar

@dataclass
class BinaryInstr(Instr):
    op: str
    left: IRVar
    right: IRVar
    dest: IRVar

@dataclass
class UnaryInstr(Instr):
    op: str
    operand: IRVar
    dest: IRVar

@dataclass
class CallInstr(Instr):
    func: str
    args: List[IRVar]
    dest: Optional[IRVar] = None

@dataclass
class ReturnInstr(Instr):
    value: Optional[IRVar] = None

@dataclass
class AllocInstr(Instr):
    type: Any
    dest: IRVar

@dataclass
class AllocStructInstr(Instr):
    struct_name: str
    dest: IRVar
    field_count: int = 0

@dataclass
class AllocArrayInstr(Instr):
    size: int
    dest: IRVar

@dataclass
class LoadInstr(Instr):
    addr: IRVar
    dest: IRVar

@dataclass
class StoreInstr(Instr):
    addr: IRVar
    value: IRVar

@dataclass
class LoadFieldInstr(Instr):
    struct: IRVar
    field: str
    dest: IRVar
    field_index: int = -1

@dataclass
class StoreFieldInstr(Instr):
    struct: IRVar
    field: str
    value: IRVar
    field_index: int = -1

@dataclass
class LoadIndexInstr(Instr):
    array: IRVar
    index: int
    dest: IRVar

@dataclass
class StoreIndexInstr(Instr):
    array: IRVar
    index: int
    value: IRVar

@dataclass
class LoadIndexVarInstr(Instr):
    array: IRVar
    index_var: IRVar
    dest: IRVar

@dataclass
class StoreIndexVarInstr(Instr):
    array: IRVar
    index_var: IRVar
    value: IRVar

@dataclass
class LoadEnumTagInstr(Instr):
    enum_var: IRVar
    dest: IRVar

@dataclass
class MakeEnumInstr(Instr):
    variant: str
    args: List[IRVar]
    dest: IRVar

@dataclass
class RefInstr(Instr):
    variable: IRVar
    dest: IRVar

@dataclass
class BranchInstr(Instr):
    cond: IRVar
    true_label: str
    false_label: str

@dataclass
class JumpInstr(Instr):
    label: str

@dataclass
class LabelInstr(Instr):
    label: str

@dataclass
class PhiInstr(Instr):
    choices: List[tuple]
    dest: IRVar

@dataclass
class ApproxInstr(Instr):
    """Annotation: the declared variable is approved for approximate
    arithmetic. Pure annotation — no operands, no runtime semantics.
    Backends must skip it; semantic enforcement is a later task."""

@dataclass
class BasicBlock(IRNode):
    name: str
    instrs: List[Instr] = field(default_factory=list)

    def terminated(self) -> bool:
        return any(isinstance(i, (ReturnInstr, BranchInstr, JumpInstr)) for i in self.instrs)

@dataclass
class FunctionDef(IRNode):
    name: str
    params: List[IRVar]
    return_type: Any
    blocks: List[BasicBlock] = field(default_factory=list)
    entry: Optional[BasicBlock] = None

@dataclass
class Module(IRNode):
    name: str
    functions: List[FunctionDef] = field(default_factory=list)
    globals: List[IRVar] = field(default_factory=list)
