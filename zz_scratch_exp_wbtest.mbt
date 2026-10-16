///|
fn wb_time(name : String, iterations : Int, f : () -> Unit) -> Unit {
  for i = 0; i < 200; i = i + 1 {
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
fn wb_make_body() -> (String, String) {
  let boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
  let mut body = ""
  for i = 0; i < 8; i = i + 1 {
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
fn wb_find_view_from(
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
  let mut i = start
  let view = haystack
  while i + length <= view.length() {
    if view.unsafe_get(i) == needle.unsafe_get(0) {
      let mut j = 1
      let mut ok = true
      while j < length {
        if view.unsafe_get(i + j) != needle.unsafe_get(j) {
          ok = false
          break
        }
        j = j + 1
      }
      if ok {
        return Some(i)
      }
    }
    i = i + 1
  }
  None
}

///|
fn wb_parse_part_headers(
  header_text : StringView,
) -> (Map[String, String], String?, Int, String?, Int) {
  let headers : Map[String, String] = Map([], capacity=4)
  let mut disposition : String? = None
  let mut disposition_matches = 0
  let mut content_type : String? = None
  let mut content_type_matches = 0
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
      let name = trim_ascii_space(header_text[pos:colon]).to_owned()
      let value = trim_ascii_space(header_text[colon + 1:line_end]).to_owned()
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
    headers,
    disposition,
    disposition_matches,
    content_type,
    content_type_matches,
  )
}

///|
fn wb_make_body_single() -> (String, String) {
  let boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
  let body = "--" +
    boundary +
    "\r\nContent-Disposition: form-data; name=\"field0\"\r\n\r\nvalue-value-value-value-0\r\n--" +
    boundary +
    "--\r\n"
  (body, "multipart/form-data; boundary=" + boundary)
}

///|
fn wb_cookies(header0 : String, capacity : Int) -> Map[String, String] {
  let cookies : Map[String, String] = Map([], capacity~)
  let header = header0.view()
  let length = header.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    while end < length && header.unsafe_get(end) != (';' : UInt16) {
      end = end + 1
    }
    let pair = trim_ascii_space(header[pos:end])
    if !pair.is_empty() {
      let pair_length = pair.length()
      let mut eq = 0
      while eq < pair_length && pair.unsafe_get(eq) != ('=' : UInt16) {
        eq = eq + 1
      }
      if eq < pair_length {
        let name = owned_trimmed(pair[:eq])
        if name != "" {
          let raw_value = pair[eq + 1:]
          let value = if raw_value.length() >= 2 &&
            raw_value.unsafe_get(0) == ('"' : UInt16) &&
            raw_value.unsafe_get(raw_value.length() - 1) == ('"' : UInt16) {
            raw_value[1:raw_value.length() - 1].to_owned()
          } else {
            raw_value.to_owned()
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
fn wb_cookies_counted(header0 : String) -> Map[String, String] {
  let header = header0.view()
  let length = header.length()
  let mut semis = 0
  for i = 0; i < length; i = i + 1 {
    if header.unsafe_get(i) == (';' : UInt16) {
      semis = semis + 1
    }
  }
  wb_cookies(header0, semis + 1)
}

///|
fn wb_parse_part_headers_find(
  header_text : StringView,
) -> (Map[String, String], String?, Int, String?, Int) {
  let headers : Map[String, String] = Map([], capacity=4)
  let mut disposition : String? = None
  let mut disposition_matches = 0
  let mut content_type : String? = None
  let mut content_type_matches = 0
  let length = header_text.length()
  let mut pos = 0
  while pos <= length {
    let end = match header_text[pos:].find("\n") {
      Some(offset) => pos + offset
      None => length
    }
    let colon = match header_text[pos:end].find(":") {
      Some(offset) => pos + offset
      None => -1
    }
    let line_end = if end > pos &&
      header_text.unsafe_get(end - 1) == ('\r' : UInt16) {
      end - 1
    } else {
      end
    }
    if line_end > pos && colon >= 0 && colon < line_end {
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
    headers,
    disposition,
    disposition_matches,
    content_type,
    content_type_matches,
  )
}

///|
fn wb_decode_only(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
fn wb_decode_strict_then_lossy(bytes : Bytes) -> String {
  try @utf8.decode(bytes) catch {
    _ => @utf8.decode_lossy(bytes)
  }
}

///|
fn wb_decode_url_v2(source : StringView, plus_as_space : Bool) -> String {
  let length = source.length()
  let mut needs = false
  let mut i = 0
  while i < length {
    let v = source.unsafe_get(i).to_int()
    if v == 37 || (v == 43 && plus_as_space) || v > 127 {
      needs = true
      break
    }
    i = i + 1
  }
  if !needs {
    return source.to_owned()
  }
  let buffer = @buffer.Buffer::Buffer(size_hint=length)
  let bytes = @utf8.encode(source)
  let mut i = 0
  while i < bytes.length() {
    let byte = bytes[i]
    if byte == b'%' && i + 2 < bytes.length() {
      let high = hex_digit(bytes[i + 1].to_int())
      let low = hex_digit(bytes[i + 2].to_int())
      if high >= 0 && low >= 0 {
        buffer.write_byte((high * 16 + low).to_byte())
        i = i + 2
      } else {
        buffer.write_byte(byte)
      }
    } else if byte == b'+' && plus_as_space {
      buffer.write_byte(b' ')
    } else {
      buffer.write_byte(byte)
    }
    i = i + 1
  }
  @utf8.decode_lossy(buffer.to_bytes())
}

///|
fn wb_decode_url_v3(source : StringView, plus_as_space : Bool) -> String {
  let buffer = @buffer.Buffer::Buffer(size_hint=source.length() + 8)
  let mut changed = false
  let mut i = 0
  let bytes = @utf8.encode(source)
  while i < bytes.length() {
    let byte = bytes[i]
    if byte == b'%' && i + 2 < bytes.length() {
      let high = hex_digit(bytes[i + 1].to_int())
      let low = hex_digit(bytes[i + 2].to_int())
      if high >= 0 && low >= 0 {
        buffer.write_byte((high * 16 + low).to_byte())
        changed = true
        i = i + 3
        continue
      }
      buffer.write_byte(byte)
    } else if byte == b'+' && plus_as_space {
      buffer.write_byte(b' ')
      changed = true
    } else {
      buffer.write_byte(byte)
    }
    i = i + 1
  }
  if !changed {
    return source.to_owned()
  }
  @utf8.decode_lossy(buffer.to_bytes())
}

///|
test "scratch-wb-experiments" {
  let (body, content_type) = wb_make_body()
  ignore(parse_multipart(body, content_type))
  wb_time("parse-multipart-8", 20000, fn() {
    ignore(parse_multipart(body, content_type))
  })
  wb_time("parse-part-headers-cur", 200000, fn() {
    ignore(parse_part_headers("Content-Disposition: form-data; name=\"field0\"".view()))
  })
  wb_time("parse-part-headers-trim", 200000, fn() {
    ignore(
      wb_parse_part_headers(
        "Content-Disposition: form-data; name=\"field0\"".view(),
      ),
    )
  })
  let delim = "\r\n----WebKitFormBoundary7MA4YWxkTrZu0gW"
  wb_time("parse-part-headers-find", 200000, fn() {
    ignore(
      wb_parse_part_headers_find(
        "Content-Disposition: form-data; name=\"field0\"".view(),
      ),
    )
  })
  let (body1, ct1) = wb_make_body_single()
  wb_time("parse-multipart-1", 20000, fn() {
    ignore(parse_multipart(body1, ct1))
  })
  let url_src = "name=%E4%B8%96%E7%95%8C+test%20foo%2Fbar&x=1"
  let url_ascii = "name=%20hello%2Fworld+test&x=1"
  wb_time("url-decode-cur", 300000, fn() {
    ignore(decode_url(url_src.view()))
  })
  wb_time("url-decode-v2", 300000, fn() {
    ignore(wb_decode_url_v2(url_src.view(), true))
  })
  wb_time("url-decode-v3", 300000, fn() {
    ignore(wb_decode_url_v3(url_src.view(), true))
  })
  wb_time("url-decode-cur-ascii", 300000, fn() {
    ignore(decode_url(url_ascii.view()))
  })
  wb_time("url-decode-v2-ascii", 300000, fn() {
    ignore(wb_decode_url_v2(url_ascii.view(), true))
  })
  wb_time("url-decode-v3-ascii", 300000, fn() {
    ignore(wb_decode_url_v3(url_ascii.view(), true))
  })
  let decoded_bytes = @utf8.encode("name=\u{4e16}\u{754c} test foo/bar&x=1")
  wb_time("decode-lossy", 500000, fn() {
    ignore(wb_decode_only(decoded_bytes))
  })
  wb_time("decode-strict-fb", 500000, fn() {
    ignore(wb_decode_strict_then_lossy(decoded_bytes))
  })
  wb_time("find-delim-cur", 200000, fn() {
    ignore(find_terminated_delimiter(body.view(), delim.view(), 0))
  })
  wb_time("find-delim-manual", 200000, fn() {
    ignore(wb_find_view_from(body.view(), delim.view(), 0))
  })
  wb_time("mp-boundary", 500000, fn() {
    ignore(multipart_boundary(content_type))
  })
  wb_time("mp-header-param", 500000, fn() {
    ignore(header_parameter("form-data; name=\"field0\"".view(), "name"))
  })
  wb_time("mp-header-param-miss", 500000, fn() {
    ignore(header_parameter("form-data; name=\"field0\"".view(), "filename"))
  })
  wb_time("mp-owned-trimmed", 500000, fn() {
    ignore(owned_trimmed(" Content-Disposition ".view()))
  })
  wb_time("mp-trim-owned", 500000, fn() {
    ignore(trim_ascii_space(" Content-Disposition ".view()).to_owned())
  })
  let cookie_header = "session=abcdef123456; theme=dark; lang=en-US; tracking=xyz987654321"
  wb_time("map-alloc-cap4", 1000000, fn() {
    ignore((Map([], capacity=4) : Map[String, String]))
  })
  wb_time("map-alloc-cap8", 1000000, fn() {
    ignore((Map([], capacity=8) : Map[String, String]))
  })
  wb_time("cookies-1cap4", 300000, fn() {
    ignore(wb_cookies("session=abcdef123456", 4))
  })
  wb_time("cookies-1cap8", 300000, fn() {
    ignore(wb_cookies("session=abcdef123456", 8))
  })
  wb_time("cookies-2cap4", 300000, fn() {
    ignore(wb_cookies("session=abcdef123456; theme=dark", 4))
  })
  wb_time("cookies-2cap8", 300000, fn() {
    ignore(wb_cookies("session=abcdef123456; theme=dark", 8))
  })
  wb_time("cookies-cap4", 300000, fn() {
    ignore(wb_cookies(cookie_header, 4))
  })
  wb_time("cookies-cap8", 300000, fn() {
    ignore(wb_cookies(cookie_header, 8))
  })
  wb_time("cookies-cap16", 300000, fn() {
    ignore(wb_cookies(cookie_header, 16))
  })
  wb_time("cookies-counted", 300000, fn() {
    ignore(wb_cookies_counted(cookie_header))
  })
  wb_time("cookies-cur", 200000, fn() {
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
    ignore(ctx.cookies())
  })
  wb_time("get-header-ci", 500000, fn() {
    let headers : Map[String, String] = Map([
      ("Content-Disposition", "form-data; name=\"field0\""),
    ])
    ignore(get_header_ignore_case(headers, "Content-Type"))
  })
  let one : Map[String, String] = Map([("Content-Disposition", "x")])
  let four : Map[String, String] = Map([
    ("Host", "a"),
    ("Accept", "b"),
    ("User-Agent", "c"),
    ("Cookie", "d"),
  ])
  wb_time("map-iter1-only", 1000000, fn() {
    let mut n = 0
    for _, _ in one {
      n = n + 1
    }
    ignore(n)
  })
  wb_time("map-iter4-only", 1000000, fn() {
    let mut n = 0
    for _, _ in four {
      n = n + 1
    }
    ignore(n)
  })
  wb_time("map-get-exact", 1000000, fn() {
    ignore(one.get("Content-Disposition"))
  })
  wb_time("map-get-lower-miss", 1000000, fn() {
    ignore(one.get("content-disposition"))
  })
  wb_time("map-get-case-miss", 1000000, fn() {
    ignore(four.get("content-disposition"))
  })
  wb_time("equal-ci-19", 1000000, fn() {
    ignore("Content-Disposition".view().equal_ignore_ascii_case("content-disposition".view()))
  })
  wb_time("header-miss", 500000, fn() {
    let ctx = Context::new({
      method: "GET",
      path: "/",
      headers: Map([("Header", "value")]),
      body: "",
    })
    ignore(ctx.header("Missing-Key"))
  })
}
