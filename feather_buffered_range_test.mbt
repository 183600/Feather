///|
fn range_request(path : String, range : String) -> @feather.Request {
  {
    method: "GET",
    path,
    headers: Map([("Range", range)]),
    body: "",
  }
}

///|
test "offline buffered response honors a byte range" {
  let app = @feather.App::new().get("/data", fn(ctx) {
    ctx.text(200, "0123456789")
  })
  let response = app.respond(range_request("/data", "bytes=2-5"))
  assert_eq(response.status, 206)
  assert_eq(response.body, "2345")
  assert_eq(response.data, None)
  assert_eq(response.headers.get("Content-Range"), Some("bytes 2-5/10"))
  assert_eq(response.headers.get("Accept-Ranges"), Some("bytes"))
  assert_eq(
    response.headers.get("Content-Type"),
    Some("text/plain; charset=utf-8"),
  )
}

///|
test "offline byte responses slice exact bytes for a range" {
  let app = @feather.App::new().get("/raw", fn(ctx) {
    ctx.bytes(200, b"\x00\x01\x02\x03\x04", content_type="application/octet-stream")
  })
  let response = app.respond(range_request("/raw", "bytes=1-3"))
  assert_eq(response.status, 206)
  assert_eq(response.body, "")
  assert_eq(response.data, Some(b"\x01\x02\x03"))
  assert_eq(response.headers.get("Content-Range"), Some("bytes 1-3/5"))
}

///|
test "offline suffix and open-ended byte ranges" {
  let app = @feather.App::new().get("/data", fn(ctx) {
    ctx.text(200, "abcdef")
  })
  let suffix = app.respond(range_request("/data", "bytes=-2"))
  assert_eq(suffix.status, 206)
  assert_eq(suffix.body, "ef")
  assert_eq(suffix.headers.get("Content-Range"), Some("bytes 4-5/6"))
  let open = app.respond(range_request("/data", "bytes=3-"))
  assert_eq(open.status, 206)
  assert_eq(open.body, "def")
  assert_eq(open.headers.get("Content-Range"), Some("bytes 3-5/6"))
}

///|
test "offline unsatisfiable range becomes 416 without stale validators" {
  let app = @feather.App::new().etag().get("/data", fn(ctx) {
    ctx.text(200, "0123456789")
  })
  let response = app.respond(range_request("/data", "bytes=20-30"))
  assert_eq(response.status, 416)
  assert_eq(response.body, "416 Range Not Satisfiable")
  assert_eq(response.data, None)
  assert_eq(response.headers.get("Content-Range"), Some("bytes */10"))
  assert_eq(response.headers.get("Accept-Ranges"), Some("bytes"))
  assert_eq(response.headers.get("ETag"), None)
  assert_eq(
    response.headers.get("Content-Type"),
    Some("text/plain; charset=utf-8"),
  )
}

///|
test "offline malformed and multi-range requests fall back to the full body" {
  let app = @feather.App::new().get("/data", fn(ctx) {
    ctx.text(200, "0123456789")
  })
  let multi = app.respond(range_request("/data", "bytes=0-1,4-5"))
  assert_eq(multi.status, 200)
  assert_eq(multi.body, "0123456789")
  assert_eq(multi.headers.get("Content-Range"), None)
  let malformed = app.respond(range_request("/data", "items=0-1"))
  assert_eq(malformed.status, 200)
  assert_eq(malformed.body, "0123456789")
}

///|
test "offline If-Range requires a matching strong validator" {
  let app = @feather.App::new().get("/data", fn(ctx) {
    ctx.set_header("ETag", "\"v1\"")
    ctx.text(200, "0123456789")
  })
  let matching = app.respond({
    method: "GET",
    path: "/data",
    headers: Map([("Range", "bytes=0-1"), ("If-Range", "\"v1\"")]),
    body: "",
  })
  assert_eq(matching.status, 206)
  assert_eq(matching.body, "01")
  for if_range in ["\"v2\"", "W/\"v1\""] {
    let response = app.respond({
      method: "GET",
      path: "/data",
      headers: Map([("Range", "bytes=0-1"), ("If-Range", if_range)]),
      body: "",
    })
    assert_eq(response.status, 200, msg=if_range)
    assert_eq(response.body, "0123456789", msg=if_range)
  }
}

///|
test "offline If-Range accepts an exact Last-Modified date" {
  let app = @feather.App::new().get("/data", fn(ctx) {
    let stamp = @feather.format_http_date(1_700_000_000L)
    ctx.set_header("Last-Modified", stamp)
    ctx.text(200, "abcdef")
  })
  let stamp = @feather.format_http_date(1_700_000_000L)
  let matching = app.respond({
    method: "GET",
    path: "/data",
    headers: Map([("Range", "bytes=0-2"), ("If-Range", stamp)]),
    body: "",
  })
  assert_eq(matching.status, 206)
  assert_eq(matching.body, "abc")
  let stale = app.respond({
    method: "GET",
    path: "/data",
    headers: Map([
      ("Range", "bytes=0-2"),
      ("If-Range", @feather.format_http_date(1_600_000_000L)),
    ]),
    body: "",
  })
  assert_eq(stale.status, 200)
  assert_eq(stale.body, "abcdef")
}

///|
test "offline HEAD and non-GET requests ignore Range" {
  let app = @feather.App::new()
    .get("/data", fn(ctx) { ctx.text(200, "0123456789") })
    .post("/data", fn(ctx) { ctx.text(200, "posted") })
  let head = app.respond({
    method: "HEAD",
    path: "/data",
    headers: Map([("Range", "bytes=0-1")]),
    body: "",
  })
  assert_eq(head.status, 200)
  assert_eq(head.body, "")
  assert_eq(head.headers.get("Content-Range"), None)
  assert_eq(head.headers.get("Content-Length"), Some("10"))
  let post = app.respond({
    method: "POST",
    path: "/data",
    headers: Map([("Range", "bytes=0-1")]),
    body: "",
  })
  assert_eq(post.status, 200)
  assert_eq(post.body, "posted")
  assert_eq(post.headers.get("Content-Range"), None)
}

///|
test "offline range on a non-200 response is left alone" {
  let app = @feather.App::new().get("/created", fn(ctx) {
    ctx.text(201, "created")
  })
  let response = app.respond(range_request("/created", "bytes=0-1"))
  assert_eq(response.status, 201)
  assert_eq(response.body, "created")
  assert_eq(response.headers.get("Content-Range"), None)
}

///|
test "offline ranged response drops a stale full-body content length" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("Content-Length", "10")
        next(ctx)
      }
    })
    .get("/data", fn(ctx) { ctx.text(200, "0123456789") })
  let response = app.respond(range_request("/data", "bytes=2-5"))
  assert_eq(response.status, 206)
  assert_eq(response.body, "2345")
  assert_eq(response.headers.get("Content-Range"), Some("bytes 2-5/10"))
  assert_eq(response.headers.get("Content-Length"), None)
}
