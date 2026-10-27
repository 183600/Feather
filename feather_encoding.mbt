///|
let base64_alphabet : Bytes = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
/// Character code (0-255) to 6-bit value for standard base64; `-1` marks every
/// character outside the alphabet.
let base64_lookup : FixedArray[Int32] = {
  let table = FixedArray::make(256, -1)
  for i = 0; i < 26; i = i + 1 {
    table[65 + i] = i
    table[97 + i] = i + 26
  }
  for i = 0; i < 10; i = i + 1 {
    table[48 + i] = i + 52
  }
  table[43] = 62
  table[47] = 63
  table
}

///|
/// Encode bytes with the standard base64 alphabet, including padding.
pub fn base64_encode(data : Bytes) -> String {
  let length = data.length()
  if length == 0 {
    return ""
  }
  let alphabet = base64_alphabet
  let out = FixedArray::make((length + 2) / 3 * 4, b'=')
  let mut i = 0
  let mut out_index = 0
  while i + 3 <= length {
    let value = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    out[out_index] = alphabet[(value >> 18) & 63]
    out[out_index + 1] = alphabet[(value >> 12) & 63]
    out[out_index + 2] = alphabet[(value >> 6) & 63]
    out[out_index + 3] = alphabet[value & 63]
    i = i + 3
    out_index = out_index + 4
  }
  let remaining = length - i
  if remaining == 1 {
    let value = data[i].to_int() << 16
    out[out_index] = alphabet[(value >> 18) & 63]
    out[out_index + 1] = alphabet[(value >> 12) & 63]
  } else if remaining == 2 {
    let value = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8)
    out[out_index] = alphabet[(value >> 18) & 63]
    out[out_index + 1] = alphabet[(value >> 12) & 63]
    out[out_index + 2] = alphabet[(value >> 6) & 63]
  }
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes())
}

///|
/// Hand `length` leading bytes of `out` over as an owned `Bytes`.
fn own_bytes_prefix(out : FixedArray[Byte], length : Int32) -> Bytes {
  if length == out.length() {
    out.unsafe_reinterpret_as_bytes()
  } else {
    Bytes::from_array(out[:length])
  }
}

///|
/// Most recently decoded base64 text and its result.
let last_base64_text : Ref[String?] = Ref(None)

///|
let last_base64_result : Ref[Bytes?] = Ref(None)

///|
let last_base64_valid : Ref[Bool] = Ref(false)

///|
/// Decode standard base64 text. Returns `None` for malformed input.
///
/// Padding may be omitted, but a stray `=` in the middle of the text is
/// rejected.
pub fn base64_decode(text : String) -> Bytes? {
  match last_base64_text.val {
    Some(cached) =>
      if last_base64_valid.val &&
        (physical_equal(cached, text) || cached == text) {
        return last_base64_result.val
      }
    None => ()
  }
  let result = base64_decode_view(text.view())
  last_base64_text.val = Some(text)
  last_base64_result.val = result
  last_base64_valid.val = true
  result
}

///|
/// Look up a character code in a base64 value table. Characters outside the
/// table (anything past Latin-1) are not part of any base64 alphabet, so they
/// map to `-1` instead of indexing out of bounds.
#inline
fn base64_table_value(table : FixedArray[Int32], code : UInt16) -> Int32 {
  let index = code.to_int()
  if index < table.length() {
    table[index]
  } else {
    -1
  }
}

