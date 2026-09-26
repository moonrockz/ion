// Black-box tests for the Ion text tokenizer (the concrete syntax layer).

///|
fn token_kinds(text : String) -> Array[String] raise {
  let tokens = @text.tokenize(text)
  let result : Array[String] = []
  for token in tokens {
    result.push(token.kind().to_text())
  }
  result
}

///|
test "tokenize a struct" {
  assert_eq(token_kinds("{a: 1, b: [x, y::2]}"), [
    "{", "symbol(a)", ":", "whitespace", "int", ",", "whitespace", "symbol(b)", ":",
    "whitespace", "[", "symbol(x)", ",", "whitespace", "symbol(y)", "::", "int",
    "]", "}",
  ])
}

///|
test "tokenize scalars and comments" {
  assert_eq(token_kinds("null"), ["null"])
  assert_eq(token_kinds("null.int"), ["null.int"])
  assert_eq(token_kinds("true"), ["bool(true)"])
  assert_eq(token_kinds("nan"), ["float"])
  assert_eq(token_kinds("+inf"), ["float"])
  assert_eq(token_kinds("2007-02-23T12:14Z"), ["timestamp"])
  assert_eq(token_kinds("{{ \"hi\" }}"), ["clob"])
  assert_eq(token_kinds("{{ aGk= }}"), ["blob"])
  assert_eq(token_kinds("// x\n1"), ["comment", "whitespace", "int"])
  assert_eq(token_kinds("/* x */ 1"), ["comment", "whitespace", "int"])
  assert_eq(token_kinds("'''a''' '''b'''"), ["long-string"])
  assert_eq(token_kinds("'hi ho'"), ["quoted-symbol(hi ho)"])
  assert_eq(token_kinds("\"hi\""), ["string"])
}

///|
test "tokenize numbers" {
  assert_eq(token_kinds("0xFF"), ["int"])
  assert_eq(token_kinds("1_000"), ["int"])
  assert_eq(token_kinds("1.5"), ["decimal"])
  assert_eq(token_kinds("1.5e0"), ["float"])
  assert_eq(token_kinds("-0"), ["int"])
}

///|
test "tokenize S-expression operators" {
  assert_eq(token_kinds("(a + b)"), [
    "(", "symbol(a)", "whitespace", "operator(+)", "whitespace", "symbol(b)", ")",
  ])
  assert_eq(token_kinds("(a+-b)"), [
    "(", "symbol(a)", "operator(+-)", "symbol(b)", ")",
  ])
}

///|
test "token spans recover the source verbatim" {
  let text = "{a: 1, // c\n b: 'x'}"
  let tokens = @text.tokenize(text)
  let mut rebuilt = ""
  for token in tokens {
    rebuilt += token.slice(text).to_owned()
  }
  assert_eq(rebuilt, text)
}
