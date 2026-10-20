///|
fn cookie_attr_ctx() -> Context {
  Context::new({ method: "GET", path: "/", headers: Map([]), body: "" })
}

///|
test "set_cookie renders the partitioned attribute" {
  let ctx = cookie_attr_ctx()
  ctx.set_cookie(
    "sid",
    "1",
    path="/",
    same_site="None",
    secure=true,
    partitioned=true,
  )
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some("sid=1; Path=/; Secure; SameSite=None; Partitioned"),
  )
  assert_eq(ctx.response.cookies.length(), 1)
  let cookie = ctx.response.cookies[0]
  assert_eq(cookie.extensions.length(), 2)
  assert_eq(cookie.extensions[0], "SameSite=None")
  assert_eq(cookie.extensions[1], "Partitioned")
}

///|
test "add_cookie records the partitioned attribute" {
  let ctx = cookie_attr_ctx()
  ctx.add_cookie("pref", "dark", partitioned=true)
  assert_eq(ctx.response.headers.get("Set-Cookie"), None)
  assert_eq(ctx.response.cookies.length(), 1)
  let cookie = ctx.response.cookies[0]
  assert_eq(cookie.extensions.length(), 1)
  assert_eq(cookie.extensions[0], "Partitioned")
}

///|
test "cookies leave partitioned off by default" {
  let ctx = cookie_attr_ctx()
  ctx.set_cookie("sid", "1", path="/")
  assert_eq(ctx.response.headers.get("Set-Cookie"), Some("sid=1; Path=/"))
}

///|
test "signed cookies can be partitioned" {
  let ctx = cookie_attr_ctx()
  ctx.set_signed_cookie(
    "token",
    "alice",
    "secret",
    path="/",
    secure=true,
    partitioned=true,
  )
  let header = match ctx.response.headers.get("Set-Cookie") {
    Some(header) => header
    None => fail("missing Set-Cookie")
  }
  assert_true(header.has_suffix("; Secure; Partitioned"))
  assert_eq(
    verify_signed_cookie_token("secret", "token", ctx.response.cookies[0].value),
    Some("alice"),
  )
}

///|
test "session cookies can be partitioned" {
  let store = SessionStore::new(ttl=3_600_000L)
  let app = App::new()
    .use(
      middleware_session(
        store,
        same_site="None",
        secure=true,
        partitioned=true,
      ),
    )
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
  assert_eq(response.cookies.length(), 1)
  let cookie = response.cookies[0]
  assert_eq(cookie.extensions.length(), 2)
  assert_eq(cookie.extensions[0], "SameSite=None")
  assert_eq(cookie.extensions[1], "Partitioned")
}

///|
test "set_cookie replaces a case-variant raw header" {
  let ctx = @feather.create_context()
  ctx.set_header("set-cookie", "forged=1")
  ctx.set_cookie("sid", "1", path="/")
  let mut count = 0
  for key, _ in ctx.response.headers {
    if key.view().equal_ignore_ascii_case("set-cookie".view()) {
      count = count + 1
    }
  }
  assert_eq(count, 1)
  assert_eq(ctx.response.headers.get("Set-Cookie"), Some("sid=1; Path=/"))
}
