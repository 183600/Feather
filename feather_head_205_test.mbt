///|
async test "HEAD reset content matches the GET zero length" {
  let app = @feather.App::new().get("/reset", fn(ctx) {
    ctx.text(205, "ignored")
  })
  with_server(app, client => {
    let get = client.get("/reset")
    assert_eq(get.code, 205)
    let get_length = get.headers.get(
      @http.CaseInsensitiveString("Content-Length"),
    )
    assert_eq(get_length, Some("0"))
    assert_eq(client.read_all().text(), "")

    client.request(@http.RequestMethod::Head, "/reset")
    let head = client.end_request()
    assert_eq(head.code, 205)
    assert_eq(
      head.headers.get(@http.CaseInsensitiveString("Content-Length")),
      get_length,
    )
    assert_eq(client.read_all().text(), "")
  })
}

///|
test "offline 205 responses frame zero length like the server" {
  let app = @feather.App::new().get("/reset", fn(ctx) {
    ctx.text(205, "ignored")
  })
  let get = app.respond({
    method: "GET",
    path: "/reset",
    headers: Map([]),
    body: "",
  })
  assert_eq(get.status, 205)
  assert_eq(get.headers.get("Content-Length"), Some("0"))
  assert_eq(get.headers.get("Content-Type"), None)
  assert_eq(get.body, "")

  let head = app.respond({
    method: "HEAD",
    path: "/reset",
    headers: Map([]),
    body: "",
  })
  assert_eq(head.status, 205)
  assert_eq(head.headers.get("Content-Length"), Some("0"))
  assert_eq(head.body, "")
}
