///|
fn tmp_write_two_digits(builder : StringBuilder, value : Int) -> Unit {
  if value >= 0 && value < 100 {
    if value < 10 {
      builder.write_char('0')
    } else {
      builder.write_char((48 + value / 10).unsafe_to_char())
    }
    builder.write_char((48 + value % 10).unsafe_to_char())
  } else if value < 10 {
    builder.write_char('0')
    builder.write_string(value.to_string())
  } else {
    builder.write_string(value.to_string())
  }
}

///|
fn tmp_write_year(builder : StringBuilder, year : Int64) -> Unit {
  if year >= 0L && year < 10000L {
    let y = year.to_int()
    builder.write_char((48 + y / 1000).unsafe_to_char())
    builder.write_char((48 + y / 100 % 10).unsafe_to_char())
    builder.write_char((48 + y / 10 % 10).unsafe_to_char())
    builder.write_char((48 + y % 10).unsafe_to_char())
  } else {
    builder.write_string(year.to_string())
  }
}

///|
fn tmp_civil_from_days(days : Int64) -> (Int64, Int, Int) {
  if days < -1000000000L || days > 1000000000L {
    return civil_from_days(days)
  }
  let z = days.to_int() + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let day = doy - (153 * mp + 2) / 5 + 1
  let month = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = if month <= 2 { y + 1 } else { y }
  (year.to_int64(), month, day)
}

///|
fn tmp_format_http_date(unix_seconds : Int64) -> String {
  let mut days = unix_seconds / 86400L
  let mut time_of_day = unix_seconds - days * 86400L
  if time_of_day < 0L {
    days = days - 1L
    time_of_day = time_of_day + 86400L
  }
  let (year, month, day) = tmp_civil_from_days(days)
  let weekday = ((days + 4L) % 7L + 7L) % 7L
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  if time_of_day >= 0L && time_of_day < 86400L {
    let tod = time_of_day.to_int()
    hour = tod / 3600
    minute = tod % 3600 / 60
    second = tod % 60
  } else {
    hour = (time_of_day / 3600L).to_int()
    minute = ((time_of_day % 3600L) / 60L).to_int()
    second = (time_of_day % 60L).to_int()
  }
  let builder = StringBuilder(size_hint=29)
  builder.write_string(http_weekdays[weekday.to_int()])
  builder.write_string(", ")
  tmp_write_two_digits(builder, day)
  builder.write_char(' ')
  builder.write_string(http_months[month - 1])
  builder.write_char(' ')
  tmp_write_year(builder, year)
  builder.write_char(' ')
  tmp_write_two_digits(builder, hour)
  builder.write_char(':')
  tmp_write_two_digits(builder, minute)
  builder.write_char(':')
  tmp_write_two_digits(builder, second)
  builder.write_string(" GMT")
  builder.to_string()
}

///|
let tmp_b64_table : Bytes = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
fn tmp_base64_encode_bytes(data : Bytes) -> String {
  let length = data.length()
  if length == 0 {
    return ""
  }
  let table = tmp_b64_table
  let builder = StringBuilder(size_hint=(length + 2) / 3 * 4)
  let mut i = 0
  while i + 3 <= length {
    let value = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    builder.write_char(table[(value >> 18) & 63].to_int().unsafe_to_char())
    builder.write_char(table[(value >> 12) & 63].to_int().unsafe_to_char())
    builder.write_char(table[(value >> 6) & 63].to_int().unsafe_to_char())
    builder.write_char(table[value & 63].to_int().unsafe_to_char())
    i = i + 3
  }
  let remaining = length - i
  if remaining == 1 {
    let value = data[i].to_int() << 16
    builder.write_char(table[(value >> 18) & 63].to_int().unsafe_to_char())
    builder.write_char(table[(value >> 12) & 63].to_int().unsafe_to_char())
    builder.write_string("==")
  } else if remaining == 2 {
    let value = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8)
    builder.write_char(table[(value >> 18) & 63].to_int().unsafe_to_char())
    builder.write_char(table[(value >> 12) & 63].to_int().unsafe_to_char())
    builder.write_char(table[(value >> 6) & 63].to_int().unsafe_to_char())
    builder.write_char('=')
  }
  builder.to_string()
}

///|
test "tmp2-format-date-fast" (b : @bench.T) {
  b.bench(() => {
    b.keep(tmp_format_http_date(1750000000L))
  })
}

///|
test "tmp2-base64-encode-bytes" (b : @bench.T) {
  let data = @utf8.encode("hello world, this is a test payload for base64")
  b.bench(() => {
    b.keep(tmp_base64_encode_bytes(data))
  })
}

