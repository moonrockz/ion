// Shallow recursive grammar. Keep its container structure in step with
// the continuation grammar in reader.mbt; scalar parsing is shared.

///|
/// Read a top-level value, and whether it is spelled as an unquoted `$ion_`
/// identifier, the only spelling of a version marker.
fn Parser::parse_top_level_value(self : Parser) -> TopLevel raise @ion.IonError {
  let marker = self.starts_with("$ion_")
  self.symbol_ids = false
  let value = self.parse_value()
  { value, marker, symbol_ids: self.symbol_ids, }
}

///|
/// Read a value, including any leading annotations.
fn Parser::parse_value(self : Parser) -> @ion.IonValue raise @ion.IonError {
  let annotations = self.parse_annotations()
  let value = self.parse_bare_value()
  if annotations.is_empty() {
    value
  } else {
    value.with_annotations(annotations)
  }
}

///|
/// Read a value with no leading annotations.
fn Parser::parse_bare_value(self : Parser) -> @ion.IonValue raise @ion.IonError {
  self.skip_ws()
  if self.at_end() {
    raise @ion.IonError::Syntax("expected an Ion value, found end of input")
  }
  let c = self.input[self.pos]
  match c {
    '[' => self.parse_container(Parser::parse_list, Parser::parse_list_deep)
    '(' => self.parse_container(Parser::parse_sexp, Parser::parse_sexp_deep)
    '{' => self.parse_braced()
    '"' => @ion.IonValue::string(self.parse_double_quoted_string())
    '\'' =>
      if self.peek_at(1) == Some('\'') && self.peek_at(2) == Some('\'') {
        @ion.IonValue::string(self.parse_long_string())
      } else {
        @ion.IonValue::symbol_token(self.parse_quoted_symbol())
      }
    _ => self.parse_unquoted()
  }
}

///|
/// Read a container with `parse`, one level deeper than the cursor is now.
/// Switch to heap continuations before exhausting the recursive fast path.
fn Parser::parse_container(
  self : Parser,
  parse : (Parser) -> @ion.IonValue raise @ion.IonError,
  parse_deep : async (Parser) -> @ion.IonValue raise @ion.IonError + nocancel,
) -> @ion.IonValue raise @ion.IonError {
  if self.recursive_levels == 0 {
    return self.runner.run(() => self.parse_container_deep(parse_deep))
  }
  let levels = self.recursive_levels
  self.recursive_levels -= 1
  defer {
    self.recursive_levels = levels
  }
  let outer = self.fuel
  defer {
    self.fuel = outer
  }
  self.fuel = outer.enter(TextRead, TextOffset(self.pos))
  parse(self)
}

///|
/// Dispatch between a struct and a blob/clob, both of which start with `{`.
fn Parser::parse_braced(self : Parser) -> @ion.IonValue raise @ion.IonError {
  if self.peek_at(1) == Some('{') {
    self.parse_lob()
  } else {
    self.parse_container(Parser::parse_struct, Parser::parse_struct_deep)
  }
}

///|
/// Read a struct.
fn Parser::parse_struct(self : Parser) -> @ion.IonValue raise @ion.IonError {
  self.pos += 1
  let fields : Array[@ion.Field] = []
  self.skip_ws()
  if self.peek_at(0) == Some('}') {
    self.pos += 1
    return @ion.IonValue::from_fields(fields)
  }
  while true {
    self.skip_ws()
    let name = self.parse_field_name()
    self.skip_ws()
    if self.peek_at(0) != Some(':') {
      raise @ion.IonError::Syntax("expected ':' after a struct field name")
    }
    self.pos += 1
    let value = self.parse_value()
    fields.push(@ion.Field::from_token(name, value))
    self.skip_ws()
    match self.peek_at(0) {
      Some(',') => {
        self.pos += 1
        self.skip_ws()
        if self.peek_at(0) == Some('}') {
          self.pos += 1
          break
        }
      }
      Some('}') => {
        self.pos += 1
        break
      }
      _ => raise @ion.IonError::Syntax("expected ',' or '}' in struct")
    }
  }
  @ion.IonValue::from_fields(fields)
}

///|
/// Read a list.
fn Parser::parse_list(self : Parser) -> @ion.IonValue raise @ion.IonError {
  self.pos += 1
  let items : Array[@ion.IonValue] = []
  self.skip_ws()
  if self.peek_at(0) == Some(']') {
    self.pos += 1
    return @ion.IonValue::list(items)
  }
  while true {
    items.push(self.parse_value())
    self.skip_ws()
    match self.peek_at(0) {
      Some(',') => {
        self.pos += 1
        self.skip_ws()
        if self.peek_at(0) == Some(']') {
          self.pos += 1
          break
        }
      }
      Some(']') => {
        self.pos += 1
        break
      }
      _ => raise @ion.IonError::Syntax("expected ',' or ']' in list")
    }
  }
  @ion.IonValue::list(items)
}

///|
/// Read an S-expression, where whitespace separates elements and operators are
/// valid symbols.
fn Parser::parse_sexp(self : Parser) -> @ion.IonValue raise @ion.IonError {
  self.pos += 1
  self.sexp_depth += 1
  let items : Array[@ion.IonValue] = []
  self.skip_ws()
  while !self.at_end() && self.input[self.pos] != ')' {
    items.push(self.parse_value())
    self.skip_ws()
  }
  self.sexp_depth -= 1
  if self.at_end() {
    raise @ion.IonError::Syntax("unterminated S-expression")
  }
  self.pos += 1
  @ion.IonValue::sexp(items)
}