///|
/// `base64_decode` core: `table` maps a character code to its 6-bit value, or
/// `-1` when the character is not in the alphabet.
fn base64_decode_core(view : StringView, table : FixedArray[Int32]) -> Bytes? {
  let length = view.length()
  if length == 0 {
    return Some(b"")
  }
  if length % 4 == 1 {
    return None
  }
  let full_groups = length / 4
  let remainder = length % 4
  let mut out_len = full_groups * 3
  if remainder == 2 {
    out_len = out_len + 1
  } else if remainder == 3 {
    out_len = out_len + 2
  } else if view.unsafe_get(length - 1) == ('=' : UInt16) {
    out_len = out_len - 1
    if view.unsafe_get(length - 2) == ('=' : UInt16) {
      out_len = out_len - 1
    }
  }
  let out = FixedArray::make(out_len, b' ')
  let mut i = 0
  let mut out_index = 0
  // Decode four alphabet characters at a time. Invalid or padded groups fall
  // back below.
  while i + 4 <= length {
    let first_code = view.unsafe_get(i).to_int()
    let second_code = view.unsafe_get(i + 1).to_int()
    let third_code = view.unsafe_get(i + 2).to_int()
    let fourth_code = view.unsafe_get(i + 3).to_int()
    if first_code >= 256 ||
      second_code >= 256 ||
      third_code >= 256 ||
      fourth_code >= 256 {
      break
    }
    let first = table[first_code]
    let second = table[second_code]
    let third = table[third_code]
    let fourth = table[fourth_code]
    if first < 0 || second < 0 || third < 0 || fourth < 0 {
      break
    }
    out[out_index] = ((first << 2) | (second >> 4)).to_byte()
    out[out_index + 1] = (((second & 15) << 4) | (third >> 2)).to_byte()
    out[out_index + 2] = (((third & 3) << 6) | fourth).to_byte()
    i = i + 4
    out_index = out_index + 3
  }
  while i < length {
    let remaining = length - i
    let first = base64_table_value(table, view.unsafe_get(i))
    let second = if remaining >= 2 {
      base64_table_value(table, view.unsafe_get(i + 1))
    } else {
      -1
    }
    if first < 0 || second < 0 {
      return None
    }
    out[out_index] = ((first << 2) | (second >> 4)).to_byte()
    out_index = out_index + 1
    if remaining <= 2 {
      return Some(own_bytes_prefix(out, out_index))
    }
    let third_raw = view.unsafe_get(i + 2)
    if remaining == 3 {
      if third_raw == ('=' : UInt16) {
        return None
      }
      let third = base64_table_value(table, third_raw)
      if third < 0 {
        return None
      }
      out[out_index] = (((second & 15) << 4) | (third >> 2)).to_byte()
      out_index = out_index + 1
      return Some(own_bytes_prefix(out, out_index))
    }
    if third_raw == ('=' : UInt16) {
      if view.unsafe_get(i + 3) != ('=' : UInt16) || remaining != 4 {
        return None
      }
      return Some(own_bytes_prefix(out, out_index))
    }
    let third = base64_table_value(table, third_raw)
    if third < 0 {
      return None
    }
    out[out_index] = (((second & 15) << 4) | (third >> 2)).to_byte()
    out_index = out_index + 1
    let fourth_raw = view.unsafe_get(i + 3)
    if fourth_raw == ('=' : UInt16) {
      if remaining != 4 {
        return None
      }
      return Some(own_bytes_prefix(out, out_index))
    }
    let fourth = base64_table_value(table, fourth_raw)
    if fourth < 0 {
      return None
    }
    out[out_index] = (((third & 3) << 6) | fourth).to_byte()
    out_index = out_index + 1
    i = i + 4
  }
  Some(own_bytes_prefix(out, out_index))
}

///|
/// `base64_decode` for a `StringView`.
fn base64_decode_view(view : StringView) -> Bytes? {
  base64_decode_core(view, base64_lookup)
}

