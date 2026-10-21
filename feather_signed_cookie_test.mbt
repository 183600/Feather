///|
fn signed_test_cookie_value(set_cookie : String, name : String) -> String {
  let prefix = name + "="
  let start = set_cookie.find(prefix).unwrap() + prefix.length()
  let rest = set_cookie[start:]
  match rest.find(";") {
    Some(end) => rest[:end].to_owned()
    None => rest.to_owned()
  }
}

///|
test "signed_cookie_token round-trips and rejects tampering" {
  let token = @feather.signed_cookie_token("s3cret", "user", "alice")
  assert_eq(
    @feather.verify_signed_cookie_token("s3cret", "user", token),
    Some("alice"),
  )
  assert_eq(
    @feather.verify_signed_cookie_token("other-secret", "user", token),
    None,
  )
  assert_eq(@feather.verify_signed_cookie_token("s3cret", "admin", token), None)
  let tail = token.view().unsafe_get(token.length() - 1).unsafe_to_char()
  let replacement = if tail == 'a' { 'b' } else { 'a' }
  let tampered = token[:token.length() - 1].to_owned() + replacement.to_string()
  assert_eq(
    @feather.verify_signed_cookie_token("s3cret", "user", tampered),
    None,
  )
}

///|
test "signed_cookie_token rejects malformed tokens" {
  assert_eq(@feather.verify_signed_cookie_token("s", "user", ""), None)
  assert_eq(@feather.verify_signed_cookie_token("s", "user", "alice"), None)
  assert_eq(@feather.verify_signed_cookie_token("s", "user", "a.b"), None)
  assert_eq(@feather.verify_signed_cookie_token("s", "user", "a.b.c.d"), None)
  assert_eq(@feather.verify_signed_cookie_token("s", "user", "a.x.b"), None)
  assert_eq(@feather.verify_signed_cookie_token("s", "user", "a.0.!!!"), None)
  assert_eq(
    @feather.verify_signed_cookie_token(
      "s",
      "user",
      @feather.signed_cookie_token("s", "user", "alice") + ".junk",
    ),
    None,
  )
}

///|
test "signed_cookie_token honours embedded expiry deadlines" {
  let token = @feather.signed_cookie_token(
    "s3cret",
    "user",
    "alice",
    expires_at=5_000L,
  )
  assert_eq(
    @feather.verify_signed_cookie_token("s3cret", "user", token, now=4_999L),
    Some("alice"),
  )
  assert_eq(
    @feather.verify_signed_cookie_token("s3cret", "user", token, now=5_000L),
    None,
  )
  assert_eq(
    @feather.verify_signed_cookie_token("s3cret", "user", token, now=5_001L),
    None,
  )
  let forever = @feather.signed_cookie_token("s3cret", "user", "alice")
  assert_eq(
    @feather.verify_signed_cookie_token(
      "s3cret",
      "user",
      forever,
      now=1_000_000_000_000L,
    ),
    Some("alice"),
  )
}

///|
test "signed_cookie_token rejects a negative expiry deadline" {
  let token = @feather.signed_cookie_token(
    "s3cret",
    "user",
    "alice",
    expires_at=-1L,
  )
  assert_eq(@feather.verify_signed_cookie_token("s3cret", "user", token), None)
}

///|
test "signed_cookie_token preserves arbitrary value text" {
  let value = "héllo wörld/+=;,\u{1F600}"
  let token = @feather.signed_cookie_token("s3cret", "note", value)
  assert_eq(
    @feather.verify_signed_cookie_token("s3cret", "note", token),
    Some(value),
  )
}

///|
test "Context signed cookies round-trip through the Set-Cookie header" {
  let setter = @feather.create_context()
  setter.set_signed_cookie(
    "user",
    "alice",
    "s3cret",
    path="/",
    max_age=3600L,
    same_site="Lax",
    http_only=true,
    secure=true,
  )
  let set_cookie = setter.response.headers.get("Set-Cookie").unwrap()
  let token = signed_test_cookie_value(set_cookie, "user")
  let reader = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "user=" + token)]),
    body: "",
  })
  assert_eq(reader.signed_cookie("user", "s3cret"), Some("alice"))
  assert_eq(reader.signed_cookie("user", "wrong-secret"), None)
  assert_eq(reader.signed_cookie("other", "s3cret"), None)
}

///|
test "signed cookies are rejected after tampering during a request" {
  let app = @feather.App::new().get("/read", fn(ctx) {
    match ctx.signed_cookie("user", "s3cret") {
      Some(name) => ctx.text(200, name)
      None => ctx.text(401, "invalid")
    }
  })
  let token = @feather.signed_cookie_token("s3cret", "user", "alice")
  let ok = app.respond({
    method: "GET",
    path: "/read",
    headers: Map([("Cookie", "user=" + token)]),
    body: "",
  })
  assert_eq(ok.status, 200)
  assert_eq(ok.body, "alice")
  let tampered = app.respond({
    method: "GET",
    path: "/read",
    headers: Map([("Cookie", "user=" + token + "x")]),
    body: "",
  })
  assert_eq(tampered.status, 401)
  assert_eq(tampered.body, "invalid")
  let missing = app.respond({
    method: "GET",
    path: "/read",
    headers: Map([]),
    body: "",
  })
  assert_eq(missing.status, 401)
}

///|
test "signed cookies expire through Context helpers" {
  let setter = @feather.create_context()
  setter.set_signed_cookie("user", "alice", "s3cret", max_age=-10L)
  let set_cookie = setter.response.headers.get("Set-Cookie").unwrap()
  let token = signed_test_cookie_value(set_cookie, "user")
  let reader = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "user=" + token)]),
    body: "",
  })
  assert_eq(reader.signed_cookie("user", "s3cret"), None)
}

///|
test "signed cookies reject negative max_age values that overflow milliseconds" {
  let setter = @feather.create_context()
  setter.set_signed_cookie(
    "user",
    "alice",
    "s3cret",
    max_age=-9223372036854775804L,
  )
  let set_cookie = setter.response.headers.get("Set-Cookie").unwrap()
  let token = signed_test_cookie_value(set_cookie, "user")
  let reader = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "user=" + token)]),
    body: "",
  })
  assert_eq(reader.signed_cookie("user", "s3cret"), None)
}

///|
test "signed cookies reject negative expires values that overflow milliseconds" {
  let setter = @feather.create_context()
  setter.set_signed_cookie(
    "user",
    "alice",
    "s3cret",
    expires=-9223372034854775808L,
  )
  let set_cookie = setter.response.headers.get("Set-Cookie").unwrap()
  let token = signed_test_cookie_value(set_cookie, "user")
  let reader = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "user=" + token)]),
    body: "",
  })
  assert_eq(reader.signed_cookie("user", "s3cret"), None)
}

///|
test "set_signed_cookie without max_age signs a session cookie" {
  let setter = @feather.create_context()
  setter.set_signed_cookie("user", "alice", "s3cret")
  let set_cookie = setter.response.headers.get("Set-Cookie").unwrap()
  assert_eq(set_cookie.view().find("Max-Age"), None)
  let token = signed_test_cookie_value(set_cookie, "user")
  let reader = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "user=" + token)]),
    body: "",
  })
  assert_eq(reader.signed_cookie("user", "s3cret"), Some("alice"))
}

///|
test "clear_signed_cookie expires the cookie for the client" {
  let ctx = @feather.create_context()
  ctx.clear_signed_cookie("user", path="/")
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some("user=; Path=/; Max-Age=0"),
  )
}
