///|
fn unknown_port_ctx(headers : Map[String, String]) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers,
    body: "",
  })
}

///|
test "forwarded_ip skips an unknown node that carries a port" {
  let ctx = unknown_port_ctx(
    Map([
      ("Forwarded", "for=unknown:4711"),
      ("X-Forwarded-For", "203.0.113.9"),
    ]),
  )
  assert_eq(ctx.forwarded_ip(), "203.0.113.9")
}

///|
test "trusted proxy chain treats unknown with a port as addressless" {
  let app = @feather.App::new()
    .trust_proxy(1)
    .use(fn(next) {
      fn(ctx) {
        ctx.state.set("remote_addr", "10.0.0.9")
        next(ctx)
      }
    })
    .get("/ip", fn(ctx) { ctx.text(200, ctx.ip()) })
  let response = app.respond({
    method: "GET",
    path: "/ip",
    headers: Map([
      ("Forwarded", "for=unknown:4711"),
      ("X-Forwarded-For", "203.0.113.9"),
    ]),
    body: "",
  })
  assert_eq(response.body, "10.0.0.9")
}
