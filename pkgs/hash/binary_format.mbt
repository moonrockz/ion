// Minimal Ion binary field encoders used by Ion Hash.
//
// Ion Hash serializes each value using Ion binary's field formats, always in
// minimal form: no padding, and optional subfields omitted whenever possible.
// These helpers append to a byte buffer.

///|
/// The minimal big-endian magnitude octets of a non-negative `BigInt`
/// (empty for zero).
fn minimal_uint(magnitude : BigInt) -> Array[Byte] {
  let octets = magnitude.to_octets()
  let view = octets[:]
  let mut start = 0
  while start < view.length() && view[start].to_int() == 0 {
    start += 1
  }
  let result : Array[Byte] = []
  for index in start..<view.length() {
    result.push(view[index])
  }
  result
}

///|
/// Append the minimal big-endian magnitude octets of a non-negative `BigInt`.
fn append_uint(out : Array[Byte], magnitude : BigInt) -> Unit {
  for byte in minimal_uint(magnitude) {
    out.push(byte)
  }
}

///|
/// Append a minimal `VarUInt` (a non-negative value).
fn append_var_uint(out : Array[Byte], value : Int) -> Unit {
  let groups : Array[Int] = []
  let mut remaining = value
  while true {
    groups.push(remaining & 0x7F)
    remaining = remaining >> 7
    if remaining == 0 {
      break
    }
  }
  for index in 0..<groups.length() {
    let group = groups[groups.length() - 1 - index]
    let last = index == groups.length() - 1
    out.push((if last { group | 0x80 } else { group }).to_byte())
  }
}

///|
/// Append a minimal sign-and-magnitude `Int` field (used for decimal
/// coefficients and timestamp fractions). A (positive) zero magnitude is
/// omitted; a negative zero is the single octet `0x80`.
fn append_int(out : Array[Byte], magnitude : BigInt, negative : Bool) -> Unit {
  let bytes = minimal_uint(magnitude)
  if bytes.length() == 0 {
    if negative {
      out.push(0x80)
    }
    return
  }
  let top = bytes[0].to_int()
  if top >= 0x80 {
    out.push((if negative { 0x80 } else { 0x00 }).to_byte())
    for byte in bytes {
      out.push(byte)
    }
  } else {
    out.push((if negative { top | 0x80 } else { top }).to_byte())
    for index in 1..<bytes.length() {
      out.push(bytes[index])
    }
  }
}

///|
/// Append a minimal sign-and-magnitude `VarInt`.
fn append_var_int(out : Array[Byte], magnitude : Int, negative : Bool) -> Unit {
  if magnitude == 0 {
    out.push((if negative { 0xC0 } else { 0x80 }).to_byte())
    return
  }
  let bits = bit_length(magnitude)
  if bits <= 6 {
    out.push((0x80 | (if negative { 0x40 } else { 0 }) | magnitude).to_byte())
    return
  }
  let count = 1 + bits / 7
  out.push(
    (((magnitude >> (7 * (count - 1))) & 0x3F) |
    (if negative { 0x40 } else { 0 })).to_byte(),
  )
  for index in 1..<count {
    let group = (magnitude >> (7 * (count - 1 - index))) & 0x7F
    let last = index == count - 1
    out.push((if last { group | 0x80 } else { group }).to_byte())
  }
}

///|
/// The number of significant bits in a positive `Int`.
fn bit_length(value : Int) -> Int {
  let mut count = 0
  let mut remaining = value
  while remaining > 0 {
    count += 1
    remaining = remaining >> 1
  }
  count
}

///|
/// Append `rep`, replacing each begin/end/escape octet with its escaped form.
fn append_escaped(out : Array[Byte], rep : Array[Byte]) -> Unit {
  for byte in rep {
    let value = byte.to_int()
    if value == 0x0B || value == 0x0E || value == 0x0C {
      out.push(0x0C)
    }
    out.push(byte)
  }
}

///|
/// Append `bytes` to `out`.
fn append_bytes(out : Array[Byte], bytes : Array[Byte]) -> Unit {
  for byte in bytes {
    out.push(byte)
  }
}
