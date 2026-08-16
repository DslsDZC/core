(* harness.ml — McTT→Core 内核移植 M1 参考侧 harness（Task 3）
 *
 * 读查询文件（每行一条查询，`#` 开头为注释行）→ 解析协议 S-表达式 →
 * 分发到提取的 McTT 判定（TypeCheck/Subtyping/NbE）→ 规范输出。
 *
 * 协议（tools/mctt_ref/protocol.md）：
 *   check   <ctx> <exp> <exp>        → check: accept | reject
 *   infer   <ctx> <exp>              → infer: type: <nf-exp> | reject
 *   convert <ctx> <exp> <exp> <exp>  → convert: yes | no
 *   subtype <ctx> <exp> <exp>        → subtype: yes | no
 *
 * 语义总化（协议 §语义）：
 * 提取代码对「判定前提不满足」的输入会触发 assert false（荒谬分支：
 * 读出形状不匹配、应用非函数值、natrec 荒谬情形）——harness 统一捕获
 * Assert_failure 并把该查询按拒绝态处理（check/infer → reject；
 * convert/subtype → no）。此即「全函数化 McTT」：McTT 有定义处输出
 * 与提取代码逐位一致，无定义处输出拒绝态。Core 侧（Task 6）必须以
 * 失败传播实现同一语义。
 *)

open Printf

(* 提取库（McttExtracted，wrapped）经显式别名引用 *)
module Syntax = McttExtracted.Syntax
module TypeCheck = McttExtracted.TypeCheck
module Subtyping = McttExtracted.Subtyping
module NbE = McttExtracted.NbE

(* ---------- 词法：括号 + 原子 ---------- *)

type tok = LP | RP | TAtom of string

exception Parse_error of string

let tokenize (line : string) : tok list =
  let n = String.length line in
  let rec skip_ws i =
    if i < n && (line.[i] = ' ' || line.[i] = '\t' || line.[i] = '\r') then
      skip_ws (i + 1)
    else i
  in
  let rec atom i =
    let j = ref i in
    while
      !j < n
      && line.[!j] <> '(' && line.[!j] <> ')'
      && line.[!j] <> ' ' && line.[!j] <> '\t' && line.[!j] <> '\r'
    do
      incr j
    done;
    if !j = i then raise (Parse_error "expected atom")
    else (String.sub line i (!j - i), !j)
  in
  let rec go i acc =
    let i = skip_ws i in
    if i >= n then List.rev acc
    else if line.[i] = '(' then go (i + 1) (LP :: acc)
    else if line.[i] = ')' then go (i + 1) (RP :: acc)
    else
      let a, j = atom i in
      go j (TAtom a :: acc)
  in
  go 0 []

(* ---------- S-表达式树 ---------- *)

type sexp = SAtom of string | SList of sexp list

