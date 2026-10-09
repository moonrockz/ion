// Structural equality of Ion values, with no recursion.
//
// Two values are compared in lockstep with a stack of value pairs, and the
// walk returns at the first difference. Struct fields are an unordered
// multiset, so for each pair of structs every field value gets an integer
// class ID, bottom-up with `fold_up`: equal values get equal IDs. The two
// structs are then equal when their sorted (field name, class ID) keys are.

///|
/// Structural equality following the Ion data model: annotations must match in
/// order, all NaNs are equivalent, positive and negative zero are not, list
/// and sexp elements are compared pairwise, and struct fields are compared as
/// an unordered multiset. It works at any nesting depth.
pub fn IonValue::equals(self : IonValue, other : IonValue) -> Bool {
  let pairs : Array[(IonValue, IonValue)] = [(self, other)]
  let classes = ValueClasses::new()
  while pairs.pop() is Some((a, b)) {
    if !annotations_equal(a.annotations, b.annotations) {
      return false
    }
    match (a.kind, b.kind) {
      (List(x), List(y)) | (Sexp(x), Sexp(y)) => {
        if x.length() != y.length() {
          return false
        }
        for index = x.length() - 1; index >= 0; index = index - 1 {
          pairs.push((x[index], y[index]))
        }
      }
      (Struct(x), Struct(y)) => if !classes.fields_equal(x, y) { return false }
      (x, y) => if !scalars_equal(x, y) { return false }
    }
  }
  true
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
