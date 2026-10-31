///|
/// The `name` and `filename` parameters of a `Content-Disposition` value,
/// extracted in one pass. `filename` prefers a well-formed RFC 8187
/// `filename*`, falling back to the plain parameter.
priv struct DispositionNames {
  name : String
  filename : String
}

///|
fn unescape_quoted_parameter(raw : StringView) -> String {
  let length = raw.length()
  let builder = StringBuilder(size_hint=length)
  let mut i = 0
  while i < length {
    let unit = raw.unsafe_get(i)
    if unit == ('\\' : UInt16) && i + 1 < length {
      builder.write_char(raw.unsafe_get(i + 1).to_int().unsafe_to_char())
      i = i + 2
    } else {
      builder.write_char(unit.to_int().unsafe_to_char())
      i = i + 1
    }
  }
  builder.to_string()
}

///|
fn disposition_names(value : StringView) -> DispositionNames {
  let length = value.length()
  let mut pos = 0
  while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
    pos = pos + 1
  }
  let mut name : String? = None
  let mut filename : String? = None
  let mut filename_ext : String? = None
  while pos < length {
    pos = pos + 1
    while pos < length &&
          (
            value.unsafe_get(pos) == (' ' : UInt16) ||
            value.unsafe_get(pos) == ('\t' : UInt16)
          ) {
      pos = pos + 1
    }
    let name_start = pos
    while pos < length &&
          value.unsafe_get(pos) != ('=' : UInt16) &&
          value.unsafe_get(pos) != (';' : UInt16) {
      pos = pos + 1
    }
    let attribute = trim_ascii_space(value[name_start:pos])
    if pos < length && value.unsafe_get(pos) == ('=' : UInt16) {
      pos = pos + 1
      while pos < length &&
            (
              value.unsafe_get(pos) == (' ' : UInt16) ||
              value.unsafe_get(pos) == ('\t' : UInt16)
            ) {
        pos = pos + 1
      }
      let parsed : String? = if pos < length &&
        value.unsafe_get(pos) == ('"' : UInt16) {
        let quoted_start = pos + 1
        let mut end = quoted_start
        while end < length {
          let unit = value.unsafe_get(end)
          if unit == ('\\' : UInt16) && end + 1 < length {
            end = end + 2
          } else if unit == ('"' : UInt16) {
            break
          } else {
            end = end + 1
          }
        }
        let result = unescape_quoted_parameter(value[quoted_start:end])
        pos = if end < length { end + 1 } else { end }
        Some(result)
      } else {
        let value_start = pos
        while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
          pos = pos + 1
        }
        Some(trim_ascii_space(value[value_start:pos]).to_owned())
      }
      if attribute.equal_ignore_ascii_case("name".view()) {
        if name is None {
          name = parsed
        }
      } else if attribute.equal_ignore_ascii_case("filename".view()) {
        if filename is None {
          filename = parsed
        }
      } else if attribute.equal_ignore_ascii_case("filename*".view()) {
        if filename_ext is None {
          filename_ext = parsed
        }
      }
    }
    while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
      pos = pos + 1
    }
  }
  let plain_filename = match filename {
    Some(value) => value
    None => ""
  }
  let resolved_filename = match filename_ext {
    Some(raw) => {
      let raw_view = raw.view()
      match raw_view.find("'") {
        Some(first) =>
          if raw_view[:first].equal_ignore_ascii_case("utf-8".view()) {
            let rest = raw_view[first + 1:]
            match rest.find("'") {
              Some(second) => decode_url_path(rest[second + 1:])
              None => plain_filename
            }
          } else {
            plain_filename
          }
        None => plain_filename
      }
    }
    None => plain_filename
  }
  {
    name: match name {
      Some(value) => value
      None => ""
    },
    filename: resolved_filename,
  }
}

///|
/// Whether the request body is `multipart/form-data`.
pub fn Context::is_multipart(self : Context) -> Bool {
  self.content_type() == "multipart/form-data"
}

///|
pub(all) struct MultipartPart {
  name : String
  filename : String
  content_type : String
  headers : Map[String, String]
  /// The part's payload as text, decoded with the charset declared by its
  /// `Content-Type` and lossily as UTF-8 when no charset is declared.
  data : String
  /// The part's payload as bytes, exactly as it arrived.
  data_bytes : Bytes
}

