// Tests for parsing Ion S-expressions that represent Scheme programs.
//
// Scheme source is S-expressions, and Ion's S-expression syntax carries most of
// them: whitespace separates elements (no commas), elements nest, and a run of
// operator characters is a valid unquoted symbol inside one. The differences
// matter too, and are pinned here:
//
//   * `-`, `?`, and `!` are Ion operator characters, so a Scheme identifier
//     such as `vector-ref`, `eq?`, or `set!` is three Ion tokens unless it is
//     quoted (`'vector-ref'`).
//   * `#t` and `#f` are not single symbols; Ion's `true` and `false` stand in.
//   * Scheme's quote shorthand `'x` is Ion's unterminated quoted-symbol syntax;
//     write `(quote x)`.

///|
/// The canonical Ion text of a Scheme program written as an S-expression.
fn scheme(text : String) -> String raise @ion.IonError {
  @text.write_ion(@text.read_ion(text))
}

///|
/// A compact description of a value's shape, for structural assertions:
/// `?name` is a symbol, `"text"` a string, and `( ... )` an S-expression.
fn shape(value : @ion.IonValue) -> String raise @ion.IonError {
  match value.kind() {
    @ion.IonValueKind::Sexp(items) => {
      let parts : Array[String] = []
      for item in items {
        parts.push(shape(item))
      }
      "(" + parts.join(" ") + ")"
    }
    @ion.IonValueKind::List(items) => {
      let parts : Array[String] = []
      for item in items {
        parts.push(shape(item))
      }
      "[" + parts.join(" ") + "]"
    }
    @ion.IonValueKind::Symbol(token) => "?" + token.require_text()
    @ion.IonValueKind::String(text) => "\"" + text + "\""
    @ion.IonValueKind::Int(n) => n.to_string()
    @ion.IonValueKind::Bool(b) => b.to_string()
    @ion.IonValueKind::Null(_) => "null"
    _ => "<" + value.ion_type().to_text() + ">"
  }
}

///|
/// The shape of a parsed Scheme program.
fn shape_of(text : String) -> String raise @ion.IonError {
  shape(@text.read_ion(text))
}

///|
test "a call is an operator followed by its arguments" {
  assert_eq(shape_of("(+ 1 2)"), "(?+ 1 2)")
  assert_eq(scheme("(+ 1 2)"), "(+ 1 2)")
  assert_eq(scheme("(- 3 4)"), "(- 3 4)")
  assert_eq(scheme("(* x (+ y 1))"), "(* x (+ y 1))")
  // A negative literal is one element, not the `-` operator applied to `3`.
  assert_eq(shape_of("(-3)"), "(-3)")
}

///|
test "identifier characters are letters, digits, underscore, and dollar" {
  assert_eq(scheme("(car (cdr lst))"), "(car (cdr lst))")
  assert_eq(scheme("(list 1 2 3)"), "(list 1 2 3)")
  assert_eq(shape_of("(a_b c$d e1)"), "(?a_b ?c$d ?e1)")
}

///|
test "operator characters end an identifier" {
  // `-`, `?`, and `!` are operator characters, so these Scheme names split.
  assert_eq(shape_of("(vector-ref v i)"), "(?vector ?- ?ref ?v ?i)")
  assert_eq(shape_of("(eq? a b)"), "(?eq ?? ?a ?b)")
  assert_eq(shape_of("(set! x 1)"), "(?set ?! ?x 1)")
  // Quoting keeps such a name as one symbol.
  assert_eq(scheme("('vector-ref' v i)"), "('vector-ref' v i)")
  assert_eq(shape_of("('eq?' 'set!')"), "(?eq? ?set!)")
}

///|
test "comparison operators and null" {
  assert_eq(scheme("(< a b)"), "(< a b)")
  assert_eq(scheme("(<= a b)"), "(<= a b)")
  assert_eq(scheme("(>= a b)"), "(>= a b)")
  assert_eq(scheme("(= a b)"), "(= a b)")
  // Ion's `null` keyword shadows the Scheme procedure of that name.
  assert_eq(shape_of("(null? x)"), "(null ?? ?x)")
  assert_eq(shape_of("('null' x)"), "(?null ?x)")
}

///|
test "definitions, lambda, let, and conditionals" {
  assert_eq(scheme("(define x 1)"), "(define x 1)")
  assert_eq(
    scheme("(define (square x) (* x x))"),
    "(define (square x) (* x x))",
  )
  assert_eq(
    scheme("(lambda (x) (if (> x 0) x (- x)))"),
    "(lambda (x) (if (> x 0) x (- x)))",
  )
  assert_eq(
    scheme("(let ((x 1) (y 2)) (+ x y))"),
    "(let ((x 1) (y 2)) (+ x y))",
  )
}

///|
test "Ion booleans stand in for Scheme's `#t` and `#f`" {
  assert_eq(scheme("(if true 1 2)"), "(if true 1 2)")
  // `#` is an operator character, so `#t` is two elements.
  assert_eq(shape_of("(#t)"), "(?# ?t)")
  assert_eq(scheme("(if '#t' 1 2)"), "(if '#t' 1 2)")
}

///|
test "quote is written out as a call" {
  assert_eq(scheme("(quote a)"), "(quote a)")
  assert_eq(scheme("(quote (a b c))"), "(quote (a b c))")
  // Ion's `'a'` is a quoted symbol, not Scheme's `'a` shorthand.
  assert_eq(shape_of("'a'"), "?a")
}

