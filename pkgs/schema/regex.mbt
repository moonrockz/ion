// The regular expressions of the ISL 2.0 `regex` constraint.
//
// ISL 2.0 takes a subset of ECMA 262 regular expressions: code points match
// themselves; `.` matches any code point but a line terminator; character
// classes such as `[a-c\d]` and `[^abc]`; the predefined classes `\d`
// (`[0-9]`), `\s` (`[ \f\n\r\t]`), `\w` (`[A-Za-z0-9_]`), and their
// complements `\D`, `\S`, `\W`; the anchors `^` and `$`; groups `(...)`;
// alternation `|`; and the greedy quantifiers `?`, `*`, `+`, `{n}`, `{n,}`,
// and `{n,m}`. A backslash escapes one of `. ^ $ | ? * + \ [ ] ( ) { }`.
// Anything else, such as a backreference, `(?` constructs, a lazy or
// possessive quantifier, or another escape, is not allowed.
//
// The flag `i` ignores case, for ASCII letters only. The flag `m` makes `^`
// and `$` match at line breaks too. A value is valid when the expression
// matches any part of it.
//
// The expression compiles to a program for a Pike VM, which runs every path
// through the expression at once, one input character at a time. Matching
// takes time linear in the input, and needs no stack for long input, so no
// expression can make it backtrack without end.

///|
/// A predefined character class.
priv enum Predefined {
  Digit
  Space
  Word
} derive(Debug)

///|
/// A member of a character class.
priv enum ClassItem {
  Single(Char)
  Span(Char, Char)
  /// A predefined class, or its complement when the flag is `true`.
  Named(Predefined, Bool)
} derive(Debug)

///|
/// A parsed regular expression.
priv enum Node {
  Literal(Char)
  AnyChar
  /// A character class, negated when the flag is `true`.
  Class(Array[ClassItem], Bool)
  LineStart
  LineEnd
  Sequence(Array[Node])
  Alternation(Array[Node])
  /// A greedy repetition, from a minimum to an optional maximum count.
  Repeat(Node, Int, Int?)
} derive(Debug)

///|
/// A regular expression of the ISL 2.0 `regex` constraint.
pub struct Regex {
  source : String
  ignore_case : Bool
  multiline : Bool
  priv program : Array[Instruction]
} derive(Debug)

///|
/// Parse `source` as an ISL 2.0 regular expression. A construct that ISL 2.0
/// does not allow raises `IonError::DataModel`.
pub fn Regex::new(
  source : String,
  ignore_case? : Bool = false,
  multiline? : Bool = false,
) -> Regex raise @ion.IonError {
  let parser = { chars: source.iter().collect(), pos: 0, }
  let node = parser.alternation()
  if parser.pos < parser.chars.length() {
    // Only an unmatched `)` stops the top-level alternation early.
    raise regex_error("unmatched ')'")
  }
  let program : Array[Instruction] = []
  compile(node, program)
  program.push(Accept)
  if program.length() > max_program {
    raise regex_error("the expression is too large")
  }
  { source, ignore_case, multiline, program, }
}

///|
/// The expression's source text.
pub fn Regex::source(self : Regex) -> String {
  self.source
}

///|
/// Whether the flag `i` is set.
pub fn Regex::ignore_case(self : Regex) -> Bool {
  self.ignore_case
}

///|
/// Whether the flag `m` is set.
pub fn Regex::multiline(self : Regex) -> Bool {
  self.multiline
}

///|
/// Whether the expression matches any part of `text`.
pub fn Regex::matches(self : Regex, text : String) -> Bool {
  let chars : Array[Char] = text.iter().collect()
  // The threads waiting to read the character at `pos`, and for each
  // instruction, the last position a thread reached it at.
  let seen = Array::make(self.program.length(), -1)
  let mut threads : Array[Int] = []
  for pos in 0..<=chars.length() {
    // A match may start at any position.
    if self.add_thread(threads, 0, chars, pos, seen) {
      return true
    }
    if pos == chars.length() {
      break
    }
    let next : Array[Int] = []
    for pc in threads {
      if self.program[pc] is Read(node) &&
        self.reads(node, chars[pos]) &&
        self.add_thread(next, pc + 1, chars, pos + 1, seen) {
        return true
      }
    }
    threads = next
  }
  false
}

///|
fn regex_error(message : String) -> @ion.IonError {
  @ion.IonError::DataModel("invalid regex: " + message)
}

///|
/// The characters a backslash may escape.
let escapable : String = ".^$|?*+\\[](){}"

///|
/// A regular expression being parsed.
priv struct Parser {
  chars : Array[Char]
  mut pos : Int
}

///|
fn Parser::peek(self : Parser) -> Char? {
  self.chars.get(self.pos)
}

///|
fn Parser::alternation(self : Parser) -> Node raise @ion.IonError {
  let branches = [self.sequence()]
  while self.peek() == Some('|') {
    self.pos += 1
    branches.push(self.sequence())
  }
  if branches.length() == 1 {
    branches[0]
  } else {
    Alternation(branches)
  }
}

