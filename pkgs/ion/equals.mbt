// Structural equality of Ion values, with no recursion.
//
// Two values are compared in lockstep on a stack of frames, one frame for
// each pair of containers being compared. Each frame compares its children
// as pairs: list and S-expression items by position, struct fields by name.
// Struct fields are an unordered multiset. When the names line up by
// position, the fields pair by position; otherwise both field arrays are
// sorted by name and pair in that order. When the names are all different,
// that pairing is the only one possible, so its result is final. When names
// repeat and the pairing finds a difference, another pairing could still
// match, so the struct falls back to class IDs: every field value gets an
// integer class ID, bottom-up with `fold_up`, and the two structs are equal
// when their sorted (field name, class ID) keys are.

///|
/// Structural equality following the Ion data model: annotations must match in
/// order, all NaNs are equivalent, positive and negative zero are not, list
/// and sexp elements are compared pairwise, and struct fields are compared as
/// an unordered multiset. It works at any nesting depth.
pub fn IonValue::equals(self : IonValue, other : IonValue) -> Bool {
  let frames : Array[PairFrame] = []
  let classes = ValueClasses::new()
  let mut result = begin_pair(self, other, frames)
  while frames.last() is Some(frame) {
    result = frame.advance(result, frames, classes)
  }
  result is Some(true)
}

///|
/// The children that a frame compares in pairs.
priv enum PairChildren {
  Items(Array[IonValue], Array[IonValue])
  Fields(Array[Field], Array[Field])
}

///|
/// A pair of containers being compared, and the index of the next pair of
/// children to compare.
priv struct PairFrame {
  children : PairChildren
  mut next : Int
}

///|
/// Start comparing `a` and `b`. Returns the result when it is known at once,
/// or `None` after pushing a frame for a pair of containers.
fn begin_pair(a : IonValue, b : IonValue, frames : Array[PairFrame]) -> Bool? {
  if !annotations_equal(a.annotations, b.annotations) {
    return Some(false)
  }
  match (a.kind, b.kind) {
    (List(x), List(y)) | (Sexp(x), Sexp(y)) => {
      if x.length() != y.length() {
        return Some(false)
      }
      frames.push({ children: Items(x, y), next: 0, })
      None
    }
    (Struct(x), Struct(y)) => {
      guard pair_fields(x, y) is Some((left, right)) else { return Some(false) }
      frames.push({ children: Fields(left, right), next: 0, })
      None
    }
    (x, y) => Some(scalars_equal(x, y))
  }
}

///|
/// Continue the comparison of this frame, the top of `frames`. `result` is
/// the result of its last pair of children, or `None` when the frame is new.
/// Returns `None` after pushing a frame for a pair of child containers, or
/// the frame's result after popping it.
fn PairFrame::advance(
  self : PairFrame,
  result : Bool?,
  frames : Array[PairFrame],
  classes : ValueClasses,
) -> Bool? {
  if result is Some(false) {
    return self.finish_unequal(frames, classes)
  }
  let length = match self.children {
    Items(left, _) => left.length()
    Fields(left, _) => left.length()
  }
  while self.next < length {
    let index = self.next
    self.next = index + 1
    let child = match self.children {
      Items(left, right) => begin_pair(left[index], right[index], frames)
      Fields(left, right) =>
        begin_pair(left[index].value, right[index].value, frames)
    }
    match child {
      None => return None
      Some(true) => ()
      Some(false) => return self.finish_unequal(frames, classes)
    }
  }
  ignore(frames.pop())
  Some(true)
}

///|
/// Pop this frame after a pair of its children differed. Items are then
/// unequal. Fields are unequal too, unless a name repeats: then another
/// pairing of the fields could match, and class IDs decide.
fn PairFrame::finish_unequal(
  self : PairFrame,
  frames : Array[PairFrame],
  classes : ValueClasses,
) -> Bool? {
  ignore(frames.pop())
  match self.children {
    Items(_, _) => Some(false)
    Fields(left, right) =>
      Some(has_repeated_names(left) && classes.fields_equal(left, right))
  }
}