///|
test "a dotted pair keeps its dot as an operator" {
  assert_eq(scheme("(a . b)"), "(a . b)")
  assert_eq(shape_of("(a . b)"), "(?a ?. ?b)")
}

///|
test "comments and ragged whitespace normalize away" {
  assert_eq(scheme("(+\n  1 /* two */\n  2\n)"), "(+ 1 2)")
  assert_eq(scheme("(display \"hi\") // greet"), "(display \"hi\")")
}

///|
test "operators that would open a comment are quoted" {
  // `//` and `/*` end an operator when it is read back, so it is quoted.
  assert_eq(scheme("('//')"), "('//')")
  assert_eq(scheme("('+//')"), "('+//')")
  assert_eq(scheme("(+/+)"), "(+/+)")
}

///|
test "a whole program is a datagram of calls" {
  let program = "(define x 1)\n(define y 2)\n(+ x y)"
  let values = @text.read_ion_datagram(program)
  assert_eq(values.length(), 3)
  assert_eq(@text.write_all(values), program)
}

///|
/// The nineteen Ion S-expression operator characters.
let operator_chars : Array[Char] = [
  '!', '#', '%', '&', '*', '+', '-', '.', '/', ';', '<', '=', '>', '?', '@', '^',
  '`', '|', '~',
]

///|
/// A run of operator characters built from `codes`.
fn operator_run(codes : Array[Int]) -> String {
  let sb = StringBuilder()
  for code in codes {
    sb.write_char(operator_chars[(code % 19 + 19) % 19])
  }
  sb.to_string()
}

///|
test "an operator symbol round-trips inside an S-expression" {
  @quickcheck.check((codes : Array[Int]) => {
    let value = @ion.IonValue::sexp([
      @ion.IonValue::symbol(operator_run(codes)),
      @ion.IonValue::int(1),
    ])
    @text.read_ion(@text.write_ion(value)).equals(value)
  })
}

///|
/// A Scheme-like S-expression, used to generate Ion text that represents code.
enum SampleExpr {
  Number(BigInt)
  Identifier(String)
  Str(String)
  Call(Array[SampleExpr])
} derive(Debug)

///|
/// Procedure names, operators, variables, and awkward symbols.
let sample_names : Array[String] = [
  "+", "-", "*", "/", "<", ">", "<=", ">=", "=", "car", "cdr", "cons", "list", "define",
  "lambda", "if", "let", "display", "x", "y", "lst", "eq?", "+//", "vector-ref",
  "'quoted'",
]

///|
/// A generator of Scheme-like S-expressions, nested up to `depth`.
fn sample_gen(depth : Int) -> @quickcheck.Generator[SampleExpr] {
  let atoms = @quickcheck.one_of([
    @quickcheck.int_range(-1000, 1000).map(n => {
      SampleExpr::Number(BigInt::from_int(n))
    }),
    @quickcheck.elements(sample_names).map(name => SampleExpr::Identifier(name)),
    @quickcheck.elements(["hi", "a b", "it's", ""]).map(text => {
      SampleExpr::Str(text)
    }),
  ])
  if depth <= 0 {
    atoms
  } else {
    @quickcheck.one_of([
      atoms,
      sample_gen(depth - 1)
      .array_with_size(3)
      .map(items => SampleExpr::Call(items)),
    ])
  }
}

///|
/// The Ion value for a generated Scheme expression.
fn to_ion(expr : SampleExpr) -> @ion.IonValue {
  match expr {
    SampleExpr::Number(n) => @ion.IonValue::big_int(n)
    SampleExpr::Identifier(name) => @ion.IonValue::symbol(name)
    SampleExpr::Str(text) => @ion.IonValue::string(text)
    SampleExpr::Call(items) => @ion.IonValue::sexp(items.map(to_ion))
  }
}

///|
test "generated Scheme programs round-trip through Ion text" {
  for expr in sample_gen(3).samples(count=200, size=8) {
    let value = to_ion(expr)
    let text = @text.write_ion(value)
    let back = @text.read_ion(text)
    if !back.equals(value) {
      fail("read back \{@text.write_ion(back)} from \{text}")
    }
  }
}

///|
test "generated Scheme programs tokenize back to their source" {
  for expr in sample_gen(3).samples(count=200, size=8) {
    let text = @text.write_ion(to_ion(expr))
    let rebuilt = StringBuilder()
    for token in @text.tokenize(text) {
      rebuilt.write_view(token.slice(text))
    }
    assert_eq(rebuilt.to_string(), text)
  }
}

///|
test "the CST keeps a Scheme program verbatim" {
  let source = "(define (square x) (* x x))"
  let document = @text.parse_cst(source)
  assert_eq(document.values().length(), 1)
  let value = document.values()[0]
  assert_eq(value.slice(source).to_owned(), source)
  assert_true(value.content() is @text.CstContent::Sexp(_))
}

///|
test "the event stream walks a Scheme call" {
  let reader = @text.IonReader::from_text("(+ 1 2)")
  let events : Array[String] = []
  for event in reader.remaining() {
    events.push(event.to_text())
  }
  assert_eq(events, [
    "DocumentStart", "SexpStart", "Scalar(symbol)", "Scalar(int)", "Scalar(int)",
    "SexpEnd", "DocumentEnd",
  ])
}