///|
fn Parser::sequence(self : Parser) -> Node raise @ion.IonError {
  let items : Array[Node] = []
  while self.peek() is Some(c) && c != '|' && c != ')' {
    let atom = self.atom()
    items.push(self.quantified(atom))
  }
  Sequence(items)
}

///|
fn Parser::atom(self : Parser) -> Node raise @ion.IonError {
  guard self.peek() is Some(c) else { raise regex_error("unexpected end") }
  self.pos += 1
  match c {
    '(' => {
      if self.peek() == Some('?') {
        raise regex_error("'(?' constructs are not allowed")
      }
      let inner = self.alternation()
      if self.peek() != Some(')') {
        raise regex_error("unmatched '('")
      }
      self.pos += 1
      inner
    }
    '[' => self.class()
    '.' => AnyChar
    '^' => LineStart
    '$' => LineEnd
    '\\' =>
      match self.escape() {
        Single(c) => Literal(c)
        item => Class([item], false)
      }
    '*' | '+' | '?' | '{' => raise regex_error("'\{c}' has nothing to repeat")
    ']' | '}' => raise regex_error("'\{c}' must be escaped")
    _ => Literal(c)
  }
}

///|
/// The character or predefined class after a backslash.
fn Parser::escape(self : Parser) -> ClassItem raise @ion.IonError {
  guard self.peek() is Some(c) else {
    raise regex_error("a pattern cannot end with '\\'")
  }
  self.pos += 1
  match c {
    'd' => Named(Digit, false)
    'D' => Named(Digit, true)
    's' => Named(Space, false)
    'S' => Named(Space, true)
    'w' => Named(Word, false)
    'W' => Named(Word, true)
    _ if escapable.contains_char(c) => Single(c)
    _ => raise regex_error("'\\\{c}' is not allowed")
  }
}

///|
/// A character class, after its `[`.
fn Parser::class(self : Parser) -> Node raise @ion.IonError {
  let negated = self.peek() == Some('^')
  if negated {
    self.pos += 1
  }
  let items : Array[ClassItem] = []
  while true {
    guard self.peek() is Some(c) else { raise regex_error("unmatched '['") }
    self.pos += 1
    let item = match c {
      ']' => break
      '[' => raise regex_error("a class inside a class is not allowed")
      '\\' => self.escape()
      _ => Single(c)
    }
    // A range, unless the `-` is the last character of the class.
    match (item, self.peek(), self.chars.get(self.pos + 1)) {
      (Single(low), Some('-'), Some(next)) if next != ']' => {
        self.pos += 2
        let high = if next == '\\' {
          match self.escape() {
            Single(high) => high
            _ => raise regex_error("a range cannot end with a class")
          }
        } else if next == '[' {
          raise regex_error("a class inside a class is not allowed")
        } else {
          next
        }
        if high < low {
          raise regex_error("the range \{low}-\{high} is out of order")
        }
        items.push(Span(low, high))
      }
      (Named(_), Some('-'), Some(next)) if next != ']' =>
        raise regex_error("a range cannot start with a class")
      _ => items.push(item)
    }
  }
  Class(items, negated)
}

///|
/// `atom` with the quantifier that follows it, if any.
fn Parser::quantified(self : Parser, atom : Node) -> Node raise @ion.IonError {
  let (min, max) = match self.peek() {
    Some('?') => (0, Some(1))
    Some('*') => (0, None)
    Some('+') => (1, None)
    Some('{') => {
      self.pos += 1
      let min = match self.number() {
        Some(n) => n
        None => raise regex_error("a quantifier needs a lower bound")
      }
      let max = if self.peek() == Some(',') {
        self.pos += 1
        self.number()
      } else {
        Some(min)
      }
      if self.peek() != Some('}') {
        raise regex_error("unmatched '{'")
      }
      if max is Some(max) && max < min {
        raise regex_error("the quantifier {\{min},\{max}} is out of order")
      }
      (min, max)
    }
    _ => return atom
  }
  self.pos += 1
  if atom is (LineStart | LineEnd) {
    raise regex_error("an anchor cannot be repeated")
  }
  if self.peek() is Some('?' | '+') {
    raise regex_error("lazy and possessive quantifiers are not allowed")
  }
  Repeat(atom, min, max)
}

///|
/// A decimal number, or `None` when there is no digit.
fn Parser::number(self : Parser) -> Int? {
  let mut value : Int? = None
  while self.peek() is Some(c) && c >= '0' && c <= '9' {
    self.pos += 1
    value = Some(value.unwrap_or(0) * 10 + (c.to_int() - '0'.to_int()))
  }
  value
}

///|
/// Whether `c` ends a line: `\n`, `\r`, U+2028, or U+2029.
fn is_line_terminator(c : Char) -> Bool {
  c == '\n' || c == '\r' || c == '\u{2028}' || c == '\u{2029}'
}