///|
/// The two field arrays in an order that pairs equivalent names: as they are
/// when the names line up by position, else both sorted by name. `None` when
/// the names differ, so the structs are unequal.
fn pair_fields(
  a : Array[Field],
  b : Array[Field],
) -> (Array[Field], Array[Field])? {
  if a.length() != b.length() {
    return None
  }
  let mut aligned = true
  for index in 0..<a.length() {
    if !a[index].name.equivalent(b[index].name) {
      aligned = false
      break
    }
  }
  if aligned {
    return Some((a, b))
  }
  let left = a.map(field => (symbol_key(field.name), field))
  let right = b.map(field => (symbol_key(field.name), field))
  left.sort_by_key(entry => entry.0)
  right.sort_by_key(entry => entry.0)
  for index in 0..<left.length() {
    if left[index].0 != right[index].0 {
      return None
    }
  }
  Some((left.map(entry => entry.1), right.map(entry => entry.1)))
}

///|
/// Whether two fields in `fields` have equivalent names.
fn has_repeated_names(fields : Array[Field]) -> Bool {
  let keys = fields.map(field => symbol_key(field.name))
  keys.sort()
  for index in 1..<keys.length() {
    if keys[index] == keys[index - 1] {
      return true
    }
  }
  false
}

///|
/// A key that is equal for two tokens exactly when `equivalent` holds.
fn symbol_key(token : SymbolToken) -> String {
  let buffer = StringBuilder()
  write_symbol_key(buffer, token)
  buffer.to_string()
}

///|
fn annotations_equal(a : Array[SymbolToken], b : Array[SymbolToken]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for index in 0..<a.length() {
    if !a[index].equivalent(b[index]) {
      return false
    }
  }
  true
}

///|
/// Equality of two kinds that are not both lists, both S-expressions or both
/// structs. Containers of different kinds are unequal.
fn scalars_equal(a : IonValueKind, b : IonValueKind) -> Bool {
  match (a, b) {
    (Null(x), Null(y)) => x == y
    (Bool(x), Bool(y)) => x == y
    (Int(x), Int(y)) => x.equal(y)
    (Float(x), Float(y)) =>
      // All NaNs are equivalent, and positive and negative zero are not.
      (x.is_nan() && y.is_nan()) ||
      x.reinterpret_as_uint64() == y.reinterpret_as_uint64()
    (Decimal(x), Decimal(y)) =>
      x.coefficient().equal(y.coefficient()) &&
      x.exponent() == y.exponent() &&
      x.is_negative_zero() == y.is_negative_zero()
    (Timestamp(x), Timestamp(y)) => x.to_ion_string() == y.to_ion_string()
    (Symbol(x), Symbol(y)) => x.equivalent(y)
    (String(x), String(y)) => x == y
    (Clob(x), Clob(y)) => x == y
    (Blob(x), Blob(y)) => x == y
    _ => false
  }
}

///|
/// Integer IDs for equality classes of values, for one `equals` call. Two
/// values get the same ID exactly when `equals` holds for them, because the
/// key of a value is built from the same comparisons.
priv struct ValueClasses {
  ids : Map[String, Int]
}

///|
fn ValueClasses::new() -> ValueClasses {
  { ids: Map([]), }
}

///|
fn ValueClasses::intern(self : ValueClasses, key : String) -> Int {
  match self.ids.get(key) {
    Some(id) => id
    None => {
      let id = self.ids.length()
      self.ids.set(key, id)
      id
    }
  }
}

///|
/// The class ID of `value`, computed bottom-up with no recursion.
fn ValueClasses::class_of(self : ValueClasses, value : IonValue) -> Int {
  value.fold_up(scalar=scalar => self.intern(scalar_key(scalar)), container=(
    current,
    children,
  ) => self.intern(container_key(current, children)))
}

///|
/// Whether two field arrays are equal as multisets of (name, value).
fn ValueClasses::fields_equal(
  self : ValueClasses,
  a : Array[Field],
  b : Array[Field],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let left = a.map(field => field_key(field.name, self.class_of(field.value)))
  let right = b.map(field => field_key(field.name, self.class_of(field.value)))
  left.sort()
  right.sort()
  left == right
}

///|
/// Append `text` with its length in front, so that no two texts run together.
fn write_counted(buffer : StringBuilder, text : String) -> Unit {
  buffer.write_string(text.length().to_string())
  buffer.write_char(':')
  buffer.write_string(text)
}

