///|
fn cookie_security_context() -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
}

///|
test "a SameSite=None cookie is marked secure" {
  let ctx = cookie_security_context()
  ctx.set_cookie("sid", "1", same_site="None")
  let header = ctx.response.headers.get("Set-Cookie").unwrap()
  assert_true(header.contains("; Secure"), msg=header)
  assert_true(header.contains("; SameSite=None"), msg=header)
  assert_eq(ctx.response.cookies[0].secure, true)
}

///|
test "a SameSite=None cookie carries the secure attribute only once" {
  let ctx = cookie_security_context()
  ctx.set_cookie("sid", "1", same_site="None", secure=true)
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some("sid=1; Secure; SameSite=None"),
  )
}

///|
test "a SameSite=None cookie added without a header is marked secure" {
  let ctx = cookie_security_context()
  ctx.add_cookie("sid", "1", same_site="None")
  assert_eq(ctx.response.cookies.length(), 1)
  assert_eq(ctx.response.cookies[0].secure, true)
}

///|
test "a __Secure- cookie is marked secure" {
  let ctx = cookie_security_context()
  ctx.set_cookie("__Secure-token", "1", path="/")
  let header = ctx.response.headers.get("Set-Cookie").unwrap()
  assert_true(header.contains("; Secure"), msg=header)
  assert_true(header.has_prefix("__Secure-token=1"), msg=header)
  assert_eq(ctx.response.cookies[0].secure, true)
}

///|
test "a __Host- cookie is secure, root-scoped and host-only" {
  let ctx = cookie_security_context()
  ctx.set_cookie(
    "__Host-token",
    "1",
    path="/api",
    domain="example.com",
  )
  let header = ctx.response.headers.get("Set-Cookie").unwrap()
  assert_true(header.contains("; Secure"), msg=header)
  assert_true(header.contains("; Path=/"), msg=header)
  assert_false(header.contains("Domain"), msg=header)
  assert_false(header.contains("Path=/api"), msg=header)
  let cookie = ctx.response.cookies[0]
  assert_eq(cookie.secure, true)
  assert_eq(cookie.path, Some("/"))
  assert_eq(cookie.domain, None)
}

///|
test "a __Host- cookie without a path is bound to the root path" {
  let ctx = cookie_security_context()
  ctx.set_cookie("__Host-token", "1")
  let cookie = ctx.response.cookies[0]
  assert_eq(cookie.secure, true)
  assert_eq(cookie.path, Some("/"))
  assert_eq(cookie.domain, None)
}

///|
test "the cookie name prefixes are matched case-sensitively" {
  let ctx = cookie_security_context()
  ctx.set_cookie("__secure-token", "1")
  ctx.set_cookie("__host-token", "1")
  assert_eq(ctx.response.cookies[0].secure, false)
  assert_eq(ctx.response.cookies[1].secure, false)
}

///|
test "clearing a __Host- cookie keeps the host-only shape" {
  let ctx = cookie_security_context()
  ctx.clear_cookie("__Host-token", path="/api", domain="example.com")
  let cookie = ctx.response.cookies[0]
  assert_eq(cookie.secure, true)
  assert_eq(cookie.path, Some("/"))
  assert_eq(cookie.domain, None)
  assert_eq(cookie.max_age, Some(0L))
}

///|
test "a signed cookie follows the cookie attribute rules" {
  let ctx = cookie_security_context()
  ctx.set_signed_cookie(
    "__Host-token",
    "alice",
    "secret",
    same_site="None",
  )
  let cookie = ctx.response.cookies[0]
  assert_eq(cookie.secure, true)
  assert_eq(cookie.path, Some("/"))
}

///|
test "a session cookie with SameSite=None is marked secure" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store, same_site="None"))
    .get("/login", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, "ok")
    })
  let response = app.respond({
    method: "GET",
    path: "/login",
    headers: Map([]),
    body: "",
  })
  let header = response.headers.get("Set-Cookie").unwrap()
  assert_true(header.contains("; Secure"), msg=header)
  assert_true(header.contains("; SameSite=None"), msg=header)
}

///|
async test "the server sends a secure SameSite=None cookie" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store, same_site="None"))
    .get("/login", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, "ok")
    })
  with_raw_server(app, conn => {
    conn.write("GET /login HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n")
    let head = conn.read_all().text()
    assert_true(head.contains("SameSite=None"), msg=head)
    assert_true(head.contains("Secure"), msg=head)
  })
}

///|
async test "the server sends a secure __Host- cookie without a domain" {
  let app = @feather.App::new().get("/login", fn(ctx) {
    ctx.set_cookie("__Host-token", "1", domain="example.com")
    ctx.text(200, "ok")
  })
  with_raw_server(app, conn => {
    conn.write("GET /login HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n")
    let head = conn.read_all().text()
    assert_true(head.contains("Set-Cookie: __Host-token=1; Path=/; Secure"), msg=head)
    assert_false(head.contains("Domain"), msg=head)
  })
}
