# Ion binary (`moonrockz/ion/binary`)

Reads and writes the Ion 1.0 binary encoding: the version marker, type
descriptors, every value type, annotation wrappers, NOP padding, and local
symbol tables. The [ion-tests](https://github.com/amazon-ion/ion-tests) suite
checks it.

| Need | API |
| --- | --- |
| A whole datagram | `read_binary`, `write_binary` |
| One value, as its own datagram | `read_binary_value`, `write_binary_value` |
| One value at a time, for a stream | `decode_value`, `encode_value`, `value_size` |
| The symbol table a writer needs | `symbols_for_values`, `local_symbol_table` |
| Type descriptors | `IonTypeCode`, `type_descriptor`, `descriptor_type_code` |

`moonrockz/ion/binary/stream` runs the same codec over async IO.

## Reading and writing

A datagram starts with the four-octet version marker `E0 01 00 EA`. The
writer adds a local symbol table when a value uses a symbol that the system
table does not define.

```mbt check
///|
fn octets(bytes : Bytes) -> String {
  bytes
  .to_array()
  .map(octet => {
    let text = octet.to_int().to_string(radix=16)
    if text.length() == 1 {
      "0" + text
    } else {
      text
    }
  })
  .join(" ")
}

///|
test "write and read a datagram" {
  let values = @text.read_ion_datagram("1 true \"hi\"")
  let bytes = @binary.write_binary(values)
  inspect(octets(bytes), content="e0 01 00 ea 21 01 11 82 68 69")
  inspect(
    @text.write_all(@binary.read_binary(bytes)),
    content=(
      #|1
      #|true
      #|"hi"
    ),
  )
}

///|
test "a symbol outside the system table gets a local symbol table" {
  let bytes = @binary.write_binary_value(@ion.IonValue::symbol("hello"))
  // The marker, `$ion_symbol_table::{symbols: ["hello"]}`, and symbol 10.
  inspect(
    octets(bytes),
    content="e0 01 00 ea eb 81 83 d8 87 b6 85 68 65 6c 6c 6f 71 0a",
  )
  inspect(@text.write_ion(@binary.read_binary_value(bytes)), content="hello")
}
```

Binary is usually smaller than text, and it keeps every value exactly:

```mbt check
///|
test "binary round trips keep precision" {
  let text = "{ price: 19.990, when: 2024-02-29T12:00:00.500+01:00, big: 123456789012345678901234567890 }"
  let values = @text.read_ion_datagram(text)
  let bytes = @binary.write_binary(values)
  assert_true(@binary.read_binary(bytes)[0].equals(values[0]))
  inspect(bytes.length() < text.length(), content="true")
}
```

Malformed input raises an `@ion.IonError`:

```mbt check
///|
test "a truncated value" {
  let bytes = @binary.write_binary_value(@ion.IonValue::string("truncated"))
  let message = try @binary.read_binary(bytes[:bytes.length() - 1]) catch {
    error => error.message()
  } noraise {
    _ => "read"
  }
  inspect(message, content="truncated Ion binary value")
}
```

## One value at a time

A streaming writer builds one symbol table for all its values, writes it
after the marker, and then encodes each value with it. A streaming reader
asks `value_size` how many octets the next value needs, and decodes it once
they have arrived.

```mbt check
///|
test "encode and decode value by value" {
  let values = [@ion.IonValue::symbol("red"), @ion.IonValue::symbol("green")]
  let symbols = @binary.symbols_for_values(values)
  let mut bytes = @binary.binary_version_marker() +
    @binary.local_symbol_table(symbols).unwrap()
  for value in values {
    bytes = bytes + @binary.encode_value(value, symbols)
  }
  inspect(
    @text.write_all(@binary.read_binary(bytes)),
    content=(
      #|red
      #|green
    ),
  )
  // Decoding from a view: the table applies to the values after it.
  let table = @ion.SymbolTable::system()
  let mut offset = 4
  let read : Array[String] = []
  while @binary.decode_value(bytes[:], offset, table) is Some((value, used)) {
    offset += used
    if @binary.accept_value(table, value) is Some(value) {
      read.push(@text.write_ion(value))
    }
  }
  debug_inspect(
    read,
    content=(
      #|["red", "green"]
    ),
  )
}
```

## Type descriptors

Each value starts with a descriptor octet: a type code in the high nibble and
a length (or a null marker) in the low nibble.

```mbt check
///|
test "type descriptors" {
  let descriptor = @binary.type_descriptor(
    @binary.IonTypeCode::from_ion_type(String),
    3,
  )
  inspect(descriptor.to_string(radix=16), content="83")
  debug_inspect(
    @binary.descriptor_type_code(0x2F).to_ion_type(),
    content="Some(Int)",
  )
  inspect(@binary.descriptor_is_null(0x2F), content="true")
}
```
