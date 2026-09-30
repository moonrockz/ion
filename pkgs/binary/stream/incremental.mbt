///|
priv struct EncodedContainer {
  kind : @ion.IonType
  annotations : Array[@ion.SymbolToken]
  body : Array[Byte]
}

///|
/// Write containers without caller-built value trees. Only encoded bytes for
/// open containers and their symbol context are retained. Provide `symbols`
/// before using unknown local IDs or shared imports inside a container.
struct IncrementalWriter {
  sink : &@io.Writer
  state : @ion.WriterState
  symbols : @ion.SymbolTable
  containers : Array[EncodedContainer]
  mut started : Bool
  mut emitted_max : Int
}

///|
pub fn IncrementalWriter::new(
  sink : &@io.Writer,
  symbols? : @ion.SymbolTable = @ion.SymbolTable::system(),
) -> IncrementalWriter {
  {
    sink,
    state: @ion.WriterState::new(),
    symbols,
    containers: [],
    started: false,
    emitted_max: 9,
  }
}

///|
pub fn IncrementalWriter::set_field_name(
  self : IncrementalWriter,
  name : @ion.SymbolToken,
) -> Unit raise @ion.IonError {
  self.state.set_field_name(name)
}

///|
pub fn IncrementalWriter::set_annotations(
  self : IncrementalWriter,
  annotations : Array[@ion.SymbolToken],
) -> Unit raise @ion.IonError {
  self.state.set_annotations(annotations)
}

///|
fn IncrementalWriter::validate_token(
  self : IncrementalWriter,
  token : @ion.SymbolToken,
) -> Unit raise @ion.IonError {
  ignore(self.symbols.writer_token_id(token))
}

///|
fn IncrementalWriter::field_bytes(
  self : IncrementalWriter,
  position : @ion.WritePosition,
) -> Bytes raise @ion.IonError {
  match position.field {
    Some(name) => {
      self.validate_token(name)
      @binary.encode_field_name(name, self.symbols)
    }
    None => b""
  }
}

///|
async fn IncrementalWriter::output(
  self : IncrementalWriter,
  bytes : Bytes,
) -> Unit {
  self.state.begin_output()
  defer self.state.end_output()
  let mut completed = false
  defer (if !completed { self.state.fail() })
  let out : Array[Byte] = []
  if !self.started {
    out.append(@binary.binary_version_marker().to_array())
    if @binary.local_symbol_table(self.symbols) is Some(table) {
      out.append(table.to_array())
    }
  } else if self.symbols.max_id() > self.emitted_max {
    let locals = self.symbols.locals()
    let count = self.symbols.max_id() - self.emitted_max
    let table = @ion.IonValue::from_fields([
      @ion.Field::new("imports", @ion.IonValue::symbol("$ion_symbol_table")),
      @ion.Field::new(
        "symbols",
        @ion.IonValue::list(
          locals[locals.length() - count:].map(text => {
            match text {
              Some(text) => @ion.IonValue::string(text)
              None => @ion.IonValue::untyped_null()
            }
          }),
        ),
      ),
    ]).with_annotation(@ion.SymbolToken::new("$ion_symbol_table"))
    out.append(@binary.encode_value(table, self.symbols).to_array())
  }
  out.append(bytes.to_array())
  self.sink.write(Bytes::from_array(out))
  completed = true
  self.started = true
  self.emitted_max = self.symbols.max_id()
}

///|
pub fn IncrementalWriter::step_in(
  self : IncrementalWriter,
  kind : @ion.IonType,
) -> Unit raise @ion.IonError {
  @ion.check_container_kind(kind)
  let position = self.state.position()
  let field = self.field_bytes(position)
  for annotation in position.annotations {
    self.validate_token(annotation)
  }
  if self.containers.last() is Some(parent) {
    parent.body.append(field.to_array())
  }
  self.containers.push({ kind, annotations: position.annotations, body: [], })
  self.state.enter(kind)
}

///|
pub async fn IncrementalWriter::step_out(self : IncrementalWriter) -> Unit {
  ignore(self.state.closing())
  let container = self.containers.last().unwrap()
  let bytes = @binary.encode_container(
    container.kind,
    Bytes::from_array(container.body),
    container.annotations,
    self.symbols,
  )
  ignore(self.containers.pop())
  self.state.leave()
  match self.containers.last() {
    Some(parent) => parent.body.append(bytes.to_array())
    None => self.output(bytes)
  }
}

///|
/// Write a scalar or already-built subtree in the current container.
pub async fn IncrementalWriter::write(
  self : IncrementalWriter,
  value : @ion.IonValue,
) -> Unit {
  let position = self.state.position()
  let field = self.field_bytes(position)
  let value = value.with_annotations(position.annotations + value.annotations())
  // Localize only to validate unknown IDs against this fixed context. The
  // binary encoder consumes the original tokens and interns known text.
  let localized = self.symbols.localize_for_text(value)
  if @ion.highest_symbol_id([localized]) > self.symbols.max_id() {
    raise @ion.IonError::Unsupported(
      "unknown symbol requires a declared writer context",
    )
  }
  let bytes = @binary.encode_value(value, self.symbols)
  match self.containers.last() {
    Some(parent) => {
      parent.body.append(field.to_array())
      parent.body.append(bytes.to_array())
    }
    None => self.output(bytes)
  }
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
/// Validate balance and metadata; an empty datagram still gets its marker.
/// The caller owns buffered-sink flushing.
pub async fn IncrementalWriter::finish(self : IncrementalWriter) -> Unit {
  self.state.check_finished()
  if !self.started {
    self.output(b"")
  }
  self.state.finish()
}
