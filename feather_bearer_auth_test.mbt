///|
test "context bearer_token parses RFC 6750 token68 values" {
  for header in [
    "Bearer abc.def",
    "bearer\tYWJjZA==",
    "Bearer abc+/_-~",
  ] {
    let ctx = @feather.Context::new({
      method: "GET",
      path: "/",
      headers: Map([("Authorization", header)]),
      body: "",
    })
    assert_true(ctx.bearer_token() is Some(_))
  }
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Authorization", "Bearer abc=")]),
    body: "",
  })
  assert_eq(ctx.bearer_token(), Some("abc="))
  let basic = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Authorization", "Basic abc")]),
    body: "",
  })
  assert_eq(basic.bearer_token(), None)
}

///|
test "context bearer_token rejects malformed credentials" {
  for header in [
    "Bearer",
    "Bearer ",
    "Bearer    ",
    "Bearer abc def",
    "Bearer abc\r\nX-Evil: 1",
    "Bearer abc!",
    "Bearer ==",
    "Bearer abc==def",
  ] {
    let ctx = @feather.Context::new({
      method: "GET",
      path: "/",
      headers: Map([("Authorization", header)]),
      body: "",
    })
    assert_eq(ctx.bearer_token(), None)
  }
}

///|
test "bearer auth middleware challenges missing and invalid tokens" {
  let calls = Ref(0)
  let app = @feather.App::new()
    .use(@feather.middleware_bearer_auth(["secret"]))
    .get("/private", fn(ctx) {
      calls.val = calls.val + 1
      ctx.text(200, "ok")
    })
  for headers in [
    Map([]),
    Map([("Authorization", "Basic secret")]),
    Map([("Authorization", "Bearer wrong")]),
    Map([("Authorization", "Bearer secret extra")]),
  ] {
    let response = app.respond({
      method: "GET",
      path: "/private",
      headers,
      body: "",
    })
    assert_eq(response.status, 401)
    assert_eq(
      response.headers.get("WWW-Authenticate"),
      Some("Bearer realm=\"Restricted\""),
    )
    assert_eq(response.body, "401 Unauthorized")
  }
  assert_eq(calls.val, 0)
}

///|
test "bearer auth middleware accepts configured tokens" {
  let tokens : Array[String] = ["alpha", "beta=="]
  let app = @feather.App::new()
    .use(@feather.middleware_bearer_auth(tokens))
    .get("/private", fn(ctx) { ctx.text(200, "welcome") })
  for token in ["alpha", "beta=="] {
    let response = app.respond({
      method: "GET",
      path: "/private",
      headers: Map([("Authorization", "Bearer " + token)]),
      body: "",
    })
    assert_eq(response.status, 200)
    assert_eq(response.body, "welcome")
  }
}

///|
test "bearer auth middleware with predicate and realm" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_bearer_auth_with(
        fn(token) { token.has_prefix("team-") },
        realm="say \"hi\"\\now",
      ),
    )
    .get("/area", fn(ctx) { ctx.text(200, "inside") })
  let rejected = app.respond({
    method: "GET",
    path: "/area",
    headers: Map([("Authorization", "Bearer user-1")]),
    body: "",
  })
  assert_eq(rejected.status, 401)
  assert_eq(
    rejected.headers.get("WWW-Authenticate"),
    Some("Bearer realm=\"say \\\"hi\\\"\\\\now\""),
  )
  let accepted = app.respond({
    method: "GET",
    path: "/area",
    headers: Map([("Authorization", "Bearer team-1")]),
    body: "",
  })
  assert_eq(accepted.status, 200)
  assert_eq(accepted.body, "inside")
}
