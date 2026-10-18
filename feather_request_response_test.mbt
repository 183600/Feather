///|
test "Context cookies strip surrounding quotes" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: { "Cookie": "a=\"hello world\"; b=plain; c=\"\"; d=unterminated\"" },
    body: "",
  })
  assert_eq(ctx.cookie("a"), Some("hello world"))
  assert_eq(ctx.cookie("b"), Some("plain"))
  assert_eq(ctx.cookie("c"), Some(""))
  assert_eq(ctx.cookie("d"), Some("unterminated\""))
}

///|
test "Context form_values collects repeated fields" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/submit",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "tag=a&tag=b%20c&other=1&tag=",
  })
  assert_eq(ctx.form_values("tag").join("|"), "a|b c|")
  assert_eq(ctx.form_values("other").join("|"), "1")
  assert_eq(ctx.form_values("missing").length(), 0)
}

///|
test "Context form_values ignores other content types" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/submit",
    headers: { "Content-Type": "application/json" },
    body: "tag=a",
  })
  assert_eq(ctx.form_values("tag").length(), 0)
  let empty = @feather.create_context()
  assert_eq(empty.form_values("tag").length(), 0)
}

///|
test "Context query_default falls back only for absent parameters" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/search?q=feather&empty=",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.query_default("q", "all"), "feather")
  assert_eq(ctx.query_default("empty", "all"), "")
  assert_eq(ctx.query_default("page", "1"), "1")
  let bare = @feather.create_context()
  assert_eq(bare.query_default("q", "all"), "all")
}

///|
test "Context form_default falls back only for absent fields" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/submit",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "name=feather&note=",
  })
  assert_eq(ctx.form_default("name", "anon"), "feather")
  assert_eq(ctx.form_default("note", "-"), "")
  assert_eq(ctx.form_default("missing", "0"), "0")
  let json = @feather.Context::new({
    method: "POST",
    path: "/submit",
    headers: { "Content-Type": "application/json" },
    body: "{\"name\":\"feather\"}",
  })
  assert_eq(json.form_default("name", "anon"), "anon")
}

///|
async test "server stamps responses with a date header" {
  let app = @feather.App::new().get("/ping", fn(ctx) { ctx.text(200, "pong") })
  with_server(app, client => {
    let response = client.get("/ping")
    assert_eq(response.code, 200)
    assert_true(
      response.headers.get(@http.CaseInsensitiveString("Date")) is Some(_),
    )
    assert_eq(client.read_all().text(), "pong")
  })
}

///|
async test "server keeps a date header provided by the handler" {
  let app = @feather.App::new().get("/fixed", fn(ctx) {
    ctx.set_header("Date", "Thu, 01 Jan 1970 00:00:00 GMT")
    ctx.text(200, "fixed")
  })
  with_server(app, client => {
    let response = client.get("/fixed")
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Date")),
      Some("Thu, 01 Jan 1970 00:00:00 GMT"),
    )
    ignore(client.read_all())
  })
}

///|
async test "server serves ranges for queued files" {
  let dir = @fs.tmpdir(prefix="feather-file-range")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new().get("/download", fn(ctx) {
    ctx.set_header("ETag", "\"v1\"")
    ctx.file(200, dir + "/digits.txt")
  })
  with_server(app, client => {
    let full = client.get("/download")
    assert_eq(full.code, 200)
    assert_eq(
      full.headers.get(@http.CaseInsensitiveString("Accept-Ranges")),
      Some("bytes"),
    )
    assert_eq(
      full.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("10"),
    )
    assert_eq(client.read_all().text(), "0123456789")
    let ranged = client.get(
      "/download",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=4-6")]),
    )
    assert_eq(ranged.code, 206)
    assert_eq(
      ranged.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes 4-6/10"),
    )
    assert_eq(
      ranged.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("3"),
    )
    assert_eq(client.read_all().text(), "456")
    let suffix = client.get(
      "/download",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=-2")]),
    )
    assert_eq(suffix.code, 206)
    assert_eq(client.read_all().text(), "89")
    let invalid = client.get(
      "/download",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=99-")]),
    )
    assert_eq(invalid.code, 416)
    assert_eq(
      invalid.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes */10"),
    )
    ignore(client.read_all())
    let matched = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=0-1"),
        (@http.CaseInsensitiveString("If-Range"), "\"v1\""),
      ]),
    )
    assert_eq(matched.code, 206)
    assert_eq(client.read_all().text(), "01")
    let stale = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=0-1"),
        (@http.CaseInsensitiveString("If-Range"), "\"stale\""),
      ]),
    )
    assert_eq(stale.code, 200)
    assert_eq(client.read_all().text(), "0123456789")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server ignores ranges for head requests on queued files" {
  let dir = @fs.tmpdir(prefix="feather-file-head-range")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new().get("/download", fn(ctx) {
    ctx.file(200, dir + "/digits.txt")
  })
  with_server(app, client => {
    client.request(
      @http.RequestMethod::Head,
      "/download",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=4-6")]),
    )
    let response = client.end_request()
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("10"),
    )
    assert_eq(client.read_all().text(), "")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
fn gzip_bytes(encoded : String) -> Bytes raise {
  match @feather.base64_decode(encoded) {
    Some(bytes) => bytes
    None => fail("invalid base64 payload")
  }
}

///|
async test "server decodes gzip request bodies" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    ctx.text(200, ctx.form("name") + "|" + ctx.header("Content-Encoding"))
  })
  with_server(app, client => {
    let response = client.post(
      "/echo",
      gzip_bytes("H4sIAAAAAAACA8tLzE21TUtNLMlILQIAbKbcFwwAAAA="),
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "application/x-www-form-urlencoded",
        ),
        (@http.CaseInsensitiveString("Content-Encoding"), "gzip"),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "feather|")
  })
}

