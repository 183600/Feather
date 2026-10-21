///|
test "set_cookie renders an absolute expiry" {
  let ctx = @feather.create_context()
  ctx.set_cookie("sid", "1", path="/", expires=0L)
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some("sid=1; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT"),
  )
  assert_eq(
    ctx.response.cookies[0].expires_raw,
    Some("Thu, 01 Jan 1970 00:00:00 GMT"),
  )
}

///|
test "set_cookie can combine expires and max_age" {
  let ctx = @feather.create_context()
  ctx.set_cookie("sid", "1", max_age=60L, expires=784111777L)
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some(
      "sid=1; Expires=" +
      @feather.format_http_date(784111777L) +
      "; Max-Age=60",
    ),
  )
}

///|
test "add_cookie records an expiry without a raw header" {
  let ctx = @feather.create_context()
  ctx.add_cookie("pref", "dark", expires=0L)
  assert_eq(ctx.response.headers.get("Set-Cookie"), None)
  assert_eq(
    ctx.response.cookies[0].expires_raw,
    Some("Thu, 01 Jan 1970 00:00:00 GMT"),
  )
}

///|
test "signed cookies honor an absolute expiry" {
  let now = @async.now() / 1000L
  let live = @feather.create_context()
  live.set_signed_cookie("user", "alice", "s3cret", expires=now + 3600L)
  let live_header = live.response.headers.get("Set-Cookie").unwrap()
  assert_true(live_header.contains("Expires="))
  let live_reader = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("Cookie", "user=" + signed_test_cookie_value(live_header, "user")),
    ]),
    body: "",
  })
  assert_eq(live_reader.signed_cookie("user", "s3cret"), Some("alice"))

  let expired = @feather.create_context()
  expired.set_signed_cookie("user", "alice", "s3cret", expires=now - 10L)
  let expired_header = expired.response.headers.get("Set-Cookie").unwrap()
  let expired_reader = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("Cookie", "user=" + signed_test_cookie_value(expired_header, "user")),
    ]),
    body: "",
  })
  assert_eq(expired_reader.signed_cookie("user", "s3cret"), None)
}

///|
async test "server sends a Date-formatted cookie expiry" {
  let app = @feather.App::new().get("/set", fn(ctx) {
    ctx.set_cookie("sid", "1", path="/", expires=0L)
    ctx.text(200, "ok")
  })
  with_server(app, client => {
    let response = client.get("/set")
    assert_eq(response.code, 200)
    assert_eq(response.cookies.length(), 1)
    assert_eq(
      response.cookies[0].expires_raw,
      Some("Thu, 01 Jan 1970 00:00:00 GMT"),
    )
    ignore(client.read_all())
  })
}