///|
test "tmp3-multipart-boundary" (b : @bench.T) {
  b.bench(() => {
    b.keep(multipart_boundary("multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW"))
  })
}

///|
test "tmp3-find-delim" (b : @bench.T) {
  let body = "--B\r\nContent-Disposition: form-data; name=\"field0\"\r\n\r\nvalue-value-value-value-0\r\n--B\r\nContent-Disposition: form-data; name=\"field1\"\r\n\r\nvalue-value-value-value-1\r\n--B--\r\n"
  let crlf = "\r\n--B"
  b.bench(() => {
    b.keep(find_terminated_delimiter(body.view(), crlf.view(), 0))
  })
}

///|
test "tmp3-header-param" (b : @bench.T) {
  let disp = "form-data; name=\"field0\""
  b.bench(() => {
    b.keep(header_parameter(disp.view(), "name"))
  })
}

///|
test "tmp3-header-param-miss" (b : @bench.T) {
  let disp = "form-data; name=\"field0\""
  b.bench(() => {
    b.keep(header_parameter(disp.view(), "filename"))
  })
}

///|
test "tmp3-parse-part-headers" (b : @bench.T) {
  let header = "Content-Disposition: form-data; name=\"field0\""
  b.bench(() => {
    b.keep(parse_part_headers(header.view()))
  })
}

///|
test "tmp3-get-header-ci" (b : @bench.T) {
  let headers : Map[String, String] = Map([
    ("Content-Disposition", "form-data; name=\"field0\""),
  ])
  b.bench(() => {
    b.keep(get_header_ignore_case(headers, "Content-Type"))
  })
}

///|
test "tmp3-to-owned" (b : @bench.T) {
  let data = "value-value-value-value-0"
  b.bench(() => {
    b.keep(data.view().to_owned())
  })
}

///|
test "tmp4-map-alloc-set" (b : @bench.T) {
  b.bench(() => {
    let m : Map[String, String] = Map([], capacity=4)
    m.set("Content-Disposition", "form-data; name=\"field0\"")
    b.keep(m)
  })
}

///|
test "tmp4-map-alloc-set1" (b : @bench.T) {
  b.bench(() => {
    let m : Map[String, String] = Map([], capacity=1)
    m.set("Content-Disposition", "form-data; name=\"field0\"")
    b.keep(m)
  })
}

///|
test "tmp4-map-get-miss" (b : @bench.T) {
  let headers : Map[String, String] = Map([
    ("Content-Disposition", "form-data; name=\"field0\""),
  ])
  b.bench(() => {
    b.keep(headers.get("Content-Type"))
  })
}

///|
test "tmp4-map-get-hit" (b : @bench.T) {
  let headers : Map[String, String] = Map([
    ("Content-Disposition", "form-data; name=\"field0\""),
  ])
  b.bench(() => {
    b.keep(headers.get("Content-Disposition"))
  })
}

///|
test "tmp4-equal-ci" (b : @bench.T) {
  let a = "Content-Disposition".view()
  let c = "Content-Type".view()
  b.bench(() => {
    b.keep(a.equal_ignore_ascii_case(c))
  })
}

///|
test "tmp4-trim-owned" (b : @bench.T) {
  let line = " Content-Disposition: form-data; name=\"field0\" "
  b.bench(() => {
    b.keep(trim_ascii_space(line.view()).to_owned())
  })
}

///|
test "tmp5-trim-only" (b : @bench.T) {
  let line = " Content-Disposition: form-data; name=\"field0\" "
  b.bench(() => {
    b.keep(trim_ascii_space(line.view()))
  })
}

///|
test "tmp5-view-only" (b : @bench.T) {
  let line = " Content-Disposition: form-data; name=\"field0\" "
  b.bench(() => {
    b.keep(line.view())
  })
}

///|
test "tmp5-sub-owned" (b : @bench.T) {
  let line = " Content-Disposition: form-data; name=\"field0\" "
  b.bench(() => {
    b.keep(line[1:47].to_owned())
  })
}


///|
test "tmp6-slice-view" (b : @bench.T) {
  let line = " Content-Disposition: form-data; name=\"field0\" "
  b.bench(() => {
    b.keep(line[1:47])
  })
}

///|
test "tmp6-full-view-owned" (b : @bench.T) {
  let line = "Content-Disposition: form-data; name=\"field0\""
  b.bench(() => {
    b.keep(line.view().to_owned())
  })
}

///|
test "tmp6-24-owned" (b : @bench.T) {
  let line = "value-value-value-value-0"
  b.bench(() => {
    b.keep(line.view().to_owned())
  })
}

