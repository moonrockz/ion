// Golden (snapshot) tests over the Ion fixtures in `tests/fixtures`.
//
// `moon test` runs from the module root, so the fixtures are read from there.
// Refresh the recorded output with `moon test --update`.

///|
fn fixture(name : String) -> String raise {
  @fs.read_file_to_string("tests/fixtures/" + name)
}

///|
fn canonical(name : String) -> String raise {
  @text.write_all(@text.read_ion_datagram(fixture(name)))
}

///|
fn event_trace(name : String) -> String raise {
  let reader = @text.IonReader::from_text(fixture(name))
  let lines : Array[String] = []
  for event in reader.remaining() {
    lines.push(event.to_text())
  }
  lines.join("\n")
}

///|
test "golden: scalars round-trip" {
  inspect(
    canonical("scalars.ion"),
    content=(
      #|null
      #|null.int
      #|null.string
      #|true
      #|false
      #|0
      #|-17
      #|255
      #|10
      #|1000000
      #|15d-1
      #|-0d-1
      #|1d3
      #|1.5e0
      #|nan
      #|+inf
      #|-inf
      #|2007T
      #|2007-02-23
      #|2007-02-23T12:14:33.079-08:00
      #|symbol
      #|'quoted symbol'
      #|"string\ttab"
      #|"long\nstring"
      #|int32::12
      #|a::b::7
      #|{{ aGk= }}
      #|{{ "clob text" }}
    ),
  )
}

///|
test "golden: containers round-trip" {
  inspect(
    canonical("containers.ion"),
    content=(
      #|[]
      #|()
      #|{}
      #|[1, 2, 3]
      #|[1, [2, [3]]]
      #|(a b c)
      #|(1 + 2 * 3)
      #|{a: 1, b: "x", c: [true, null]}
      #|{outer: {inner: {deep: 1}}}
      #|[1, 2]
      #|ann::[1, 2]
    ),
  )
}

///|
test "golden: sample event stream" {
  inspect(
    event_trace("sample.ion"),
    content=(
      #|DocumentStart
      #|StructStart
      #|FieldName(name)
      #|Scalar(string)
      #|FieldName(version)
      #|Scalar(int)
      #|FieldName(tags)
      #|ListStart
      #|Scalar(symbol)
      #|Scalar(symbol)
      #|ListEnd
      #|FieldName(pi)
      #|Scalar(decimal)
      #|FieldName(created)
      #|Scalar(timestamp)
      #|StructEnd
      #|DocumentEnd
    ),
  )
}

///|
fn token_trace(name : String) -> String raise {
  let tokens = @text.tokenize(fixture(name))
  let lines : Array[String] = []
  for token in tokens {
    if token.kind() is @text.IonTokenKind::Whitespace {
      continue
    }
    lines.push(token.kind().to_text())
  }
  lines.join(" ")
}

///|
test "golden: sample token stream" {
  inspect(
    token_trace("sample.ion"),
    content=(
      #|{ symbol(name) : string , symbol(version) : int , symbol(tags) : [ symbol(ion) , symbol(schema) ] , symbol(pi) : decimal , symbol(created) : timestamp , }
    ),
  )
}
