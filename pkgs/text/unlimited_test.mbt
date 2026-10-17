///|
test "text reading accepts 10000 nested containers without caller fuel" {
  for (open, close) in [("[", "]"), ("(", ")"), ("{a:", "}"), ("x::[", "]")] {
    let source = open.repeat(10000) + "1" + close.repeat(10000)
    let value = @text.read_ion(source)
    assert_eq(
      value.fold_up(scalar=_ => 0, container=(_, children) => children[0].1 + 1),
      10000,
    )
  }
}

///|
test "text fuel and annotations remain consistent across the execution switch" {
  let source = "tag::[".repeat(140) + "[1],[2]" + "]".repeat(140)
  ignore(@text.read_ion(source, fuel=Limited(@ion.Budget(141))))
  let exhausted = try
    @text.read_ion(source, fuel=Limited(@ion.Budget(140)))
  catch {
    @ion.IonError::FuelExhausted(..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}

///|
struct FuelHandler {}

///|
impl @text.IonHandler for FuelHandler

///|
test "handler parsing honors caller fuel" {
  let exhausted = try
    @text.parse_with_handler(
      "[[1]]",
      FuelHandler::{ },
      fuel=Limited(@ion.Budget(1)),
    )
  catch {
    @ion.IonError::FuelExhausted(..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}

///|
test "text event readers honor caller fuel" {
  let exhausted = try
    @text.IonReader::from_text("[[[1]]]", fuel=Limited(@ion.Budget(2)))
  catch {
    @ion.IonError::FuelExhausted(..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}

///|
test "finite text fuel counts open containers and is reused by siblings" {
  let fuel = @ion.Fuel::Limited(@ion.Budget(2))
  ignore(@text.read_ion("[[1],[2],[]]", fuel~))
  assert_eq(@text.read_ion_datagram("[[1]] [[2]]", fuel~).length(), 2)
  let exhausted = try {
    ignore(@text.read_ion("[[[1]]]", fuel~))
    false
  } catch {
    @ion.IonError::FuelExhausted(budget~, operation~, location~) => {
      assert_eq(budget.units(), 2)
      assert_eq(operation, @ion.FuelOperation::TextRead)
      assert_eq(location, @ion.FuelLocation::TextOffset(2))
      true
    }
    _ => false
  }
  assert_true(exhausted)
}

///|
test "prefix parsing propagates fuel exhaustion before input ends" {
  let symbols = @ion.SymbolTable::system()
  let error = try {
    ignore(
      @text.read_ion_prefix(
        "[[[",
        symbols~,
        end_of_input=false,
        fuel=Limited(@ion.Budget(2)),
      ),
    )
    None
  } catch {
    @ion.IonError::FuelExhausted(..) => Some("fuel")
    _ => Some("other")
  }
  assert_eq(error, Some("fuel"))
  assert_true(
    @text.read_ion_prefix("[[[", symbols~, end_of_input=false) is None,
  )
}

///|
test "deep malformed text unwinds and a new parse remains independent" {
  let source = "[".repeat(10000) + "1" + "]".repeat(9999)
  let syntax_error = try @text.read_ion(source) catch {
    @ion.IonError::Syntax(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(syntax_error)
  assert_true(@text.read_ion("[1]").kind() is @ion.IonValueKind::List(_))
}

///|
test "CST reading accepts deep containers and honors optional fuel" {
  let source = "[".repeat(10000) + "1" + "]".repeat(10000)
  let document = @text.parse_cst(source)
  assert_eq(document.values()[0].end(), source.length())
  let exhausted = try
    @text.parse_cst("[[[1]]]", fuel=Limited(@ion.Budget(2)))
  catch {
    @ion.IonError::FuelExhausted(operation=CstRead, ..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}