///|
test "tmp6-builder-owned" (b : @bench.T) {
  let line = " Content-Disposition: form-data; name=\"field0\" "
  b.bench(() => {
    let sb = StringBuilder(size_hint=46)
    sb.write_stringview(line[1:47])
    b.keep(sb.to_string())
  })
}

///|
test "tmp7-map-iter1" (b : @bench.T) {
  let headers : Map[String, String] = Map([
    ("Content-Disposition", "form-data; name=\"field0\""),
  ])
  b.bench(() => {
    let mut found = false
    for key, _ in headers {
      if key.view().equal_ignore_ascii_case("Content-Type".view()) {
        found = true
      }
    }
    b.keep(found)
  })
}

///|
test "tmp7-slice-owned" (b : @bench.T) {
  let line = "Content-Disposition: form-data; name=\"field0\""
  b.bench(() => {
    b.keep(line[0:19].to_owned())
  })
}

///|
test "tmp7-slice-owned24" (b : @bench.T) {
  let line = "Content-Disposition: form-data; name=\"field0\""
  b.bench(() => {
    b.keep(line[19:43].to_owned())
  })
}

///|
test "tmp7-header-param2" (b : @bench.T) {
  let disp = "form-data; name=\"field0\"; filename=\"f.txt\""
  b.bench(() => {
    b.keep(header_parameter(disp.view(), "name"))
  })
}

///|
fn tmp_owned_trimmed(view : StringView) -> String {
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
  view.data().unsafe_substring(
    start=view.start_offset() + start,
    end=view.start_offset() + end,
  )
}

///|
test "tmp8-owned-trimmed" (b : @bench.T) {
  let line = " Content-Disposition: form-data; name=\"field0\" "
  b.bench(() => {
    b.keep(tmp_owned_trimmed(line[1:47]))
  })
}

///|
test "tmp8-trim-owned" (b : @bench.T) {
  let line = " Content-Disposition: form-data; name=\"field0\" "
  b.bench(() => {
    b.keep(trim_ascii_space(line[1:47]).to_owned())
  })
}

///|
test "tmp9-map-alloc-default" (b : @bench.T) {
  b.bench(() => {
    let m : Map[String, String] = Map([])
    b.keep(m)
  })
}

///|
test "tmp9-map-alloc-cap4" (b : @bench.T) {
  b.bench(() => {
    let m : Map[String, String] = Map([], capacity=4)
    b.keep(m)
  })
}

///|
test "tmp9-map-alloc-cap0" (b : @bench.T) {
  b.bench(() => {
    let m : Map[String, String] = Map([], capacity=0)
    b.keep(m)
  })
}

///|
test "tmp9-ctx-new" (b : @bench.T) {
  let req : Request = {
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  }
  b.bench(() => {
    b.keep(Context::new(req))
  })
}

///|
test "tmp9-ctx-new-empty-req" (b : @bench.T) {
  b.bench(() => {
    b.keep(create_context())
  })
}

///|
fn tmp_make_app() -> App {
  let app = App::new()
  ignore(app.get("/", fn(ctx) { ctx.text(200, "hello") }))
  ignore(app.get("/api/users", fn(ctx) { ctx.json_value(200, Json::object(Map([]))) }))
  ignore(app.get("/api/users/:id", fn(ctx) { ctx.text(200, ctx.param("id")) }))
  ignore(app.get("/api/users/:id/posts/:post", fn(ctx) {
    ctx.text(200, ctx.param("id") + ":" + ctx.param("post"))
  }))
  ignore(app.post("/api/users", fn(ctx) { ctx.json_value(200, Json::object(Map([]))) }))
  ignore(app.get("/static/*path", fn(ctx) { ctx.text(200, ctx.param("path")) }))
  app
}

///|
test "tmp10-match-dispatch-miss" (b : @bench.T) {
  let app = tmp_make_app()
  let path = "/api/users/12345/posts/678"
  b.bench(() => {
    b.keep(app.router.match_dispatch("POST", path.view()))
  })
}

///|
test "tmp10-allowed-methods" (b : @bench.T) {
  let app = tmp_make_app()
  let path = "/api/users/12345/posts/678"
  b.bench(() => {
    b.keep(app.router.allowed_methods(path.view()))
  })
}

