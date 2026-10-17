// Container grammar runs on the continuation executor. Core JSON still
// decodes scalar tokens, preserving its number and Unicode semantics without
// invoking its recursive container parser.

///|
priv struct JsonParser {
  input : StringView
  mut pos : Int32
  runner : @work.Runner
  mut fuel : @core.FuelState
}

///|
fn JsonParser::peek(self : JsonParser) -> UInt16? {
  if self.pos < self.input.length() {
    Some(self.input[self.pos])
  } else {
    None
  }
}

///|
fn JsonParser::skip_ws(self : JsonParser) -> Unit {
  while self.peek() is Some(' ' | '\t' | '\r' | '\n') {
    self.pos += 1
  }
}

///|
fn JsonParser::error(self : JsonParser, message : String) -> @core.IonError {
  @core.IonError::Syntax(
    "invalid JSON at UTF-16 offset \{self.pos}: \{message}",
  )
}

///|
async fn JsonParser::value(
  self : JsonParser,
) -> Json raise @core.IonError + nocancel {
  self.skip_ws()
  match self.peek() {
    Some('[') => self.array()
    Some('{') => self.object()
    None => raise self.error("expected a value")
    _ => self.scalar()
  }
}

///|
fn JsonParser::scalar(self : JsonParser) -> Json raise @core.IonError {
  let start = self.pos
  if self.peek() == Some('"') {
    self.pos += 1
    let mut closed = false
    while self.peek() is Some(c) {
      self.pos += 1
      if c == '\\' {
        if self.peek() is None {
          break
        }
        self.pos += 1
      } else if c == '"' {
        closed = true
        break
      }
    }
    if !closed {
      raise self.error("unterminated string")
    }
  } else {
    while self.peek() is Some(c) {
      match c {
        ' ' | '\t' | '\r' | '\n' | ',' | '[' | ']' | '{' | '}' | ':' | '"' =>
          break
        _ => self.pos += 1
      }
    }
    if self.pos == start {
      raise self.error("expected a scalar")
    }
  }
  @cjson.parse(self.input[start:self.pos]) catch {
    error => raise self.error("\{error}")
  }
}

///|
async fn JsonParser::array(
  self : JsonParser,
) -> Json raise @core.IonError + nocancel {
  self.runner.pause()
  defer self.runner.pause()
  let outer = self.fuel
  defer {
    self.fuel = outer
  }
  self.fuel = outer.enter(JsonRead, TextOffset(self.pos))
  self.pos += 1
  self.skip_ws()
  let items : Array[Json] = []
  if self.peek() == Some(']') {
    self.pos += 1
    return Json::array(items)
  }
  while true {
    items.push(self.value())
    self.skip_ws()
    match self.peek() {
      Some(']') => {
        self.pos += 1
        break
      }
      Some(',') => self.pos += 1
      _ => raise self.error("expected ',' or ']'")
    }
  }
  Json::array(items)
}

///|
async fn JsonParser::object(
  self : JsonParser,
) -> Json raise @core.IonError + nocancel {
  self.runner.pause()
  defer self.runner.pause()
  let outer = self.fuel
  defer {
    self.fuel = outer
  }
  self.fuel = outer.enter(JsonRead, TextOffset(self.pos))
  self.pos += 1
  self.skip_ws()
  let fields : Map[String, Json] = Map([])
  if self.peek() == Some('}') {
    self.pos += 1
    return Json::object(fields)
  }
  while true {
    self.skip_ws()
    if self.peek() != Some('"') {
      raise self.error("expected a quoted field name")
    }
    let name = match self.scalar() {
      Json::String(name) => name
      _ => raise self.error("expected a string field name")
    }
    self.skip_ws()
    if self.peek() != Some(':') {
      raise self.error("expected ':'")
    }
    self.pos += 1
    fields[name] = self.value()
    self.skip_ws()
    match self.peek() {
      Some('}') => {
        self.pos += 1
        break
      }
      Some(',') => self.pos += 1
      _ => raise self.error("expected ',' or '}'")
    }
  }
  Json::object(fields)
}
