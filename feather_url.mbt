///|
fn owned_trimmed(view : StringView) -> String {
  let length = view.length()
  let mut start = 0
  while start < length {
    let code = view.unsafe_get(start)
    if code > (' ' : UInt16) {
      break
    }
    if code != (' ' : UInt16) &&
      code != ('\t' : UInt16) &&
      code != ('\n' : UInt16) &&
      code != ('\r' : UInt16) {
      break
    }
    start = start + 1
  }
  let mut end = length
  while end > start {
    let code = view.unsafe_get(end - 1)
    if code > (' ' : UInt16) {
      break
    }
    if code != (' ' : UInt16) &&
      code != ('\t' : UInt16) &&
      code != ('\n' : UInt16) &&
      code != ('\r' : UInt16) {
      break
    }
    end = end - 1
  }
  let offset = view.start_offset()
  view.data().unsafe_substring(start=offset + start, end=offset + end)
}

///|
fn trim_ascii_space(view : StringView) -> StringView {
  let length = view.length()
  let mut start = 0
  while start < length {
    let code = view.unsafe_get(start)
    if code > (' ' : UInt16) {
      break
    }
    if code != (' ' : UInt16) &&
      code != ('\t' : UInt16) &&
      code != ('\n' : UInt16) &&
      code != ('\r' : UInt16) {
      break
    }
    start = start + 1
  }
  let mut end = length
  while end > start {
    let code = view.unsafe_get(end - 1)
    if code > (' ' : UInt16) {
      break
    }
    if code != (' ' : UInt16) &&
      code != ('\t' : UInt16) &&
      code != ('\n' : UInt16) &&
      code != ('\r' : UInt16) {
      break
    }
    end = end - 1
  }
  view[start:end]
}

///|
#inline
fn hex_digit(value : Int32) -> Int32 {
  if value >= 48 && value <= 57 {
    value - 48
  } else if value >= 65 && value <= 70 {
    value - 55
  } else if value >= 97 && value <= 102 {
    value - 87
  } else {
    -1
  }
}

///|
fn decode_url_bytes(bytes : BytesView, plus_as_space : Bool) -> String {
  let length = bytes.length()
  let out = FixedArray::make(length, b' ')
  let mut out_index = 0
  let mut i = 0
  while i < length {
    let byte = bytes[i].to_int()
    if byte == 37 && i + 2 < length {
      let high = hex_digit(bytes[i + 1].to_int())
      let low = hex_digit(bytes[i + 2].to_int())
      if high >= 0 && low >= 0 {
        out[out_index] = (high * 16 + low).to_byte()
        out_index = out_index + 1
        i = i + 3
        continue
      }
    } else if byte == 43 && plus_as_space {
      out[out_index] = b' '
      out_index = out_index + 1
      i = i + 1
      continue
    }
    out[out_index] = byte.to_byte()
    out_index = out_index + 1
    i = i + 1
  }
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes()[:out_index])
}

