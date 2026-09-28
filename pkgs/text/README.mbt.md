# Ion text (`moonrockz/ion/text`)

Reads and writes the Ion text encoding, and offers the four ways to consume
a document: a lossless token stream and syntax tree (CST), the `IonValue`
tree (DOM), and a flat event stream, pulled or pushed (SAX).

| Need | API |
| --- | --- |
| One value, or a whole datagram | `read_ion`, `read_ion_datagram` |
| Text back out | `write_ion`, `write_all`, and `_pretty` forms |
| Tokens and source spans | `tokenize`, `parse_cst` |
| Events without building the tree | `IonReader` (pull), `parse_with_handler` (push) |
| Text that arrives in pieces | `read_ion_prefix`, `write_stream_value` |

The reader follows the Ion 1.0 text specification, and the
[ion-tests](https://github.com/amazon-ion/ion-tests) suite checks it. It
applies version markers and local symbol tables rather than returning them.

## Reading and writing

```mbt check
///|
test "read a datagram and write it back" {
  let values = @text.read_ion_datagram(
    "// a comment\n{ name: \"Ion\", released: 2016-04-19, rating: 4.5 } 'a symbol' [1, 0x2A]",
  )
  inspect(values.length(), content="3")
  inspect(
    @text.write_all(values),
    content=(
      #|{name: "Ion", released: 2016-04-19, rating: 45d-1}
      #|'a symbol'
      #|[1, 42]
    ),
  )
}
```

The writer spells every value so it reads back to the same value: symbols
are quoted only when they must be, floats keep an exponent, and decimals keep
their precision.

```mbt check
///|
test "the writer keeps every value distinct" {
  let values = @text.read_ion_datagram(
    "null true 'null' 2.50 2.5e0 $ion_symbol_table",
  )
  inspect(
    @text.write_all(values),
    content=(
      #|null
      #|true
      #|'null'
      #|250d-2
      #|2.5e0
      #|$ion_symbol_table
    ),
  )
}
```

`write_ion_pretty` indents containers:

```mbt check
///|
test "pretty text" {
  let value = @text.read_ion("{ name: \"Ion\", tags: [data, format] }")
  inspect(
    @text.write_ion_pretty(value),
    content=(
      #|{
      #|  name: "Ion",
      #|  tags: [
      #|    data,
      #|    format
      #|  ]
      #|}
    ),
  )
}
```

Errors are `@ion.IonError` values:

```mbt check
///|
test "a syntax error" {
  let message = try @text.read_ion("[1, 2") catch {
    error => error.message()
  } noraise {
    _ => "read"
  }
  inspect(message, content="expected ',' or ']' in list")
}
```

## Symbol tables

A local symbol table gives text to symbol IDs such as `$10`; it is applied,
not returned. A version marker, `$ion_1_0`, resets it.

```mbt check
///|
test "a local symbol table" {
  let values = @text.read_ion_datagram(
    "$ion_symbol_table::{ symbols: [\"red\", \"green\"] } $10 $11 $ion_1_0 $4",
  )
  inspect(
    @text.write_all(values),
    content=(
      #|red
      #|green
      #|name
    ),
  )
}
```

## Tokens and the syntax tree

`tokenize` is lossless: every character belongs to a token, whitespace and
comments included, and each token records its source span. `parse_cst` builds
a tree of those tokens.

```mbt check
///|
test "tokens keep their spans" {
  let source = "int32::12 // twelve"
  let tokens = @text.tokenize(source)
  debug_inspect(
    tokens.map(token => {
      token.kind().to_text() + " " + token.slice(source).to_owned()
    }),
    content=(
      #|[
      #|  "symbol(int32) int32",
      #|  ":: ::",
      #|  "int 12",
      #|  "whitespace  ",
      #|  "comment // twelve",
      #|]
    ),
  )
  let document = @text.parse_cst(source)
  let value = document.values()[0]
  inspect(value.annotations().length(), content="1")
  inspect(value.slice(source), content="int32::12")
}
```

## Events

`IonReader` pulls a flat event stream, and `parse_with_handler` pushes the
same events to an `IonHandler`, whose methods all default to doing nothing.

```mbt check
///|
test "pull events" {
  let reader = @text.IonReader::from_text("point::{ x: 1, y: [2] }")
  debug_inspect(
    reader.remaining().map(event => event.to_text()),
    content=(
      #|[
      #|  "DocumentStart",
      #|  "Annotation(point)",
      #|  "StructStart",
      #|  "FieldName(x)",
      #|  "Scalar(int)",
      #|  "FieldName(y)",
      #|  "ListStart",
      #|  "Scalar(int)",
      #|  "ListEnd",
      #|  "StructEnd",
      #|  "DocumentEnd",
      #|]
    ),
  )
}

///|
struct Depth {
  mut depth : Int
  mut deepest : Int
}

///|
impl @text.IonHandler for Depth with fn on_list_start(self) {
  self.depth += 1
  self.deepest = @cmp.maximum(self.depth, self.deepest)
}

///|
impl @text.IonHandler for Depth with fn on_list_end(self) {
  self.depth -= 1
}

///|
test "push events to a handler" {
  let handler : Depth = { depth: 0, deepest: 0, }
  @text.parse_with_handler("[1, [2, [3]], [4]]", handler)
  inspect(handler.deepest, content="3")
}
```

## Text that arrives in pieces

`read_ion_prefix` reads the first value of text that may be cut short, as a
streaming reader sees it, and says how much text it used. `None` asks for
more text. `moonrockz/ion/text/stream` builds its async reader on it.

```mbt check
///|
test "read a prefix" {
  let symbols = @ion.SymbolTable::system()
  // `12` may continue, so it is not settled yet.
  debug_inspect(
    @text.read_ion_prefix("{a: 1} 12", symbols~, end_of_input=false).map(pair => {
      pair.1
    }),
    content="Some(7)",
  )
  inspect(
    @text.read_ion_prefix("12", symbols~, end_of_input=false) is None,
    content="true",
  )
  debug_inspect(
    @text.read_ion_prefix("12", symbols~, end_of_input=true).map(pair => pair.1),
    content="Some(2)",
  )
}
```
