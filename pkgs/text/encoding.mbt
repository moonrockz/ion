// The character encoding of Ion text in octets.
//
// Ion text is usually UTF-8, but readers also accept UTF-16 and UTF-32, as
// ion-tests' good/utf16.ion and good/utf32.ion require. A byte order mark
// decides the encoding when there is one. Otherwise the zero octets of the
// first character do, as RFC 4627 does for JSON: Ion text always starts with
// an ASCII character (whitespace, a comment, a quote, or the start of a
// value), which is one non-zero octet padded with zeros in UTF-16 and UTF-32.

///|
/// A character encoding of Ion text.
pub(all) enum TextEncoding {
  UTF8
  UTF16BE
  UTF16LE
  UTF32BE
  UTF32LE
} derive(Eq, Debug)

///|
/// The encoding of Ion text that starts with `bytes`, and the length of its
/// byte order mark (0 when there is none). Four octets decide; fewer are
/// enough only for UTF-8 and UTF-16.
pub fn detect_encoding(bytes : BytesView) -> (TextEncoding, Int) {
  let n = bytes.length()
  let at = (index : Int) => if index < n { bytes[index].to_int() } else { -1 }
  let (b0, b1, b2, b3) = (at(0), at(1), at(2), at(3))
  // The UTF-32LE mark starts like the UTF-16LE one, so it is tested first.
  if b0 == 0x00 && b1 == 0x00 && b2 == 0xFE && b3 == 0xFF {
    (UTF32BE, 4)
  } else if b0 == 0xFF && b1 == 0xFE && b2 == 0x00 && b3 == 0x00 {
    (UTF32LE, 4)
  } else if b0 == 0xEF && b1 == 0xBB && b2 == 0xBF {
    (UTF8, 3)
  } else if b0 == 0xFE && b1 == 0xFF {
    (UTF16BE, 2)
  } else if b0 == 0xFF && b1 == 0xFE {
    (UTF16LE, 2)
  } else if n >= 4 && b0 == 0 && b1 == 0 && b2 == 0 && b3 != 0 {
    (UTF32BE, 0)
  } else if n >= 4 && b0 != 0 && b1 == 0 && b2 == 0 && b3 == 0 {
    (UTF32LE, 0)
  } else if n >= 2 && b0 == 0 && b1 != 0 {
    (UTF16BE, 0)
  } else if n >= 2 && b0 != 0 && b1 == 0 {
    (UTF16LE, 0)
  } else {
    (UTF8, 0)
  }
}

///|
/// Decode Ion text in octets, detecting the encoding as `detect_encoding`
/// does and skipping a byte order mark.
pub fn decode_ion_text(bytes : BytesView) -> String raise @ion.IonError {
  let (encoding, mark) = detect_encoding(bytes)
  decode_text(encoding, bytes[mark:])
}

///|
/// Decode whole characters of `encoding`. Octets that are malformed, or that
/// end inside a character, raise `IonError::Syntax`.
pub fn decode_text(
  encoding : TextEncoding,
  bytes : BytesView,
) -> String raise @ion.IonError {
  match encoding {
    UTF8 =>
      @utf8.decode(bytes) catch {
        _ => raise @ion.IonError::Syntax("the Ion text is not valid UTF-8")
      }
    UTF16BE | UTF16LE => {
      if bytes.length() % 2 != 0 ||
        complete_length(encoding, bytes) != bytes.length() {
        raise @ion.IonError::Syntax(
          "the Ion text ends inside a UTF-16 character",
        )
      }
      let endianness : @utf16.Endian = if encoding is UTF16BE {
        Big
      } else {
        Little
      }
      @utf16.decode(bytes, endianness~) catch {
        _ => raise @ion.IonError::Syntax("the Ion text is not valid UTF-16")
      }
    }
    UTF32BE | UTF32LE => {
      if bytes.length() % 4 != 0 {
        raise @ion.IonError::Syntax(
          "the Ion text ends inside a UTF-32 character",
        )
      }
      let text = StringBuilder()
      for index = 0; index < bytes.length(); index = index + 4 {
        let octet = (offset : Int) => bytes[index + offset].to_int()
        let code = if encoding is UTF32BE {
          (octet(0) << 24) | (octet(1) << 16) | (octet(2) << 8) | octet(3)
        } else {
          (octet(3) << 24) | (octet(2) << 16) | (octet(1) << 8) | octet(0)
        }
        if code < 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF) {
          raise @ion.IonError::Syntax("the Ion text is not valid UTF-32")
        }
        text.write_char(code.unsafe_to_char())
      }
      text.to_string()
    }
  }
}

///|
/// The length of the longest prefix of `bytes` that does not end inside a
/// character of `encoding`, for a reader that decodes text as it arrives.
/// Only an incomplete character at the end is held back; any other
/// malformation is left for `decode_text` to report.
pub fn complete_length(encoding : TextEncoding, bytes : BytesView) -> Int {
  let n = bytes.length()
  match encoding {
    UTF8 => {
      for back in 1..<=3 {
        if back > n {
          break
        }
        let octet = bytes[n - back].to_int()
        if octet < 0x80 {
          return n
        }
        if octet >= 0xC0 {
          let width = if octet >= 0xF0 {
            4
          } else if octet >= 0xE0 {
            3
          } else {
            2
          }
          return if width > back { n - back } else { n }
        }
      }
      n
    }
    UTF16BE | UTF16LE => {
      let even = n - n % 2
      if even < 2 {
        return even
      }
      // A high surrogate needs the low surrogate after it.
      let last = if encoding is UTF16BE {
        (bytes[even - 2].to_int() << 8) | bytes[even - 1].to_int()
      } else {
        (bytes[even - 1].to_int() << 8) | bytes[even - 2].to_int()
      }
      if last >= 0xD800 && last <= 0xDBFF {
        even - 2
      } else {
        even
      }
    }
    UTF32BE | UTF32LE => n - n % 4
  }
}

///|
pub extend TextEncoding with Eq::{equal, not_equal}

///|
pub extend TextEncoding with @debug.Debug::{to_repr}
