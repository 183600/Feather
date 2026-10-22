///|
async test "HEAD empty body drops seeded content length like GET" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("Content-Length", "999")
        next(ctx)
      }
    })
    .get("/empty", fn(_ctx) { () })
  with_server(app, client => {
    let get_response = client.get("/empty")
    let get_length = get_response.headers.get(
      @http.CaseInsensitiveString("Content-Length"),
    )
    assert_eq(get_length, Some("0"))
    assert_eq(client.read_all().text(), "")
    client.request(@http.RequestMethod::Head, "/empty")
    let head_response = client.end_request()
    assert_eq(
      head_response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      get_length,
    )
    assert_eq(client.read_all().text(), "")
  })
}

///|
test "offline HEAD empty body drops seeded content length" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("Content-Length", "999")
        next(ctx)
      }
    })
    .get("/empty", fn(_ctx) { () })
  let head = app.respond({
    method: "HEAD",
    path: "/empty",
    headers: Map([]),
    body: "",
  })
  assert_eq(head.status, 200)
  assert_eq(head.headers.get("Content-Length"), Some("0"))
  assert_eq(head.body, "")
  assert_eq(head.data, None)
}