///|
/// Encode `source` as UTF-8, replacing unpaired surrogates with U+FFFD so the
/// conversion is total for any `String`.
fn encode_utf8_lossy(source : StringView) -> Bytes {
  let length = source.length()
  let out : Array[Byte] = Array(capacity=length)
  let mut i = 0
  while i < length {
    let code = source.unsafe_get(i).to_int()
    if code >= 0xD800 &&
      code <= 0xDBFF &&
      i + 1 < length &&
      source.unsafe_get(i + 1).to_int() >= 0xDC00 &&
      source.unsafe_get(i + 1).to_int() <= 0xDFFF {
      let low = source.unsafe_get(i + 1).to_int()
      let full = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
      out.push(((full >> 18) | 0xF0).to_byte())
      out.push((((full >> 12) & 0x3F) | 0x80).to_byte())
      out.push((((full >> 6) & 0x3F) | 0x80).to_byte())
      out.push(((full & 0x3F) | 0x80).to_byte())
      i = i + 2
      continue
    }
    let scalar = if code >= 0xD800 && code <= 0xDFFF { 0xFFFD } else { code }
    if scalar < 0x80 {
      out.push(scalar.to_byte())
    } else if scalar < 0x800 {
      out.push(((scalar >> 6) | 0xC0).to_byte())
      out.push(((scalar & 0x3F) | 0x80).to_byte())
    } else {
      out.push(((scalar >> 12) | 0xE0).to_byte())
      out.push((((scalar >> 6) & 0x3F) | 0x80).to_byte())
      out.push(((scalar & 0x3F) | 0x80).to_byte())
    }
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
fn decode_url_impl(source : StringView, plus_as_space : Bool) -> String {
  let length = source.length()
  let mut ascii_only = true
  let mut needs_decoding = false
  let mut needs_surrogate_repair = false
  let mut i = 0
  // Scan once to choose between the ASCII and UTF-8 decoding paths.
  while i < length {
    let value = source.unsafe_get(i).to_int()
    if value > 127 {
      ascii_only = false
    } else if value == 37 || (value == 43 && plus_as_space) {
      needs_decoding = true
    }
    if value >= 0xD800 && value <= 0xDBFF {
      if i + 1 < length &&
        source.unsafe_get(i + 1).to_int() >= 0xDC00 &&
        source.unsafe_get(i + 1).to_int() <= 0xDFFF {
        i = i + 1
      } else {
        needs_surrogate_repair = true
      }
    } else if value >= 0xDC00 && value <= 0xDFFF {
      needs_surrogate_repair = true
    }
    i = i + 1
  }
  if !needs_decoding {
    // Without escapes the common case is a pure copy. A lone surrogate is not
    // valid text, so repair it the same way the percent-decoding path does.
    if !needs_surrogate_repair {
      return source.to_owned()
    }
    return @utf8.decode_lossy(encode_utf8_lossy(source))
  }
  if !ascii_only {
    return decode_url_bytes(encode_utf8_lossy(source), plus_as_space)
  }
  let out = FixedArray::make(length, b' ')
  let mut out_index = 0
  let mut j = 0
  while j < length {
    let code = source.unsafe_get(j).to_int()
    if code == 37 && j + 2 < length {
      let high = hex_digit(source.unsafe_get(j + 1).to_int())
      let low = hex_digit(source.unsafe_get(j + 2).to_int())
      if high >= 0 && low >= 0 {
        out[out_index] = (high * 16 + low).to_byte()
        out_index = out_index + 1
        j = j + 3
        continue
      }
    } else if code == 43 && plus_as_space {
      out[out_index] = b' '
      out_index = out_index + 1
      j = j + 1
      continue
    }
    out[out_index] = code.to_byte()
    out_index = out_index + 1
    j = j + 1
  }
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes()[:out_index])
}

///|
fn decode_url(source : StringView) -> String {
  decode_url_impl(source, true)
}

///|
fn decode_url_path(source : StringView) -> String {
  decode_url_impl(source, false)
}

///|
pub fn url_decode(source : String) -> String {
  decode_url(source)
}

///|
#inline
fn is_url_unreserved(value : Int32) -> Bool {
  (value >= 48 && value <= 57) ||
  (value >= 65 && value <= 90) ||
  (value >= 97 && value <= 122) ||
  value == 45 ||
  value == 46 ||
  value == 95 ||
  value == 126
}

///|
#inline
fn percent_hex_byte(value : Int32) -> Byte {
  if value < 10 {
    (b'0'.to_int() + value).to_byte()
  } else {
    (b'A'.to_int() + (value - 10)).to_byte()
  }
}

///|
#inline
fn write_percent_to(
  out : FixedArray[Byte],
  offset : Int32,
  value : Int32,
) -> Unit {
  out[offset] = b'%'
  out[offset + 1] = percent_hex_byte(value / 16)
  out[offset + 2] = percent_hex_byte(value % 16)
}

///|
/// Most recently encoded source string and its result.
let last_url_encode_source : Ref[String?] = Ref(None)

///|
let last_url_encode_value : Ref[String] = Ref("")

///|
pub fn url_encode(source : String) -> String {
  match last_url_encode_source.val {
    Some(cached) =>
      if physical_equal(cached, source) {
        return last_url_encode_value.val
      }
    None => ()
  }
  let view = source.view()
  let length = view.length()
  let mut start = 0
  while start < length && is_url_unreserved(view.unsafe_get(start).to_int()) {
    start = start + 1
  }
  if start == length {
    last_url_encode_source.val = Some(source)
    last_url_encode_value.val = source
    return source
  }
  let mut out_len = start
  let mut i = start
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code < 0x80 {
      out_len = out_len + (if is_url_unreserved(code) { 1 } else { 3 })
    } else if code < 0x800 {
      out_len = out_len + 6
    } else if code >= 0xD800 && code <= 0xDBFF && i + 1 < length {
      let low = view.unsafe_get(i + 1).to_int()
      if low >= 0xDC00 && low <= 0xDFFF {
        out_len = out_len + 12
        i = i + 2
        continue
      }
      out_len = out_len + 9
    } else {
      out_len = out_len + 9
    }
    i = i + 1
  }
  let out = FixedArray::make(out_len, b' ')
  let mut p = 0
  while p < start {
    out[p] = view.unsafe_get(p).to_int().to_byte()
    p = p + 1
  }
  let mut out_index = start
  let mut j = start
  while j < length {
    let code = view.unsafe_get(j).to_int()
    if code < 0x80 {
      if is_url_unreserved(code) {
        out[out_index] = code.to_byte()
        out_index = out_index + 1
      } else {
        write_percent_to(out, out_index, code)
        out_index = out_index + 3
      }
    } else if code < 0x800 {
      write_percent_to(out, out_index, 0xC0 | (code >> 6))
      write_percent_to(out, out_index + 3, 0x80 | (code & 0x3F))
      out_index = out_index + 6
    } else if code >= 0xD800 && code <= 0xDBFF {
      if j + 1 < length {
        let low = view.unsafe_get(j + 1).to_int()
        if low >= 0xDC00 && low <= 0xDFFF {
          let scalar = ((code - 0xD800) << 10) + (low - 0xDC00) + 0x10000
          write_percent_to(out, out_index, 0xF0 | (scalar >> 18))
          write_percent_to(out, out_index + 3, 0x80 | ((scalar >> 12) & 0x3F))
          write_percent_to(out, out_index + 6, 0x80 | ((scalar >> 6) & 0x3F))
          write_percent_to(out, out_index + 9, 0x80 | (scalar & 0x3F))
          out_index = out_index + 12
          j = j + 2
          continue
        }
      }
      write_percent_to(out, out_index, 0xEF)
      write_percent_to(out, out_index + 3, 0xBF)
      write_percent_to(out, out_index + 6, 0xBD)
      out_index = out_index + 9
    } else if code >= 0xDC00 && code <= 0xDFFF {
      write_percent_to(out, out_index, 0xEF)
      write_percent_to(out, out_index + 3, 0xBF)
      write_percent_to(out, out_index + 6, 0xBD)
      out_index = out_index + 9
    } else {
      write_percent_to(out, out_index, 0xE0 | (code >> 12))
      write_percent_to(out, out_index + 3, 0x80 | ((code >> 6) & 0x3F))
      write_percent_to(out, out_index + 6, 0x80 | (code & 0x3F))
      out_index = out_index + 9
    }
    j = j + 1
  }
  let result = @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes()[:out_index])
  last_url_encode_source.val = Some(source)
  last_url_encode_value.val = result
  result
}

