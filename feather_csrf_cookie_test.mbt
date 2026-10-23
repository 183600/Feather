///|
fn csrf_cookie_request(
  method : String,
  headers : Map[String, String],
  body : String,
) -> @feather.Context {
  @feather.Context::new({ method, path: "/submit", headers, body, })
}

///|
fn csrf_cookie_issue(
  secret : String,
  middleware? : @feather.Middleware,
) -> (String, String) raise {
  let handler = @feather.apply_middleware(
    [
      match middleware {
        Some(middleware) => middleware
        None => @feather.middleware_csrf_cookie(secret)
      },
    ],
    fn(ctx) { ctx.text(200, ctx.csrf_cookie_token()) },
  )
  let ctx = csrf_cookie_request("GET", Map([]), "")
  handler(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.cookies.length(), 1)
  (ctx.response.body, ctx.response.cookies[0].value)
}

///|
test "csrf_cookie issues a signed token on a safe request" {
  let secret = "csrf-cookie-secret"
  let (token, cookie_value) = csrf_cookie_issue(secret)
  assert_eq(token.length(), 32)
  assert_true(cookie_value != token)
  assert_eq(
    @feather.verify_signed_cookie_token(secret, "feather_csrf", cookie_value),
    Some(token),
  )
}

///|
test "csrf_cookie accepts a matching header token" {
  let secret = "csrf-cookie-secret"
  let (token, cookie_value) = csrf_cookie_issue(secret)
  let handler = @feather.apply_middleware(
    [@feather.middleware_csrf_cookie(secret)],
    fn(ctx) { ctx.text(200, "ok") },
  )
  let ctx = csrf_cookie_request(
    "POST",
    Map([
      ("Cookie", "feather_csrf=" + cookie_value),
      ("X-CSRF-Token", token),
    ]),
    "",
  )
  handler(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "ok")
}

///|
test "csrf_cookie rejects unsafe requests without a valid token cookie" {
  let secret = "csrf-cookie-secret"
  let handler = @feather.apply_middleware(
    [@feather.middleware_csrf_cookie(secret)],
    fn(ctx) { ctx.text(200, "ok") },
  )
  let missing = csrf_cookie_request(
    "POST",
    Map([("X-CSRF-Token", "token")]),
    "",
  )
  handler(missing)
  assert_eq(missing.response.status, 403)
  assert_eq(missing.response.cookies.length(), 0)
  let (token, cookie_value) = csrf_cookie_issue(secret)
  let tampered = csrf_cookie_request(
    "POST",
    Map([
      ("Cookie", "feather_csrf=" + cookie_value + "x"),
      ("X-CSRF-Token", token),
    ]),
    "",
  )
  handler(tampered)
  assert_eq(tampered.response.status, 403)
  let mismatched = csrf_cookie_request(
    "POST",
    Map([
      ("Cookie", "feather_csrf=" + cookie_value),
      ("X-CSRF-Token", "not-the-token"),
    ]),
    "",
  )
  handler(mismatched)
  assert_eq(mismatched.response.status, 403)
}

///|
test "csrf_cookie accepts form and multipart fields" {
  let secret = "csrf-cookie-secret"
  let (token, cookie_value) = csrf_cookie_issue(secret)
  let cookie = "feather_csrf=" + cookie_value
  let handler = @feather.apply_middleware(
    [@feather.middleware_csrf_cookie(secret)],
    fn(ctx) { ctx.text(200, "ok") },
  )
  let form = csrf_cookie_request(
    "PATCH",
    Map([
      ("Cookie", cookie),
      ("Content-Type", "application/x-www-form-urlencoded"),
    ]),
    "name=feather&_csrf=" + token,
  )
  handler(form)
  assert_eq(form.response.status, 200)
  let body = "--B\r\nContent-Disposition: form-data; name=\"_csrf\"\r\n\r\n" +
    token +
    "\r\n--B--\r\n"
  let multipart = csrf_cookie_request(
    "PUT",
    Map([
      ("Cookie", cookie),
      ("Content-Type", "multipart/form-data; boundary=B"),
    ]),
    body,
  )
  handler(multipart)
  assert_eq(multipart.response.status, 200)
}

///|
test "csrf_cookie supports custom cookie, field and header names" {
  let secret = "csrf-cookie-secret"
  let middleware = @feather.middleware_csrf_cookie(
    secret,
    cookie="xsrf",
    field="authenticity_token",
    header="X-XSRF-Token",
    max_age=120L,
  )
  let (token, cookie_value) = csrf_cookie_issue(secret, middleware~)
  let handler = @feather.apply_middleware(
    [middleware],
    fn(ctx) { ctx.text(200, "ok") },
  )
  let accepted = csrf_cookie_request(
    "POST",
    Map([("Cookie", "xsrf=" + cookie_value), ("X-XSRF-Token", token)]),
    "",
  )
  handler(accepted)
  assert_eq(accepted.response.status, 200)
  let default_header = csrf_cookie_request(
    "POST",
    Map([("Cookie", "xsrf=" + cookie_value), ("X-CSRF-Token", token)]),
    "",
  )
  handler(default_header)
  assert_eq(default_header.response.status, 403)
}

///|
test "csrf_cookie replaces an invalid cookie on safe requests" {
  let secret = "csrf-cookie-secret"
  let handler = @feather.apply_middleware(
    [@feather.middleware_csrf_cookie(secret)],
    fn(ctx) { ctx.text(200, ctx.csrf_cookie_token()) },
  )
  let ctx = csrf_cookie_request(
    "GET",
    Map([("Cookie", "feather_csrf=forged.value.signature")]),
    "",
  )
  handler(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body.length(), 32)
  assert_eq(ctx.response.cookies.length(), 1)
  let fresh = ctx.response.cookies[0].value
  assert_eq(
    @feather.verify_signed_cookie_token(secret, "feather_csrf", fresh),
    Some(ctx.response.body),
  )
}

///|
test "csrf_cookie honors custom safe methods" {
  let secret = "csrf-cookie-secret"
  let handler = @feather.apply_middleware(
    [@feather.middleware_csrf_cookie(secret, safe_methods=["POST"])],
    fn(ctx) { ctx.text(200, "ok") },
  )
  let post = csrf_cookie_request("POST", Map([]), "")
  handler(post)
  assert_eq(post.response.status, 200)
  assert_eq(post.response.body, "ok")
  let get = csrf_cookie_request("GET", Map([]), "")
  handler(get)
  assert_eq(get.response.status, 403)
}

///|
test "csrf_cookie token is empty without the middleware" {
  let ctx = csrf_cookie_request("GET", Map([]), "")
  assert_eq(ctx.csrf_cookie_token(), "")
}
