// The symbol tokens of a value, at any depth.
//
// Each walk recurses while a value is at most MAX_NESTING_DEPTH levels deep,
// which is the fastest walk and covers every value a reader returns, and
// switches to an explicit stack below that depth.

///|
/// Whether `found` holds for a symbol token in `self`: an annotation, a struct
/// field name or a symbol value at any depth. The tokens come in no fixed
/// order, so below the recursion limit the walk needs only a stack of
/// containers, which costs less than a `ValueWalker`. Use
/// [`IonValue::each_token`] when the order matters.
fn IonValue::any_token(self : IonValue, found : (SymbolToken) -> Bool) -> Bool {
  any_token_shallow(self, found, MAX_NESTING_DEPTH)
}

///|
/// `any_token` with recursion while `levels` is above zero.
fn any_token_shallow(
  value : IonValue,
  found : (SymbolToken) -> Bool,
  levels : Int32,
) -> Bool {
  if levels == 0 {
    return any_token_deep(value, found)
  }
  for annotation in value.annotations {
    if found(annotation) {
      return true
    }
  }
  match value.kind {
    Symbol(token) => found(token)
    List(items) | Sexp(items) => {
      for item in items {
        if any_token_shallow(item, found, levels - 1) {
          return true
        }
      }
      false
    }
    Struct(fields) => {
      for field in fields {
        if found(field.name) ||
          any_token_shallow(field.value, found, levels - 1) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
/// `any_token` with no recursion, on a stack of containers.
fn any_token_deep(value : IonValue, found : (SymbolToken) -> Bool) -> Bool {
  let containers : Array[IonValue] = []
  if visit_own_tokens(value, containers, found) {
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
  each_token_shallow(self, visit, MAX_NESTING_DEPTH)
}

///|
/// `each_token` with recursion while `levels` is above zero.
fn each_token_shallow(
  value : IonValue,
  visit : (SymbolToken) -> Unit,
  levels : Int32,
) -> Unit {
  if levels == 0 {
    return each_token_deep(value, visit)
  }
  for annotation in value.annotations {
    visit(annotation)
  }
  match value.kind {
    Symbol(token) => visit(token)
    List(items) | Sexp(items) =>
      for item in items {
        each_token_shallow(item, visit, levels - 1)
      }
    Struct(fields) =>
      for field in fields {
        visit(field.name)
        each_token_shallow(field.value, visit, levels - 1)
      }
    _ => ()
  }
}

///|
/// `each_token` with no recursion, on a `ValueWalker`.
fn each_token_deep(value : IonValue, visit : (SymbolToken) -> Unit) -> Unit {
  let walker = value.walker()
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
/// names and symbol values at any depth. `rewrite` sees the tokens in
/// document order (see [`IonValue::each_token`]), so when it raises, the error
/// is for the first failing token in the text.
fn IonValue::map_tokens(
  self : IonValue,
  rewrite : (SymbolToken) -> SymbolToken raise IonError,
) -> IonValue raise IonError {
  map_tokens_shallow(self, rewrite, MAX_NESTING_DEPTH)
}

///|
/// `map_tokens` with recursion while `levels` is above zero. A field name is
/// rewritten before its value, and a value's annotations before its symbol
/// or children, so the order is the same as in `map_tokens_deep`. A value
/// whose tokens all come back unchanged (the same token objects) is returned
/// as it is, so a value with nothing to rewrite costs no copy.
fn map_tokens_shallow(
  value : IonValue,
  rewrite : (SymbolToken) -> SymbolToken raise IonError,
  levels : Int32,
) -> IonValue raise IonError {
  if levels == 0 {
    return map_tokens_deep(value, rewrite)
  }
  let annotations = map_annotations(value.annotations, rewrite)
  let rebuilt = match value.kind {
    Symbol(token) => {
      let rewritten = rewrite(token)
      if physical_equal(rewritten, token) {
        value
      } else {
        IonValue::symbol_token(rewritten)
      }
    }
    List(items) =>
      match map_items(items, rewrite, levels - 1) {
        Some(rewritten) => IonValue::list(rewritten)
        None => value
      }
    Sexp(items) =>
      match map_items(items, rewrite, levels - 1) {
        Some(rewritten) => IonValue::sexp(rewritten)
        None => value
      }
    Struct(fields) =>
      match map_fields(fields, rewrite, levels - 1) {
        Some(rewritten) => IonValue::from_fields(rewritten)
        None => value
      }
    _ => value
  }
  match annotations {
    Some(annotations) => rebuilt.with_annotations(annotations)
    None if physical_equal(rebuilt, value) => value
    None => rebuilt.with_annotations(value.annotations)
  }
}

///|
/// The rewritten annotations, or `None` when every one comes back unchanged.
fn map_annotations(
  annotations : Array[SymbolToken],
  rewrite : (SymbolToken) -> SymbolToken raise IonError,
) -> Array[SymbolToken]? raise IonError {
  let mut changed : Array[SymbolToken]? = None
  for index, annotation in annotations {
    let rewritten = rewrite(annotation)
    match changed {
      Some(out) => out.push(rewritten)
      None if physical_equal(rewritten, annotation) => ()
      None => {
        let out : Array[SymbolToken] = Array(capacity=annotations.length())
        for earlier in annotations[:index] {
          out.push(earlier)
        }
        out.push(rewritten)
        changed = Some(out)
      }
    }
  }
  changed
}

///|
/// The rewritten items, or `None` when every one comes back unchanged.
fn map_items(
  items : Array[IonValue],
  rewrite : (SymbolToken) -> SymbolToken raise IonError,
  levels : Int32,
) -> Array[IonValue]? raise IonError {
  let mut changed : Array[IonValue]? = None
  for index, item in items {
    let rewritten = map_tokens_shallow(item, rewrite, levels)
    match changed {
      Some(out) => out.push(rewritten)
      None if physical_equal(rewritten, item) => ()
      None => {
        let out : Array[IonValue] = Array(capacity=items.length())
        for earlier in items[:index] {
          out.push(earlier)
        }
        out.push(rewritten)
        changed = Some(out)
      }
    }
  }
  changed
}

///|
/// The rewritten fields, or `None` when every name and value comes back
/// unchanged.
fn map_fields(
  fields : Array[Field],
  rewrite : (SymbolToken) -> SymbolToken raise IonError,
  levels : Int32,
) -> Array[Field]? raise IonError {
  let mut changed : Array[Field]? = None
  for index, field in fields {
    let name = rewrite(field.name)
    let value = map_tokens_shallow(field.value, rewrite, levels)
    match changed {
      Some(out) => out.push(Field::from_token(name, value))
      None if physical_equal(name, field.name) &&
        physical_equal(value, field.value) => ()
      None => {
        let out : Array[Field] = Array(capacity=fields.length())
        for earlier in fields[:index] {
          out.push(earlier)
        }
        out.push(Field::from_token(name, value))
        changed = Some(out)
      }
    }
  }
  changed
}

///|
/// `map_tokens` with no recursion, on a `ValueWalker`. Each value is built
/// and added to its parent when the walk enters it.
fn map_tokens_deep(
  value : IonValue,
  rewrite : (SymbolToken) -> SymbolToken raise IonError,
) -> IonValue raise IonError {
  let walker = value.walker()
  let open : Array[Rebuilt] = []
  let mut root = value
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
