///|
fn absolute_target_validation_request(path : String) -> @feather.Request {
  {
    method: "GET",
    path,
    headers: Map([("Host", "original.example")]),
    body: "",
  }
}

///|
test "malformed absolute-form authorities are not normalized" {
  let app = @feather.App::new().get("/x", fn(ctx) {
    ctx.text(200, ctx.host())
  })
  for target in [
    "http://exa mple.com/x",
    "http://example.com:bad/x",
    "http://example.com:70000/x",
    "http://[::1]junk/x",
    "http://[not-an-ip]/x",
    "http://user@/x",
    "http://:8080/x",
  ] {
    let response = app.respond(absolute_target_validation_request(target))
    assert_eq(response.status, 404, msg=target)
  }
}

///|
test "valid absolute-form authorities still replace the host" {
  let app = @feather.App::new().get("/x", fn(ctx) {
    ctx.text(200, ctx.host())
  })
  let userinfo = app.respond(
    absolute_target_validation_request("http://user@example.com/x"),
  )
  assert_eq(userinfo.status, 200)
  assert_eq(userinfo.body, "example.com")
  let ipv6 = app.respond(
    absolute_target_validation_request("http://[2001:db8::1]:8080/x"),
  )
  assert_eq(ipv6.status, 200)
  assert_eq(ipv6.body, "[2001:db8::1]")
}
