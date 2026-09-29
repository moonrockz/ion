// Black-box tests for detecting and decoding the character encoding of Ion
// text.

///|
/// UTF-32 octets of `text`, big- or little-endian.
fn utf32(text : String, big~ : Bool) -> Bytes {
  let octets : Array[Byte] = []
  for c in text {
    let code = c.to_int()
    let units = [
      code >> 24,
      (code >> 16) & 0xFF,
      (code >> 8) & 0xFF,
      code & 0xFF,
    ]
    if !big {
      units.rev_in_place()
    }
    for unit in units {
      octets.push(unit.to_byte())
    }
  }
  Bytes::from_array(octets)
}

///|
/// UTF-16 octets of `text`, big- or little-endian.
fn utf16(text : String, big~ : Bool) -> Bytes {
  @utf16.encode(text, endianness=if big { Big } else { Little })
}

///|
test "the encoding follows the zero octets of the first character" {
  let text = "{a: \"é 😀\"}"
  debug_inspect(@text.detect_encoding(@utf8.encode(text)), content="(UTF8, 0)")
  debug_inspect(
    @text.detect_encoding(utf16(text, big=true)),
    content="(UTF16BE, 0)",
  )
  debug_inspect(
    @text.detect_encoding(utf16(text, big=false)),
    content="(UTF16LE, 0)",
  )
  debug_inspect(
    @text.detect_encoding(utf32(text, big=true)),
    content="(UTF32BE, 0)",
  )
  debug_inspect(
    @text.detect_encoding(utf32(text, big=false)),
    content="(UTF32LE, 0)",
  )
}

///|
test "a byte order mark decides the encoding and is skipped" {
  debug_inspect(@text.detect_encoding(b"\xEF\xBB\xBF1"), content="(UTF8, 3)")
  debug_inspect(
    @text.detect_encoding(b"\xFE\xFF\x00\x31"),
    content="(UTF16BE, 2)",
  )
  debug_inspect(
    @text.detect_encoding(b"\xFF\xFE\x31\x00"),
    content="(UTF16LE, 2)",
  )
  debug_inspect(
    @text.detect_encoding(b"\x00\x00\xFE\xFF\x00\x00\x00\x31"),
    content="(UTF32BE, 4)",
  )
  debug_inspect(
    @text.detect_encoding(b"\xFF\xFE\x00\x00\x31\x00\x00\x00"),
    content="(UTF32LE, 4)",
  )
}

///|
test "short and empty input" {
  debug_inspect(@text.detect_encoding(b""), content="(UTF8, 0)")
  debug_inspect(@text.detect_encoding(b"1"), content="(UTF8, 0)")
  debug_inspect(@text.detect_encoding(b"\x00\x31"), content="(UTF16BE, 0)")
  debug_inspect(@text.detect_encoding(b"\x31\x00"), content="(UTF16LE, 0)")
}

///|
test "decode_ion_text decodes every encoding to the same text" {
  let text = "{a: \"é 😀\", b: [1, 2]}\n"
  for
    bytes in [
      @utf8.encode(text),
      @utf8.encode(text, bom=true),
      utf16(text, big=true),
      utf16(text, big=false),
      @utf16.encode(text, bom=true, endianness=Big),
      utf32(text, big=true),
      utf32(text, big=false),
    ] {
    assert_eq(@text.decode_ion_text(bytes), text)
  }
}

///|
test "malformed octets in any encoding are an error" {
  for
    bytes in [
      b"1 \xFF",
      // An odd number of UTF-16 octets.
       b"\x00\x31\x00",
      // An unpaired UTF-16 high surrogate.
       b"\x00\x31\xD8\x3D",
      // UTF-32 whose length is not a multiple of four.
       b"\x00\x00\x00\x31\x00",
      // A UTF-32 code point above U+10FFFF.
       b"\x00\x00\x00\x31\x00\x11\x00\x00",
    ] {
    let failed = try @text.decode_ion_text(bytes) catch {
      _ => true
    } noraise {
      _ => false
    }
    assert_true(failed)
  }
}
