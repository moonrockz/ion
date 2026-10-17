// Where the text writer puts each value: separators, indents, field names,
// and bare operators inside S-expressions. The incremental writers depend on
// `write_fragment` placing a value inside text that they already wrote.

///|
test "empty, typed-null and annotated containers in compact text" {
  inspect(
    @text.write_ion(@text.read_ion("{a: [], b: null.list, c: x::(), d: y::{}}")),
    content="{a: [], b: null.list, c: x::(), d: y::{}}",
  )
}

///|
test "empty, typed-null and annotated containers in pretty text" {
  inspect(
    @text.write_ion_pretty(
      @text.read_ion("{a: [], b: null.list, c: x::(+ 1), d: [y::{e: 2}]}"),
    ),
    content=(
      #|{
      #|  a: [],
      #|  b: null.list,
      #|  c: x::(
      #|    +
      #|    1
      #|  ),
      #|  d: [
      #|    y::{
      #|      e: 2
      #|    }
      #|  ]
      #|}
    ),
  )
}

///|
test "write_fragment indents from the depth it is given" {
  inspect(
    @text.write_fragment(@text.read_ion("[1, (a)]"), depth=2, pretty=true),
    content=(
      #|[
      #|      1,
      #|      (
      #|        a
      #|      )
      #|    ]
    ),
  )
}

///|
test "write_fragment writes an operator bare only inside an S-expression" {
  let plus = @ion.IonValue::symbol("+")
  inspect(@text.write_fragment(plus, in_sexp=true), content="+")
  inspect(@text.write_fragment(plus), content="'+'")
  inspect(
    @text.write_fragment(@ion.IonValue::list([plus]), in_sexp=true),
    content="['+']",
  )
  inspect(
    @text.write_fragment(
      @ion.IonValue::sexp([plus]).with_annotation(
        @ion.SymbolToken::SymbolToken("+"),
      ),
    ),
    content="'+'::(+)",
  )
}
