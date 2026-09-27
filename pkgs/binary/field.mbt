// Low-level Ion binary subfields: `UInt`, `Int`, `VarUInt`, and `VarInt`.
//
// These are the octet sequences that follow a type descriptor and its length.
// A reader accepts any well-formed encoding — Ion binary permits a `VarUInt`
// with leading zero groups — while a writer always emits the shortest form.

///|
/// A read cursor over a byte view.
priv struct Cursor {
  bytes : BytesView
  mut pos : Int
  limit : Int
}

///|
/// A cursor over `bytes[start..<limit]`.
fn Cursor::new(bytes : BytesView, start : Int, limit : Int) -> Cursor {
  { bytes, pos: start, limit, }
}

///|
/// Whether every octet up to the limit has been read.
fn Cursor::at_end(self : Cursor) -> Bool {
  self.pos >= self.limit
}

///|
/// The number of octets left before the limit.
fn Cursor::remaining(self : Cursor) -> Int {
  self.limit - self.pos
}

///|
/// Read one octet.
fn Cursor::octet(self : Cursor) -> Int raise @ion.IonError {
  if self.pos >= self.limit {
    raise @ion.IonError::Syntax("unexpected end of Ion binary input")
  }
  let value = self.bytes[self.pos].to_int()
  self.pos += 1
  value
}

///|
/// Read `count` octets.
fn Cursor::take(self : Cursor, count : Int) -> BytesView raise @ion.IonError {
  if count < 0 || self.pos + count > self.limit {
    raise @ion.IonError::Syntax("truncated Ion binary field")
  }
  let view = self.bytes[self.pos:self.pos + count]
  self.pos += count
  view
}

///|
/// Read a `VarUInt`: seven-bit groups, the high bit set on the last octet.
fn Cursor::var_uint(self : Cursor) -> Int raise @ion.IonError {
  let mut value = 0
  let mut done = false
  while !done {
    if value > 0x00FF_FFFF {
      raise @ion.IonError::Syntax("VarUInt field is too large")
    }
    let octet = self.octet()
    value = (value << 7) | (octet & 0x7F)
    if (octet & 0x80) != 0 {
      done = true
    }
  }
  value
}

///|
/// Read a `VarInt`: sign-and-magnitude, the sign in the second-high bit of the
/// first octet and seven-bit groups after it.
fn Cursor::var_int(self : Cursor) -> (Int, Bool) raise @ion.IonError {
  let first = self.octet()
  let negative = (first & 0x40) != 0
  let mut value = first & 0x3F
  let mut more = (first & 0x80) == 0
  while more {
    if value > 0x00FF_FFFF {
      raise @ion.IonError::Syntax("VarInt field is too large")
    }
    let octet = self.octet()
    value = (value << 7) | (octet & 0x7F)
    if (octet & 0x80) != 0 {
      more = false
    }
  }
  (value, negative)
}

///|
/// Read a fixed-width unsigned integer.
fn Cursor::uint(self : Cursor, count : Int) -> BigInt raise @ion.IonError {
  BigInt::from_octets(self.take(count))
}

