// The symbol tokens of a value, with no recursion.

///|
/// Whether `found` holds for a symbol token in `self`: an annotation, a struct
/// field name or a symbol value at any depth. The tokens come in no fixed
/// order, so the walk needs only a stack of containers, which costs less than
/// a `ValueWalker`. Use [`IonValue::each_token`] when the order matters.
fn IonValue::any_token(self : IonValue, found : (SymbolToken) -> Bool) -> Bool {
  let containers : Array[IonValue] = []
  if visit_own_tokens(self, containers, found) {
    return true
  }
  while containers.pop() is Some(container) {
    match container.kind {
      List(items) | Sexp(items) =>
        for item in items {
          if visit_own_tokens(item, containers, found) {
            return true
          }
        }
      Struct(fields) =>
        for field in fields {
          if found(field.name) ||
            visit_own_tokens(field.value, containers, found) {
            return true
          }
        }
      _ => ()
    }
  }
  false
}

///|
/// Whether `found` holds for an annotation or the symbol value of `value`.
/// A container goes on `containers`, for its children.
fn visit_own_tokens(
  value : IonValue,
  containers : Array[IonValue],
  found : (SymbolToken) -> Bool,
) -> Bool {
  for annotation in value.annotations {
    if found(annotation) {
      return true
    }
  }
  match value.kind {
    Symbol(token) => found(token)
    List(_) | Sexp(_) | Struct(_) => {
      containers.push(value)
      false
    }
    _ => false
  }
}

///|
/// Call `visit` on every symbol token in `self`, in document order: for each
/// value, its struct field name, then its annotations, then its symbol value.
/// Writers intern symbols in this order, so batch and incremental writers give
/// the same IDs.
fn IonValue::each_token(self : IonValue, visit : (SymbolToken) -> Unit) -> Unit {
  let walker = self.walker()
  while true {
    match walker.step() {
      AtScalar | AtEnter => ()
      AtExit => continue
      Done => break
    }
    if walker.current_field is Some(name) {
      visit(name)
    }
    let value = walker.current
    for annotation in value.annotations {
      visit(annotation)
    }
    if value.kind is Symbol(token) {
      visit(token)
    }
  }
}

///|
/// The rebuilt children of a container that `map_tokens` is inside.
priv enum Rebuilt {
  Items(Array[IonValue])
  Fields(Array[Field])
}

///|
/// `self` with `rewrite` applied to every symbol token: annotations, field
/// names and symbol values at any depth, with no recursion. `rewrite` sees the
/// tokens in document order (see [`IonValue::each_token`]), so when it raises,
/// the error is for the first failing token in the text. Each value is built
/// and added to its parent when the walk enters it.
fn IonValue::map_tokens(
  self : IonValue,
  rewrite : (SymbolToken) -> SymbolToken raise IonError,
) -> IonValue raise IonError {
  let walker = self.walker()
  let open : Array[Rebuilt] = []
  let mut root = self
  while true {
    match walker.step() {
      AtScalar | AtEnter => ()
      AtExit => {
        ignore(open.pop())
        continue
      }
      Done => break
    }
    let value = walker.current
    let name = match walker.current_field {
      Some(token) => Some(rewrite(token))
      None => None
    }
    let annotations = value.annotations.map(rewrite)
    let (rebuilt, children) = match value.kind {
      Symbol(token) => (IonValue::symbol_token(rewrite(token)), None)
      List(_) => {
        let items : Array[IonValue] = []
        (IonValue::list(items), Some(Rebuilt::Items(items)))
      }
      Sexp(_) => {
        let items : Array[IonValue] = []
        (IonValue::sexp(items), Some(Rebuilt::Items(items)))
      }
      Struct(_) => {
        let fields : Array[Field] = []
        (IonValue::from_fields(fields), Some(Rebuilt::Fields(fields)))
      }
      _ => (value, None)
    }
    // A scalar with no tokens to rewrite is kept as it is.
    let result = if annotations.is_empty() && physical_equal(rebuilt, value) {
      value
    } else {
      rebuilt.with_annotations(annotations)
    }
    match (open.last(), name) {
      (None, _) => root = result
      (Some(Items(items)), _) => items.push(result)
      (Some(Fields(fields)), Some(name)) =>
        fields.push(Field::from_token(name, result))
      // A struct child always has a field name.
      (Some(Fields(_)), None) => ()
    }
    if children is Some(children) {
      open.push(children)
    }
  }
  root
}
