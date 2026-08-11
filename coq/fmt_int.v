(* =====================================================================
   fmt_int.v — 用 Coq (Rocq) 验证 Core stdlib 的 int_str ↔ str_int 互逆

   源码: src/stdlib/fmt.cr:96 (int_str), src/stdlib/fmt.cr:134 (str_int)
   文档: docs/coq/README.md

   建模约定 (见 docs/coq/README.md 第①步):
   - string 建模为 list nat (digits 0..9), 消去 alloc/load8/store8/header
   - ASCII +48/-48 消去 (验证算法语义, 不是字符编码)
   - int 建模为 nat (非负情形; 负数/溢出留待后续)

   翻译对照:
   - int_str 循环1 (数位数, 决定 buffer 大小) → 消去 (list 自动增长)
   - int_str 循环2 (从高位往低位填位) → digits_rev (低位在前递归)
   - str_int 主循环 (res = res*10 + d) → parse_fwd (累加器递归)

   验证目标:
   Theorem roundtrip : forall n, parse_fwd 0 (digits n) = n.
   (对任意非负整数 n: str_int(int_str(n)) == n)
   ===================================================================== *)

From Stdlib Require Import List PeanoNat Recdef Lia.
From Stdlib Require Import Wf_nat.
Import ListNotations.

(* ---- int_str 循环2 的翻译: 逆序 digits (低位在前) ----
   除法递归, 结构上不递减, 需 measure + 终止性证明 *)
Function digits_rev (n : nat) {measure (fun x => x) n} : list nat :=
  match n with
  | 0 => nil
  | S _ => (n mod 10) :: digits_rev (n / 10)
  end.
(* 终止性义务: n/10 < n (n ≠ 0) *)
Proof.
  intros.
  apply Nat.div_lt; lia.
Qed.

(* ---- str_int 的翻译: 从左往右解析 (累加器递归, 结构递减, 直接通过) ---- *)
Fixpoint parse_fwd (acc : nat) (ds : list nat) : nat :=
  match ds with
  | nil => acc
  | d :: rest => parse_fwd (acc * 10 + d) rest
  end.

(* ---- 逆序解析: 对应 digits_rev 的逆序列表 (低位系数小) ---- *)
Fixpoint parse_rev (ds : list nat) : nat :=
  match ds with
  | nil => 0
  | d :: rest => d + 10 * parse_rev rest
  end.

(* ---- int_str 的输出: 正序 digits (n=0 特例 "0") ---- *)
Definition digits (n : nat) : list nat :=
  match n with
  | 0 => [0]
  | _ => rev (digits_rev n)
  end.

(* =====================================================================
   引理① (核心): 逆序 digits 解析回来等于原数
   parse_rev (digits_rev n) = n
   证明: 良基归纳 (m < n 的假设), 关键步用 Nat.div_mod 展开 n
   ===================================================================== *)
Lemma parse_rev_digits_rev : forall n : nat, parse_rev (digits_rev n) = n.
Proof.
  induction n as [n IHn] using lt_wf_ind.
  destruct n as [| m].
  - rewrite (digits_rev_equation 0). simpl. reflexivity.
  - (* 用 equation 引理精确展开 digits_rev (S m)，避免 simpl 展开 wf 包装 *)
    rewrite (digits_rev_equation (S m)).
    Opaque Nat.div Nat.modulo Nat.mul.  (* 锁住 div/mod/mul，保持文字形态 *)
    simpl.
    (* parse_rev ((S m) mod 10 :: digits_rev ((S m)/10))
       = (S m) mod 10 + 10 * parse_rev (digits_rev ((S m)/10)) *)
    rewrite IHn; [| apply Nat.div_lt; lia].
    (* 目标: (S m) mod 10 + 10 * ((S m)/10) = S m
       由 Nat.div_mod: S m = 10 * (S m / 10) + S m mod 10 *)
    symmetry.
    (* at 1: 只替换最外层的 S m，不动 mod/div 参数里的 *)
    rewrite (Nat.div_mod (S m) 10) at 1; [ lia | lia ].
Qed.

(* =====================================================================
   引理② (桥): 正序解析 = 逆序解析
   先证 append 一步的展开, 再用它推全列表
   ===================================================================== *)
Lemma parse_fwd_snoc : forall (acc : nat) (l : list nat) (x : nat),
  parse_fwd acc (l ++ [x]) = parse_fwd acc l * 10 + x.
Proof.
  intros acc l x.
  induction l as [| y l' IH] in acc |- *; simpl.
  - reflexivity.
  - rewrite IH. reflexivity.
Qed.

Lemma parse_fwd_rev : forall l : list nat, parse_fwd 0 (rev l) = parse_rev l.
Proof.
  induction l as [| x l' IH]; simpl.
  - reflexivity.
  - rewrite parse_fwd_snoc. rewrite IH. lia.
Qed.

(* =====================================================================
   主定理: 对任意自然数 n, 先转 digits 再解析回来, 等于 n
   ===================================================================== *)
Theorem roundtrip : forall n : nat, parse_fwd 0 (digits n) = n.
Proof.
  intros n.
  unfold digits.
  destruct n as [| n'].
  - simpl. reflexivity.                 (* n = 0: parse_fwd 0 [0] = 0 *)
  - rewrite parse_fwd_rev.              (* 正序解析 = 逆序解析 *)
    apply parse_rev_digits_rev.         (* 核心引理 *)
Qed.