///|
test "tmp10-respond-miss" (b : @bench.T) {
  let app = tmp_make_app()
  let req : Request = {
    method: "POST",
    path: "/api/users/12345/posts/678",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  b.bench(() => {
    let resp = app.respond(req)
    b.keep(resp.status)
  })
}

///|
test "tmp10-respond-static" (b : @bench.T) {
  let app = tmp_make_app()
  let req : Request = {
    method: "GET",
    path: "/api/users",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  b.bench(() => {
    let resp = app.respond(req)
    b.keep(resp.status)
  })
}

///|
test "tmp11-sb-write-char" (b : @bench.T) {
  b.bench(() => {
    let sb = StringBuilder(size_hint=120)
    for i = 0; i < 120; i = i + 1 {
      sb.write_char('x')
    }
    b.keep(sb.to_string())
  })
}

///|
test "tmp11-buffer-write-byte" (b : @bench.T) {
  b.bench(() => {
    let buf = @buffer.Buffer::Buffer(size_hint=120)
    for i = 0; i < 120; i = i + 1 {
      buf.write_byte(b'x')
    }
    b.keep(@utf8.decode_lossy(buf.to_bytes()))
  })
}

///|
test "tmp11-find-qmark" (b : @bench.T) {
  let path = "/api/users/12345/posts/678"
  b.bench(() => {
    b.keep(path.view().find("?"))
  })
}

///|
test "tmp11-scan-qmark" (b : @bench.T) {
  let path = "/api/users/12345/posts/678"
  b.bench(() => {
    let view = path.view()
    let length = view.length()
    let mut i = 0
    while i < length && view.unsafe_get(i) != ('?' : UInt16) {
      i = i + 1
    }
    b.keep(i)
  })
}

///|
fn tmp_write_percent_byte_buf(buf : @buffer.Buffer, value : Int) -> Unit {
  buf.write_byte(b'%')
  buf.write_byte(hex_byte(value / 16))
  buf.write_byte(hex_byte(value % 16))
}

///|
fn hex_byte(value : Int) -> Byte {
  if value < 10 {
    (b'0'.to_int() + value).to_byte()
  } else {
    (b'A'.to_int() + (value - 10)).to_byte()
  }
}

///|
fn tmp_url_encode(source : String) -> String {
  let view = source.view()
  let length = view.length()
  let mut start = 0
  while start < length && is_url_unreserved(view.unsafe_get(start).to_int()) {
    start = start + 1
  }
  if start == length {
    return source
  }
  let buf = @buffer.Buffer::Buffer(size_hint=length + 8)
  let mut p = 0
  while p < start {
    buf.write_byte(view.unsafe_get(p).to_int().to_byte())
    p = p + 1
  }
  let mut i = start
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code < 0x80 {
      if is_url_unreserved(code) {
        buf.write_byte(code.to_byte())
      } else {
        tmp_write_percent_byte_buf(buf, code)
      }
    } else if code < 0x800 {
      tmp_write_percent_byte_buf(buf, 0xC0 | (code >> 6))
      tmp_write_percent_byte_buf(buf, 0x80 | (code & 0x3F))
    } else if code >= 0xD800 && code <= 0xDBFF {
      if i + 1 < length {
        let low = view.unsafe_get(i + 1).to_int()
        if low >= 0xDC00 && low <= 0xDFFF {
          let scalar = ((code - 0xD800) << 10) + (low - 0xDC00) + 0x10000
          tmp_write_percent_byte_buf(buf, 0xF0 | (scalar >> 18))
          tmp_write_percent_byte_buf(buf, 0x80 | ((scalar >> 12) & 0x3F))
          tmp_write_percent_byte_buf(buf, 0x80 | ((scalar >> 6) & 0x3F))
          tmp_write_percent_byte_buf(buf, 0x80 | (scalar & 0x3F))
          i = i + 2
          continue
        }
      }
      tmp_write_percent_byte_buf(buf, 0xEF)
      tmp_write_percent_byte_buf(buf, 0xBF)
      tmp_write_percent_byte_buf(buf, 0xBD)
    } else if code >= 0xDC00 && code <= 0xDFFF {
      tmp_write_percent_byte_buf(buf, 0xEF)
      tmp_write_percent_byte_buf(buf, 0xBF)
      tmp_write_percent_byte_buf(buf, 0xBD)
    } else {
      tmp_write_percent_byte_buf(buf, 0xE0 | (code >> 12))
      tmp_write_percent_byte_buf(buf, 0x80 | ((code >> 6) & 0x3F))
      tmp_write_percent_byte_buf(buf, 0x80 | (code & 0x3F))
    }
    i = i + 1
  }
  @utf8.decode_lossy(buf.to_bytes())
}

///|
test "tmp12-url-encode-buf" (b : @bench.T) {
  let source = "hello world/foo bar?baz=qux&name=\u{4e16}\u{754c}"
  b.bench(() => {
    b.keep(tmp_url_encode(source))
  })
}
