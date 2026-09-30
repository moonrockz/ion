///|
/// Write containers without building value trees. Text is emitted immediately;
/// retained state is proportional to depth plus the supplied symbol context.
/// Provide `symbols` before writing unknown symbol IDs/import locations.
struct IncrementalWriter {
  sink : &@io.Writer
  state : @ion.WriterState
  symbols : @ion.SymbolTable
  pretty : Bool
  mut started : Bool
}

///|
pub fn IncrementalWriter::new(
  sink : &@io.Writer,
  pretty? : Bool = false,
  symbols? : @ion.SymbolTable = @ion.SymbolTable::system(),
) -> IncrementalWriter {
  { sink, state: @ion.WriterState::new(), symbols, pretty, started: false, }
}

///|
pub fn IncrementalWriter::set_field_name(
  self : IncrementalWriter,
  name : @ion.SymbolToken,
) -> Unit raise @ion.IonError {
  self.state.set_field_name(name)
}

///|
/// Set annotations for the next value/container. For write(value), these
/// precede the annotations already on the supplied value.
pub fn IncrementalWriter::set_annotations(
  self : IncrementalWriter,
  annotations : Array[@ion.SymbolToken],
) -> Unit raise @ion.IonError {
  self.state.set_annotations(annotations)
}

///|
fn IncrementalWriter::token(
  self : IncrementalWriter,
  token : @ion.SymbolToken,
) -> @ion.SymbolToken raise @ion.IonError {
  if token.text() is Some(_) {
    return token
  }
  let sid = self.symbols.writer_token_id(token)
  @ion.SymbolToken::from_sid(sid)
}

///|
fn IncrementalWriter::prefix(
  self : IncrementalWriter,
  position : @ion.WritePosition,
) -> String raise @ion.IonError {
  let buffer = StringBuilder()
  match position.parent {
    None => if position.index > 0 { buffer.write_string("\n") }
    Some(kind) => {
      if position.index > 0 {
        buffer.write_string(if kind == Sexp { "" } else { "," })
        if !self.pretty {
          buffer.write_string(" ")
        }
      }
      if self.pretty {
        buffer.write_string("\n")
        for _ in 0..<position.depth {
          buffer.write_string("  ")
        }
      }
    }
  }
  if position.field is Some(name) {
    buffer.write_string(@text.symbol_to_text(self.token(name)))
    buffer.write_string(": ")
  }
  buffer.to_string()
}

///|
async fn IncrementalWriter::emit(
  self : IncrementalWriter,
  text : String,
) -> Unit {
  self.state.begin_output()
  defer self.state.end_output()
  let mut completed = false
  defer (if !completed { self.state.fail() })
  let text = if !self.started {
    match self.symbols.to_local_symbol_table() {
      Some(table) =>
        @text.write_fragment(table, pretty=self.pretty) + "\n" + text
      None => text
    }
  } else {
    text
  }
  self.sink.write(@utf8.encode(text))
  completed = true
  self.started = true
}

///|
/// Enter a list, sexp, or struct; pending field/annotations apply to it.
pub async fn IncrementalWriter::step_in(
  self : IncrementalWriter,
  kind : @ion.IonType,
) -> Unit {
  @ion.check_container_kind(kind)
  let position = self.state.position()
  let prefix = self.prefix(position)
  let annotations = position.annotations
    .map(token => @text.symbol_to_text(self.token(token)) + "::")
    .join("")
  let open = match kind {
    List => "["
    Sexp => "("
    Struct => "{"
    _ => abort("validated container")
  }
  self.emit(prefix + annotations + open)
  self.state.enter(kind)
}

///|
pub async fn IncrementalWriter::step_out(self : IncrementalWriter) -> Unit {
  let (kind, count, depth) = self.state.closing()
  let buffer = StringBuilder()
  if self.pretty && count > 0 {
    buffer.write_string("\n")
    for _ in 0..<depth {
      buffer.write_string("  ")
    }
  }
  buffer.write_string(
    match kind {
      List => "]"
      Sexp => ")"
      Struct => "}"
      _ => abort("validated container")
    },
  )
  self.emit(buffer.to_string())
  self.state.leave()
}

///|
/// Write a scalar or already-built subtree in the current container.
pub async fn IncrementalWriter::write(
  self : IncrementalWriter,
  value : @ion.IonValue,
) -> Unit {
  let position = self.state.position()
  let value = value.with_annotations(position.annotations + value.annotations())
  // Validate every unknown token before emitting any part of this value.
  let localized = self.symbols.localize_for_text(value)
  if @ion.highest_symbol_id([localized]) > self.symbols.max_id() {
    raise @ion.IonError::Unsupported(
      "unknown symbol requires a declared writer context",
    )
  }
  let text = self.prefix(position) +
    @text.write_fragment(
      localized,
      depth=position.depth,
      pretty=self.pretty,
      in_sexp=position.parent == Some(Sexp),
    )
  self.emit(text)
  self.state.commit()
}

///|
pub async fn IncrementalWriter::write_int(
  self : IncrementalWriter,
  value : Int,
) -> Unit {
  self.write(@ion.IonValue::int(value))
}

///|
pub async fn IncrementalWriter::write_string(
  self : IncrementalWriter,
  value : String,
) -> Unit {
  self.write(@ion.IonValue::string(value))
}

///|
pub async fn IncrementalWriter::write_bool(
  self : IncrementalWriter,
  value : Bool,
) -> Unit {
  self.write(@ion.IonValue::bool(value))
}

///|
pub async fn IncrementalWriter::write_null(
  self : IncrementalWriter,
  kind? : @ion.IonType = Null,
) -> Unit {
  self.write(@ion.IonValue::typed_null(kind))
}

///|
/// Validate balanced containers and consumed metadata. The caller owns flush.
pub fn IncrementalWriter::finish(
  self : IncrementalWriter,
) -> Unit raise @ion.IonError {
  self.state.check_finished()
  self.state.finish()
}
