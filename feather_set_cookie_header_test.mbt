///|
fn count_occurrences(haystack : String, needle : String) -> Int {
  let view = haystack.view()
  let needle_view = needle.view()
  let length = view.length()
  let mut count = 0
  let mut pos = 0
  while pos < length {
    match view[pos:].find(needle_view) {
      Some(index) => {
        count = count + 1
        pos = pos + index + needle_view.length()
      }
      None => break
    }
  }
  count
}

///|
async test "a hand-written Set-Cookie header survives a pending cookie" {
  let app = @feather.App::new().get("/cookies", fn(ctx) {
    ctx.set_header("Set-Cookie", "manual=1")
    ctx.add_cookie("added", "2")
    ctx.text(200, "ok")
  })
  with_raw_server(app, conn => {
    conn.write("GET /cookies HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n")
    let head = conn.read_all().text()
    assert_true(head.contains("Set-Cookie: manual=1"), msg=head)
    assert_true(head.contains("Set-Cookie: added=2"), msg=head)
    assert_eq(count_occurrences(head, "Set-Cookie: "), 2)
  })
}

///|
async test "a cookie written by the helper is not sent twice" {
  let app = @feather.App::new().get("/cookies", fn(ctx) {
    ctx.set_cookie("sid", "1")
    ctx.add_cookie("added", "2")
    ctx.text(200, "ok")
  })
  with_raw_server(app, conn => {
    conn.write("GET /cookies HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n")
    let head = conn.read_all().text()
    assert_true(head.contains("Set-Cookie: sid=1"), msg=head)
    assert_true(head.contains("Set-Cookie: added=2"), msg=head)
    assert_eq(count_occurrences(head, "Set-Cookie: "), 2)
  })
}

///|
async test "a hand-written Set-Cookie header is sent without a pending cookie" {
  let app = @feather.App::new().get("/cookies", fn(ctx) {
    ctx.set_header("Set-Cookie", "manual=1")
    ctx.text(200, "ok")
  })
  with_raw_server(app, conn => {
    conn.write("GET /cookies HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n")
    let head = conn.read_all().text()
    assert_true(head.contains("Set-Cookie: manual=1"), msg=head)
    assert_eq(count_occurrences(head, "Set-Cookie: "), 1)
  })
}

///|
async test "a hand-written Set-Cookie header survives an event stream" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("Set-Cookie", "manual=1")
        ctx.add_cookie("added", "2")
        next(ctx)
      }
    })
    .sse("/events", async fn(_ctx, sse) {
      sse.send("tick")
      sse.close()
    })
  with_raw_server(app, conn => {
    conn.write("GET /events HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n")
    let head = conn.read_all().text()
    assert_true(head.contains("Set-Cookie: manual=1"), msg=head)
    assert_true(head.contains("Set-Cookie: added=2"), msg=head)
  })
}

///|
async test "a hand-written Set-Cookie header survives a streamed response" {
  let app = @feather.App::new().stream("/stream", async fn(_ctx, out) {
    out.set_header("Set-Cookie", "manual=1")
    out.add_cookie("added", "2")
    out.write("chunk")
  })
  with_raw_server(app, conn => {
    conn.write("GET /stream HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n")
    let head = conn.read_all().text()
    assert_true(head.contains("Set-Cookie: manual=1"), msg=head)
    assert_true(head.contains("Set-Cookie: added=2"), msg=head)
  })
}

///|
async test "a hand-written Set-Cookie header survives a seeded stream" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("Set-Cookie", "manual=1")
        ctx.add_cookie("added", "2")
        next(ctx)
      }
    })
    .stream("/stream", async fn(_ctx, out) {
      out.write("chunk")
    })
  with_raw_server(app, conn => {
    conn.write("GET /stream HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n")
    let head = conn.read_all().text()
    assert_true(head.contains("Set-Cookie: manual=1"), msg=head)
    assert_true(head.contains("Set-Cookie: added=2"), msg=head)
  })
}

///|
test "the offline facade keeps a hand-written Set-Cookie header" {
  let app = @feather.App::new().get("/cookies", fn(ctx) {
    ctx.set_header("Set-Cookie", "manual=1")
    ctx.add_cookie("added", "2")
    ctx.text(200, "ok")
  })
  let response = app.respond({
    method: "GET",
    path: "/cookies",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.headers.get("Set-Cookie"), Some("manual=1"))
  assert_eq(response.cookies.length(), 1)
}
