///|
fn method_request(method : String, path : String) -> @feather.Request {
  { method, path, headers: Map([]), body: "", }
}

///|
test "App exposes CONNECT and TRACE routes" {
  let app = @feather.App::new()
    .connect("/tunnel", fn(ctx) { ctx.text(200, "connect") })
    .trace("/echo", fn(ctx) { ctx.text(200, "trace") })

  let connect = app.respond(method_request("CONNECT", "/tunnel"))
  assert_eq(connect.status, 200)
  assert_eq(connect.body, "connect")

  let trace = app.respond(method_request("TRACE", "/echo"))
  assert_eq(trace.status, 200)
  assert_eq(trace.body, "trace")

  let wrong = app.respond(method_request("GET", "/tunnel"))
  assert_eq(wrong.status, 405)
}

///|
test "App all covers every standard HTTP method" {
  let app = @feather.App::new().all("/all", fn(ctx) { ctx.text(200, "ok") })
  for method in [
    "GET",
    "POST",
    "PUT",
    "PATCH",
    "DELETE",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
  ] {
    assert_true(app.has_route(method, "/all"))
    let response = app.respond(method_request(method, "/all"))
    // HEAD carries the same status but no body.
    assert_eq(response.status, 200)
    if method == "HEAD" {
      assert_eq(response.body, "")
    } else {
      assert_eq(response.body, "ok")
    }
  }
}

///|
test "group and facade all include CONNECT and TRACE" {
  let app = @feather.App::new()
  ignore(
    app
    .group("/g")
    .connect("/connect", fn(ctx) { ctx.text(200, "gc") })
    .trace("/trace", fn(ctx) { ctx.text(200, "gt") })
    .all("/all", fn(ctx) { ctx.text(200, "ga") }),
  )
  for method in ["CONNECT", "TRACE"] {
    let response = app.respond(method_request(method, "/g/all"))
    assert_eq(response.status, 200)
    assert_eq(response.body, "ga")
  }
  assert_eq(
    app.respond(method_request("CONNECT", "/g/connect")).body,
    "gc",
  )
  assert_eq(app.respond(method_request("TRACE", "/g/trace")).body, "gt")

  let facade = @feather.create_feather({
    host: "127.0.0.1",
    port: 0,
    timeout: 0,
  })
  ignore(
    facade
    .connect("/connect", fn(ctx) { ctx.text(200, "fc") })
    .trace("/trace", fn(ctx) { ctx.text(200, "ft") })
    .all("/all", fn(ctx) { ctx.text(200, "fa") }),
  )
  assert_eq(facade.handle(method_request("CONNECT", "/connect")).body, "fc")
  assert_eq(facade.handle(method_request("TRACE", "/trace")).body, "ft")
  assert_eq(facade.handle(method_request("CONNECT", "/all")).body, "fa")
  assert_eq(facade.handle(method_request("TRACE", "/all")).body, "fa")
}
