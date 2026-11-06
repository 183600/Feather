///|
fn csrf_cookie_issue_pair(
  secret : String,
) -> (String, String) raise {
  let issue = @feather.Context::new({
    method: "GET",
    path: "/token",
    headers: Map([]),
    body: "",
  })
  @feather.apply_middleware(
    [@feather.middleware_csrf_cookie(secret)],
    fn(ctx) { ctx.text(200, ctx.csrf_cookie_token()) },
  )(issue)
  let cookie = issue.response.cookies[0]
  (issue.response.body, cookie.value)
}

///|
fn csrf_cookie_post(
  secret : String,
  headers : Map[String, String],
  body : String,
) -> @feather.Context raise {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/submit",
    headers,
    body,
  })
  @feather.apply_middleware(
    [@feather.middleware_csrf_cookie(secret)],
    fn(ctx) { ctx.text(200, "ok") },
  )(ctx)
  ctx
}

///|
test "csrf_cookie accepts the signed cookie value as the echoed token" {
  let secret = "csrf-cookie-secret"
  let (_, cookie_value) = csrf_cookie_issue_pair(secret)
  let ctx = csrf_cookie_post(
    secret,
    Map([
      ("Cookie", "feather_csrf=" + cookie_value),
      ("X-CSRF-Token", cookie_value),
    ]),
    "",
  )
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "ok")
}

///|
test "csrf_cookie accepts the signed cookie value in a form field" {
  let secret = "csrf-cookie-secret"
  let (_, cookie_value) = csrf_cookie_issue_pair(secret)
  let ctx = csrf_cookie_post(
    secret,
    Map([
      ("Cookie", "feather_csrf=" + cookie_value),
      ("Content-Type", "application/x-www-form-urlencoded"),
    ]),
    "_csrf=" + cookie_value,
  )
  assert_eq(ctx.response.status, 200)
}

///|
test "csrf_cookie still rejects a forged cookie value" {
  let secret = "csrf-cookie-secret"
  let ctx = csrf_cookie_post(
    secret,
    Map([
      ("Cookie", "feather_csrf=forged.value.signature"),
      ("X-CSRF-Token", "forged.value.signature"),
    ]),
    "",
  )
  assert_eq(ctx.response.status, 403)
}

///|
test "csrf_cookie still rejects a tampered signed cookie value" {
  let secret = "csrf-cookie-secret"
  let (_, cookie_value) = csrf_cookie_issue_pair(secret)
  let ctx = csrf_cookie_post(
    secret,
    Map([
      ("Cookie", "feather_csrf=" + cookie_value + "x"),
      ("X-CSRF-Token", cookie_value),
    ]),
    "",
  )
  assert_eq(ctx.response.status, 403)
}

///|
test "csrf_cookie still accepts the plain token" {
  let secret = "csrf-cookie-secret"
  let (token, cookie_value) = csrf_cookie_issue_pair(secret)
  let ctx = csrf_cookie_post(
    secret,
    Map([
      ("Cookie", "feather_csrf=" + cookie_value),
      ("X-CSRF-Token", token),
    ]),
    "",
  )
  assert_eq(ctx.response.status, 200)
}
