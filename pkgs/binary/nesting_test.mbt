// The binary readers accept containers nested up to @ion.MAX_NESTING_DEPTH
// and raise IonError::LimitExceeded past it, however deep the input goes,
// instead of overflowing the call stack.

///|
/// The `VarUInt` encoding of `n`: seven bits per octet, most significant
/// first, with the high bit set on the last octet.
fn var_uint(n : Int) -> Array[Byte] {
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
fn header(type_code : Int, length : Int) -> Array[Byte] {
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
  type_code : Int
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
fn nested(frames : Array[Frame], depth : Int) -> Bytes {
  let inner : Array[Byte] = [b'\x21', b'\x01']
  let headers : Array[Array[Byte]] = []
  let mut length = inner.length()
  for _ in 0..<depth {
    for frame in frames {
      let level = [
        ..header(frame.type_code, frame.prefix.length() + length),
        ..frame.prefix,
      ]
      headers.push(level)
      length += level.length()
    }
  }
  let out : Array[Byte] = []
  for index = headers.length() - 1; index >= 0; index = index - 1 {
    out.push_iter(headers[index].iter())
  }
  out.push_iter(inner.iter())
  Bytes::from_array(out)
}

///|
/// Whether `read` raises `IonError::LimitExceeded`.
fn exceeds_limit(read : () -> Unit raise @ion.IonError) -> Bool {
  try read() catch {
    @ion.IonError::LimitExceeded(_) => true
    _ => false
  } noraise {
    _ => false
  }
}

///|
test "read_binary accepts containers nested to MAX_NESTING_DEPTH" {
  for frames in spellings {
    let value = @binary.read_binary_value(
      nested(frames, @ion.MAX_NESTING_DEPTH),
    )
    let again = @binary.read_binary_value(@binary.write_binary_value(value))
    assert_true(value.equals(again))
  }
}

///|
test "read_binary rejects containers nested one level past MAX_NESTING_DEPTH" {
  for frames in spellings {
    let bytes = nested(frames, @ion.MAX_NESTING_DEPTH + 1)
    assert_true(exceeds_limit(() => ignore(@binary.read_binary(bytes))))
  }
}

///|
test "read_binary rejects 100,000 nested containers without overflowing the stack" {
  for frames in spellings {
    let bytes = nested(frames, 100_000)
    assert_true(exceeds_limit(() => ignore(@binary.read_binary(bytes))))
  }
}

///|
test "decode_value applies the limit to the value it decodes" {
  let bytes = nested(spellings[0], @ion.MAX_NESTING_DEPTH + 1)
  let table = @ion.SymbolTable::system()
  assert_true(
    exceeds_limit(() => ignore(@binary.decode_value(bytes, 0, table))),
  )
}