///|
fn has_ascii_upper(view : StringView) -> Bool {
  let length = view.length()
  let mut i = 0
  while i < length {
    let value = view.unsafe_get(i)
    if value >= ('A' : UInt16) && value <= ('Z' : UInt16) {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn starts_with_ignore_ascii_case(
  view : StringView,
  prefix : StringView,
) -> Bool {
  let length = prefix.length()
  if view.length() < length {
    return false
  }
  let mut i = 0
  while i < length {
    let left = view.unsafe_get(i)
    let right = prefix.unsafe_get(i)
    if left != right {
      let mut left_code = left.to_int()
      let mut right_code = right.to_int()
      if left_code >= 65 && left_code <= 90 {
        left_code = left_code + 32
      }
      if right_code >= 65 && right_code <= 90 {
        right_code = right_code + 32
      }
      if left_code != right_code {
        return false
      }
    }
    i = i + 1
  }
  true
}

///|
let mime_table : Map[String, String] = Map([
  ("html", "text/html; charset=utf-8"),
  ("htm", "text/html; charset=utf-8"),
  ("css", "text/css; charset=utf-8"),
  ("js", "text/javascript; charset=utf-8"),
  ("mjs", "text/javascript; charset=utf-8"),
  ("json", "application/json; charset=utf-8"),
  ("map", "application/json; charset=utf-8"),
  ("webmanifest", "application/manifest+json; charset=utf-8"),
  ("yaml", "application/yaml; charset=utf-8"),
  ("yml", "application/yaml; charset=utf-8"),
  ("toml", "application/toml; charset=utf-8"),
  ("txt", "text/plain; charset=utf-8"),
  ("text", "text/plain; charset=utf-8"),
  ("log", "text/plain; charset=utf-8"),
  ("md", "text/markdown; charset=utf-8"),
  ("markdown", "text/markdown; charset=utf-8"),
  ("csv", "text/csv; charset=utf-8"),
  ("xml", "application/xml"),
  ("svg", "image/svg+xml"),
  ("png", "image/png"),
  ("jpg", "image/jpeg"),
  ("jpeg", "image/jpeg"),
  ("gif", "image/gif"),
  ("webp", "image/webp"),
  ("avif", "image/avif"),
  ("bmp", "image/bmp"),
  ("ico", "image/x-icon"),
  ("wasm", "application/wasm"),
  ("pdf", "application/pdf"),
  ("zip", "application/zip"),
  ("gz", "application/gzip"),
  ("mp3", "audio/mpeg"),
  ("wav", "audio/wav"),
  ("ogg", "audio/ogg"),
  ("mp4", "video/mp4"),
  ("webm", "video/webm"),
  ("mov", "video/quicktime"),
  ("woff", "font/woff"),
  ("woff2", "font/woff2"),
  ("ttf", "font/ttf"),
  ("otf", "font/otf"),
  ("eot", "application/vnd.ms-fontobject"),
  ("tif", "image/tiff"),
  ("tiff", "image/tiff"),
  ("heic", "image/heic"),
  ("heif", "image/heif"),
  ("apng", "image/apng"),
  ("psd", "image/vnd.adobe.photoshop"),
  ("aac", "audio/aac"),
  ("flac", "audio/flac"),
  ("m4a", "audio/mp4"),
  ("opus", "audio/ogg"),
  ("mid", "audio/midi"),
  ("midi", "audio/midi"),
  ("mpeg", "video/mpeg"),
  ("mpg", "video/mpeg"),
  ("avi", "video/x-msvideo"),
  ("mkv", "video/x-matroska"),
  ("3gp", "video/3gpp"),
  ("ts", "video/mp2t"),
  ("m3u8", "application/vnd.apple.mpegurl"),
  ("xhtml", "application/xhtml+xml"),
  ("rss", "application/rss+xml"),
  ("atom", "application/atom+xml"),
  ("epub", "application/epub+zip"),
  ("doc", "application/msword"),
  (
    "docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ),
  ("xls", "application/vnd.ms-excel"),
  ("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
  ("ppt", "application/vnd.ms-powerpoint"),
  (
    "pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  ),
  ("odt", "application/vnd.oasis.opendocument.text"),
  ("ods", "application/vnd.oasis.opendocument.spreadsheet"),
  ("odp", "application/vnd.oasis.opendocument.presentation"),
  ("rtf", "application/rtf"),
  ("7z", "application/x-7z-compressed"),
  ("rar", "application/vnd.rar"),
  ("tar", "application/x-tar"),
  ("xz", "application/x-xz"),
  ("bz2", "application/x-bzip2"),
  ("zst", "application/zstd"),
  ("ics", "text/calendar"),
  ("vtt", "text/vtt"),
  ("sh", "application/x-sh"),
  ("sql", "application/sql"),
  ("ini", "text/plain; charset=utf-8"),
  ("conf", "text/plain; charset=utf-8"),
])

///|
fn mime_for_extension(extension : StringView) -> String {
  match mime_table.get_from_string(extension) {
    Some(value) => value
    None => "application/octet-stream"
  }
}

///|
/// Most recently resolved file path and its media type.
let last_mime_path : Ref[String?] = Ref(None)

///|
let last_mime_value : Ref[String] = Ref("")

///|
/// The media type associated with the extension of `path`.
///
/// Matching is case-insensitive and only the last path segment is considered.
/// A URL query string or fragment is ignored, so `mime_type_for` works for both
/// filesystem paths (`"public/app.js"`) and URLs (`"/app.js?v=1"`). Paths
/// without an extension get `"application/octet-stream"`.
pub fn mime_type_for(path : String) -> String {
  match last_mime_path.val {
    Some(cached) =>
      if physical_equal(cached, path) {
        return last_mime_value.val
      }
    None => ()
  }
  let view = path.view()
  // A query or fragment is not part of the extension, even though it may
  // itself contain a dot (`app.js?v=1.2`).
  let mut end = view.length()
  let mut scan = 0
  while scan < end {
    let code = view.unsafe_get(scan)
    if code == ('?' : UInt16) || code == ('#' : UInt16) {
      end = scan
      break
    }
    scan = scan + 1
  }
  let mut dot = -1
  let mut i = end - 1
  while i >= 0 {
    let code = view.unsafe_get(i)
    if code == ('.' : UInt16) {
      dot = i
      break
    }
    if code == ('/' : UInt16) {
      break
    }
    i = i - 1
  }
  let result = if dot >= 0 {
    let extension = view[dot + 1:end]
    if has_ascii_upper(extension) {
      let lower = extension.to_lower().view()
      mime_for_extension(lower)
    } else {
      mime_for_extension(extension)
    }
  } else {
    mime_for_extension("")
  }
  last_mime_path.val = Some(path)
  last_mime_value.val = result
  result
}

