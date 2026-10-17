///|
let zopt_report : Ref[String] = Ref("")

///|
fn zopt_time(name : String, iterations : Int, f : () -> Unit) -> Unit {
  for i = 0; i < 200; i = i + 1 {
    f()
  }
  let start = @async.now()
  for i = 0; i < iterations; i = i + 1 {
    f()
  }
  let elapsed = @async.now() - start
  zopt_report.val = zopt_report.val + "\{name}: \{elapsed}ms/\{iterations}; "
}

///|
fn zopt_trim_ascii_space(view : StringView) -> StringView {
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
fn zopt_owned_trimmed(view : StringView) -> String {
  let trimmed = zopt_trim_ascii_space(view)
  let offset = trimmed.start_offset()
  trimmed.data().unsafe_substring(start=offset, end=offset + trimmed.length())
}

///|
fn zopt_find_lower_view(
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
fn zopt_is_parameter_boundary(value : UInt16) -> Bool {
  value == (' ' : UInt16) ||
  value == (';' : UInt16) ||
  value == ('\t' : UInt16)
}

///|
fn zopt_header_parameter_fast(value : StringView, name : String) -> String? {
  let target = name.view()
  let name_length = name.length()
  let length = value.length()
  let mut start = 0
  let mut result : String? = None
  let mut done = false
  while !done {
    let index = match zopt_find_lower_view(value, target, start) {
      Some(index) => index
      None => {
        done = true
        continue
      }
    }
    let after = index + name_length
    let at_boundary = index == 0 ||
      zopt_is_parameter_boundary(value.unsafe_get(index - 1))
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
        result = Some(zopt_trim_ascii_space(value[pos:end]).to_owned())
      }
      done = true
    } else {
      start = index + 1
    }
  }
  result
}

///|
fn zopt_parse_part_headers_scan(
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
      let name = zopt_owned_trimmed(header_text[pos:colon])
      let value = zopt_owned_trimmed(header_text[colon + 1:line_end])
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
fn zopt_find_view_from(
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
fn zopt_delimiter_is_terminated(view : StringView, after : Int32) -> Bool {
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
fn zopt_find_terminated_delimiter(
  view : StringView,
  needle : StringView,
  start : Int32,
) -> Int32? {
  let needle_length = needle.length()
  let mut search = start
  while search <= view.length() - needle_length {
    let index = match zopt_find_view_from(view, needle, search) {
      Some(index) => index
      None => return None
    }
    if zopt_delimiter_is_terminated(view, index + needle_length) {
      return Some(index)
    }
    search = index + 1
  }
  None
}

///|
fn zopt_get_header_ignore_case(
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
fn zopt_parse_multipart_fast(
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
  let mut pos = match zopt_find_terminated_delimiter(view, delimiter_view, 0) {
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
    let data_end = match zopt_find_terminated_delimiter(
      view,
      crlf_delimiter_view,
      pos,
    ) {
      Some(index) => index
      None =>
        match zopt_find_terminated_delimiter(view, lf_delimiter_view, pos) {
          Some(index) => index
          None => break
        }
    }
    let header_end = match zopt_find_view_from(view, crlfcrlf_view, pos) {
      Some(index) => index
      None =>
        match zopt_find_view_from(view, lflf_view, pos) {
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
    let (headers, disposition) = zopt_parse_part_headers_scan(view[pos:header_end])
    let data = view[header_end + separator_length:data_end]
    let mut name = ""
    let mut filename = ""
    match disposition {
      Some(disposition) => {
        name = match zopt_header_parameter_fast(disposition.view(), "name") {
          Some(value) => value
          None => ""
        }
        filename = match zopt_header_parameter_fast(disposition.view(), "filename") {
          Some(value) => value
          None => ""
        }
      }
      None => ()
    }
    let part_content_type = match zopt_get_header_ignore_case(headers, "Content-Type") {
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
fn zopt_build_multipart_body(parts_count : Int) -> (String, String) {
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
fn zopt_cookies_direct(header : StringView) -> Map[String, String] {
  parse_cookie_map(header)
}

///|
test "zopt-timings" {
  let req : Request = {
    method: "GET",
    path: "/api/users",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  zopt_time("ctx-new", 1000, fn() {
    ignore(Context::new(req))
  })
  let ct = "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW"
  zopt_time("mp-boundary-current", 1000, fn() {
    ignore(multipart_boundary(ct))
  })
  zopt_time("mp-boundary-fast", 1000, fn() {
    ignore(zopt_header_parameter_fast(ct.view(), "boundary"))
  })
  let part_header = "Content-Disposition: form-data; name=\"field\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\nX-Empty:\r\nNoColonLine\r\n"
  zopt_time("part-headers-current", 1000, fn() {
    ignore(parse_part_headers(part_header.view()))
  })
  zopt_time("part-headers-scan", 1000, fn() {
    ignore(zopt_parse_part_headers_scan(part_header.view()))
  })
  let ci_hay = "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW".view()
  let ci_needle = "BOUNDARY".view()
  zopt_time("find-ci-current", 1000, fn() {
    ignore(find_view_ignore_ascii_case(ci_hay, ci_needle, 0))
  })
  zopt_time("find-ci-lower", 1000, fn() {
    ignore(zopt_find_lower_view(ci_hay, ci_needle, 0))
  })
  let (body8, ct8) = zopt_build_multipart_body(8)
  zopt_time("multipart-current", 200, fn() {
    ignore(parse_multipart(body8, ct8))
  })
  zopt_time("multipart-fast", 200, fn() {
    ignore(zopt_parse_multipart_fast(body8, ct8))
  })
  let cookie_ctx = Context::new({
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
  zopt_time("cookies-current", 1000, fn() {
    ignore(cookie_ctx.cookies())
  })
  let cookie_header = cookie_ctx.header("Cookie")
  zopt_time("cookies-direct", 1000, fn() {
    ignore(zopt_cookies_direct(cookie_header.view()))
  })
  let hmctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Header", "value")]),
    body: "",
  })
  zopt_time("header-miss", 10000, fn() {
    ignore(hmctx.header("Missing-Key"))
  })
  zopt_time("header-hit", 10000, fn() {
    ignore(hmctx.header("Header"))
  })
  let qctx = Context::new({
    method: "GET",
    path: "/search?q=hello&page=2&sort=desc&filter=active",
    headers: Map([]),
    body: "",
  })
  zopt_time("queries-copy", 1000, fn() {
    ignore(qctx.queries())
  })
  zopt_time("query-param", 1000, fn() {
    ignore(qctx.query("filter"))
  })
  let url_src = "hello world/foo bar?baz=qux&name=\u{4e16}\u{754c}"
  zopt_time("url-encode-current", 1000, fn() {
    ignore(url_encode(url_src))
  })
  let payload = @utf8.encode("hello world, this is a test payload for base64")
  zopt_time("b64-encode-current", 1000, fn() {
    ignore(base64_encode(payload))
  })
  zopt_report.val = zopt_report.val + "END"
  assert_true(zopt_report.val.length() > 0)
}
