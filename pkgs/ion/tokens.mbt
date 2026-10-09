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
