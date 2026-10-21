///|
fn zzref_alpha(rng : FuzzRng, pool : Array[String], max_len : Int32) -> String {
  fuzz_random_string(rng, pool, max_len)
}

///|
fn zzref_b64_value(code : Int32, url : Bool) -> Int32 {
  if code >= 65 && code <= 90 {
    code - 65
  } else if code >= 97 && code <= 122 {
    code - 97 + 26
  } else if code >= 48 && code <= 57 {
    code - 48 + 52
  } else if url && (code == 45 || code == 43) {
    62
  } else if url && (code == 95 || code == 47) {
    63
  } else if !url && code == 43 {
    62
  } else if !url && code == 47 {
    63
  } else {
    -1
  }
}

///|
fn zzref_b64_decode(view : StringView, url : Bool) -> Bytes? {
  let length = view.length()
  if length == 0 {
    return Some(b"")
  }
  if length % 4 == 1 {
    return None
  }
  let out : FixedArray[Byte] = FixedArray::make((length + 3) / 4 * 3, b'\x00')
  let mut out_index = 0
  let padded_final = length % 4 == 0
  let normal_groups = if padded_final { length / 4 - 1 } else { length / 4 }
  for group = 0; group < normal_groups; group = group + 1 {
    let base = group * 4
    let first = zzref_b64_value(view.unsafe_get(base).to_int(), url)
    let second = zzref_b64_value(view.unsafe_get(base + 1).to_int(), url)
    let third = zzref_b64_value(view.unsafe_get(base + 2).to_int(), url)
    let fourth = zzref_b64_value(view.unsafe_get(base + 3).to_int(), url)
    if first < 0 || second < 0 || third < 0 || fourth < 0 {
      return None
    }
    out[out_index] = ((first << 2) | (second >> 4)).to_byte()
    out[out_index + 1] = (((second & 15) << 4) | (third >> 2)).to_byte()
    out[out_index + 2] = (((third & 3) << 6) | fourth).to_byte()
    out_index = out_index + 3
  }
  let start = normal_groups * 4
  if padded_final {
    let first = zzref_b64_value(view.unsafe_get(start).to_int(), url)
    let second = zzref_b64_value(view.unsafe_get(start + 1).to_int(), url)
    let third_code = view.unsafe_get(start + 2).to_int()
    let fourth_code = view.unsafe_get(start + 3).to_int()
    let third_raw = if third_code == 61 {
      -2
    } else {
      zzref_b64_value(third_code, url)
    }
    let fourth_raw = if fourth_code == 61 {
      -2
    } else {
      zzref_b64_value(fourth_code, url)
    }
    if first < 0 || second < 0 {
      return None
    }
    if third_raw == -2 {
      if fourth_raw != -2 {
        return None
      }
      out[out_index] = ((first << 2) | (second >> 4)).to_byte()
      return Some(own_bytes_prefix(out, out_index + 1))
    }
    if third_raw < 0 {
      return None
    }
    out[out_index] = ((first << 2) | (second >> 4)).to_byte()
    if fourth_raw == -2 {
      out[out_index + 1] = (((second & 15) << 4) | (third_raw >> 2)).to_byte()
      return Some(own_bytes_prefix(out, out_index + 2))
    }
    if fourth_raw < 0 {
      return None
    }
    out[out_index + 1] = (((second & 15) << 4) | (third_raw >> 2)).to_byte()
    out[out_index + 2] = (((third_raw & 3) << 6) | fourth_raw).to_byte()
    return Some(own_bytes_prefix(out, out_index + 3))
  }
  let first = zzref_b64_value(view.unsafe_get(start).to_int(), url)
  let second = zzref_b64_value(view.unsafe_get(start + 1).to_int(), url)
  if first < 0 || second < 0 {
    return None
  }
  out[out_index] = ((first << 2) | (second >> 4)).to_byte()
  out_index = out_index + 1
  if length % 4 == 2 {
    return Some(own_bytes_prefix(out, out_index))
  }
  let third = zzref_b64_value(view.unsafe_get(start + 2).to_int(), url)
  if third < 0 {
    return None
  }
  out[out_index] = (((second & 15) << 4) | (third >> 2)).to_byte()
  out_index = out_index + 1
  Some(own_bytes_prefix(out, out_index))
}

///|
fn zzref_b64_current(view : StringView, url : Bool) -> Bytes? {
  if url {
    base64url_decode_view(view)
  } else {
    base64_decode_view(view)
  }
}

