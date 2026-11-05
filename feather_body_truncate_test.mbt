///|
test "middleware_body_truncate truncates oversized request body" {
  let app = @feather.App::new()
    .use(@feather.middleware_body_truncate(5))
    .post("/echo", fn(ctx) {
      ctx.text(200, ctx.body_text())
    })
  let response = app.respond({
    method: "POST",
    path: "/echo",
    headers: Map([("Content-Type", "text/plain")]),
    body: "hello world",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "hello")
}

///|
test "middleware_body_truncate leaves small body unchanged" {
  let app = @feather.App::new()
    .use(@feather.middleware_body_truncate(10))
    .post("/echo", fn(ctx) {
      ctx.text(200, ctx.body_text())
    })
  let response = app.respond({
    method: "POST",
    path: "/echo",
    headers: Map([("Content-Type", "text/plain")]),
    body: "hello",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "hello")
}

///|
test "middleware_body_truncate with zero limit produces empty body" {
  let app = @feather.App::new()
    .use(@feather.middleware_body_truncate(0))
    .post("/echo", fn(ctx) {
      ctx.text(200, ctx.body_text())
    })
  let response = app.respond({
    method: "POST",
    path: "/echo",
    headers: Map([("Content-Type", "text/plain")]),
    body: "nonempty",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "")
}

///|
test "middleware_body_truncate negative limit behaves as zero" {
  let app = @feather.App::new()
    .use(@feather.middleware_body_truncate(-1))
    .post("/echo", fn(ctx) {
      ctx.text(200, ctx.body_text())
    })
  let response = app.respond({
    method: "POST",
    path: "/echo",
    headers: Map([("Content-Type", "text/plain")]),
    body: "x",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "")
}

///|
test "middleware_body_truncate works with body_bytes" {
  let app = @feather.App::new()
    .use(@feather.middleware_body_truncate(3))
    .post("/len", fn(ctx) {
      ctx.text(200, ctx.body_bytes().length().to_string())
    })
  let response = app.respond({
    method: "POST",
    path: "/len",
    headers: Map([]),
    body: "abcdef",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "3")
}
