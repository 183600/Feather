///|
test "audit fresh with stored weak etag" {
  let ctx = @feather.create_context()
  ctx.request.headers.set("If-None-Match", "\"abc\"")
  assert_true(ctx.fresh("W/\"abc\""))
}

///|
test "audit cookie quoted and equality" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "a=\"b c\"; d=e=f; f=\"\"; g=")]),
    body: "",
  })
  let all = ctx.cookies()
  assert_eq(all.get("a"), Some("b c"))
  assert_eq(all.get("d"), Some("e=f"))
  assert_eq(all.get("f"), Some(""))
  assert_eq(all.get("g"), Some(""))
  assert_eq(ctx.cookie("a"), Some("b c"))
  assert_eq(ctx.cookie("d"), Some("e=f"))
  assert_eq(ctx.cookie("f"), Some(""))
  assert_eq(ctx.cookie("g"), Some(""))
}

///|
test "audit host and full_url variants" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/p?q=1",
    headers: Map([("Host", "[::1]:8080")]),
    body: "",
  })
  assert_eq(ctx.host(), "[::1]")
  assert_eq(ctx.full_url(), "http://[::1]:8080/p?q=1")
  let ctx2 = @feather.Context::new({
    method: "GET",
    path: "/p",
    headers: Map([("Host", "example.com")]),
    body: "",
  })
  assert_eq(ctx2.host(), "example.com")
  assert_eq(ctx2.full_url(), "http://example.com/p")
}

///|
fn audit_range(raw : String, size : Int64) -> (String, Int64, Int64) {
  match @feather.parse_byte_range(raw, size) {
    @feather.ByteRangeSpec(start, end_) => ("spec", start, end_)
    @feather.ByteRangeFull => ("full", 0L, 0L)
    @feather.ByteRangeInvalid => ("invalid", 0L, 0L)
  }
}

///|
test "audit byte ranges" {
  assert_eq(audit_range("bytes=-5", 10L), ("spec", 5L, 9L))
  assert_eq(audit_range("bytes=5-", 10L), ("spec", 5L, 9L))
  assert_eq(audit_range("bytes=0-0", 10L), ("spec", 0L, 0L))
  assert_eq(audit_range("bytes=0-100", 10L), ("spec", 0L, 9L))
  assert_eq(audit_range("bytes=5-3", 10L), ("full", 0L, 0L))
  assert_eq(audit_range("bytes=0-0,2-2", 10L), ("full", 0L, 0L))
  assert_eq(audit_range("bytes=-0", 10L), ("invalid", 0L, 0L))
  assert_eq(audit_range("bytes=10-", 10L), ("invalid", 0L, 0L))
  assert_eq(audit_range("items=0-1", 10L), ("full", 0L, 0L))
  assert_eq(audit_range("bytes=", 10L), ("full", 0L, 0L))
}

///|
async fn with_server_audit(
  app : @feather.App,
  run : async (@http.Client) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg(no_wait=true, () => app.serve_with(server))
    @async.sleep(50)
    let client = @http.Client("http://127.0.0.1:\{addr.port()}")
    defer client.close()
    run(client)
    server.close()
  })
}

///|
async test "audit head agrees with get when route and static file coexist" {
  let dir = @fs.tmpdir(prefix="feather-audit")
  @fs.write_file(dir + "/app.js", "static-body")
  let app = @feather.App::new()
    .static_files("/assets", dir)
    .get("/assets/app.js", fn(ctx) { ctx.text(200, "route-body") })
  with_server_audit(app, client => {
    let get_response = client.get("/assets/app.js")
    assert_eq(get_response.code, 200)
    let get_body = client.read_all().text()
    assert_eq(get_body, "route-body")
    client.request(@http.RequestMethod::Head, "/assets/app.js")
    let head_response = client.end_request()
    ignore(client.read_all())
    assert_eq(head_response.code, 200)
    assert_eq(
      head_response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("10"),
    )
  })
  @fs.rmdir(dir, recursive=true)
}
