#!/usr/bin/env python3
"""dex 类型核心测试（Python bootstrap）—— 数值迁移 Task 3。

bootstrap 与自举侧同步认识 dex（内部类型名 'float' → 'dex'，binary64 实现保留
= apx 快路径参考实现）；float 关键字并存期仍接受（映射到同一 dex 类型）。

断言点：
- `fn main() -> dex` + `x : dex = 3.14` 全管线通过（解释执行返回 3.14）
- dex 算术（Python float 实现 = binary64 参考）结果正确
- float 关键字并存期仍有效（与 dex 同一类型）
"""
import sys
sys.path.insert(0, 'bootstrap')

from corec.frontend.lexer import Lexer
from corec.frontend.parser import Parser
from corec.frontend.name_resolver import NameResolver
from corec.frontend.desugar import MatchDesugarer
from corec.frontend.type_checker import TypeChecker
from corec.frontend.ir_gen import IRGen
from corec.backend.interpreter import Interpreter


def run_test(name, src, expected):
    """Compile Core source through the full bootstrap pipeline and compare interpreter result."""
    try:
        lex = Lexer(src)
        ast = Parser(lex.tokenize()).parse_compilation_unit()
        resolver = NameResolver()
        resolver.resolve(ast)
        desugarer = MatchDesugarer(resolver.symtab)
        ast = desugarer.desugar(ast)
        checker = TypeChecker(resolver.symtab)
        checker.check(ast)
        if resolver.errors or checker.errors:
            print(f"[FAIL] {name}: errors={resolver.errors + checker.errors}")
            return False
        ir_gen = IRGen(resolver.symtab)
        mod = ir_gen.gen_module(ast)
        interp = Interpreter(mod)
        result = interp.run('main', [])
        if result == expected:
            print(f"[PASS] {name}: got {result}")
            return True
        print(f"[FAIL] {name}: expected {expected}, got {result}")
        return False
    except Exception as e:
        print(f"[ERROR] {name}: {e}")
        import traceback; traceback.print_exc()
        return False


def main():
    results = [
        run_test('Dex Declare + Literal', '''
fn main() -> dex {
    x : dex = 3.14;
    return x;
}
''', 3.14),
        run_test('Dex Arithmetic', '''
fn main() -> dex {
    return 1.5 + 1.25;
}
''', 2.75),
        run_test('Float Keyword Co-existence', '''
fn main() -> float {
    x : float = 3.14;
    return x;
}
''', 3.14),
    ]
    print(f"{sum(results)}/{len(results)} passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
