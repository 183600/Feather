///|
test "route body limit applies to parameter and wildcard patterns" {
  let app = @feather.App::new()
    .post("/items/:id", fn(ctx) { ctx.text(200, ctx.request.body) })
    .post("/files/*path", fn(ctx) { ctx.text(200, ctx.request.body) })
    .route_body_limit("POST", "/items/:id", 25)
    .route_body_limit("POST", "/files/*path", 75)
  assert_eq(app.router.body_limit_for("POST", "/items/42"), 25)
  assert_eq(app.router.body_limit_for("HEAD", "/items/42"), 0)
  assert_eq(app.router.body_limit_for("POST", "/files/a/b"), 75)
  assert_eq(app.router.body_limit_for("POST", "/other"), 0)
}

///|
test "route body limit can be cleared and is reset by re-registration" {
  let app = @feather.App::new()
    .post("/items/:id", fn(ctx) { ctx.text(200, ctx.request.body) })
    .route_body_limit("POST", "/items/:id", 25)
  assert_eq(app.router.body_limit_for("POST", "/items/1"), 25)
  ignore(app.route_body_limit("POST", "/items/:id", 0))
  assert_eq(app.router.body_limit_for("POST", "/items/1"), 0)
  ignore(app.route_body_limit("POST", "/items/:id", 25))
  ignore(app.post("/items/:id", fn(ctx) { ctx.text(201, ctx.request.body) }))
  assert_eq(app.router.body_limit_for("POST", "/items/1"), 0)
}

///|
test "route body limit through a group uses the prefixed path" {
  let app = @feather.App::new()
  let group = app.group("/api")
    .post("/upload", fn(ctx) { ctx.text(200, ctx.request.body) })
    .route_body_limit("POST", "/upload", 30)
  ignore(group)
  assert_eq(app.router.body_limit_for("POST", "/api/upload"), 30)
  assert_eq(app.router.body_limit_for("POST", "/upload"), 0)
}

///|
test "the feather facade forwards route body limits" {
  let feather = @feather.create_feather({
    host: "127.0.0.1",
    port: 0,
    timeout: 0,
  })
  ignore(feather.post("/upload", fn(ctx) { ctx.text(200, ctx.request.body) }))
  ignore(feather.route_body_limit("POST", "/upload", 15))
  assert_eq(feather.app.router.body_limit_for("POST", "/upload"), 15)
}

///|
test "mounted routes keep their per-route body limit" {
  let child = @feather.App::new()
    .post("/upload", fn(ctx) { ctx.text(200, ctx.request.body) })
    .route_body_limit("POST", "/upload", 40)
  let parent = @feather.App::new().mount("/api", child)
  assert_eq(parent.router.body_limit_for("POST", "/api/upload"), 40)
}

///|
async test "a route body limit overrides the application limit" {
  let app = @feather.App::new()
    .max_body_size(1000)
    .post("/small", fn(ctx) { ctx.text(200, ctx.request.body) })
    .post("/normal", fn(ctx) { ctx.text(200, ctx.request.body) })
    .route_body_limit("POST", "/small", 4)
  with_server(app, client => {
    let accepted = client.post("/normal", "hello")
    assert_eq(accepted.code, 200)
    assert_eq(client.read_all().text(), "hello")
    let rejected = client.post("/small", "hello")
    assert_eq(rejected.code, 413)
    ignore(client.read_all())
  })
}

///|
async test "a route body limit can raise the application limit" {
  let app = @feather.App::new()
    .max_body_size(4)
    .post("/big", fn(ctx) { ctx.text(200, ctx.request.body) })
    .post("/normal", fn(ctx) { ctx.text(200, ctx.request.body) })
    .route_body_limit("POST", "/big", 10)
  with_server(app, client => {
    let accepted = client.post("/big", "hello")
    assert_eq(accepted.code, 200)
    assert_eq(client.read_all().text(), "hello")
    let rejected = client.post("/normal", "hello")
    assert_eq(rejected.code, 413)
    ignore(client.read_all())
  })
}

///|
async test "declared body limit uses the matching route override" {
  let app = @feather.App::new()
    .post("/small", fn(ctx) { ctx.text(200, ctx.request.body) })
    .route_body_limit("POST", "/small", 4)
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "POST /small HTTP/1.1\r\nHost: test\r\nContent-Length: 5\r\n\r\n",
      ),
    )
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 413"), msg=head)
  })
}

///|
async test "gzip route body limit applies to the decoded representation" {
  let payload = gzip_limit_payload()
  let compressed = gzip_encode_for_test(payload)
  assert_true(compressed.length() > payload.length())
  let app = @feather.App::new()
    .max_body_size(1)
    .post("/echo", fn(ctx) {
      ctx.text(200, ctx.body_bytes().length().to_string())
    })
    .route_body_limit("POST", "/echo", payload.length())
  with_raw_server(app, conn => {
    write_gzip_request(conn, "POST", "/echo", compressed)
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
  })
}
