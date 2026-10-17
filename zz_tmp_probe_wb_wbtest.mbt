///|
fn tmp_build_multipart(parts : Int) -> (String, String) {
  let boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
  let mut body = ""
  for i = 0; i < parts; i = i + 1 {
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
test "probe-parse-part-headers" (b : @bench.T) {
  let header = "Content-Disposition: form-data; name=\"field0\""
  b.bench(() => {
    b.keep(parse_part_headers(header.view()))
  })
}

///|
test "probe-header-parameter-name" (b : @bench.T) {
  let value = "form-data; name=\"field0\""
  b.bench(() => {
    b.keep(header_parameter(value.view(), "name"))
  })
}

///|
test "probe-header-parameter-filename-miss" (b : @bench.T) {
  let value = "form-data; name=\"field0\""
  b.bench(() => {
    b.keep(header_parameter(value.view(), "filename"))
  })
}

///|
test "probe-header-ext-miss" (b : @bench.T) {
  let value = "form-data; name=\"field0\""
  b.bench(() => {
    b.keep(header_ext_parameter(value.view(), "filename"))
  })
}

///|
test "probe-find-own-delimiter" (b : @bench.T) {
  let (body, ct) = tmp_build_multipart(8)
  let boundary = multipart_boundary(ct).unwrap()
  let delimiter = "\r\n--" + boundary
  b.bench(() => {
    b.keep(find_terminated_delimiter(body.view(), delimiter.view(), 0))
  })
}

///|
test "probe-multipart-8" (b : @bench.T) {
  let (body, ct) = tmp_build_multipart(8)
  b.bench(() => {
    b.keep(parse_multipart(body, ct))
  })
}

///|
test "probe-multipart-boundary" (b : @bench.T) {
  let ct = "multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW"
  b.bench(() => {
    b.keep(multipart_boundary(ct))
  })
}

///|
test "probe-equal-ci" (b : @bench.T) {
  let a = "Content-Disposition".view()
  let c = "Content-Disposition".view()
  b.bench(() => {
    b.keep(a.equal_ignore_ascii_case(c))
  })
}

///|
test "probe-pph-parts" (b : @bench.T) {
  let header = "Content-Disposition: form-data; name=\"field0\""
  let view = header.view()
  let name = owned_trimmed(view[0:19])
  let value = owned_trimmed(view[21:view.length()])
  b.bench(() => {
    let m : Map[String, String] = Map([], capacity=4)
    m.set(name, value)
    b.keep(m.length())
  })
}

///|
test "probe-pph-trim" (b : @bench.T) {
  let header = "Content-Disposition: form-data; name=\"field0\""
  let view = header.view()
  b.bench(() => {
    let name = owned_trimmed(view[0:19])
    let value = owned_trimmed(view[21:view.length()])
    b.keep(name.length() + value.length())
  })
}

///|
test "probe-pph-eq" (b : @bench.T) {
  let header = "Content-Disposition: form-data; name=\"field0\""
  let view = header.view()
  let name = owned_trimmed(view[0:19])
  b.bench(() => {
    b.keep(name.view().equal_ignore_ascii_case("Content-Disposition".view()))
  })
}

///|
test "probe-pph-scan" (b : @bench.T) {
  let header = "Content-Disposition: form-data; name=\"field0\""
  let view = header.view()
  let length = view.length()
  b.bench(() => {
    let mut end = 0
    while end < length && view.unsafe_get(end) != ('\n' : UInt16) {
      end = end + 1
    }
    let line_end = if end > 0 && view.unsafe_get(end - 1) == ('\r' : UInt16) {
      end - 1
    } else {
      end
    }
    let mut colon = 0
    while colon < line_end && view.unsafe_get(colon) != (':' : UInt16) {
      colon = colon + 1
    }
    b.keep(colon)
  })
}

///|
fn tmp_set_probe(cap : Int, b : @bench.T) -> Unit {
  let name = "Content-Disposition"
  let value = "form-data; name=\"field0\""
  b.bench(() => {
    let m : Map[String, String] = Map([], capacity=cap)
    m.set(name, value)
    b.keep(m.length())
  })
}

///|
test "probe-set-cap0" (b : @bench.T) {
  tmp_set_probe(0, b)
}

///|
test "probe-set-cap1" (b : @bench.T) {
  tmp_set_probe(1, b)
}

///|
test "probe-set-cap2" (b : @bench.T) {
  tmp_set_probe(2, b)
}

///|
test "probe-set-cap4" (b : @bench.T) {
  tmp_set_probe(4, b)
}

///|
test "probe-cookie-find-first" (b : @bench.T) {
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
  b.bench(() => {
    b.keep(ctx.cookie("session"))
  })
}

///|
test "probe-cookie-find-last" (b : @bench.T) {
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
  b.bench(() => {
    b.keep(ctx.cookie("tracking"))
  })
}

///|
test "probe-cookie-find-miss" (b : @bench.T) {
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
  b.bench(() => {
    b.keep(ctx.cookie("missing"))
  })
}

///|
test "probe-cookies-map" (b : @bench.T) {
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
  b.bench(() => {
    b.keep(ctx.cookies())
  })
}
