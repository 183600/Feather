///|
async fn with_server3(
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
async test "probe server HEAD falls back to GET even when HEAD tree exists" {
  let app = @feather.App::new()
    .head("/only-head", fn(ctx) { ctx.text(200, "h") })
    .get("/only-get", fn(ctx) { ctx.text(200, "g") })
  with_server3(app, client => {
    client.request(@http.RequestMethod::Head, "/only-get")
    let response = client.end_request()
    assert_eq(response.code, 200)
    ignore(client.read_all())
  })
}

///|
async test "probe server keep alive post then get" {
  let app = @feather.App::new()
    .post("/echo", fn(ctx) { ctx.text(200, ctx.request.body) })
    .get("/ping", fn(ctx) { ctx.text(200, "pong") })
  with_server3(app, client => {
    let r1 = client.post("/echo", "hello")
    assert_eq(r1.code, 200)
    assert_eq(client.read_all().text(), "hello")
    let r2 = client.get("/ping")
    assert_eq(r2.code, 200)
    assert_eq(client.read_all().text(), "pong")
  })
}

///|
async test "probe server 405 allow header" {
  let app = @feather.App::new().get("/r", fn(ctx) { ctx.text(200, "g") })
  with_server3(app, client => {
    let response = client.post("/r", "")
    assert_eq(response.code, 405)
    match response.headers.get(@http.CaseInsensitiveString("Allow")) {
      Some(allow) => assert_true(allow.contains("GET"))
      None => fail("missing Allow header")
    }
    ignore(client.read_all())
  })
}

///|
async test "probe server OPTIONS with cors" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors())
    .get("/hello", fn(ctx) { ctx.text(200, "hello") })
  with_server3(app, client => {
    client.request(@http.RequestMethod::Options, "/hello")
    let response = client.end_request()
    assert_eq(response.code, 204)
    ignore(client.read_all())
  })
}

///|
async test "probe server middleware order" {
  let order : Array[String] = []
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        order.push("a")
        next(ctx)
        order.push("a2")
      }
    })
    .use(fn(next) {
      fn(ctx) raise {
        order.push("b")
        next(ctx)
        order.push("b2")
      }
    })
    .get("/o", fn(ctx) {
      order.push("h")
      ctx.text(200, "o")
    })
  with_server3(app, client => {
    let response = client.get("/o")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "o")
    assert_eq(order.join(","), "a,b,h,b2,a2")
  })
}

///|
async test "probe server param with nested route" {
  let app = @feather.App::new().get("/users/:id/posts/:pid", fn(ctx) {
    ctx.text(200, ctx.param("id") + "/" + ctx.param("pid"))
  })
  with_server3(app, client => {
    let response = client.get("/users/7/posts/9")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "7/9")
  })
}

///|
async test "probe server wildcard root" {
  let app = @feather.App::new().get("/files/*rest", fn(ctx) {
    ctx.text(200, ctx.param("rest"))
  })
  with_server3(app, client => {
    let response = client.get("/files/a/b/c.txt")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "a/b/c.txt")
  })
}
