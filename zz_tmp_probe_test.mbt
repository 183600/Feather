///|
fn count_header_lines(head : String, name : String) -> Int32 {
  let mut count = 0
  for line in head.split("\n") {
    if line.has_prefix(name.view()) {
      count = count + 1
    }
  }
  count
}

///|
fn count_header_ignore_case(
  headers : Map[String, String],
  name : String,
) -> Int32 {
  let mut count = 0
  for key, _ in headers {
    if key.view().equal_ignore_ascii_case(name.view()) {
      count = count + 1
    }
  }
  count
}

///|
test "response helpers replace case-variant header spellings" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("content-type", "application/xml")
        ctx.set_header("location", "/wrong")
        ctx.set_header("content-disposition", "inline")
        ctx.set_header("allow", "PATCH")
        next(ctx)
      }
    })
    .get("/text", fn(ctx) { ctx.text(200, "hi") })
    .get("/redir", fn(ctx) { ctx.redirect(302, "/new") })
    .get("/file", fn(ctx) {
      ctx.file(
        200,
        "/tmp/unused.txt",
        content_type="application/pdf",
        download_name="unused.txt",
      )
    })
    .get("/empty", fn(ctx) { ctx.no_content() })
  let text = app.respond({
    method: "GET",
    path: "/text",
    headers: Map([]),
    body: "",
  })
  assert_eq(count_header_ignore_case(text.headers, "content-type"), 1)
  assert_eq(text.headers.get("Content-Type"), Some("text/plain; charset=utf-8"))
  let redirect = app.respond({
    method: "GET",
    path: "/redir",
    headers: Map([]),
    body: "",
  })
  assert_eq(count_header_ignore_case(redirect.headers, "location"), 1)
  assert_eq(redirect.headers.get("Location"), Some("/new"))
  let file = app.respond({
    method: "GET",
    path: "/file",
    headers: Map([]),
    body: "",
  })
  assert_eq(count_header_ignore_case(file.headers, "content-type"), 1)
  assert_eq(file.headers.get("Content-Type"), Some("application/pdf"))
  assert_eq(count_header_ignore_case(file.headers, "content-disposition"), 1)
  let empty = app.respond({
    method: "GET",
    path: "/empty",
    headers: Map([]),
    body: "",
  })
  assert_eq(empty.status, 204)
  assert_eq(count_header_ignore_case(empty.headers, "content-type"), 0)
  let denied = app.respond({
    method: "DELETE",
    path: "/text",
    headers: Map([]),
    body: "",
  })
  assert_eq(denied.status, 405)
  assert_eq(count_header_ignore_case(denied.headers, "allow"), 1)
  assert_eq(denied.headers.get("Allow"), Some("GET, HEAD"))
  assert_eq(count_header_ignore_case(denied.headers, "content-type"), 1)
}

///|
async test "wire response carries one content type after a case-variant middleware set" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("CONTENT-TYPE", "application/xml")
        ctx.set_header("LOCATION", "/wrong")
        next(ctx)
      }
    })
    .get("/text", fn(ctx) { ctx.text(200, "hi") })
    .get("/redir", fn(ctx) { ctx.redirect(302, "/new") })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /text HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_eq(count_header_lines(head, "Content-Type"), 1)
    assert_false(head.contains("application/xml"))
    assert_true(head.contains("text/plain; charset=utf-8"))
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /redir HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 302"))
    assert_true(head.contains("\nLocation: /new"))
    assert_false(head.contains("/wrong"))
  })
}
