// Optional binary fuel bounds active container nesting independently of the
// machine stack. The default accepts any finite nesting depth.

///|
/// The `VarUInt` encoding of `n`: seven bits per octet, most significant
/// first, with the high bit set on the last octet.
fn var_uint(n : Int32) -> Array[Byte] {
  let groups = [(n & 0x7F) | 0x80]
  let mut rest = n >> 7
  while rest > 0 {
    groups.push(rest & 0x7F)
    rest = rest >> 7
  }
  groups.rev().map(group => group.to_byte())
}

///|
/// The type descriptor and length of a value with type code `type_code`
/// whose body is `length` octets.
fn header(type_code : Int32, length : Int32) -> Array[Byte] {
  if length < 14 {
    [((type_code << 4) | length).to_byte()]
  } else {
    [((type_code << 4) | 14).to_byte(), ..var_uint(length)]
  }
}

///|
/// One level of nesting in Ion binary: a container type code and the octets
/// that come before the nested value inside it.
struct Frame {
  type_code : Int32
  prefix : Array[Byte]
}

///|
/// A list, an S-expression, a struct (field `name`, symbol ID 4), and an
/// annotated list (annotation `name`; annotations do not add depth).
let spellings : Array[Array[Frame]] = [
  [{ type_code: 11, prefix: [], }],
  [{ type_code: 12, prefix: [], }],
  [{ type_code: 13, prefix: [b'\x84'], }],
  [
    { type_code: 11, prefix: [], },
    { type_code: 14, prefix: [b'\x81', b'\x84'], },
  ],
]

///|
/// Ion binary for `depth` levels of `frames` nested around the int `1`. The
/// headers are built from the inside out and written from the outside in, so
/// the cost stays linear in the depth.
fn nested(frames : Array[Frame], depth : Int32) -> Bytes {
  let inner : Array[Byte] = [b'\x21', b'\x01']
  let headers : Array[Array[Byte]] = []
  let mut length = inner.length()
  for _ in 0..<depth {
    for frame in frames {
      let level = header(frame.type_code, frame.prefix.length() + length)
      for octet in frame.prefix {
        level.push(octet)
      }
      headers.push(level)
      length += level.length()
    }
  }
  let out : Array[Byte] = Array(capacity=length)
  for index = headers.length() - 1; index >= 0; index = index - 1 {
    for octet in headers[index] {
      out.push(octet)
    }
  }
  for octet in inner {
    out.push(octet)
  }
  Bytes::from_array(out)
}

///|
/// Whether `read` raises `IonError::FuelExhausted`.
fn exceeds_limit(read : () -> Unit raise @ion.IonError) -> Bool {
  try read() catch {
    @ion.IonError::FuelExhausted(..) => true
    _ => false
  } noraise {
    _ => false
  }
}

///|
test "read_binary accepts containers nested to the finite fuel budget" {
  for frames in spellings {
    let value = @binary.read_binary_value(nested(frames, 128))
    let again = @binary.read_binary_value(@binary.write_binary_value(value))
    assert_true(value.equals(again))
  }
}

///|
test "finite binary fuel refuses containers one level past the budget" {
  for frames in spellings {
    let bytes = nested(frames, 128 + 1)
    assert_true(
      exceeds_limit(() => {
        ignore(@binary.read_binary(bytes, fuel=Limited(@ion.Budget(128))))
      }),
    )
  }
}

///|
test "finite binary fuel refuses 100000 nested containers without stack overflow" {
  for frames in spellings {
    let bytes = nested(frames, 100_000)
    assert_true(
      exceeds_limit(() => {
        ignore(@binary.read_binary(bytes, fuel=Limited(@ion.Budget(128))))
      }),
    )
  }
}

///|
test "decode_value applies the limit to the value it decodes" {
  let bytes = nested(spellings[0], 128 + 1)
  let table = @ion.SymbolTable::system()
  assert_true(
    exceeds_limit(() => {
      ignore(
        @binary.decode_value(bytes, 0, table, fuel=Limited(@ion.Budget(128))),
      )
    }),
  )
}
