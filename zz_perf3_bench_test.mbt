///|
fn p3_time(name : String, iterations : Int, f : () -> Unit) -> Unit {
  for i = 0; i < 500; i = i + 1 {
    f()
  }
  let start = @async.now()
  for i = 0; i < iterations; i = i + 1 {
    f()
  }
  let elapsed = @async.now() - start
  let per_op = elapsed.to_double() * 1000000.0 / iterations.to_double()
  println("\{name}: \{per_op} ns/op")
}

///|
fn p3_bench_ctx_new_variant(
  cap_headers : Int,
  cap_state : Int,
  cap_json : Int,
  request : Request,
) -> Context {
  {
    request,
    response: {
      status: 200,
      headers: Map([], capacity=cap_headers),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map([], capacity=cap_state),
    json_state: Map([], capacity=cap_json),
    cleanups: [],
    file: None,
  }
}

///|
fn p3_cookies_fast(header : StringView) -> Map[String, String] {
  let cookies : Map[String, String] = Map([], capacity=8)
  let length = header.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    while end < length && header.unsafe_get(end) != (';' : UInt16) {
      end = end + 1
    }
    let mut start = pos
    while start < end {
      let code = header.unsafe_get(start)
      if code != (' ' : UInt16) &&
        code != ('\t' : UInt16) &&
        code != ('\n' : UInt16) &&
        code != ('\r' : UInt16) {
        break
      }
      start = start + 1
    }
    let mut stop = end
    while stop > start {
      let code = header.unsafe_get(stop - 1)
      if code != (' ' : UInt16) &&
        code != ('\t' : UInt16) &&
        code != ('\n' : UInt16) &&
        code != ('\r' : UInt16) {
        break
      }
      stop = stop - 1
    }
    if start < stop {
      let mut eq = start
      while eq < stop && header.unsafe_get(eq) != ('=' : UInt16) {
        eq = eq + 1
      }
      if eq < stop {
        let mut name_end = eq
        while name_end > start {
          let code = header.unsafe_get(name_end - 1)
          if code != (' ' : UInt16) &&
            code != ('\t' : UInt16) &&
            code != ('\n' : UInt16) &&
            code != ('\r' : UInt16) {
            break
          }
          name_end = name_end - 1
        }
        if name_end > start {
          let name = header[start:name_end].to_owned()
          let raw_start = eq + 1
          let value = if stop - raw_start >= 2 &&
            header.unsafe_get(raw_start) == ('"' : UInt16) &&
            header.unsafe_get(stop - 1) == ('"' : UInt16) {
            header[raw_start + 1:stop - 1].to_owned()
          } else {
            header[raw_start:stop].to_owned()
          }
          cookies.set(name, value)
        }
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  cookies
}

///|
fn p3_trim_ascii_space(view : StringView) -> StringView {
  let length = view.length()
  let mut start = 0
  while start < length {
    let code = view.unsafe_get(start)
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
fn p3_owned_trimmed(view : StringView) -> String {
  let trimmed = p3_trim_ascii_space(view)
  let offset = trimmed.start_offset()
  trimmed.data().unsafe_substring(
    start=offset,
    end=offset + trimmed.length(),
  )
}

///|
fn p3_find_view_from(
  haystack : StringView,
  needle : StringView,
  start : Int32,
) -> Int32? {
  let length = needle.length()
  if length == 0 {
    return Some(start)
  }
  if start > haystack.length() - length {
    return None
  }
  match haystack[start:].find(needle) {
    Some(offset) => Some(start + offset)
    None => None
  }
}

///|
fn p3_delimiter_is_terminated(view : StringView, after : Int32) -> Bool {
  let length = view.length()
  if after >= length {
    return true
  }
  let code = view.unsafe_get(after)
  if code == ('\r' : UInt16) || code == ('\n' : UInt16) {
    return true
  }
  if code == ('-' : UInt16) {
    return after + 1 < length && view.unsafe_get(after + 1) == ('-' : UInt16)
  }
  false
}

///|
fn p3_find_terminated_delimiter(
  view : StringView,
  needle : StringView,
  start : Int32,
) -> Int32? {
  let needle_length = needle.length()
  let mut search = start
  while search <= view.length() - needle_length {
    let index = match p3_find_view_from(view, needle, search) {
      Some(index) => index
      None => return None
    }
    if p3_delimiter_is_terminated(view, index + needle_length) {
      return Some(index)
    }
    search = index + 1
  }
  None
}

///|
fn p3_find_lower_view(
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
  let mut i = start
  while i <= last {
    let value = haystack.unsafe_get(i).to_int()
    if value == first {
      let mut j = 1
      let mut matched = true
      while j < length {
        if haystack.unsafe_get(i + j) != needle.unsafe_get(j) {
          matched = false
          break
        }
        j = j + 1
      }
      if matched {
        return Some(i)
      }
    } else if value >= 65 && value <= 90 && value + 32 == first {
      let mut j = 1
      let mut matched = true
      while j < length {
        let mut left = haystack.unsafe_get(i + j).to_int()
        let right = needle.unsafe_get(j).to_int()
        if left >= 65 && left <= 90 {
          left = left + 32
        }
        if left != right {
          matched = false
          break
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
fn p3_is_parameter_boundary(value : UInt16) -> Bool {
  value == (' ' : UInt16) ||
  value == (';' : UInt16) ||
  value == ('\t' : UInt16)
}

///|
fn p3_header_parameter_fast(value : StringView, name : String) -> String? {
  let target = name.view()
  let name_length = name.length()
  let length = value.length()
  let mut start = 0
  let mut result : String? = None
  let mut done = false
  while !done {
    let index = match p3_find_lower_view(value, target, start) {
      Some(index) => index
      None => {
        done = true
        continue
      }
    }
    let after = index + name_length
    let at_boundary = index == 0 ||
      p3_is_parameter_boundary(value.unsafe_get(index - 1))
    if at_boundary && after < length && value.unsafe_get(after) == ('=' : UInt16) {
      let mut pos = after + 1
      while pos < length && value.unsafe_get(pos) == (' ' : UInt16) {
        pos = pos + 1
      }
      if pos < length && value.unsafe_get(pos) == ('"' : UInt16) {
        let quoted_start = pos + 1
        let mut end = quoted_start
        while end < length && value.unsafe_get(end) != ('"' : UInt16) {
          end = end + 1
        }
        result = Some(value[quoted_start:end].to_owned())
      } else {
        let mut end = pos
        while end < length && value.unsafe_get(end) != (';' : UInt16) {
          end = end + 1
        }
        result = Some(p3_trim_ascii_space(value[pos:end]).to_owned())
      }
      done = true
    } else {
      start = index + 1
    }
  }
  result
}

///|
fn p3_base64_encode_sb(data : Bytes) -> String {
  let length = data.length()
  if length == 0 {
    return ""
  }
  let alphabet : Bytes = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let builder = StringBuilder(size_hint=(length + 2) / 3 * 4)
  let mut i = 0
  while i + 3 <= length {
    let value = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    builder.write_char(alphabet[(value >> 18) & 63].to_int().unsafe_to_char())
    builder.write_char(alphabet[(value >> 12) & 63].to_int().unsafe_to_char())
    builder.write_char(alphabet[(value >> 6) & 63].to_int().unsafe_to_char())
    builder.write_char(alphabet[value & 63].to_int().unsafe_to_char())
    i = i + 3
  }
  let remaining = length - i
  if remaining == 1 {
    let value = data[i].to_int() << 16
    builder.write_char(alphabet[(value >> 18) & 63].to_int().unsafe_to_char())
    builder.write_char(alphabet[(value >> 12) & 63].to_int().unsafe_to_char())
    builder.write_string("==")
  } else if remaining == 2 {
    let value = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8)
    builder.write_char(alphabet[(value >> 18) & 63].to_int().unsafe_to_char())
    builder.write_char(alphabet[(value >> 12) & 63].to_int().unsafe_to_char())
    builder.write_char(alphabet[(value >> 6) & 63].to_int().unsafe_to_char())
    builder.write_char('=')
  }
  builder.to_string()
}

///|
fn p3_percent_hex(value : Int) -> Char {
  if value < 10 {
    (48 + value).unsafe_to_char()
  } else {
    (55 + value).unsafe_to_char()
  }
}

///|
fn p3_url_encode_sb(source : String) -> String {
  let view = source.view()
  let length = view.length()
  let mut start = 0
  while start < length {
    let code = view.unsafe_get(start).to_int()
    let unreserved = (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 45 ||
      code == 46 ||
      code == 95 ||
      code == 126
    if !unreserved {
      break
    }
    start = start + 1
  }
  if start == length {
    return source
  }
  let builder = StringBuilder(size_hint=length + 8)
  let mut p = 0
  while p < start {
    builder.write_char(view.unsafe_get(p).to_int().unsafe_to_char())
    p = p + 1
  }
  let mut i = start
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code < 0x80 {
      if (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 45 ||
        code == 46 ||
        code == 95 ||
        code == 126 {
        builder.write_char(code.unsafe_to_char())
      } else {
        builder.write_char('%')
        builder.write_char(p3_percent_hex(code / 16))
        builder.write_char(p3_percent_hex(code % 16))
      }
    } else if code < 0x800 {
      builder.write_char('%')
      builder.write_char(p3_percent_hex((0xC0 | (code >> 6)) / 16))
      builder.write_char(p3_percent_hex((0xC0 | (code >> 6)) % 16))
      builder.write_char('%')
      builder.write_char(p3_percent_hex((0x80 | (code & 0x3F)) / 16))
      builder.write_char(p3_percent_hex((0x80 | (code & 0x3F)) % 16))
    } else if code >= 0xD800 && code <= 0xDBFF {
      if i + 1 < length {
        let low = view.unsafe_get(i + 1).to_int()
        if low >= 0xDC00 && low <= 0xDFFF {
          let scalar = ((code - 0xD800) << 10) + (low - 0xDC00) + 0x10000
          let b0 = 0xF0 | (scalar >> 18)
          let b1 = 0x80 | ((scalar >> 12) & 0x3F)
          let b2 = 0x80 | ((scalar >> 6) & 0x3F)
          let b3 = 0x80 | (scalar & 0x3F)
          builder.write_char('%')
          builder.write_char(p3_percent_hex(b0 / 16))
          builder.write_char(p3_percent_hex(b0 % 16))
          builder.write_char('%')
          builder.write_char(p3_percent_hex(b1 / 16))
          builder.write_char(p3_percent_hex(b1 % 16))
          builder.write_char('%')
          builder.write_char(p3_percent_hex(b2 / 16))
          builder.write_char(p3_percent_hex(b2 % 16))
          builder.write_char('%')
          builder.write_char(p3_percent_hex(b3 / 16))
          builder.write_char(p3_percent_hex(b3 % 16))
          i = i + 2
          continue
        }
      }
      builder.write_string("%EF%BF%BD")
    } else if code >= 0xDC00 && code <= 0xDFFF {
      builder.write_string("%EF%BF%BD")
    } else {
      let b0 = 0xE0 | (code >> 12)
      let b1 = 0x80 | ((code >> 6) & 0x3F)
      let b2 = 0x80 | (code & 0x3F)
      builder.write_char('%')
      builder.write_char(p3_percent_hex(b0 / 16))
      builder.write_char(p3_percent_hex(b0 % 16))
      builder.write_char('%')
      builder.write_char(p3_percent_hex(b1 / 16))
      builder.write_char(p3_percent_hex(b1 % 16))
      builder.write_char('%')
      builder.write_char(p3_percent_hex(b2 / 16))
      builder.write_char(p3_percent_hex(b2 % 16))
    }
    i = i + 1
  }
  builder.to_string()
}

///|
fn p3_get_header_ignore_case(
  headers : Map[String, String],
  name : String,
) -> String? {
  match headers.get(name) {
    Some(value) => return Some(value)
    None => ()
  }
  let target = name.view()
  for key, value in headers {
    if key.view().equal_ignore_ascii_case(target) {
      return Some(value)
    }
  }
  None
}

///|
fn p3_parse_part_headers_fast(
  header_text : StringView,
) -> (Map[String, String], String?) {
  let headers : Map[String, String] = Map([], capacity=4)
  let mut disposition : String? = None
  let length = header_text.length()
  let mut pos = 0
  while pos <= length {
    let end = match header_text[pos:].find("\n") {
      Some(offset) => pos + offset
      None => length
    }
    let line_end = if end > pos &&
      header_text.unsafe_get(end - 1) == ('\r' : UInt16) {
      end - 1
    } else {
      end
    }
    if line_end > pos {
      let colon = match header_text[pos:line_end].find(":") {
        Some(offset) => pos + offset
        None => -1
      }
      if colon >= 0 {
        let name = p3_owned_trimmed(header_text[pos:colon])
        let value = p3_owned_trimmed(header_text[colon + 1:line_end])
        if name != "" {
          headers.set(name, value)
          if name.view().equal_ignore_ascii_case("Content-Disposition".view()) {
            disposition = Some(value)
          }
        }
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  (headers, disposition)
}

///|
fn p3_parse_multipart_fast(
  body : String,
  content_type : String,
) -> Array[MultipartPart]? {
  let boundary = match multipart_boundary(content_type) {
    Some(boundary) if boundary != "" => boundary
    _ => return None
  }
  let delimiter = "--" + boundary
  let delimiter_view = delimiter.view()
  let delimiter_length = delimiter.length()
  let crlf_delimiter = "\r\n" + delimiter
  let crlf_delimiter_view = crlf_delimiter.view()
  let lf_delimiter = "\n" + delimiter
  let lf_delimiter_view = lf_delimiter.view()
  let crlfcrlf_view = "\r\n\r\n".view()
  let lflf_view = "\n\n".view()
  let view = body.view()
  let mut pos = match p3_find_terminated_delimiter(view, delimiter_view, 0) {
    Some(index) => index + delimiter_length
    None => return Some([])
  }
  let estimate = body.length() / (crlf_delimiter.length() + 8)
  let parts : Array[MultipartPart] = Array(
    capacity=if estimate > 64 { 64 } else { estimate + 1 },
  )
  while pos <= view.length() {
    if pos + 1 < view.length() &&
      view.unsafe_get(pos) == ('-' : UInt16) &&
      view.unsafe_get(pos + 1) == ('-' : UInt16) {
      break
    }
    if pos + 1 < view.length() &&
      view.unsafe_get(pos) == ('\r' : UInt16) &&
      view.unsafe_get(pos + 1) == ('\n' : UInt16) {
      pos = pos + 2
    } else if pos < view.length() && view.unsafe_get(pos) == ('\n' : UInt16) {
      pos = pos + 1
    }
    let data_end = match p3_find_terminated_delimiter(view, crlf_delimiter_view, pos) {
      Some(index) => index
      None =>
        match p3_find_terminated_delimiter(view, lf_delimiter_view, pos) {
          Some(index) => index
          None => break
        }
    }
    let header_end = match p3_find_view_from(view, crlfcrlf_view, pos) {
      Some(index) => index
      None =>
        match p3_find_view_from(view, lflf_view, pos) {
          Some(index) => index
          None => break
        }
    }
    if header_end >= data_end {
      break
    }
    let separator_length = if view.unsafe_get(header_end) == ('\r' : UInt16) {
      4
    } else {
      2
    }
    if header_end + separator_length > data_end {
      break
    }
    let (headers, disposition) = p3_parse_part_headers_fast(view[pos:header_end])
    let data = view[header_end + separator_length:data_end]
    let mut name = ""
    let mut filename = ""
    match disposition {
      Some(disposition) => {
        name = match p3_header_parameter_fast(disposition.view(), "name") {
          Some(value) => value
          None => ""
        }
        filename = match p3_header_parameter_fast(disposition.view(), "filename") {
          Some(value) => value
          None => ""
        }
      }
      None => ()
    }
    let part_content_type = match p3_get_header_ignore_case(headers, "Content-Type") {
      Some(value) => value
      None => ""
    }
    parts.push({
      name,
      filename,
      content_type: part_content_type,
      headers,
      data: data.to_owned(),
    })
    pos = data_end
    if pos + 1 < view.length() &&
      view.unsafe_get(pos) == ('\r' : UInt16) &&
      view.unsafe_get(pos + 1) == ('\n' : UInt16) {
      pos = pos + 2
    } else if pos < view.length() && view.unsafe_get(pos) == ('\n' : UInt16) {
      pos = pos + 1
    }
    pos = pos + delimiter_length
  }
  Some(parts)
}

///|
fn p3_build_multipart_body(parts_count : Int) -> (String, String) {
  let boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
  let mut body = ""
  for i = 0; i < parts_count; i = i + 1 {
    body = body +
      "--" +
      boundary +
      "\r\nContent-Disposition: form-data; name=\"field" +
      i.to_string() +
      "\"\r\n\r\nvalue-value-value-value-" +
      i.to_string() +
      "\r\n"
  }
  body = body + "--" + boundary + "--\r\n"
  (body, "multipart/form-data; boundary=" + boundary)
}

///|
fn p3_parse_part_headers_scan(
  header_text : StringView,
) -> (Map[String, String], String?) {
  let headers : Map[String, String] = Map([], capacity=4)
  let mut disposition : String? = None
  let length = header_text.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    let mut colon = -1
    while end < length {
      let code = header_text.unsafe_get(end)
      if code == ('\n' : UInt16) {
        break
      }
      if code == (':' : UInt16) && colon < 0 {
        colon = end
      }
      end = end + 1
    }
    let line_end = if end > pos &&
      header_text.unsafe_get(end - 1) == ('\r' : UInt16) {
      end - 1
    } else {
      end
    }
    if line_end > pos && colon >= 0 && colon < line_end {
      let name = p3_owned_trimmed(header_text[pos:colon])
      let value = p3_owned_trimmed(header_text[colon + 1:line_end])
      if name != "" {
        headers.set(name, value)
        if name.view().equal_ignore_ascii_case("Content-Disposition".view()) {
          disposition = Some(value)
        }
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  (headers, disposition)
}

///|
fn p3_find_ci_new(
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
  let lower_first = if first >= 65 && first <= 90 {
    first + 32
  } else {
    first
  }
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
          let mut lower_left = left
          if lower_left >= 65 && lower_left <= 90 {
            lower_left = lower_left + 32
          }
          let mut lower_right = right
          if lower_right >= 65 && lower_right <= 90 {
            lower_right = lower_right + 32
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
fn p3_find_ci_old(
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
  let lower_first = if first >= 65 && first <= 90 {
    first + 32
  } else {
    first
  }
  let mut i = start
  while i <= last {
    let value = haystack.unsafe_get(i).to_int()
    let lower_value = if value >= 65 && value <= 90 {
      value + 32
    } else {
      value
    }
    if lower_value == lower_first {
      let mut j = 1
      let mut matched = true
      while j < length {
        let mut left = haystack.unsafe_get(i + j).to_int()
        let mut right = needle.unsafe_get(j).to_int()
        if left >= 65 && left <= 90 {
          left = left + 32
        }
        if right >= 65 && right <= 90 {
          right = right + 32
        }
        if left != right {
          matched = false
          break
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
test "p3-timings" {
  let req : Request = {
    method: "GET",
    path: "/api/users",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  ignore(Context::new(req))
  p3_time("ctx-new-current", 300000, fn() {
    ignore(Context::new(req))
  })
  p3_time("ctx-new-json0", 300000, fn() {
    ignore(p3_bench_ctx_new_variant(4, 4, 0, req))
  })
  p3_time("ctx-new-slim", 300000, fn() {
    ignore(p3_bench_ctx_new_variant(2, 2, 2, req))
  })
  p3_time("map-alloc-c0", 500000, fn() {
    let m : Map[String, String] = Map([], capacity=0)
    ignore(m)
  })
  p3_time("map-alloc-c1", 500000, fn() {
    let m : Map[String, String] = Map([], capacity=1)
    ignore(m)
  })
  p3_time("map-alloc-c2", 500000, fn() {
    let m : Map[String, String] = Map([], capacity=2)
    ignore(m)
  })
  p3_time("map-alloc-c4", 500000, fn() {
    let m : Map[String, String] = Map([], capacity=4)
    ignore(m)
  })
  p3_time("empty-array-alloc", 500000, fn() {
    let a : Array[String] = []
    ignore(a)
  })
  let ctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      (
        "Cookie",
        "session=abcdef123456; theme=dark; lang=en-US; tracking=xyz987654321",
      ),
    ]),
    body: "",
  })
  let cookie_header = ctx.header("Cookie")
  p3_time("cookies-current", 200000, fn() {
    ignore(ctx.cookies())
  })
  p3_time("cookies-direct", 200000, fn() {
    ignore(p3_cookies_fast(cookie_header.view()))
  })
  p3_time("mp-boundary-current", 300000, fn() {
    ignore(
      multipart_boundary(
        "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW",
      ),
    )
  })
  p3_time("mp-boundary-fast", 300000, fn() {
    ignore(
      p3_header_parameter_fast(
        "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW".view(),
        "boundary",
      ),
    )
  })
  let payload = @utf8.encode("hello world, this is a test payload for base64")
  ignore(base64_encode(payload))
  p3_time("b64-current", 500000, fn() {
    ignore(base64_encode(payload))
  })
  p3_time("b64-sb", 500000, fn() {
    ignore(p3_base64_encode_sb(payload))
  })
  let url_src = "hello world/foo bar?baz=qux&name=\u{4e16}\u{754c}"
  ignore(url_encode(url_src))
  p3_time("url-encode-current", 500000, fn() {
    ignore(url_encode(url_src))
  })
  p3_time("url-encode-sb", 500000, fn() {
    ignore(p3_url_encode_sb(url_src))
  })
  let (body, ct) = p3_build_multipart_body(8)
  ignore(parse_multipart(body, ct))
  p3_time("multipart-current", 20000, fn() {
    ignore(parse_multipart(body, ct))
  })
  p3_time("multipart-fast", 20000, fn() {
    ignore(p3_parse_multipart_fast(body, ct))
  })
  p3_time("ctx-new-current-2", 300000, fn() {
    ignore(Context::new(req))
  })
  p3_time("ctx-new-slim-2", 300000, fn() {
    ignore(p3_bench_ctx_new_variant(2, 2, 2, req))
  })
  p3_time("ctx-new-current-3", 300000, fn() {
    ignore(Context::new(req))
  })
  p3_time("cookies-current-2", 200000, fn() {
    ignore(ctx.cookies())
  })
  p3_time("cookies-direct-2", 200000, fn() {
    ignore(p3_cookies_fast(cookie_header.view()))
  })
  p3_time("cookies-current-3", 200000, fn() {
    ignore(ctx.cookies())
  })
  p3_time("mp-boundary-current-2", 300000, fn() {
    ignore(
      multipart_boundary(
        "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW",
      ),
    )
  })
  p3_time("mp-boundary-fast-2", 300000, fn() {
    ignore(
      p3_header_parameter_fast(
        "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW".view(),
        "boundary",
      ),
    )
  })
  p3_time("mp-boundary-current-3", 300000, fn() {
    ignore(
      multipart_boundary(
        "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW",
      ),
    )
  })
  let part_header = "Content-Disposition: form-data; name=\"field\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\nX-Empty:\r\nNoColonLine\r\n"
  ignore(p3_parse_part_headers_fast(part_header.view()))
  p3_time("part-headers-find", 500000, fn() {
    ignore(p3_parse_part_headers_fast(part_header.view()))
  })
  p3_time("part-headers-scan", 500000, fn() {
    ignore(p3_parse_part_headers_scan(part_header.view()))
  })
  p3_time("part-headers-find-2", 500000, fn() {
    ignore(p3_parse_part_headers_fast(part_header.view()))
  })
  p3_time("part-headers-scan-2", 500000, fn() {
    ignore(p3_parse_part_headers_scan(part_header.view()))
  })
  let ci_hay = "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW".view()
  let ci_needle = "BOUNDARY".view()
  ignore(p3_find_ci_new(ci_hay, ci_needle, 0))
  p3_time("find-ci-new", 500000, fn() {
    ignore(p3_find_ci_new(ci_hay, ci_needle, 0))
  })
  p3_time("find-ci-old", 500000, fn() {
    ignore(p3_find_ci_old(ci_hay, ci_needle, 0))
  })
  p3_time("find-ci-new-2", 500000, fn() {
    ignore(p3_find_ci_new(ci_hay, ci_needle, 0))
  })
  p3_time("find-ci-old-2", 500000, fn() {
    ignore(p3_find_ci_old(ci_hay, ci_needle, 0))
  })
  let qctx = Context::new({
    method: "GET",
    path: "/search?q=hello&page=2&sort=desc&filter=active",
    headers: Map([]),
    body: "",
  })
  ignore(qctx.queries())
  p3_time("queries-current", 300000, fn() {
    ignore(qctx.queries())
  })
  p3_time("query-param-current", 300000, fn() {
    ignore(qctx.query("filter"))
  })
  p3_time("parse-urlencoded-current", 300000, fn() {
    ignore(parse_urlencoded("q=hello&page=2&sort=desc&filter=active"))
  })
  p3_time("queries-current-2", 300000, fn() {
    ignore(qctx.queries())
  })
  let hmctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Header", "value")]),
    body: "",
  })
  p3_time("header-miss-only", 500000, fn() {
    ignore(hmctx.header("Missing-Key"))
  })
  p3_time("header-hit-only", 500000, fn() {
    ignore(hmctx.header("Header"))
  })
  p3_time("header-fallback-hit", 500000, fn() {
    ignore(hmctx.header("header"))
  })
  p3_time("req-map-literal", 500000, fn() {
    let r : Request = {
      method: "GET",
      path: "/",
      headers: Map([("Header", "value")]),
      body: "",
    }
    ignore(r)
  })
  p3_time("ctx-new-plus-miss", 500000, fn() {
    let ctx = Context::new({
      method: "GET",
      path: "/",
      headers: Map([("Header", "value")]),
      body: "",
    })
    ignore(ctx.header("Missing-Key"))
  })
}