///|
/// Decode bytes without losing any information.
///
/// Well-formed UTF-8 becomes the text it encodes. A byte that is not part of a
/// valid sequence is mapped to the private code unit `0xDC00 + byte`, the same
/// escaping `WTF-8` uses, which `encode_utf8_lossless` turns back into that
/// byte. Unlike the standard decoders the result may therefore hold lone
/// surrogates, so it must only be re-encoded with the matching encoder.
fn decode_utf8_lossless(bytes : Bytes) -> String {
  let result = StringBuilder()
  let length = bytes.length()
  let mut i = 0
  while i < length {
    let b0 = bytes[i].to_int()
    if b0 < 0x80 {
      result.write_char(b0.unsafe_to_char())
      i = i + 1
    } else if b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 < length {
        let b1 = bytes[i + 1].to_int()
        if b1 >= 0x80 && b1 <= 0xBF {
          let code = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
          result.write_char(code.unsafe_to_char())
          i = i + 2
        } else {
          result.write_char((0xDC00 + b0).unsafe_to_char())
          i = i + 1
        }
      } else {
        result.write_char((0xDC00 + b0).unsafe_to_char())
        i = i + 1
      }
    } else if b0 >= 0xE0 &&
      b0 <= 0xEF &&
      i + 2 < length &&
      !(b0 == 0xE0 && bytes[i + 1].to_int() < 0xA0) &&
      !(b0 == 0xED && bytes[i + 1].to_int() > 0x9F) &&
      bytes[i + 1].to_int() >= 0x80 &&
      bytes[i + 1].to_int() <= 0xBF &&
      bytes[i + 2].to_int() >= 0x80 &&
      bytes[i + 2].to_int() <= 0xBF {
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      let code = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      result.write_char(code.unsafe_to_char())
      i = i + 3
    } else if b0 >= 0xF0 &&
      b0 <= 0xF4 &&
      i + 3 < length &&
      !(b0 == 0xF0 && bytes[i + 1].to_int() < 0x90) &&
      !(b0 == 0xF4 && bytes[i + 1].to_int() > 0x8F) &&
      bytes[i + 1].to_int() >= 0x80 &&
      bytes[i + 1].to_int() <= 0xBF &&
      bytes[i + 2].to_int() >= 0x80 &&
      bytes[i + 2].to_int() <= 0xBF &&
      bytes[i + 3].to_int() >= 0x80 &&
      bytes[i + 3].to_int() <= 0xBF {
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      let b3 = bytes[i + 3].to_int()
      let code = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      let code = code - 0x10000
      result.write_char(((code >> 10) + 0xD800).unsafe_to_char())
      result.write_char(((code & 0x3FF) + 0xDC00).unsafe_to_char())
      i = i + 4
    } else {
      result.write_char((0xDC00 + b0).unsafe_to_char())
      i = i + 1
    }
  }
  result.to_string()
}

///|
/// Recover a part's exact bytes and its well-formed text.
///
/// `raw_data` is the lossless slice from the raw body (supplementary code
/// units intact, invalid bytes escaped), so the bytes come back byte for byte.
/// `data` is decoded with the charset the part's `Content-Type` declares,
/// falling back to lossy UTF-8 when the part names none. A part parsed without
/// a raw body falls back to re-encoding its text.
fn resolve_part_bytes(
  data : String,
  raw_data : String?,
  content_type~ : String = "",
) -> (Bytes, String) {
  let bytes = match raw_data {
    Some(raw) => encode_utf8_lossless(raw)
    None => encode_utf8_lossy(data.view())
  }
  (bytes, decode_multipart_part_text(bytes, content_type))
}

///|
/// Decode a part's payload as text using its declared charset. Multipart
/// parsers cannot return a per-part error, so an unsupported charset falls back
/// to the lossy UTF-8 view instead of failing the entire form.
fn decode_multipart_part_text(bytes : Bytes, content_type : String) -> String {
  match header_parameter(content_type.view(), "charset") {
    Some(charset) =>
      decode_body_charset(bytes, charset) catch {
        _ => @utf8.decode_lossy(bytes)
      }
    None => @utf8.decode_lossy(bytes)
  }
}

///|
/// A high surrogate followed by a low surrogate is a supplementary character;
/// any other code unit in `0xDC00..=0xDCFF` stands for the single byte
/// `code - 0xDC00`. Valid text that contains no such escape encodes to its
/// normal UTF-8 bytes.
fn encode_utf8_lossless(text : String) -> Bytes {
  let out : Array[Byte] = Array(capacity=text.length())
  let length = text.length()
  let mut i = 0
  while i < length {
    let code = text.unsafe_get(i).to_int()
    if code >= 0xD800 &&
      code <= 0xDBFF &&
      i + 1 < length &&
      text.unsafe_get(i + 1).to_int() >= 0xDC00 &&
      text.unsafe_get(i + 1).to_int() <= 0xDFFF {
      let low = text.unsafe_get(i + 1).to_int()
      let full = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
      out.push(((full >> 18) | 0xF0).to_byte())
      out.push((((full >> 12) & 0x3F) | 0x80).to_byte())
      out.push((((full >> 6) & 0x3F) | 0x80).to_byte())
      out.push(((full & 0x3F) | 0x80).to_byte())
      i = i + 2
    } else if code >= 0xDC00 && code <= 0xDCFF {
      out.push((code - 0xDC00).to_byte())
      i = i + 1
    } else if code < 0x80 {
      out.push(code.to_byte())
      i = i + 1
    } else if code < 0x800 {
      out.push(((code >> 6) | 0xC0).to_byte())
      out.push(((code & 0x3F) | 0x80).to_byte())
      i = i + 1
    } else {
      out.push(((code >> 12) | 0xE0).to_byte())
      out.push((((code >> 6) & 0x3F) | 0x80).to_byte())
      out.push(((code & 0x3F) | 0x80).to_byte())
      i = i + 1
    }
  }
  Bytes::from_array(out)
}

///|
pub impl Eq for MultipartPart with fn equal(x, y) {
  x.name == y.name &&
  x.filename == y.filename &&
  x.content_type == y.content_type &&
  x.data == y.data
}

///|
pub impl Show for MultipartPart with fn to_string(self) {
  "@feather.MultipartPart(\{self.name}, \{self.filename}, \{self.content_type}, \{self.data})"
}

///|
pub impl Debug for MultipartPart with fn to_repr(self) {
  Repr::record({
    "name": Repr::string(self.name),
    "filename": Repr::string(self.filename),
    "content_type": Repr::string(self.content_type),
    "data": Repr::string(self.data),
  })
}

///|
pub extend MultipartPart with Eq::{not_equal, equal}

///|
pub extend MultipartPart with Show::{output, to_string}

///|
pub extend MultipartPart with Debug::{to_repr}