///|
/// Read a fixed-width sign-and-magnitude integer: the sign is the high bit of
/// the first octet. The magnitude is returned with the sign bit cleared.
fn Cursor::int(
  self : Cursor,
  count : Int,
) -> (BigInt, Bool) raise @ion.IonError {
  if count == 0 {
    return (BigInt::from_int(0), false)
  }
  let view = self.take(count)
  let first = view[0].to_int()
  let negative = (first & 0x80) != 0
  let magnitude : Array[Byte] = [(first & 0x7F).to_byte()]
  for index in 1..<count {
    magnitude.push(view[index])
  }
  (BigInt::from_octets(Bytes::from_array(magnitude)), negative)
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
/// The number of octets a `VarUInt` needs.
fn var_uint_length(value : Int) -> Int {
  let mut length = 1
  let mut remaining = value >> 7
  while remaining > 0 {
    length += 1
    remaining = remaining >> 7
  }
  length
}

///|
/// The number of octets a `VarInt` needs to carry `magnitude`.
fn var_int_length(magnitude : Int) -> Int {
  let bits = bit_length(magnitude)
  if bits <= 6 {
    1
  } else {
    1 + bits / 7
  }
}

///|
/// The minimal big-endian octets of a non-negative magnitude (empty for zero).
fn magnitude_octets(magnitude : BigInt) -> Array[Byte] {
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
/// Append the minimal big-endian octets of a non-negative magnitude.
fn push_uint(out : Array[Byte], magnitude : BigInt) -> Unit {
  for octet in magnitude_octets(magnitude) {
    out.push(octet)
  }
}

///|
/// Append a minimal `VarUInt`.
fn push_var_uint(out : Array[Byte], value : Int) -> Unit {
  let length = var_uint_length(value)
  for index in 0..<length {
    let shift = 7 * (length - 1 - index)
    let group = (value >> shift) & 0x7F
    out.push((if index == length - 1 { group | 0x80 } else { group }).to_byte())
  }
}

///|
/// Append a minimal `VarInt` (a non-negative magnitude plus a sign).
fn push_var_int(out : Array[Byte], magnitude : Int, negative : Bool) -> Unit {
  let sign = if negative { 0x40 } else { 0 }
  if magnitude <= 0x3F {
    out.push((0x80 | sign | magnitude).to_byte())
    return
  }
  let length = var_int_length(magnitude)
  let head = (magnitude >> (7 * (length - 1))) & 0x3F
  out.push((sign | head).to_byte())
  for index in 1..<length {
    let shift = 7 * (length - 1 - index)
    let group = (magnitude >> shift) & 0x7F
    out.push((if index == length - 1 { group | 0x80 } else { group }).to_byte())
  }
}

///|
/// Append a minimal fixed-width sign-and-magnitude `Int`: the magnitude's
/// octets with the sign in the high bit of the first octet. A zero magnitude is
/// omitted when positive, and is the single octet `0x80` when negative.
fn push_int(out : Array[Byte], magnitude : BigInt, negative : Bool) -> Unit {
  let octets = magnitude_octets(magnitude)
  if octets.length() == 0 {
    if negative {
      out.push(0x80)
    }
    return
  }
  let top = octets[0].to_int()
  if top >= 0x80 {
    out.push((if negative { 0x80 } else { 0x00 }).to_byte())
    for octet in octets {
      out.push(octet)
    }
  } else {
    out.push((if negative { top | 0x80 } else { top }).to_byte())
    for index in 1..<octets.length() {
      out.push(octets[index])
    }
  }
}

///|
/// Append `count` octets of a `VarUInt` length that is at least `14`, or the
/// nibble itself when it fits. Ion binary uses the nibble `14` to signal a
/// `VarUInt` length, so a length below that stays in the descriptor.
fn push_length(out : Array[Byte], length : Int) -> Int {
  if length < 14 {
    length
  } else {
    push_var_uint(out, length)
    14
  }
}

///|
/// Skip a NOP padding value at the cursor, when one is there: a type code of
/// zero with a length nibble other than `15` occupies the descriptor, an
/// optional `VarUInt` length, and that many padding octets.
fn Cursor::skip_padding(self : Cursor) -> Bool raise @ion.IonError {
  if self.at_end() {
    return false
  }
  let descriptor = self.bytes[self.pos].to_int()
  if descriptor >> 4 != 0 || (descriptor & 0x0F) == 0x0F {
    return false
  }
  let nibble = descriptor & 0x0F
  self.pos += 1
  let length = if nibble == 0x0E { self.var_uint() } else { nibble }
  ignore(self.take(length))
  true
}

///|
/// A cursor over the same bytes, positioned where this one is and ending at
/// `end`: how a container's contents are decoded, so the enclosing cursor's
/// limit is untouched.
fn Cursor::scoped(self : Cursor, end : Int) -> Cursor {
  { bytes: self.bytes, pos: self.pos, limit: end, }
}

///|
/// Move the cursor to `pos`.
fn Cursor::seek(self : Cursor, pos : Int) -> Unit {
  self.pos = pos
}