///|
/// Append a key that is equal for two tokens exactly when `equivalent` holds:
/// known text, an imported location, or (for local symbols with no text) `$0`.
fn write_symbol_key(buffer : StringBuilder, token : SymbolToken) -> Unit {
  match (token.text, token.import_location) {
    (Some(text), _) => {
      buffer.write_char('t')
      write_counted(buffer, text)
    }
    (None, Some(location)) => {
      buffer.write_char('i')
      write_counted(buffer, location.name)
      buffer.write_string(location.sid.to_string())
      buffer.write_char(';')
    }
    (None, None) => buffer.write_char('z')
  }
}

///|
fn write_annotations_key(buffer : StringBuilder, value : IonValue) -> Unit {
  buffer.write_string(value.annotations.length().to_string())
  buffer.write_char('@')
  for annotation in value.annotations {
    write_symbol_key(buffer, annotation)
  }
}

///|
fn write_bytes_key(buffer : StringBuilder, bytes : Bytes) -> Unit {
  let digits = "0123456789abcdef"
  buffer.write_string(bytes.length().to_string())
  buffer.write_char(':')
  for byte in bytes {
    let value = byte.to_int()
    buffer.write_view(digits[value >> 4:(value >> 4) + 1])
    buffer.write_view(digits[value & 0xF:(value & 0xF) + 1])
  }
}

///|
/// The key of a value with no children (a typed null of a container type
/// included), from the same comparisons as `scalars_equal`.
fn scalar_key(value : IonValue) -> String {
  let buffer = StringBuilder()
  write_annotations_key(buffer, value)
  match value.kind {
    Null(t) => {
      buffer.write_char('n')
      buffer.write_string(t.to_text())
    }
    Bool(b) => buffer.write_string(if b { "b1" } else { "b0" })
    Int(n) => {
      buffer.write_char('i')
      buffer.write_string(n.to_string())
    }
    Float(f) =>
      if f.is_nan() {
        buffer.write_string("fnan")
      } else {
        buffer.write_char('f')
        buffer.write_string(f.reinterpret_as_uint64().to_string())
      }
    Decimal(d) => {
      buffer.write_char('d')
      buffer.write_string(d.coefficient().to_string())
      buffer.write_char('e')
      buffer.write_string(d.exponent().to_string())
      buffer.write_string(if d.is_negative_zero() { "-" } else { "+" })
    }
    Timestamp(t) => {
      buffer.write_char('T')
      write_counted(buffer, t.to_ion_string())
    }
    Symbol(token) => {
      buffer.write_char('s')
      write_symbol_key(buffer, token)
    }
    String(text) => {
      buffer.write_char('S')
      write_counted(buffer, text)
    }
    Clob(bytes) => {
      buffer.write_char('c')
      write_bytes_key(buffer, bytes)
    }
    Blob(bytes) => {
      buffer.write_char('B')
      write_bytes_key(buffer, bytes)
    }
    // An empty container: `fold_up` gives it to `container`, not here.
    List(_) | Sexp(_) | Struct(_) => buffer.write_char('?')
  }
  buffer.to_string()
}

///|
/// The key of a list, S-expression or struct from its children's class IDs:
/// in order for a list or S-expression, sorted by field key for a struct.
fn container_key(
  value : IonValue,
  children : Array[(SymbolToken?, Int)],
) -> String {
  let buffer = StringBuilder()
  write_annotations_key(buffer, value)
  match value.kind {
    Struct(_) => {
      buffer.write_char('R')
      let keys = children.map(child => {
        match child.0 {
          Some(name) => field_key(name, child.1)
          None => child.1.to_string()
        }
      })
      keys.sort()
      for key in keys {
        write_counted(buffer, key)
      }
    }
    kind => {
      buffer.write_char(if kind is Sexp(_) { 'X' } else { 'L' })
      for child in children {
        buffer.write_string(child.1.to_string())
        buffer.write_char(',')
      }
    }
  }
  buffer.to_string()
}

///|
/// The key of one struct field: its name's key and its value's class ID.
fn field_key(name : SymbolToken, id : Int) -> String {
  let buffer = StringBuilder()
  write_symbol_key(buffer, name)
  buffer.write_char('=')
  buffer.write_string(id.to_string())
  buffer.to_string()
}