///|
/// First index at or after `start` where a part header block ends with a blank
/// line, using either CRLF or bare LF line endings: the earliest position of
/// `\r\n\r\n` or `\n\n`.
fn find_header_end(view : StringView, start : Int32) -> Int32? {
  let length = view.length()
  let mut i = start
  while i + 1 < length {
    if view.unsafe_get(i) == ('\n' : UInt16) {
      if view.unsafe_get(i + 1) == ('\n' : UInt16) {
        return Some(i)
      }
      if i > start &&
        view.unsafe_get(i - 1) == ('\r' : UInt16) &&
        view.unsafe_get(i + 1) == ('\r' : UInt16) &&
        i + 2 < length &&
        view.unsafe_get(i + 2) == ('\n' : UInt16) {
        return Some(i - 1)
      }
    }
    i = i + 1
  }
  None
}

///|
fn delimiter_is_terminated(view : StringView, after : Int32) -> Bool {
  let length = view.length()
  if after < length && view.unsafe_get(after) == ('-' : UInt16) {
    if after + 1 >= length || view.unsafe_get(after + 1) != ('-' : UInt16) {
      return false
    }
    let mut tail = after + 2
    while tail < length &&
          (
            view.unsafe_get(tail) == (' ' : UInt16) ||
            view.unsafe_get(tail) == ('\t' : UInt16)
          ) {
      tail = tail + 1
    }
    if tail >= length {
      return true
    }
    let tail_code = view.unsafe_get(tail)
    if tail_code == ('\r' : UInt16) {
      return tail + 1 < length &&
        view.unsafe_get(tail + 1) == ('\n' : UInt16)
    }
    return tail_code == ('\n' : UInt16)
  }
  let mut index = after
  while index < length &&
        (
          view.unsafe_get(index) == (' ' : UInt16) ||
          view.unsafe_get(index) == ('\t' : UInt16)
        ) {
    index = index + 1
  }
  if index >= length {
    // A bare delimiter at end of input is neither a part separator followed
    // by headers nor a close-delimiter (`--boundary--`), so it cannot
    // terminate a multipart body.
    return false
  }
  let code = view.unsafe_get(index)
  if code == ('\r' : UInt16) {
    // A delimiter line ends with CRLF, not with a bare CR. Data can legitimately
    // contain CR bytes, so treating a lone CR as a line break would split a
    // payload whose text merely starts with the boundary spelling.
    return index + 1 < length && view.unsafe_get(index + 1) == ('\n' : UInt16)
  }
  code == ('\n' : UInt16)
}

///|
/// Prefix-function table for the delimiter scans below: entry `i` is the length
/// of the longest proper prefix of `needle[:i+1]` that is also a suffix of it.
fn delimiter_match_table(needle : StringView) -> Array[Int32] {
  let length = needle.length()
  let table : Array[Int32] = Array::make(length, 0)
  let mut matched = 0
  let mut index = 1
  while index < length {
    while matched > 0 && needle.unsafe_get(index) != needle.unsafe_get(matched) {
      matched = table[matched - 1]
    }
    if needle.unsafe_get(index) == needle.unsafe_get(matched) {
      matched = matched + 1
    }
    table[index] = matched
    index = index + 1
  }
  table
}

///|
/// First index at or after `start` where `needle` starts a line and is
/// terminated by whitespace, a line break or `--`. The precomputed
/// prefix-function `table` guides a single forward scan.
fn find_terminated_delimiter(
  view : StringView,
  needle : StringView,
  table : Array[Int32],
  start : Int32,
) -> Int32? {
  let needle_length = needle.length()
  if needle_length == 0 {
    return Some(start)
  }
  let length = view.length()
  let mut matched = 0
  let mut index = start
  while index < length {
    let code = view.unsafe_get(index)
    while matched > 0 && code != needle.unsafe_get(matched) {
      matched = table[matched - 1]
    }
    if code == needle.unsafe_get(matched) {
      matched = matched + 1
    }
    if matched == needle_length {
      let match_start = index + 1 - needle_length
      if (match_start == 0 ||
          view.unsafe_get(match_start - 1) == ('\n' : UInt16)) &&
        delimiter_is_terminated(view, index + 1) {
        return Some(match_start)
      }
      matched = table[matched - 1]
    }
    index = index + 1
  }
  None
}

///|
/// Find the earliest position where either the CRLF-prefixed or the LF-prefixed
/// part delimiter starts and is properly terminated. Both needles are matched
/// in a single forward pass; because the CRLF prefix is one byte longer, a CRLF
/// match ending no later than an LF match also starts no later than it, so the
/// first terminated completion in scan order is the earliest match.
fn find_part_delimiter(
  view : StringView,
  crlf_delimiter : StringView,
  lf_delimiter : StringView,
  crlf_table : Array[Int32],
  lf_table : Array[Int32],
  start : Int32,
) -> Int32? {
  let lf_length = lf_delimiter.length()
  if lf_length == 0 {
    return Some(start)
  }
  let crlf_length = crlf_delimiter.length()
  let length = view.length()
  let mut lf_matched = 0
  let mut crlf_matched = 0
  let mut index = start
  while index < length {
    let code = view.unsafe_get(index)
    while crlf_matched > 0 && code != crlf_delimiter.unsafe_get(crlf_matched) {
      crlf_matched = crlf_table[crlf_matched - 1]
    }
    if code == crlf_delimiter.unsafe_get(crlf_matched) {
      crlf_matched = crlf_matched + 1
    }
    if crlf_matched == crlf_length {
      let match_start = index + 1 - crlf_length
      if delimiter_is_terminated(view, index + 1) {
        return Some(match_start)
      }
      crlf_matched = crlf_table[crlf_matched - 1]
    }
    while lf_matched > 0 && code != lf_delimiter.unsafe_get(lf_matched) {
      lf_matched = lf_table[lf_matched - 1]
    }
    if code == lf_delimiter.unsafe_get(lf_matched) {
      lf_matched = lf_matched + 1
    }
    if lf_matched == lf_length {
      let match_start = index + 1 - lf_length
      if delimiter_is_terminated(view, index + 1) {
        return Some(match_start)
      }
      lf_matched = lf_table[lf_matched - 1]
    }
    index = index + 1
  }
  None
}

