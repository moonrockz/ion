// Construct a writer context from symbols originating in different streams.

///|
/// Whether any unknown symbol value, field name, or annotation retains a
/// shared-table import location.
pub fn IonValue::has_imported_symbols(self : IonValue) -> Bool {
  let token = fn(found : Bool, token : SymbolToken) -> FoldAction[Bool] {
    if token.text is None && token.import_location is Some(_) {
      Stop(true)
    } else {
      Continue(found)
    }
  }
  self.fold(false, {
    visit_value: fn(found, value) {
      match value.kind() {
        Symbol(symbol) => token(found, symbol)
        _ => Continue(found)
      }
    },
    visit_annotation: token,
    visit_field_name: token,
  })
}

///|
/// Build a symbol table for serializing `values`. Unknown imported symbols
/// retain their shared-table name, version, and slot; their stream-local IDs
/// may change. Unknown local IDs are reserved after the imports.
/// Conflicting versions of the same unknown shared table in one context are
/// rejected because a catalog could resolve their null slots differently.
pub fn SymbolTable::for_values(
  values : Array[IonValue],
) -> SymbolTable raise IonError {
  let tokens : Array[SymbolToken] = []
  let add = fn(acc : Unit, token : SymbolToken) -> FoldAction[Unit] {
    tokens.push(token)
    Continue(acc)
  }
  fold_values(values, (), {
    visit_value: fn(acc, value) {
      if value.kind() is Symbol(token) {
        tokens.push(token)
      }
      Continue(acc)
    },
    visit_annotation: add,
    visit_field_name: add,
  })
  let table = SymbolTable::system()
  let mut highest_local = 9
  for token in tokens {
    if token.text is Some(_) {
      continue
    }
    match token.import_location {
      Some(location) => {
        let version = token.import_version.unwrap_or(1)
        if location.name == "" ||
          location.name == "$ion" ||
          location.sid < 1 ||
          version < 1 {
          raise DataModel("invalid shared-symbol import location")
        }
        let mut found = false
        for index in 0..<table.imports.length() {
          let import_ = table.imports[index]
          if import_.name == location.name {
            if import_.version != version {
              raise Unsupported(
                "cannot serialize unknown symbols from different versions of shared table \{location.name} in one context",
              )
            }
            table.imports[index] = {
              ..import_,
              count: @cmp.maximum(import_.count, location.sid),
            }
            found = true
            break
          }
        }
        if !found {
          table.imports.push({
            name: location.name,
            version,
            count: location.sid,
            known: [],
          })
        }
      }
      None => {
        let sid = token.sid.unwrap_or(0)
        if sid < 0 {
          raise DataModel("a symbol ID cannot be negative")
        }
        highest_local = @cmp.maximum(highest_local, sid)
      }
    }
  }
  for import_ in table.imports {
    if import_.count > 0x7FFF_FFFF - 9 - table.imported {
      raise DataModel("writer symbol table exceeds the symbol ID range")
    }
    table.imported += import_.count
  }
  if highest_local > 0x7FFF_FFFF - table.imported {
    raise DataModel("writer symbol table exceeds the symbol ID range")
  }
  table.reserved = highest_local - 9
  for token in tokens {
    ignore(table.intern_token(token))
  }
  table
}

///|
/// The ID a writer context assigns to `token`. Imported unknown symbols are
/// located by table name and slot; local unknown IDs follow this context's
/// imported IDs. Known text is interned as usual.
pub fn SymbolTable::intern_token(
  self : SymbolTable,
  token : SymbolToken,
) -> Int raise IonError {
  if token.text is Some(text) {
    if self.find(text) is None && self.max_id() == 0x7FFF_FFFF {
      raise DataModel("writer symbol table exceeds the symbol ID range")
    }
    return self.intern(text)
  }
  if token.import_location is Some(location) {
    let mut offset = 9
    for import_ in self.imports {
      if import_.name == location.name &&
        Some(import_.version) == token.import_version &&
        location.sid >= 1 &&
        location.sid <= import_.count {
        return offset + location.sid
      }
      offset += import_.count
    }
    raise Unsupported(
      "writer context does not declare the symbol's shared import",
    )
  }
  match token.sid {
    Some(sid) if sid >= 0 => {
      if sid > 0x7FFF_FFFF - self.imported {
        raise DataModel("writer symbol table exceeds the symbol ID range")
      }
      if sid > 9 {
        sid + self.imported
      } else {
        sid
      }
    }
    _ => raise DataModel("a symbol has no valid text or ID")
  }
}

///|
/// Replace unknown tokens with this context's IDs for rendering symbol-ID
/// literals in text. Emit this context's local symbol table before the result.
pub fn SymbolTable::localize_for_text(
  self : SymbolTable,
  value : IonValue,
) -> IonValue raise IonError {
  let rewrite = fn(token : SymbolToken) -> SymbolToken raise IonError {
    if token.text is Some(_) {
      token
    } else {
      SymbolToken::from_sid(self.intern_token(token))
    }
  }
  let annotations = value.annotations().map(rewrite)
  let mapped = match value.kind() {
    Symbol(token) => IonValue::symbol_token(rewrite(token))
    List(items) =>
      IonValue::list(items.map(item => self.localize_for_text(item)))
    Sexp(items) =>
      IonValue::sexp(items.map(item => self.localize_for_text(item)))
    Struct(fields) =>
      IonValue::from_fields(
        fields.map(field => {
          Field::from_token(
            rewrite(field.name()),
            self.localize_for_text(field.value()),
          )
        }),
      )
    _ => value
  }
  mapped.with_annotations(annotations)
}
