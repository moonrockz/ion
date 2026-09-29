// Black-box tests for the ISL 2.0 regular expressions.

///|
fn regex(
  source : String,
  ignore_case? : Bool = false,
  multiline? : Bool = false,
) -> @schema.Regex {
  @schema.Regex::new(source, ignore_case~, multiline~) catch {
    error => abort("\{source}: \{error.message()}")
  }
}

///|
test "a regex matches any part of the text" {
  assert_true(regex("b+").matches("abbc"))
  assert_true(!regex("^b").matches("abc"))
  assert_true(regex("c$").matches("abc"))
  assert_true(regex("^$").matches(""))
  assert_true(regex("x*").matches("abc"))
}

///|
test "quantifiers, groups, and alternation" {
  let r = regex("^(a|bc|def){2,3}$")
  for text in ["aa", "bcdef", "defdefdef", "abca"] {
    assert_true(r.matches(text))
  }
  for text in ["", "a", "aaaa", "abc0def"] {
    assert_true(!r.matches(text))
  }
  assert_true(regex("^ab{2,}c$").matches("abbbc"))
  assert_true(!regex("^ab{2,}c$").matches("abc"))
  assert_true(regex("^(ab)*$").matches("ababab"))
  // An empty iteration does not loop.
  assert_true(regex("^(a*)*$").matches("aaa"))
  assert_true(!regex("^(a*)*$").matches("aab"))
}

///|
test "classes, escapes, and code points" {
  assert_true(regex("^[a-c\\d_]+$").matches("ab_09c"))
  assert_true(!regex("[^a-c]").matches("abc"))
  assert_true(regex("^\\w\\s\\W$").matches("a\t!"))
  assert_true(!regex("\\s").matches("\u{0B}"))
  assert_true(regex("^\\.\\*\\[\\]$").matches(".*[]"))
  assert_true(regex("^[😀😊]{2}$").matches("😊😀"))
  // `.` matches a code point, but not a line terminator.
  assert_true(regex("^.$").matches("😊"))
  assert_true(!regex("^.$").matches("\n"))
}

///|
test "the flags i and m" {
  assert_true(regex("hello", ignore_case=true).matches("HeLLo"))
  assert_true(!regex("hello").matches("HELLO"))
  assert_true(regex("[^a]", ignore_case=true).matches("b"))
  assert_true(!regex("[^a]", ignore_case=true).matches("A"))
  let lines = regex("^hello$", multiline=true)
  assert_true(lines.matches("one\r\nhello\ntwo"))
  assert_true(!regex("^hello$").matches("one\nhello"))
  assert_true(!lines.matches("hello there"))
}

///|
test "constructs outside the ISL subset are errors" {
  for
    source in [
      "\\1", "\\p{L}", "\\b", "[a-d[m-p]]", "a*?", "a++", "a{,2}", "(?:a)", "(a",
      "a)", "[a", "a{2,1}", "[z-a]", "*a", "a**", "]", "^*", "\\",
    ] {
    let failed = try @schema.Regex::new(source) catch {
      @ion.IonError::DataModel(_) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(failed, msg=source)
  }
}

///|
test "the regex constraint applies to strings and symbols" {
  let schema = @schema.Schema::load_from_text(
    "type::{ name: code, regex: i::\"^[a-z]{3}$\" }",
  )
  assert_true(schema.is_valid("code", @text.read_ion("ABC")))
  assert_true(schema.is_valid("code", @text.read_ion("\"abc\"")))
  assert_true(!schema.is_valid("code", @text.read_ion("abcd")))
  assert_true(!schema.is_valid("code", @text.read_ion("null.string")))
  assert_true(!schema.is_valid("code", @text.read_ion("123")))
  for
    bad in [
      "regex: \"\"", "regex: 'abc'", "regex: null.string", "regex: I::\"a\"", "regex: i::i::\"a\"",
      "regex: \"(?i)a\"",
    ] {
    let failed = try
      @schema.Schema::load_from_text("type::{ name: t, \{bad} }")
    catch {
      @ion.IonError::DataModel(_) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(failed, msg=bad)
  }
}

///|
test "matching takes linear time and no stack for long input" {
  let long = "a".repeat(100_000)
  assert_true(regex("^a*b$").matches(long + "b"))
  assert_true(!regex("^a*b$").matches(long))
  // A backtracking matcher takes exponential time here.
  assert_true(!regex("^(a*)*b$").matches("a".repeat(40)))
  assert_true(!regex("^(a|aa)+$").matches("a".repeat(5000) + "b"))
}

///|
test "an expression that compiles too large is an error" {
  for source in ["(a{1000}){1000}", "a{0,100000000}"] {
    let failed = try @schema.Regex::new(source) catch {
      @ion.IonError::DataModel(_) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(failed, msg=source)
  }
  assert_true(regex("^a{3,500}$").matches("a".repeat(400)))
}
