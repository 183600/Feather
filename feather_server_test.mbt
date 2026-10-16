///|
async fn with_server(
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
async test "server serves text route" {
  let app = @feather.App::new().get("/hello", fn(ctx) {
    ctx.text(200, "hello world")
  })
  with_server(app, client => {
    let response = client.get("/hello")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "hello world")
  })
}

///|
async test "server exposes route parameters" {
  let app = @feather.App::new().get("/users/:id", fn(ctx) {
    ctx.text(200, "user=" + ctx.param("id"))
  })
  with_server(app, client => {
    let response = client.get("/users/42")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "user=42")
  })
}

///|
async test "server serves json route" {
  let app = @feather.App::new().get("/api/status", fn(ctx) {
    ctx.json(200, { "ok": "true" })
  })
  with_server(app, client => {
    let response = client.get("/api/status")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "{\"ok\":\"true\"}")
  })
}

///|
async test "server returns 404 for unknown route" {
  let app = @feather.App::new().get("/known", fn(ctx) { ctx.text(200, "known") })
  with_server(app, client => {
    let response = client.get("/unknown")
    assert_eq(response.code, 404)
    assert_eq(client.read_all().text(), "404 Not Found")
  })
}

///|
async test "server returns 405 for wrong method" {
  let app = @feather.App::new().get("/resource", fn(ctx) { ctx.text(200, "ok") })
  with_server(app, client => {
    let response = client.post("/resource", "")
    assert_eq(response.code, 405)
    assert_eq(client.read_all().text(), "405 Method Not Allowed")
  })
}

///|
async test "server echoes form values" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    ctx.text(200, ctx.form("name"))
  })
  with_server(app, client => {
    let response = client.post(
      "/echo",
      "name=feather",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "application/x-www-form-urlencoded",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "feather")
  })
}

///|
async test "server reads query parameters" {
  let app = @feather.App::new().get("/search", fn(ctx) {
    ctx.text(200, ctx.query("q"))
  })
  with_server(app, client => {
    let response = client.get("/search?q=feather%20web")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "feather web")
  })
}

///|
async test "server serves wildcard route" {
  let app = @feather.App::new().get("/static/*path", fn(ctx) {
    ctx.text(200, "path=" + ctx.param("path"))
  })
  with_server(app, client => {
    let response = client.get("/static/css/app.css")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "path=css/app.css")
  })
}

///|
async test "server applies middleware" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors())
    .get("/hello", fn(ctx) { ctx.text(200, "hello") })
  with_server(app, client => {
    let response = client.get("/hello")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(
        @http.CaseInsensitiveString("Access-Control-Allow-Origin"),
      ),
      Some("*"),
    )
    ignore(client.read_all())
  })
}

///|
async test "server recovers from handler errors" {
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .get("/boom", fn(_ctx) raise { raise Failure("boom") })
  with_server(app, client => {
    let response = client.get("/boom")
    assert_eq(response.code, 500)
    assert_eq(client.read_all().text(), "Internal Server Error")
  })
}

///|
async test "server rejects oversized bodies" {
  let app = @feather.App::new().post("/upload", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_server(app, client => {
    let response = client.post("/upload", "x".repeat(2000))
    assert_eq(response.code, 413)
    ignore(client.read_all())
  })
}

///|
async test "server handles head requests" {
  let app = @feather.App::new().get("/head", fn(ctx) { ctx.text(200, "body") })
  with_server(app, client => {
    client.request(@http.RequestMethod::Head, "/head")
    let response = client.end_request()
    assert_eq(response.code, 200)
    ignore(client.read_all())
  })
}