///|
fn find_view_ignore_ascii_case(
  haystack : StringView,
  needle : StringView,
  start : Int32,
) -> Int32? {
  let length = needle.length()
  if length == 0 {
    return Some(start)
  }
  let last = haystack.length() - length
  let first = needle.unsafe_get(0).to_int()
  let lower_first = if first >= 65 && first <= 90 { first + 32 } else { first }
  let mut i = start
  while i <= last {
    let value = haystack.unsafe_get(i).to_int()
    let first_matches = if value == first {
      true
    } else {
      let lower_value = if value >= 65 && value <= 90 {
        value + 32
      } else {
        value
      }
      lower_value == lower_first
    }
    if first_matches {
      let mut j = 1
      let mut matched = true
      while j < length {
        let left = haystack.unsafe_get(i + j).to_int()
        let right = needle.unsafe_get(j).to_int()
        if left != right {
          let lower_left = if left >= 65 && left <= 90 {
            left + 32
          } else {
            left
          }
          let lower_right = if right >= 65 && right <= 90 {
            right + 32
          } else {
            right
          }
          if lower_left != lower_right {
            matched = false
            break
          }
        }
        j = j + 1
      }
      if matched {
        return Some(i)
      }
    }
    i = i + 1
  }
  None
}

///|
/// Look up a `;`-separated parameter such as `boundary` or `filename` in a
/// header value, honoring quoted string values.
///
/// The first segment (the media type or disposition itself) is skipped and
/// attribute names are read as whole tokens, so a name that only appears
/// inside another quoted value is never mistaken for a parameter.
fn header_parameter(value : StringView, name : String) -> String? {
  let length = value.length()
  let target = name.view()
  let mut pos = 0
  while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
    pos = pos + 1
  }
  while pos < length {
    pos = pos + 1
    while pos < length &&
          (
            value.unsafe_get(pos) == (' ' : UInt16) ||
            value.unsafe_get(pos) == ('\t' : UInt16)
          ) {
      pos = pos + 1
    }
    let name_start = pos
    while pos < length &&
          value.unsafe_get(pos) != ('=' : UInt16) &&
          value.unsafe_get(pos) != (';' : UInt16) {
      pos = pos + 1
    }
    let attribute = trim_ascii_space(value[name_start:pos])
    if pos < length && value.unsafe_get(pos) == ('=' : UInt16) {
      pos = pos + 1
      while pos < length &&
            (
              value.unsafe_get(pos) == (' ' : UInt16) ||
              value.unsafe_get(pos) == ('\t' : UInt16)
            ) {
        pos = pos + 1
      }
      let parsed : String? = if pos < length &&
        value.unsafe_get(pos) == ('"' : UInt16) {
        let quoted_start = pos + 1
        let mut end = quoted_start
        while end < length {
          let unit = value.unsafe_get(end)
          if unit == ('\\' : UInt16) && end + 1 < length {
            end = end + 2
          } else if unit == ('"' : UInt16) {
            break
          } else {
            end = end + 1
          }
        }
        let result = unescape_quoted_parameter(value[quoted_start:end])
        pos = if end < length { end + 1 } else { end }
        Some(result)
      } else {
        let value_start = pos
        while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
          pos = pos + 1
        }
        Some(trim_ascii_space(value[value_start:pos]).to_owned())
      }
      if attribute.equal_ignore_ascii_case(target) {
        return parsed
      }
    }
    while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
      pos = pos + 1
    }
  }
  None
}

///|
/// Most recently parsed `Content-Type` value and the boundary it resolved to.
let last_boundary_content_type : Ref[String?] = Ref(None)

///|
let last_boundary_value : Ref[String?] = Ref(None)

///|
pub fn multipart_boundary(content_type : String) -> String? {
  match last_boundary_content_type.val {
    Some(cached) =>
      if physical_equal(cached, content_type) {
        return last_boundary_value.val
      }
    None => ()
  }
  let view = content_type.view()
  let length = view.length()
  let mut pos = 0
  while pos < length && view.unsafe_get(pos) != (';' : UInt16) {
    pos = pos + 1
  }
  let media_type = trim_ascii_space(view[:pos])
  let result = if media_type.equal_ignore_ascii_case(
      "multipart/form-data".view(),
    ) {
    header_parameter(view, "boundary")
  } else {
    None
  }
  last_boundary_content_type.val = Some(content_type)
  last_boundary_value.val = result
  result
}

///|
/// Two most recently indexed header maps, their sizes and their lower-cased
/// name indexes. The index maps a lower-cased header name to the spelling
/// stored in the map. Only positive entries are cached: the map can be mutated
/// in place with its size unchanged, so a remembered absence could be stale,
/// while a remembered spelling is always re-validated against the map before it
/// is trusted.
let header_index_map0 : Ref[Map[String, String]?] = Ref(None)

