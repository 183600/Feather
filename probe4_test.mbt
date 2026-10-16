///|
async fn with_server4(
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
async test "probe server lowercase content-type form" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    ctx.text(200, ctx.header("Content-Type") + "|" + ctx.form("name"))
  })
  with_server4(app, client => {
    let response = client.post(
      "/echo",
      "name=feather",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("content-type"),
          "application/x-www-form-urlencoded",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    let text = client.read_all().text()
    assert_eq(text, "application/x-www-form-urlencoded|feather")
  })
}

///|
async test "probe server enforces custom body size at boundary" {
  let app = @feather.App::new()
    .max_body_size(5)
    .post("/echo", fn(ctx) { ctx.text(200, ctx.request.body) })
  with_server4(app, client => {
    let ok = client.post("/echo", "12345")
    assert_eq(ok.code, 200)
    assert_eq(client.read_all().text(), "12345")
    let too_big = client.post("/echo", "123456")
    assert_eq(too_big.code, 413)
    ignore(client.read_all())
  })
}
