// The symbol tokens of a value, in document order, with no recursion.

///|
/// Every symbol token in `self`, in document order: for each value, its
/// struct field name, then its annotations, then its symbol value. Writers
/// intern symbols in this order, so batch and incremental writers give the
/// same IDs.
fn IonValue::tokens(self : IonValue) -> Iter[SymbolToken] {
  let walker = self.walker()
  // The tokens of the current value that are still to come, last one first.
  let pending : Array[SymbolToken] = []
  Iter::new(() => {
    while pending.is_empty() {
      let (value, field) = match walker.next() {
        None => return None
        Some(Exit(_, ..)) => continue
        Some(Scalar(value, field~)) | Some(Enter(value, field~)) =>
          (value, field)
      }
      if value.kind is Symbol(token) {
        pending.push(token)
      }
      for index = value.annotations.length() - 1; index >= 0; index = index - 1 {
        pending.push(value.annotations[index])
      }
      if field is Some(name) {
        pending.push(name)
      }
    }
    pending.pop()
  })
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
/// tokens in document order (see [`IonValue::tokens`]), so when it raises, the
/// error is for the first failing token in the text. Each value is built and
/// added to its parent when the walk enters it.
fn IonValue::map_tokens(
  self : IonValue,
  rewrite : (SymbolToken) -> SymbolToken raise IonError,
) -> IonValue raise IonError {
  let open : Array[Rebuilt] = []
  let mut root = self
  for event in self.walk() {
    let (value, field) = match event {
      Scalar(value, field~) | Enter(value, field~) => (value, field)
      Exit(_, ..) => {
        ignore(open.pop())
        continue
      }
    }
    let name = match field {
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
    let result = rebuilt.with_annotations(annotations)
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
