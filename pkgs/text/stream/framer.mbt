// Finding where a top-level value may end in text that arrives a chunk at a
// time.
//
// Parsing an unfinished value again after every chunk costs time quadratic in
// its length. The framer reads each code unit once and keeps just enough
// lexical state (container depth, strings, comments, lobs, and unquoted
// tokens) to see when the text is back at the top level between values. A
// value can end only there, or settle within the few code units after it, so
// only then is a parse worth trying.

///|
/// The lexical context of the code unit the framer reads next.
priv enum Mode {
  /// Between tokens.
  Normal
  /// Inside an unquoted top-level token, such as a number or a symbol.
  Token
  /// Inside a `"..."` string.
  ShortString
  /// Inside a `'...'` symbol.
  QuotedSymbol
  /// Inside a `'''...'''` string.
  LongString
  /// Inside a `//` comment.
  LineComment
  /// Inside a `/* ... */` comment.
  BlockComment
}

///|
/// The lexical state of the text read so far.
priv struct Framer {
  mut mode : Mode
  /// The previous code unit was a backslash inside a string or symbol.
  mut escaped : Bool
  /// The number of open containers and lobs.
  mut depth : Int
  /// Inside a `{{ ... }}` lob, where `/` does not start a comment.
  mut in_lob : Bool
  /// The code units read since the text was last at the top level.
  mut since_top : Int
  /// Since the reader last cleared this flag, the text was at the top level
  /// between values, or a code unit arrived that may settle the value before.
  mut at_top : Bool
}

///|
/// How many code units after the top level may settle the value before
/// them: `@text.read_ion_prefix` settles a value that does not close with a
/// delimiter once three code units follow it.
let settle_lookahead : Int = 3

///|
/// A framer at the start of a stream.
fn Framer::new() -> Framer {
  {
    mode: Normal,
    escaped: false,
    depth: 0,
    in_lob: false,
    since_top: 0,
    at_top: false,
  }
}

///|
/// Read `text` from `from` on, and return where the framer stopped. It stops
/// before the end only at a code unit whose meaning depends on text that has
/// not arrived yet, such as a `/` that may start a comment.
fn Framer::scan(self : Framer, text : StringView, from : Int) -> Int {
  let mut index = from
  while index < text.length() {
    self.note_top()
    match self.step(text, index) {
      Some(width) => {
        index += width
        self.since_top += width
        if self.since_top <= settle_lookahead {
          self.at_top = true
        }
      }
      None => break
    }
  }
  self.note_top()
  index
}

///|
/// Record whether the text is at the top level between values.
fn Framer::note_top(self : Framer) -> Unit {
  if self.depth == 0 && self.mode is Normal {
    self.since_top = 0
    self.at_top = true
  }
}

///|
/// Read the code unit at `index`: the number of code units it spans with the
/// code units it needs after it, or `None` when those have not arrived yet. A
/// width of zero ends a token without reading the code unit, which the next
/// step reads again between tokens.
fn Framer::step(self : Framer, text : StringView, index : Int) -> Int? {
  let c = text[index]
  match self.mode {
    LineComment => {
      if c == '\n' || c == '\r' {
        self.mode = Normal
      }
      Some(1)
    }
    BlockComment =>
      if c != '*' {
        Some(1)
      } else {
        match unit_at(text, index + 1) {
          None => None
          Some('/') => {
            self.mode = Normal
            Some(2)
          }
          _ => Some(1)
        }
      }
    ShortString => self.string_step(c, '"')
    QuotedSymbol => self.string_step(c, '\'')
    LongString =>
      if self.escaped || c == '\\' {
        self.string_step(c, '\'')
      } else if c == '\'' {
        match (unit_at(text, index + 1), unit_at(text, index + 2)) {
          (Some('\''), Some('\'')) => {
            self.mode = Normal
            Some(3)
          }
          (None, _) | (Some('\''), None) => None
          _ => Some(1)
        }
      } else {
        Some(1)
      }
    Token =>
      if ends_token(c) {
        self.mode = Normal
        Some(0)
      } else {
        Some(1)
      }
    Normal =>
      if self.in_lob {
        self.lob_step(text, index)
      } else {
        self.normal_step(text, index)
      }
  }
}

///|
/// Read a code unit inside a string or symbol that `close` ends. A backslash
/// escapes the code unit after it.
fn Framer::string_step(self : Framer, c : UInt16, close : UInt16) -> Int? {
  if self.escaped {
    self.escaped = false
  } else if c == '\\' {
    self.escaped = true
  } else if c == close {
    self.mode = Normal
  }
  Some(1)
}

///|
/// Read a code unit between tokens, outside a lob.
fn Framer::normal_step(self : Framer, text : StringView, index : Int) -> Int? {
  match text[index] {
    '[' | '(' => {
      self.depth += 1
      Some(1)
    }
    ']' | ')' | '}' => {
      if self.depth > 0 {
        self.depth -= 1
      }
      Some(1)
    }
    '{' =>
      match unit_at(text, index + 1) {
        None => None
        Some('{') => {
          self.depth += 1
          self.in_lob = true
          Some(2)
        }
        _ => {
          self.depth += 1
          Some(1)
        }
      }
    '"' => {
      self.mode = ShortString
      Some(1)
    }
    '\'' => self.quote_step(text, index, QuotedSymbol)
    '/' =>
      match unit_at(text, index + 1) {
        None => None
        Some('/') => {
          self.mode = LineComment
          Some(2)
        }
        Some('*') => {
          self.mode = BlockComment
          Some(2)
        }
        _ => Some(1)
      }
    c => {
      if self.depth == 0 && !ends_token(c) {
        self.mode = Token
      }
      Some(1)
    }
  }
}

///|
/// Read a code unit inside a lob, where only strings and the closing `}}`
/// matter.
fn Framer::lob_step(self : Framer, text : StringView, index : Int) -> Int? {
  match text[index] {
    '"' => {
      self.mode = ShortString
      Some(1)
    }
    '\'' => self.quote_step(text, index, Normal)
    '}' =>
      match unit_at(text, index + 1) {
        None => None
        Some('}') => {
          self.in_lob = false
          self.depth -= 1
          Some(2)
        }
        _ => Some(1)
      }
    _ => Some(1)
  }
}

///|
/// Read a `'`, which opens a long string when two more follow it and
/// otherwise enters `single`.
fn Framer::quote_step(
  self : Framer,
  text : StringView,
  index : Int,
  single : Mode,
) -> Int? {
  match (unit_at(text, index + 1), unit_at(text, index + 2)) {
    (Some('\''), Some('\'')) => {
      self.mode = LongString
      Some(3)
    }
    (None, _) | (Some('\''), None) => None
    _ => {
      self.mode = single
      Some(1)
    }
  }
}

///|
/// The code unit at `index`, or `None` when it has not arrived yet.
fn unit_at(text : StringView, index : Int) -> UInt16? {
  if index < text.length() {
    Some(text[index])
  } else {
    None
  }
}

///|
/// Whether a code unit ends an unquoted token.
fn ends_token(c : UInt16) -> Bool {
  match c.to_int() {
    0x20 | 0x09 | 0x0A | 0x0D | 0x0B | 0x0C => true
    _ =>
      match c {
        '[' | ']' | '(' | ')' | '{' | '}' | '"' | '\'' | ',' | '/' => true
        _ => false
      }
  }
}
