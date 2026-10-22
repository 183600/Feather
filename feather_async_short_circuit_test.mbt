///|
async test "sse middleware short circuit honors conditional requests" {
  let app = @feather.App::new()
    .etag()
    .use(fn(next) {
      fn(ctx) raise {
        ignore(next)
        ctx.set_header("ETag", "\"short-circuit\"")
        ctx.text(200, "plain response")
      }
    })
    .sse("/events", async fn(_ctx, sse) { sse.send("unreachable") })
  with_sse_server(app, client => {
    let first = client.get("/events")
    assert_eq(first.code, 200)
    assert_eq(
      first.headers.get(@http.CaseInsensitiveString("ETag")),
      Some("\"short-circuit\""),
    )
    assert_eq(client.read_all().text(), "plain response")
    let second = client.get(
      "/events",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("If-None-Match"),
          "\"short-circuit\"",
        ),
      ]),
    )
    assert_eq(second.code, 304)
    assert_eq(client.read_all().text(), "")
  })
}

///|
async test "sse middleware short circuit is compressed like a normal route" {
  let payload = "compressible ".repeat(200)
  let app = @feather.App::new()
    .compress(min_size=0)
    .use(fn(next) {
      fn(ctx) raise {
        ctx.text(200, payload)
        ignore(next)
      }
    })
    .sse("/events", async fn(_ctx, sse) { sse.send("unreachable") })
  with_sse_server(app, client => {
    let response = client.get(
      "/events",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept-Encoding"), "gzip"),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    ignore(client.read_all())
  })
}
