///|
fn buffered_range_request(
  method : String,
  headers : Map[String, String],
) -> @feather.Request {
  { method, path: "/data", headers, body: "", }
}

///|
fn buffered_range_app() -> @feather.App {
  @feather.App::new().compress(min_size=0).get("/data", fn(ctx) {
    ctx.text(200, "0123456789".repeat(64))
  })
}

///|
async test "a malformed range is ignored even when compression is enabled" {
  let response = buffered_range_app().respond_async(
    buffered_range_request("GET", Map([
      ("Range", "garbage"),
      ("Accept-Encoding", "gzip"),
    ])),
  )
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Content-Range"), None)
  assert_eq(response.body.length(), 640)
}

///|
async test "a multi-range request is ignored even when compression is enabled" {
  let response = buffered_range_app().respond_async(
    buffered_range_request("GET", Map([
      ("Range", "bytes=0-1,3-4"),
      ("Accept-Encoding", "gzip"),
    ])),
  )
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Content-Range"), None)
  assert_eq(response.body.length(), 640)
}

///|
async test "an unsatisfiable range is reported even when compression is enabled" {
  let response = buffered_range_app().respond_async(
    buffered_range_request("GET", Map([
      ("Range", "bytes=9999-"),
      ("Accept-Encoding", "gzip"),
    ])),
  )
  assert_eq(response.status, 416)
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Content-Range"), Some("bytes */640"))
  assert_eq(response.body, "416 Range Not Satisfiable")
}

///|
async test "a stale If-Range keeps the full body when compression is enabled" {
  let response = buffered_range_app().respond_async(
    buffered_range_request("GET", Map([
      ("Range", "bytes=4-6"),
      ("If-Range", "\"stale\""),
      ("Accept-Encoding", "gzip"),
    ])),
  )
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Content-Range"), None)
  assert_eq(response.body.length(), 640)
}

///|
async test "a HEAD request ignores the range even when compression is enabled" {
  let response = buffered_range_app().respond_async(
    buffered_range_request("HEAD", Map([
      ("Range", "bytes=4-6"),
      ("Accept-Encoding", "gzip"),
    ])),
  )
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Content-Range"), None)
  assert_eq(response.body, "")
}

///|
test "an offline buffered range refuses an identity-only client" {
  let app = @feather.App::new().get("/data", fn(ctx) {
    ctx.text(200, "0123456789".repeat(64))
  })
  let response = app.respond({
    method: "GET",
    path: "/data",
    headers: Map([
      ("Range", "bytes=4-6"),
      ("Accept-Encoding", "gzip, identity;q=0"),
    ]),
    body: "",
  })
  assert_eq(response.status, 406)
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Content-Range"), None)
  assert_eq(response.body, "406 Not Acceptable")
}

///|
async test "an async buffered range refuses an identity-only client" {
  let app = @feather.App::new().get("/data", fn(ctx) {
    ctx.text(200, "0123456789".repeat(64))
  })
  let response = app.respond_async({
    method: "GET",
    path: "/data",
    headers: Map([
      ("Range", "bytes=4-6"),
      ("Accept-Encoding", "gzip, identity;q=0"),
    ]),
    body: "",
  })
  assert_eq(response.status, 406)
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Content-Range"), None)
  assert_eq(response.body, "406 Not Acceptable")
}

///|
async test "a compressed buffered range refuses an identity-only client" {
  let app = @feather.App::new().compress(min_size=0).get("/data", fn(ctx) {
    ctx.text(200, "0123456789".repeat(64))
  })
  let response = app.respond_async({
    method: "GET",
    path: "/data",
    headers: Map([
      ("Range", "bytes=4-6"),
      ("Accept-Encoding", "gzip, identity;q=0"),
    ]),
    body: "",
  })
  assert_eq(response.status, 406)
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Content-Range"), None)
  assert_eq(response.body, "406 Not Acceptable")
}