(* 从 tok 流解析一个 sexp，返回 (sexp, 剩余 tok) *)
let rec parse_sexp = function
  | LP :: rest ->
      let rec items = function
        | RP :: rest -> ([], rest)
        | [] -> raise (Parse_error "unbalanced parens")
        | toks ->
            let s, rest = parse_sexp toks in
            let l, rest' = items rest in
            (s :: l, rest')
      in
      let l, rest = items rest in
      (SList l, rest)
  | TAtom a :: rest -> (SAtom a, rest)
  | [] -> raise (Parse_error "unexpected end of line")
  | RP :: _ -> raise (Parse_error "unexpected )")

(* ---------- 协议语法 → 提取模块术语值 ---------- *)

let int_of_atom = function
  | SAtom s ->
      if s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s then
        try int_of_string s
        with Failure _ -> raise (Parse_error ("int out of range, got " ^ s))
      else raise (Parse_error ("expected non-negative int, got " ^ s))
  | _ -> raise (Parse_error "expected int atom")

let rec exp_of_sexp = function
  | SList [ SAtom "typ"; n ] -> Syntax.Coq_a_typ (int_of_atom n)
  | SList [ SAtom "nat" ] -> Syntax.Coq_a_nat
  | SList [ SAtom "zero" ] -> Syntax.Coq_a_zero
  | SList [ SAtom "succ"; e ] -> Syntax.Coq_a_succ (exp_of_sexp e)
  | SList [ SAtom "natrec"; a; mz; ms; m ] ->
      Syntax.Coq_a_natrec (exp_of_sexp a, exp_of_sexp mz, exp_of_sexp ms, exp_of_sexp m)
  | SList [ SAtom "pi"; a; b ] -> Syntax.Coq_a_pi (exp_of_sexp a, exp_of_sexp b)
  | SList [ SAtom "fn"; a; m ] -> Syntax.Coq_a_fn (exp_of_sexp a, exp_of_sexp m)
  | SList [ SAtom "app"; m; n ] -> Syntax.Coq_a_app (exp_of_sexp m, exp_of_sexp n)
  | SList [ SAtom "var"; n ] -> Syntax.Coq_a_var (int_of_atom n)
  | SList [ SAtom "sub"; e; s ] -> Syntax.Coq_a_sub (exp_of_sexp e, sub_of_sexp s)
  | _ -> raise (Parse_error "malformed exp")

and sub_of_sexp = function
  | SList [ SAtom "id" ] -> Syntax.Coq_a_id
  | SList [ SAtom "weaken" ] -> Syntax.Coq_a_weaken
  | SList [ SAtom "compose"; s1; s2 ] ->
      Syntax.Coq_a_compose (sub_of_sexp s1, sub_of_sexp s2)
  | SList [ SAtom "extend"; s; e ] ->
      Syntax.Coq_a_extend (sub_of_sexp s, exp_of_sexp e)
  | _ -> raise (Parse_error "malformed sub")

(* 上下文：exp list，头部 = 最近绑定 = var 0（kernel-spec.md §0.1） *)
let ctx_of_sexp = function
  | SList (SAtom "ctx" :: es) -> List.map exp_of_sexp es
  | _ -> raise (Parse_error "malformed ctx")

(* ---------- 输出：nf/ne 按协议 S-表达式打印 ---------- *)

let rec sub_to_string = function
  | Syntax.Coq_a_id -> "(id)"
  | Syntax.Coq_a_weaken -> "(weaken)"
  | Syntax.Coq_a_compose (s1, s2) ->
      "(compose " ^ sub_to_string s1 ^ " " ^ sub_to_string s2 ^ ")"
  | Syntax.Coq_a_extend (s, e) ->
      "(extend " ^ sub_to_string s ^ " " ^ exp_to_string e ^ ")"

and exp_to_string = function
  | Syntax.Coq_a_typ n -> "(typ " ^ string_of_int n ^ ")"
  | Syntax.Coq_a_nat -> "(nat)"
  | Syntax.Coq_a_zero -> "(zero)"
  | Syntax.Coq_a_succ e -> "(succ " ^ exp_to_string e ^ ")"
  | Syntax.Coq_a_natrec (a, mz, ms, m) ->
      "(natrec " ^ exp_to_string a ^ " " ^ exp_to_string mz ^ " "
      ^ exp_to_string ms ^ " " ^ exp_to_string m ^ ")"
  | Syntax.Coq_a_pi (a, b) -> "(pi " ^ exp_to_string a ^ " " ^ exp_to_string b ^ ")"
  | Syntax.Coq_a_fn (a, m) -> "(fn " ^ exp_to_string a ^ " " ^ exp_to_string m ^ ")"
  | Syntax.Coq_a_app (m, n) -> "(app " ^ exp_to_string m ^ " " ^ exp_to_string n ^ ")"
  | Syntax.Coq_a_var n -> "(var " ^ string_of_int n ^ ")"
  | Syntax.Coq_a_sub (e, s) -> "(sub " ^ exp_to_string e ^ " " ^ sub_to_string s ^ ")"

(* 推断结果（nf）经 nf_to_exp 打印为协议 exp 语法 *)
let nf_to_string (nf : Syntax.nf) : string = exp_to_string (Syntax.nf_to_exp nf)

(* ---------- 查询分发 ---------- *)

(* 注意：提取的 type_check 签名是 (ctx, 类型, 项)——类型在前、项在后
   （TypeCheck.ml: `type_check g a m` 判定 m : a）；协议行是
   `check <ctx> <项> <类型>`，故此处交换实参。type_infer 为 (ctx, 项)。 *)

type query =
  | QCheck of Syntax.exp list * Syntax.exp * Syntax.exp
  | QInfer of Syntax.exp list * Syntax.exp
  | QConvert of Syntax.exp list * Syntax.exp * Syntax.exp * Syntax.exp
  | QSubtype of Syntax.exp list * Syntax.exp * Syntax.exp

let parse_query (toks : tok list) : query =
  match toks with
  | TAtom "check" :: rest ->
      let c, r1 = parse_sexp rest in
      let t, r2 = parse_sexp r1 in
      let ty, r3 = parse_sexp r2 in
      if r3 <> [] then raise (Parse_error "extra tokens in check query");
      QCheck (ctx_of_sexp c, exp_of_sexp t, exp_of_sexp ty)
  | TAtom "infer" :: rest ->
      let c, r1 = parse_sexp rest in
      let t, r2 = parse_sexp r1 in
      if r2 <> [] then raise (Parse_error "extra tokens in infer query");
      QInfer (ctx_of_sexp c, exp_of_sexp t)
  | TAtom "convert" :: rest ->
      let c, r1 = parse_sexp rest in
      let t1, r2 = parse_sexp r1 in
      let t2, r3 = parse_sexp r2 in
      let ty, r4 = parse_sexp r3 in
      if r4 <> [] then raise (Parse_error "extra tokens in convert query");
      QConvert (ctx_of_sexp c, exp_of_sexp t1, exp_of_sexp t2, exp_of_sexp ty)
  | TAtom "subtype" :: rest ->
      let c, r1 = parse_sexp rest in
      let a, r2 = parse_sexp r1 in
      let b, r3 = parse_sexp r2 in
      if r3 <> [] then raise (Parse_error "extra tokens in subtype query");
      QSubtype (ctx_of_sexp c, exp_of_sexp a, exp_of_sexp b)
  | TAtom cmd :: _ -> raise (Parse_error ("unknown command: " ^ cmd))
  | _ -> raise (Parse_error "expected command")

(* 语义总化：提取代码的荒谬分支（assert false）→ 拒绝态。
   'a option = None 表示触发了荒谬分支（提取代码 assert false）。 *)
let totalized (f : unit -> 'a) : 'a option =
  try Some (f ()) with Assert_failure _ -> None

let run_query (q : query) : string =
  match q with
  | QCheck (ctx, t, ty) -> (
      match totalized (fun () -> TypeCheck.type_check ctx ty t) with
      | Some true -> "check: accept"
      | _ -> "check: reject")
  | QInfer (ctx, t) -> (
      match totalized (fun () -> TypeCheck.type_infer ctx t) with
      | Some (Some nf) -> "infer: type: " ^ nf_to_string nf
      | _ -> "infer: reject")
  | QConvert (ctx, t1, t2, ty) -> (
      match
        totalized (fun () ->
            Syntax.nf_eq_dec (NbE.nbe_impl ctx t1 ty) (NbE.nbe_impl ctx t2 ty))
      with
      | Some true -> "convert: yes"
      | _ -> "convert: no")
  | QSubtype (ctx, a, b) -> (
      match totalized (fun () -> Subtyping.subtyping_impl ctx a b) with
      | Some true -> "subtype: yes"
      | _ -> "subtype: no")

(* ---------- 逐行处理 ---------- *)

(* 返回 true 表示该行是注释/空行（无输出） *)
let is_comment_or_blank (line : string) : bool =
  let l = String.trim line in
  l = "" || l.[0] = '#'

let process_line (line : string) (malformed : int ref) : unit =
  if not (is_comment_or_blank line) then
    let toks = tokenize line in
    match parse_query toks with
    | exception Parse_error msg ->
        incr malformed;
        eprintf "harness: parse error: %s (line: %s)\n%!" msg line
    | q -> print_endline (run_query q)

let () =
  let args = Array.to_list Sys.argv in
  match args with
  | _ :: _ :: _ ->
      let malformed = ref 0 in
      List.iter
        (fun file ->
          let ic = open_in file in
          (try
             while true do
               process_line (input_line ic) malformed
             done
           with End_of_file -> ());
          close_in ic)
        (List.tl args);
      if !malformed > 0 then exit 1
  | _ ->
      eprintf "usage: %s QUERY_FILE...\n" Sys.argv.(0);
      exit 1
