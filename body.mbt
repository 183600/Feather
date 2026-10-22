///|
/// The request body as text.
///
/// The bytes are the ones the request carried, the same bytes
/// `Context::body_bytes` returns, so a body that is not valid UTF-8 is not
/// mangled by the decoding.
///
/// When `charset` is omitted, the character set declared by the request's
/// `Content-Type` is used, falling back to UTF-8 when the header names none;
/// pass it explicitly to override the header. `utf-8` (the default) decodes the
/// body as UTF-8 and replaces invalid sequences, `iso-8859-1` (also spelled
/// `latin1`) maps every byte to the code point of the same value,
/// `us-ascii` (also spelled `ascii`) replaces the bytes above `0x7f`, and
/// `utf-16` / `utf-16le` / `utf-16be` decode UTF-16 with the declared byte
/// order (`utf-16` follows a leading byte-order mark and defaults to
/// big-endian without one). Unpaired surrogates and a trailing odd byte are
/// replaced with U+FFFD. Any other charset raises `415 Unsupported Media
/// Type`.
///
/// `limit` caps the number of bytes that are decoded; a larger body raises
/// `413 Payload Too Large`. A negative limit, the default, decodes the whole
/// body, which the server already caps with `App::max_body_size`.
pub fn Context::body_text(
  self : Context,
  limit~ : Int32 = -1,
  charset? : String,
) -> String raise HttpError {
  let bytes = self.body_bytes()
  if limit >= 0 && bytes.length() > limit {
    raise HttpError(413, "request body too large")
  }
  let name = match charset {
    Some(charset) => charset
    None => self.body_charset()
  }
  decode_body_charset(bytes, name)
}

///|
/// The character set the `Content-Type` header declares, or `"utf-8"` when the
/// header names none.
///
/// Text bodies are usually UTF-8, but a form or a document may declare another
/// character set; `Context::body_charset` reports what the request asked for.
pub fn Context::body_charset(self : Context) -> String {
  let content_type = self.header("Content-Type")
  if content_type.is_empty() {
    return "utf-8"
  }
  match header_parameter(content_type.view(), "charset") {
    Some(charset) => {
      let name = trim_ascii_space(charset.view())
      if name.is_empty() {
        "utf-8"
      } else {
        name.to_owned()
      }
    }
    None => "utf-8"
  }
}

///|
/// Decode `bytes` with the named character set.
fn decode_body_charset(
  bytes : Bytes,
  charset : String,
) -> String raise HttpError {
  let name = trim_ascii_space(charset.view())
  if name.is_empty() ||
    name.equal_ignore_ascii_case("utf-8".view()) ||
    name.equal_ignore_ascii_case("utf8".view()) {
    return @utf8.decode_lossy(bytes)
  }
  if name.equal_ignore_ascii_case("iso-8859-1".view()) ||
    name.equal_ignore_ascii_case("iso8859-1".view()) ||
    name.equal_ignore_ascii_case("latin1".view()) {
    return decode_latin1(bytes)
  }
  if name.equal_ignore_ascii_case("us-ascii".view()) ||
    name.equal_ignore_ascii_case("ascii".view()) {
    return decode_ascii(bytes)
  }
  if name.equal_ignore_ascii_case("utf-16".view()) ||
    name.equal_ignore_ascii_case("utf16".view()) {
    return decode_utf16_auto(bytes)
  }
  if name.equal_ignore_ascii_case("utf-16le".view()) ||
    name.equal_ignore_ascii_case("utf16le".view()) {
    return decode_utf16(bytes, little_endian=true)
  }
  if name.equal_ignore_ascii_case("utf-16be".view()) ||
    name.equal_ignore_ascii_case("utf16be".view()) {
    return decode_utf16(bytes, little_endian=false)
  }
  raise HttpError(415, "unsupported charset: \{charset}")
}

