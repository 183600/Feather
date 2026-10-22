///|
fn lone_surrogate_text(prefix : String, suffix : String) -> String {
  prefix + String::from_array([Char::from_int(0xD800)]) + suffix
}

///|
test "cookies drop lone surrogates from names values and paths" {
  let ctx = @feather.create_context()
  ctx.set_cookie(
    lone_surrogate_text("a", "b"),
    lone_surrogate_text("x", "y"),
    path="/p" + String::from_array([Char::from_int(0xDC00)]) + "q",
  )
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some("ab=xy; Path=/pq"),
  )
}

///|
async test "server sends cookies after dropping lone surrogates" {
  let app = @feather.App::new().get("/set", fn(ctx) {
    ctx.set_cookie("token", lone_surrogate_text("a", "b"))
    ctx.text(200, "ok")
  })
  with_server(app, client => {
    let response = client.get("/set")
    assert_eq(response.code, 200)
    assert_eq(response.cookies.length(), 1)
    assert_eq(response.cookies[0].name, "token")
    assert_eq(response.cookies[0].value, "ab")
    ignore(client.read_all())
  })
}