///|
let header_index_size0 : Ref[Int32] = Ref(-1)

///|
let header_index_value0 : Ref[Map[String, String]?] = Ref(None)

///|
let header_index_map1 : Ref[Map[String, String]?] = Ref(None)

///|
let header_index_size1 : Ref[Int32] = Ref(-1)

///|
let header_index_value1 : Ref[Map[String, String]?] = Ref(None)

///|
/// Slot that receives the next rebuilt index.
let header_index_next : Ref[Int32] = Ref(0)

///|
/// Lower-cased spellings of recently seen header names.
let header_lower_cache : Map[String, String] = Map([])

///|
/// Recency ticks for `header_lower_cache`.
let header_lower_cache_ages : Map[String, Int32] = Map([])

///|
/// Maximum number of header names tracked by `header_lower_cache`.
const HEADER_LOWER_CACHE_LIMIT : Int32 = 128

///|
/// Lower-case a header name only when it contains upper-case letters. The
/// lower-cased form is kept in a bounded cache.
fn header_name_lower(name : String) -> String {
  if !has_ascii_upper(name.view()) {
    return name
  }
  match header_lower_cache.get(name) {
    Some(lower) => {
      cache_touch(header_lower_cache_ages, name)
      lower
    }
    None => {
      let lower = name.to_lower()
      cache_set(
        header_lower_cache,
        header_lower_cache_ages,
        HEADER_LOWER_CACHE_LIMIT,
        name,
        lower,
      )
      lower
    }
  }
}

///|
/// The lower-cased name index for `headers`, plus whether it was built during
/// this call (in which case it reflects the map's current contents exactly).
fn header_index_for(
  headers : Map[String, String],
) -> (Map[String, String], Bool) {
  match header_index_map0.val {
    Some(cached) =>
      if physical_equal(cached, headers) &&
        header_index_size0.val == headers.length() {
        match header_index_value0.val {
          Some(index) => return (index, false)
          None => ()
        }
      }
    None => ()
  }
  match header_index_map1.val {
    Some(cached) =>
      if physical_equal(cached, headers) &&
        header_index_size1.val == headers.length() {
        match header_index_value1.val {
          Some(index) => return (index, false)
          None => ()
        }
      }
    None => ()
  }
  let index : Map[String, String] = Map([], capacity=headers.length())
  for name, _ in headers {
    let lower = header_name_lower(name)
    if !index.contains(lower) {
      index.set(lower, name)
    }
  }
  let size = headers.length()
  if header_index_next.val == 0 {
    header_index_map0.val = Some(headers)
    header_index_size0.val = size
    header_index_value0.val = Some(index)
    header_index_next.val = 1
  } else {
    header_index_map1.val = Some(headers)
    header_index_size1.val = size
    header_index_value1.val = Some(index)
    header_index_next.val = 0
  }
  (index, true)
}

///|
fn get_header_ignore_case(
  headers : Map[String, String],
  name : String,
) -> String? {
  if headers.is_empty() {
    return None
  }
  match headers.get(name) {
    Some(value) => return Some(value)
    None => ()
  }
  let (index, fresh) = header_index_for(headers)
  let lower = header_name_lower(name)
  match index.get(lower) {
    Some(actual) =>
      match headers.get(actual) {
        Some(value) => return Some(value)
        None => ()
      }
    None =>
      // The index was built from the current contents, so a miss there means
      // no spelling of `name` is present.
      if fresh {
        return None
      }
  }
  // A `None` from `cached_header_spelling` proves the header is absent.
  match cached_header_spelling(headers, name) {
    Some(actual) =>
      match headers.get(actual) {
        Some(value) => {
          index.set(lower, actual)
          return Some(value)
        }
        None => ()
      }
    None => return None
  }
  None
}

///|
/// Canonical spellings of recently encountered header names, keyed by their
/// lower-cased form.
let header_spelling_cache : Map[String, String] = Map([])

///|
/// Recency ticks for `header_spelling_cache`.
let header_spelling_cache_ages : Map[String, Int32] = Map([])

///|
/// Find the spelling under which `name` is stored, ignoring case, and
/// re-validate it against the map so in-place replacements are picked up.
fn cached_header_spelling(
  headers : Map[String, String],
  name : String,
) -> String? {
  let lower = header_name_lower(name)
  match header_spelling_cache.get(lower) {
    Some(actual) => {
      cache_touch(header_spelling_cache_ages, lower)
      if headers.contains(actual) &&
        actual.view().equal_ignore_ascii_case(name.view()) {
        return Some(actual)
      }
    }
    None => ()
  }
  let target = name.view()
  let target_length = target.length()
  let mut found : String? = None
  for key in headers.keys() {
    if key.length() == target_length &&
      key.view().equal_ignore_ascii_case(target) {
      found = Some(key)
      break
    }
  }
  match found {
    Some(key) => {
      parse_cache_set(
        header_spelling_cache, header_spelling_cache_ages, lower, key,
      )
      Some(key)
    }
    None => None
  }
}

///|
/// Whether `code` may appear in an HTTP field name (RFC 9110 §5.6.2 `token`).
fn is_http_token_character(code : Int32) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 33 ||
  code == 35 ||
  code == 36 ||
  code == 37 ||
  code == 38 ||
  code == 39 ||
  code == 42 ||
  code == 43 ||
  code == 45 ||
  code == 46 ||
  code == 94 ||
  code == 95 ||
  code == 96 ||
  code == 124 ||
  code == 126
}