///|
/// Decode `bytes` as ISO-8859-1, where every byte is the code point of the
/// same value.
fn decode_latin1(bytes : Bytes) -> String {
  let builder = StringBuilder(size_hint=bytes.length())
  for byte in bytes.iter() {
    builder.write_char(byte.to_int().unsafe_to_char())
  }
  builder.to_string()
}

///|
/// The Unicode replacement character, used for bytes a character set cannot
/// represent.
const REPLACEMENT_CODE_POINT : Int = 65533

///|
/// Read one UTF-16 code unit from two adjacent bytes.
fn utf16_unit(
  bytes : Bytes,
  offset : Int32,
  little_endian : Bool,
) -> Int32 {
  let first = bytes[offset].to_int()
  let second = bytes[offset + 1].to_int()
  if little_endian {
    first | (second << 8)
  } else {
    (first << 8) | second
  }
}

///|
/// Append one Unicode scalar value as UTF-16, splitting supplementary code
/// points into a surrogate pair. The input is never a surrogate code unit.
fn write_utf16_scalar(builder : StringBuilder, code : Int32) -> Unit {
  if code >= 0x10000 {
    let scalar = code - 0x10000
    builder.write_char((0xD800 + (scalar >> 10)).unsafe_to_char())
    builder.write_char((0xDC00 + (scalar & 0x3FF)).unsafe_to_char())
  } else {
    builder.write_char(code.unsafe_to_char())
  }
}

///|
/// Decode UTF-16 bytes with the given byte order. A matching byte-order mark
/// at the start is consumed; an unpaired surrogate, an unexpected trailing
/// byte and a lone low surrogate become U+FFFD.
fn decode_utf16(bytes : Bytes, little_endian~ : Bool) -> String {
  let length = bytes.length()
  let builder = StringBuilder(size_hint=length / 2)
  let mut i = 0
  if length >= 2 {
    let first = bytes[0].to_int()
    let second = bytes[1].to_int()
    let has_matching_bom = if little_endian {
      first == 0xFF && second == 0xFE
    } else {
      first == 0xFE && second == 0xFF
    }
    if has_matching_bom {
      i = 2
    }
  }
  while i + 1 < length {
    let unit = utf16_unit(bytes, i, little_endian)
    if unit >= 0xD800 && unit <= 0xDBFF {
      if i + 3 < length {
        let low = utf16_unit(bytes, i + 2, little_endian)
        if low >= 0xDC00 && low <= 0xDFFF {
          let scalar = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
          write_utf16_scalar(builder, scalar)
          i = i + 4
          continue
        }
      }
      builder.write_char(REPLACEMENT_CODE_POINT.unsafe_to_char())
      i = i + 2
    } else if unit >= 0xDC00 && unit <= 0xDFFF {
      builder.write_char(REPLACEMENT_CODE_POINT.unsafe_to_char())
      i = i + 2
    } else {
      builder.write_char(unit.unsafe_to_char())
      i = i + 2
    }
  }
  if i < length {
    builder.write_char(REPLACEMENT_CODE_POINT.unsafe_to_char())
  }
  builder.to_string()
}

///|
/// Decode UTF-16 without an explicit byte order. A leading byte-order mark
/// selects little- or big-endian; RFC 2781 makes big-endian the default when
/// the mark is absent.
fn decode_utf16_auto(bytes : Bytes) -> String {
  if bytes.length() >= 2 &&
    bytes[0].to_int() == 0xFF &&
    bytes[1].to_int() == 0xFE {
    decode_utf16(bytes, little_endian=true)
  } else {
    decode_utf16(bytes, little_endian=false)
  }
}

///|
/// Decode `bytes` as US-ASCII, replacing the bytes above `0x7f` with the
/// replacement character.
fn decode_ascii(bytes : Bytes) -> String {
  let builder = StringBuilder(size_hint=bytes.length())
  for byte in bytes.iter() {
    let value = byte.to_int()
    if value < 0x80 {
      builder.write_char(value.unsafe_to_char())
    } else {
      builder.write_char(REPLACEMENT_CODE_POINT.unsafe_to_char())
    }
  }
  builder.to_string()
}