///|
fn in_predefined(class : Predefined, c : Char) -> Bool {
  match class {
    Digit => c >= '0' && c <= '9'
    Space => c == ' ' || c == '\u{0C}' || c == '\n' || c == '\r' || c == '\t'
    Word => c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_'
  }
}

///|
fn in_class(items : Array[ClassItem], c : Char) -> Bool {
  items
  .iter()
  .any(item => {
    match item {
      Single(single) => c == single
      Span(low, high) => c >= low && c <= high
      Named(class, negated) => in_predefined(class, c) != negated
    }
  })
}

///|
/// Whether `c` matches a character test, folding ASCII case when the flag `i`
/// is set.
fn Regex::char_matches(
  self : Regex,
  accepts : (Char) -> Bool,
  c : Char,
) -> Bool {
  accepts(c) ||
  (
    self.ignore_case &&
    (accepts(c.to_ascii_lowercase()) || accepts(c.to_ascii_uppercase()))
  )
}

///|
/// A Pike VM instruction.
priv enum Instruction {
  /// Read one character that matches a `Literal`, `AnyChar`, or `Class`.
  Read(Node)
  /// Go on at a `LineStart` or `LineEnd` only.
  Check(Node)
  /// Go on at both targets.
  Fork(Int, Int)
  Jump(Int)
  Accept
} derive(Debug)

///|
/// The most instructions an expression may compile to. Counted repetition
/// copies its body, so `(a{1000}){1000}` is too large.
let max_program : Int = 100_000

///|
/// Append the instructions for `node` to `program`.
fn compile(node : Node, program : Array[Instruction]) -> Unit {
  // Stop early when the program is too large; `Regex::new` reports it.
  if program.length() > max_program {
    return
  }
  match node {
    Literal(_) | AnyChar | Class(_, _) => program.push(Read(node))
    LineStart | LineEnd => program.push(Check(node))
    Sequence(items) =>
      for item in items {
        compile(item, program)
      }
    Alternation(branches) => {
      // Each branch but the last forks to itself or to the next branch, and
      // jumps to the end when it is done.
      let jumps : Array[Int] = []
      for index, branch in branches {
        if index < branches.length() - 1 {
          let fork = program.length()
          program.push(Fork(fork + 1, -1))
          compile(branch, program)
          jumps.push(program.length())
          program.push(Jump(-1))
          program[fork] = Fork(fork + 1, program.length())
        } else {
          compile(branch, program)
        }
      }
      for jump in jumps {
        program[jump] = Jump(program.length())
      }
    }
    Repeat(inner, min, max) => {
      for _ in 0..<min {
        if program.length() > max_program {
          return
        }
        compile(inner, program)
      }
      match max {
        None => {
          let fork = program.length()
          program.push(Fork(fork + 1, -1))
          compile(inner, program)
          program.push(Jump(fork))
          program[fork] = Fork(fork + 1, program.length())
        }
        Some(max) => {
          // Each optional copy may be skipped, to the end of them all.
          let forks : Array[Int] = []
          for _ in min..<max {
            if program.length() > max_program {
              return
            }
            forks.push(program.length())
            program.push(Fork(program.length() + 1, -1))
            compile(inner, program)
          }
          for fork in forks {
            program[fork] = Fork(fork + 1, program.length())
          }
        }
      }
    }
  }
}

///|
/// Add a thread at `pc` to `threads`, following forks, jumps, and checks,
/// for the character at `pos`. `true` when a thread reaches `Accept`.
fn Regex::add_thread(
  self : Regex,
  threads : Array[Int],
  pc : Int,
  chars : Array[Char],
  pos : Int,
  seen : Array[Int],
) -> Bool {
  let stack = [pc]
  while stack.pop() is Some(pc) {
    if seen[pc] == pos {
      continue
    }
    seen[pc] = pos
    match self.program[pc] {
      Read(_) => threads.push(pc)
      Check(node) => if self.holds(node, chars, pos) { stack.push(pc + 1) }
      Fork(first, second) => {
        stack.push(second)
        stack.push(first)
      }
      Jump(target) => stack.push(target)
      Accept => return true
    }
  }
  false
}

///|
/// Whether an anchor holds at `pos`.
fn Regex::holds(
  self : Regex,
  anchor : Node,
  chars : Array[Char],
  pos : Int,
) -> Bool {
  match anchor {
    LineStart =>
      pos == 0 || (self.multiline && is_line_terminator(chars[pos - 1]))
    LineEnd =>
      pos == chars.length() ||
      (self.multiline && is_line_terminator(chars[pos]))
    _ => false
  }
}

///|
/// Whether a `Read` node reads `c`.
fn Regex::reads(self : Regex, node : Node, c : Char) -> Bool {
  match node {
    Literal(expected) => self.char_matches(c => c == expected, c)
    AnyChar => !is_line_terminator(c)
    Class(items, negated) =>
      self.char_matches(c => in_class(items, c), c) != negated
    _ => false
  }
}

///|
pub extend Regex with @debug.Debug::{to_repr}