///|
test "zzref base64 fast path matches reference decoder" {
  let rng = FuzzRng::new(90210L)
  let pool : Array[String] = [
    "A", "B", "Z", "a", "z", "0", "9", "+", "/", "-", "_", "=", "*", " ", "é",
  ]
  let mut iterations = 0
  while iterations < 20000 {
    let text = zzref_alpha(rng, pool, 10)
    let view = text.view()
    let current_std = zzref_b64_current(view, false)
    let ref_std = zzref_b64_decode(view, false)
    if current_std != ref_std {
      fail("std mismatch for \{text}: current=\{current_std} ref=\{ref_std}")
    }
    let current_url = zzref_b64_current(view, true)
    let ref_url = zzref_b64_decode(view, true)
    if current_url != ref_url {
      fail("url mismatch for \{text}: current=\{current_url} ref=\{ref_url}")
    }
    iterations = iterations + 1
  }
}

///|
fn zzref_urlencoded_multi_naive(
  source : StringView,
) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = Map([])
  let length = source.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    let mut eq = -1
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) && eq < 0 {
        eq = end
      }
      end = end + 1
    }
    if end > pos {
      let raw_key = if eq >= 0 { source[pos:eq] } else { source[pos:end] }
      let key = decode_url(raw_key)
      let value = if eq >= 0 { decode_url(source[eq + 1:end]) } else { "" }
      match result.get(key) {
        Some(values) => values.push(value)
        None => result.set(key, [value])
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  result
}

///|
fn zzref_multi_eq(
  a : Map[String, Array[String]],
  b : Map[String, Array[String]],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for key, values in a {
    match b.get(key) {
      Some(other) => {
        if values.length() != other.length() {
          return false
        }
        for i = 0; i < values.length(); i = i + 1 {
          if values[i] != other[i] {
            return false
          }
        }
      }
      None => return false
    }
  }
  true
}

///|
test "zzref urlencoded multi fast path matches naive decode" {
  let rng = FuzzRng::new(5150L)
  let pool : Array[String] = [
    "a", "b", "=", "&", "%20", "%2B", "+", "%", "1", "%ZZ", "k", "v", "",
  ]
  let mut iterations = 0
  while iterations < 20000 {
    let source = zzref_alpha(rng, pool, 12)
    let current = parse_urlencoded_multi(source.view())
    let ref = zzref_urlencoded_multi_naive(source.view())
    if !zzref_multi_eq(current, ref) {
      fail(
        "urlencoded multi mismatch for \{source}: current=\{current} ref=\{ref}",
      )
    }
    iterations = iterations + 1
  }
}

///|
fn zzref_find_part_delimiter_old(
  view : StringView,
  crlf_delimiter : StringView,
  lf_delimiter : StringView,
  crlf_table : Array[Int32],
  lf_table : Array[Int32],
  start : Int32,
) -> Int32? {
  let lf = find_terminated_delimiter(view, lf_delimiter, lf_table, start)
  let crlf = find_terminated_delimiter(view, crlf_delimiter, crlf_table, start)
  match lf {
    Some(lf_index) =>
      match crlf {
        Some(crlf_index) =>
          Some(if crlf_index < lf_index { crlf_index } else { lf_index })
        None => Some(lf_index)
      }
    None => crlf
  }
}

///|
test "zzref multipart delimiter single pass matches two searches" {
  let rng = FuzzRng::new(777L)
  let boundary = "XY"
  let delimiters = multipart_delimiters(boundary)
  let crlf_delimiter = delimiters.crlf_delimiter.view()
  let lf_delimiter = delimiters.lf_delimiter.view()
  let crlf_table = delimiters.crlf_delimiter_table
  let lf_table = delimiters.lf_delimiter_table
  let pool : Array[String] = [
    "\r", "\n", "-", "X", "Y", "a", "\r\n", "--", "--XY", "\n--XY", "\r\n--XY", " ",
  ]
  let mut iterations = 0
  while iterations < 20000 {
    let body = zzref_alpha(rng, pool, 12)
    let view = body.view()
    let current = find_part_delimiter(
      view, crlf_delimiter, lf_delimiter, crlf_table, lf_table, 0,
    )
    let old = zzref_find_part_delimiter_old(
      view, crlf_delimiter, lf_delimiter, crlf_table, lf_table, 0,
    )
    if current != old {
      fail("delimiter mismatch for \{body}: current=\{current} old=\{old}")
    }
    iterations = iterations + 1
  }
}

///|
fn zzref_header_ext_parameter(value : StringView, name : String) -> String? {
  if find_view_from(value, "*".view(), 0) is None {
    return None
  }
  let raw = match header_parameter(value, name + "*") {
    Some(raw) => raw
    None => return None
  }
  let view = raw.view()
  let first = match view.find("'") {
    Some(index) => index
    None => return None
  }
  if !view[:first].equal_ignore_ascii_case("utf-8".view()) {
    return None
  }
  let rest = view[first + 1:]
  let second = match rest.find("'") {
    Some(index) => index
    None => return None
  }
  Some(decode_url_path(rest[second + 1:]))
}

///|
fn zzref_disposition_old(value : StringView) -> (String, String) {
  let name = match header_parameter(value, "name") {
    Some(name) => name
    None => ""
  }
  let filename = match zzref_header_ext_parameter(value, "filename") {
    Some(filename) => filename
    None =>
      match header_parameter(value, "filename") {
        Some(filename) => filename
        None => ""
      }
  }
  (name, filename)
}

///|
test "zzref disposition parser matches old parameter helpers" {
  let rng = FuzzRng::new(31337L)
  let pool : Array[String] = [
    "form-data", ";", " ", "name", "filename", "filename*", "=", "\"", "'", "utf-8",
    "%20", "a.txt", "x", "\"quoted\"",
  ]
  let mut iterations = 0
  while iterations < 20000 {
    let text = zzref_alpha(rng, pool, 10)
    let current = disposition_names(text.view())
    let old = zzref_disposition_old(text.view())
    if current.name != old.0 || current.filename != old.1 {
      fail(
        "disposition mismatch for \{text}: current=(\{current.name},\{current.filename}) old=\{(old.0)},\{(old.1)}",
      )
    }
    iterations = iterations + 1
  }
}

///|
test "zzref json_object_text matches json stringify" {
  let rng = FuzzRng::new(4242L)
  let pool : Array[String] = [
    "", "a", "\"", "\\", "\n", "\r", "\t", "\u0008", "\u000c", "\u0000", "\u001f",
    "é", "中", "😀", "x y", "0", "ABC", "<>&", "\\u0041",
  ]
  let mut iterations = 0
  while iterations < 5000 {
    let data : Map[String, String] = Map([])
    let count = rng.below(4)
    for i = 0; i < count; i = i + 1 {
      let key = zzref_alpha(rng, pool, 4)
      let value = zzref_alpha(rng, pool, 8)
      data.set(key, value)
    }
    let current = json_object_text(data)
    let expected = match data.is_empty() {
      true => "{}"
      false => json_object(data).stringify()
    }
    if current != expected {
      fail("json mismatch for \{data}: current=\{current} expected=\{expected}")
    }
    iterations = iterations + 1
  }
}

///|
test "zzref parse_urlencoded cache matches view parser" {
  let rng = FuzzRng::new(606L)
  let pool : Array[String] = [
    "a", "b", "1", "&", "=", "%20", "%2F", "+", "%", "%zz", " ", "é", "=",
  ]
  let mut iterations = 0
  while iterations < 20000 {
    let text = zzref_alpha(rng, pool, 12)
    let current = parse_urlencoded(text)
    let view = parse_urlencoded_view(text.view())
    if !fuzz_map_eq(current, view) {
      fail("urlencoded mismatch for \{text}: current=\{current} view=\{view}")
    }
    iterations = iterations + 1
  }
}

///|
test "zzref hmac key cache stale after caller mutation" {
  let reference_jefe = hmac_sha256(b"Jefe", b"msg")
  let reference_kefe = hmac_sha256(b"Kefe", b"msg")
  if constant_time_bytes_equal(reference_jefe, reference_kefe) {
    fail("reference digests unexpectedly equal")
  }
  let backing : FixedArray[Byte] = FixedArray::from_array([
    b'J', b'e', b'f', b'e',
  ])
  let key = backing.unsafe_reinterpret_as_bytes()
  ignore(hmac_sha256(key, b"msg"))
  backing[0] = b'K'
  let after = hmac_sha256(key, b"msg")
  if !constant_time_bytes_equal(after, reference_kefe) {
    fail(
      "stale hmac midstate after key mutation: \{test_hex(after)} vs \{test_hex(reference_kefe)}",
    )
  }
}
