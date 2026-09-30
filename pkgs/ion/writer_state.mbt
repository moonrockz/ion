// Shared validation for the text and binary incremental writers.

///|
priv struct WriterFrame {
  kind : IonType
  mut count : Int
  mut field : SymbolToken?
}

///|
/// The position of the next value in an incremental writer.
pub struct WritePosition {
  depth : Int
  parent : IonType?
  index : Int
  field : SymbolToken?
  annotations : Array[SymbolToken]
}

///|
/// Container, field, and annotation validation shared by incremental codecs.
struct WriterState {
  frames : Array[WriterFrame]
  mut annotations : Array[SymbolToken]
  mut count : Int
  mut busy : Bool
  mut failed : Bool
  mut finished : Bool
}

///|
pub fn WriterState::new() -> WriterState {
  {
    frames: [],
    annotations: [],
    count: 0,
    busy: false,
    failed: false,
    finished: false,
  }
}

///|
pub fn WriterState::check(self : WriterState) -> Unit raise IonError {
  if self.failed {
    raise DataModel("incremental writer failed during output")
  }
  if self.finished {
    raise DataModel("incremental writer is finished")
  }
  if self.busy {
    raise DataModel("concurrent incremental writer operation")
  }
}

///|
pub fn WriterState::set_field_name(
  self : WriterState,
  name : SymbolToken,
) -> Unit raise IonError {
  self.check()
  match self.frames.last() {
    Some(frame) if frame.kind == Struct => {
      if frame.field is Some(_) {
        raise DataModel("field name already pending")
      }
      frame.field = Some(name)
    }
    _ => raise DataModel("field names require an open struct")
  }
}

///|
pub fn WriterState::set_annotations(
  self : WriterState,
  annotations : Array[SymbolToken],
) -> Unit raise IonError {
  self.check()
  self.annotations = annotations.copy()
}

///|
/// Validate the next slot without consuming pending metadata.
pub fn WriterState::position(
  self : WriterState,
) -> WritePosition raise IonError {
  self.check()
  match self.frames.last() {
    Some(frame) => {
      if frame.kind == Struct && frame.field is None {
        raise DataModel("a struct value requires a field name")
      }
      {
        depth: self.frames.length(),
        parent: Some(frame.kind),
        index: frame.count,
        field: frame.field,
        annotations: self.annotations,
      }
    }
    None =>
      {
        depth: 0,
        parent: None,
        index: self.count,
        field: None,
        annotations: self.annotations,
      }
  }
}

///|
/// Consume the validated slot after successful encoding/output.
pub fn WriterState::commit(self : WriterState) -> Unit {
  match self.frames.last() {
    Some(frame) => {
      frame.count += 1
      frame.field = None
    }
    None => self.count += 1
  }
  self.annotations = []
}

///|
pub fn WriterState::enter(self : WriterState, kind : IonType) -> Unit {
  self.commit()
  self.frames.push({ kind, count: 0, field: None, })
}

///|
pub fn WriterState::closing(
  self : WriterState,
) -> (IonType, Int, Int) raise IonError {
  self.check()
  if !self.annotations.is_empty() {
    raise DataModel("annotations have no following value")
  }
  match self.frames.last() {
    Some(frame) => {
      if frame.field is Some(_) {
        raise DataModel("field name has no following value")
      }
      (frame.kind, frame.count, self.frames.length() - 1)
    }
    None => raise DataModel("no container to step out of")
  }
}

///|
pub fn WriterState::leave(self : WriterState) -> Unit {
  ignore(self.frames.pop())
}

///|
pub fn WriterState::check_finished(self : WriterState) -> Unit raise IonError {
  self.check()
  if !self.frames.is_empty() {
    raise DataModel("incremental writer has unclosed containers")
  }
  if !self.annotations.is_empty() {
    raise DataModel("annotations have no following value")
  }
}

///|
pub fn WriterState::finish(self : WriterState) -> Unit {
  self.finished = true
}

///|
pub fn WriterState::begin_output(self : WriterState) -> Unit raise IonError {
  self.check()
  self.busy = true
}

///|
pub fn WriterState::end_output(self : WriterState) -> Unit {
  self.busy = false
}

///|
pub fn WriterState::fail(self : WriterState) -> Unit {
  self.failed = true
}

///|
/// Validate the container kind accepted by step-in.
pub fn check_container_kind(kind : IonType) -> Unit raise IonError {
  match kind {
    List | Sexp | Struct => ()
    _ => raise DataModel("step-in requires list, sexp, or struct")
  }
}