///|
/// Return `name` when it is a non-empty HTTP token, or `""` when it could
/// inject separators, whitespace or a whole extra header line.
fn sanitize_response_header_name(name : String) -> String {
  if name.is_empty() {
    return ""
  }
  for i = 0; i < name.length(); i = i + 1 {
    if !is_http_token_character(name[i].to_int()) {
      return ""
    }
  }
  name
}

///|
/// Set a header under its canonical spelling, dropping any existing entry whose
/// name differs only by case so the outgoing response has exactly one of it.
///
/// Header names and values are checked here because every response helper
/// funnels through this function. An invalid field name is ignored rather than
/// written, and control characters are removed from the value, so a handler
/// that forwards client-controlled text cannot forge an extra header line.
fn set_header_ignore_case(
  headers : Map[String, String],
  name : String,
  value : String,
) -> Unit {
  let name = sanitize_response_header_name(name)
  if name == "" {
    return
  }
  let value = strip_control_characters(value)
  let stale : Array[String] = []
  for key in headers.keys() {
    if key.view().equal_ignore_ascii_case(name.view()) {
      stale.push(key)
    }
  }
  for key in stale {
    ignore(headers.remove(key))
  }
  headers.set(name, value)
}

///|
/// Remove a header by name regardless of case. Returns whether one was found.
fn remove_header_ignore_case(
  headers : Map[String, String],
  name : String,
) -> Bool {
  let stale : Array[String] = []
  for key in headers.keys() {
    if key.view().equal_ignore_ascii_case(name.view()) {
      stale.push(key)
    }
  }
  if stale.is_empty() {
    return false
  }
  for key in stale {
    ignore(headers.remove(key))
  }
  true
}

