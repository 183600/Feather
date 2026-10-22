///|
test "offline absolute-form targets replace the Host header" {
  let app = @feather.App::new().get("/who", fn(ctx) {
    ctx.json(200, { "host": ctx.host(), "url": ctx.full_url() })
  })
  let response = app.respond({
    method: "GET",
    path: "http://target.example:8080/who",
    headers: Map([("Host", "ignored.example")]),
    body: "",
  })
  assert_eq(response.status, 200)
  let parsed = @json.parse(response.body) catch { _ => Json::null() }
  assert_eq(parsed, {
    "host": "target.example",
    "url": "http://target.example:8080/who",
  })
}

///|
test "offline absolute-form target authority still honors userinfo stripping" {
  let app = @feather.App::new().get("/who", fn(ctx) {
    ctx.text(200, ctx.host())
  })
  let response = app.respond({
    method: "GET",
    path: "http://user:secret@target.example/who",
    headers: Map([("Host", "ignored.example")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "target.example")
}