///|
async test "server decodes gzip json bodies" {
  let app = @feather.App::new().post("/json", fn(ctx) {
    let body = ctx.json_body() catch {
      _ => {
        ctx.text(400, "bad json")
        return
      }
    }
    let msg = if body is Object(fields) {
      match fields.get("msg") {
        Some(String(value)) => value
        _ => "missing"
      }
    } else {
      "missing"
    }
    ctx.text(200, msg)
  })
  with_server(app, client => {
    let response = client.post(
      "/json",
      gzip_bytes("H4sIAAAAAAACA6tWyi1OV7JSykjNyclXSK/KLFCqBQC1Qk5IFAAAAA=="),
      extra_headers=Map([
        (@http.CaseInsensitiveString("Content-Type"), "application/json"),
        (@http.CaseInsensitiveString("Content-Encoding"), "gzip"),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "hello gzip")
  })
}

///|
async test "server bounds decompressed request bodies" {
  let app = @feather.App::new().post("/bomb", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_server(app, client => {
    let response = client.post(
      "/bomb",
      gzip_bytes("H4sIAAAAAAACA+3BMQEAAADCoErrn84UfkABAAAAAG8DBD38qIgTAAA="),
      extra_headers=Map([
        (@http.CaseInsensitiveString("Content-Encoding"), "gzip"),
      ]),
    )
    assert_eq(response.code, 413)
    ignore(client.read_all())
  })
}

///|
async test "server rejects malformed gzip request bodies" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_server(app, client => {
    let response = client.post(
      "/echo",
      "not gzip",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Content-Encoding"), "gzip"),
      ]),
    )
    assert_eq(response.code, 400)
    ignore(client.read_all())
  })
}

///|
async test "server serves conditional queued files" {
  let dir = @fs.tmpdir(prefix="feather-file-cond")
  @fs.write_file(dir + "/data.txt", "0123456789")
  let app = @feather.App::new().get("/data", fn(ctx) {
    ctx.file(200, dir + "/data.txt")
  })
  with_server(app, client => {
    let first = client.get("/data")
    assert_eq(first.code, 200)
    let etag = match first.headers.get(@http.CaseInsensitiveString("ETag")) {
      Some(etag) => etag
      None => fail("missing ETag")
    }
    let last_modified = match first.headers.get(
      @http.CaseInsensitiveString("Last-Modified"),
    ) {
      Some(value) => value
      None => fail("missing Last-Modified")
    }
    assert_eq(client.read_all().text(), "0123456789")
    let revalidated = client.get(
      "/data",
      extra_headers=Map([(@http.CaseInsensitiveString("If-None-Match"), etag)]),
    )
    assert_eq(revalidated.code, 304)
    assert_eq(
      revalidated.headers.get(@http.CaseInsensitiveString("ETag")),
      Some(etag),
    )
    assert_eq(client.read_all().text(), "")
    let by_date = client.get(
      "/data",
      extra_headers=Map([
        (@http.CaseInsensitiveString("If-Modified-Since"), last_modified),
      ]),
    )
    assert_eq(by_date.code, 304)
    ignore(client.read_all())
    let ranged = client.get(
      "/data",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=0-3"),
        (@http.CaseInsensitiveString("If-Range"), etag),
      ]),
    )
    assert_eq(ranged.code, 206)
    assert_eq(client.read_all().text(), "0123")
  })
  @fs.rmdir(dir, recursive=true)
}