///|
fn parse_part_headers(
  header_text : StringView,
) -> (Map[String, String], String?, Int32, String?, Int32) {
  let headers : Map[String, String] = Map([], capacity=4)
  let mut disposition : String? = None
  let mut disposition_matches = 0
  let mut content_type : String? = None
  let mut content_type_matches = 0
  let length = header_text.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    while end < length && header_text.unsafe_get(end) != ('\n' : UInt16) {
      end = end + 1
    }
    let line_end = if end > pos &&
      header_text.unsafe_get(end - 1) == ('\r' : UInt16) {
      end - 1
    } else {
      end
    }
    let mut colon = pos
    while colon < line_end && header_text.unsafe_get(colon) != (':' : UInt16) {
      colon = colon + 1
    }
    if line_end > pos && colon < line_end {
      let name = owned_trimmed(header_text[pos:colon])
      let value = owned_trimmed(header_text[colon + 1:line_end])
      if name != "" {
        headers.set(name, value)
        if name.view().equal_ignore_ascii_case("Content-Disposition".view()) {
          disposition = Some(value)
          disposition_matches = disposition_matches + 1
        } else if name.view().equal_ignore_ascii_case("Content-Type".view()) {
          content_type = Some(value)
          content_type_matches = content_type_matches + 1
        }
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  (
    headers, disposition, disposition_matches, content_type, content_type_matches,
  )
}

///|
fn skip_line_break(view : StringView, pos : Int32) -> Int32 {
  let length = view.length()
  let mut index = pos
  while index < length &&
        (
          view.unsafe_get(index) == (' ' : UInt16) ||
          view.unsafe_get(index) == ('\t' : UInt16)
        ) {
    index = index + 1
  }
  if index + 1 < length &&
    view.unsafe_get(index) == ('\r' : UInt16) &&
    view.unsafe_get(index + 1) == ('\n' : UInt16) {
    index + 2
  } else if index < length && view.unsafe_get(index) == ('\n' : UInt16) {
    index + 1
  } else {
    pos
  }
}

///|
/// One-entry cache of the delimiters and their prefix tables, keyed by the
/// boundary they were built from.
priv struct MultipartDelimiters {
  boundary : String
  delimiter : String
  crlf_delimiter : String
  lf_delimiter : String
  delimiter_table : Array[Int32]
  crlf_delimiter_table : Array[Int32]
  lf_delimiter_table : Array[Int32]
}

///|
let last_multipart_delimiters : Ref[MultipartDelimiters?] = Ref(None)

///|
/// Delimiters and prefix tables for `boundary`.
fn multipart_delimiters(boundary : String) -> MultipartDelimiters {
  match last_multipart_delimiters.val {
    Some(cached) => if cached.boundary == boundary { return cached }
    None => ()
  }
  let delimiter = "--" + boundary
  let crlf_delimiter = "\r\n" + delimiter
  let lf_delimiter = "\n" + delimiter
  let cached : MultipartDelimiters = {
    boundary,
    delimiter,
    crlf_delimiter,
    lf_delimiter,
    delimiter_table: delimiter_match_table(delimiter.view()),
    crlf_delimiter_table: delimiter_match_table(crlf_delimiter.view()),
    lf_delimiter_table: delimiter_match_table(lf_delimiter.view()),
  }
  last_multipart_delimiters.val = Some(cached)
  cached
}

///|
/// Most recent body and content type passed to `parse_multipart`, with the
/// owned parse they produced. Callers receive a copy of the parts, including
/// their header maps, so they can mutate the result freely.
let last_parsed_multipart_body : Ref[String?] = Ref(None)

///|
let last_parsed_multipart_content_type : Ref[String?] = Ref(None)

///|
let last_parsed_multipart_result : Ref[Array[MultipartPart]?] = Ref(None)

///|
let last_parsed_multipart_valid : Ref[Bool] = Ref(false)

///|
pub fn parse_multipart(
  body : String,
  content_type : String,
) -> Array[MultipartPart]? {
  match last_parsed_multipart_body.val {
    Some(cached_body) =>
      if last_parsed_multipart_valid.val &&
        (physical_equal(cached_body, body) || cached_body == body) &&
        last_parsed_multipart_content_type.val is Some(cached_type) &&
        (
          physical_equal(cached_type, content_type) ||
          cached_type == content_type
        ) {
        return match last_parsed_multipart_result.val {
          Some(parts) => Some(clone_multipart_parts(parts))
          None => None
        }
      }
    None => ()
  }
  let parsed = parse_multipart_uncached(body, content_type)
  if body.length() <= PARSE_CACHE_MAX_KEY {
    last_parsed_multipart_body.val = Some(body)
    last_parsed_multipart_content_type.val = Some(content_type)
    last_parsed_multipart_result.val = parsed
    last_parsed_multipart_valid.val = true
  }
  match parsed {
    Some(parts) => Some(clone_multipart_parts(parts))
    None => None
  }
}

///|
fn parse_multipart_uncached(
  body : String,
  content_type : String,
  raw_body~ : String? = None,
) -> Array[MultipartPart]? {
  let boundary = match multipart_boundary(content_type) {
    Some(boundary) if boundary != "" => boundary
    _ => return None
  }
  let delimiters = multipart_delimiters(boundary)
  let delimiter = delimiters.delimiter
  let delimiter_view = delimiter.view()
  let delimiter_length = delimiter.length()
  let crlf_delimiter = delimiters.crlf_delimiter
  let crlf_delimiter_view = crlf_delimiter.view()
  let lf_delimiter = delimiters.lf_delimiter
  let lf_delimiter_view = lf_delimiter.view()
  let delimiter_table = delimiters.delimiter_table
  let crlf_delimiter_table = delimiters.crlf_delimiter_table
  let lf_delimiter_table = delimiters.lf_delimiter_table
  // With a raw body available the parse runs over its lossless text, where
  // every received byte is still represented (supplementary characters intact,
  // invalid bytes escaped); the resulting slices can then be encoded back to
  // the exact payload. Without one the parse only sees well-formed text.
  let lossless = raw_body is Some(_)
  let source = match raw_body {
    Some(raw) => raw
    None => body
  }
  let view = source.view()
  let mut pos = match
    find_terminated_delimiter(view, delimiter_view, delimiter_table, 0) {
    Some(index) => index + delimiter_length
    // A multipart body always contains at least one dash-boundary (a valid
    // empty body is `--boundary--`). Without one the body is malformed, not
    // an empty list of parts.
    None => return None
  }
  let estimate = source.length() / (crlf_delimiter.length() + 8)
  let parts : Array[MultipartPart] = Array(
    capacity=if estimate > 64 { 64 } else { estimate + 1 },
  )
  let mut closed = false
  while pos <= view.length() {
    if pos + 1 < view.length() &&
      view.unsafe_get(pos) == ('-' : UInt16) &&
      view.unsafe_get(pos + 1) == ('-' : UInt16) {
      closed = true
      break
    }
    pos = skip_line_break(view, pos)
    // A part may carry no headers at all, in which case its blank line comes
    // immediately after the delimiter line.
    let (header_end, separator_length) = if pos + 1 < view.length() &&
      view.unsafe_get(pos) == ('\r' : UInt16) &&
      view.unsafe_get(pos + 1) == ('\n' : UInt16) {
      (pos, 2)
    } else if pos < view.length() && view.unsafe_get(pos) == ('\n' : UInt16) {
      (pos, 1)
    } else {
      match find_header_end(view, pos) {
        Some(index) =>
          if view.unsafe_get(index) == ('\r' : UInt16) {
            (index, 4)
          } else {
            (index, 2)
          }
        None => break
      }
    }
    let data_start = header_end + separator_length
    // Start the search after the blank line that separates the headers from
    // the payload. Searching from the header block would let the final CRLF
    // of that separator combine with a payload that begins with the boundary
    // spelling (`\r\n--boundary`) and mistake it for the next part.
    let data_end = match
      find_part_delimiter(
        view, crlf_delimiter_view, lf_delimiter_view, crlf_delimiter_table, lf_delimiter_table,
        data_start,
      ) {
      Some(index) => index
      None => break
    }
    if data_start > data_end {
      break
    }
    let (
      headers,
      tracked_disposition,
      disposition_matches,
      tracked_content_type,
      content_type_matches,
    ) = parse_part_headers(view[pos:header_end])
    let data = view[data_start:data_end]
    let disposition = if disposition_matches == 1 {
      tracked_disposition
    } else if disposition_matches == 0 {
      None
    } else {
      get_header_ignore_case(headers, "Content-Disposition")
    }
    let (name, filename) = match disposition {
      Some(disposition) => {
        let names = disposition_names(disposition.view())
        (names.name, names.filename)
      }
      None => ("", "")
    }
    let part_content_type = if content_type_matches == 1 {
      tracked_content_type.unwrap_or("")
    } else if content_type_matches == 0 {
      ""
    } else {
      get_header_ignore_case(headers, "Content-Type").unwrap_or("")
    }
    let part_data = data.to_owned()
    let (data_bytes, data_text) = resolve_part_bytes(
      part_data,
      if lossless {
        Some(part_data)
      } else {
        None
      },
      content_type=part_content_type,
    )
    parts.push({
      name,
      filename,
      content_type: part_content_type,
      headers,
      data: data_text,
      data_bytes,
    })
    pos = skip_line_break(view, data_end) + delimiter_length
  }
  // A truncated body that stops after part data (or after a bare delimiter)
  // must not be reported as a successful, complete multipart payload. Every
  // valid multipart/form-data body ends with `--boundary--`.
  if !closed {
    return None
  }
  Some(parts)
}

///|
/// Cached parts of a multipart request, or `None` when the body is not
/// multipart. Reads and normalizes the `Content-Type` header.
fn Context::multipart_entries(self : Context) -> Array[MultipartPart]? {
  let header = self.header("Content-Type")
  if parsed_content_type(header) != "multipart/form-data" {
    return None
  }
  // A binary body was preserved verbatim, so parse its lossless text and let
  // each part recover its exact bytes; otherwise the well-formed body is used
  // directly.
  let raw_body = match self.state.get(RAW_BODY_STATE_KEY) {
    Some(encoded) =>
      match base64_decode(encoded) {
        Some(bytes) => Some(decode_utf8_lossless(bytes))
        None => None
      }
    None => None
  }
  multipart_parts_lookup(self.request.body, header, raw_body~)
}

///|
/// The parsed multipart body. The result array is a copy, but its parts and
/// their header maps are shared with the parse cache and must be treated as
/// read-only.
pub fn Context::multipart(self : Context) -> Array[MultipartPart] {
  match self.multipart_entries() {
    Some(parts) => copy_multipart_parts(parts)
    None => []
  }
}

///|
/// Whether a part carries a `filename` (or RFC 8187 `filename*`) parameter.
/// The parameter's presence marks a file part even when its value is empty,
/// which is what browsers submit for an empty file input.
fn multipart_part_is_file(part : MultipartPart) -> Bool {
  match get_header_ignore_case(part.headers, "Content-Disposition") {
    Some(value) =>
      header_parameter(value.view(), "filename") is Some(_) ||
      header_parameter(value.view(), "filename*") is Some(_)
    None => false
  }
}

///|
pub fn Context::multipart_value(self : Context, name : String) -> String {
  match self.multipart_entries() {
    Some(parts) => {
      for part in parts {
        if !multipart_part_is_file(part) && part.name == name {
          return part.data
        }
      }
      ""
    }
    None => ""
  }
}

///|
pub fn Context::multipart_file(self : Context, name : String) -> MultipartPart? {
  match self.multipart_entries() {
    Some(parts) => {
      for part in parts {
        if part.name == name && multipart_part_is_file(part) {
          return Some(copy_multipart_part(part))
        }
      }
      None
    }
    None => None
  }
}

///|
/// Every text field named `name`, in the order the parts appear in the body.
/// File parts with the same name are skipped; use `multipart_files` for those.
/// Returns an empty array when the request is not multipart or carries no such
/// field.
pub fn Context::multipart_values(
  self : Context,
  name : String,
) -> Array[String] {
  let values : Array[String] = []
  match self.multipart_entries() {
    Some(parts) =>
      for part in parts {
        if !multipart_part_is_file(part) && part.name == name {
          values.push(part.data)
        }
      }
    None => ()
  }
  values
}

///|
/// Last text field named `name`, or `None` when the body is not multipart or
/// carries no such field. The `form` helpers use this spelling so a repeated
/// field resolves to its last value, exactly like an urlencoded form.
fn Context::multipart_form_value(
  self : Context,
  name : String,
) -> String? {
  match self.multipart_entries() {
    Some(parts) => {
      let mut value : String? = None
      for part in parts {
        if !multipart_part_is_file(part) && part.name == name {
          value = Some(part.data)
        }
      }
      value
    }
    None => None
  }
}

///|
/// Every text field named `name`, in body order, skipping file parts.
fn Context::multipart_form_values(
  self : Context,
  name : String,
) -> Array[String] {
  let values : Array[String] = []
  match self.multipart_entries() {
    Some(parts) =>
      for part in parts {
        if !multipart_part_is_file(part) && part.name == name {
          values.push(part.data)
        }
      }
    None => ()
  }
  values
}

///|
/// Multipart text fields keyed by name, with the last value of a repeated field
/// winning like `Context::form_map`.
fn Context::multipart_form_map(self : Context) -> Map[String, String] {
  let result : Map[String, String] = Map([], capacity=8)
  match self.multipart_entries() {
    Some(parts) =>
      for part in parts {
        if !multipart_part_is_file(part) {
          result.set(part.name, part.data)
        }
      }
    None => ()
  }
  result
}

///|
/// Multipart text fields keyed by name, preserving every repeated value in body
/// order like `Context::form_all`.
fn Context::multipart_form_all(
  self : Context,
) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = Map([], capacity=8)
  match self.multipart_entries() {
    Some(parts) =>
      for part in parts {
        if !multipart_part_is_file(part) {
          match result.get(part.name) {
            Some(values) => values.push(part.data)
            None => result.set(part.name, [part.data])
          }
        }
      }
    None => ()
  }
  result
}

///|
/// Every uploaded file named `name`, in the order the parts appear in the body.
/// Each returned part owns a copy of its header map, so callers may mutate the
/// result without disturbing the parse cache. A part with an empty `filename`
/// parameter is still a file part. Returns an empty array when the request is
/// not multipart or carries no such file.
pub fn Context::multipart_files(
  self : Context,
  name : String,
) -> Array[MultipartPart] {
  let files : Array[MultipartPart] = []
  match self.multipart_entries() {
    Some(parts) =>
      for part in parts {
        if part.name == name && multipart_part_is_file(part) {
          files.push(copy_multipart_part(part))
        }
      }
    None => ()
  }
  files
}

