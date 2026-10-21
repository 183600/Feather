///|
/// The request body as text.
///
/// The bytes are the ones the request carried, the same bytes
/// `Context::body_bytes` returns, so a body that is not valid UTF-8 is not
/// mangled by the decoding.
///
/// `charset` selects the character set: `utf-8` (the default) decodes the body
/// as UTF-8 and replaces invalid sequences, `iso-8859-1` (also spelled
/// `latin1`) maps every byte to the code point of the same value, and
/// `us-ascii` (also spelled `ascii`) replaces the bytes above `0x7f`. Any
/// other charset raises `415 Unsupported Media Type`.
///
/// `limit` caps the number of bytes that are decoded; a larger body raises
/// `413 Payload Too Large`. A negative limit, the default, decodes the whole
/// body, which the server already caps with `App::max_body_size`.
pub fn Context::body_text(
  self : Context,
  limit~ : Int32 = -1,
  charset~ : String = "utf-8",
) -> String raise HttpError {
  let bytes = self.body_bytes()
  if limit >= 0 && bytes.length() > limit {
    raise HttpError(413, "request body too large")
  }
  decode_body_charset(bytes, charset)
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
    Some(charset) =>
      if trim_ascii_space(charset.view()).is_empty() {
        "utf-8"
      } else {
        charset
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
