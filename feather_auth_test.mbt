///|
test "context basic_auth parses credentials" {
  let token = @feather.base64_encode(@utf8.encode("alice:s3cret"))
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/private",
    headers: Map([("Authorization", "Basic " + token)]),
    body: "",
  })
  assert_eq(ctx.basic_auth(), Some(("alice", "s3cret")))
}

///|
test "context basic_auth keeps colons inside the password" {
  let token = @feather.base64_encode(@utf8.encode("alice:a:b:c"))
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/private",
    headers: Map([("Authorization", "basic " + token)]),
    body: "",
  })
  assert_eq(ctx.basic_auth(), Some(("alice", "a:b:c")))
}

///|
test "context basic_auth rejects other schemes and bad payloads" {
  let empty = @feather.Context::new({
    method: "GET",
    path: "/private",
    headers: Map([]),
    body: "",
  })
  assert_eq(empty.basic_auth(), None)
  let bearer = @feather.Context::new({
    method: "GET",
    path: "/private",
    headers: Map([("Authorization", "Bearer abc")]),
    body: "",
  })
  assert_eq(bearer.basic_auth(), None)
  let malformed = @feather.Context::new({
    method: "GET",
    path: "/private",
    headers: Map([("Authorization", "Basic !!!!")]),
    body: "",
  })
  assert_eq(malformed.basic_auth(), None)
  let no_colon = @feather.Context::new({
    method: "GET",
    path: "/private",
    headers: Map([
      ("Authorization", "Basic " + @feather.base64_encode(b"alice")),
    ]),
    body: "",
  })
  assert_eq(no_colon.basic_auth(), Some(("alice", "")))
}

///|
test "context basic_auth rejects empty credentials" {
  for header in ["Basic ", "Basic \t ", "Basic\r\n"] {
    let ctx = @feather.Context::new({
      method: "GET",
      path: "/private",
      headers: Map([("Authorization", header)]),
      body: "",
    })
    assert_eq(ctx.basic_auth(), None)
  }
  let empty_pair = @feather.Context::new({
    method: "GET",
    path: "/private",
    headers: Map([
      ("Authorization", "Basic " + @feather.base64_encode(@utf8.encode(":"))),
    ]),
    body: "",
  })
  assert_eq(empty_pair.basic_auth(), Some(("", "")))
}

///|
test "context basic_auth rejects CRLF after the scheme" {
  let token = @feather.base64_encode(@utf8.encode("alice:s3cret"))
  for header in ["Basic\r\n" + token, "Basic\r" + token, "Basic\n" + token] {
    let ctx = @feather.Context::new({
      method: "GET",
      path: "/private",
      headers: Map([("Authorization", header)]),
      body: "",
    })
    assert_eq(ctx.basic_auth(), None, msg=header)
  }
}

///|
test "basic auth middleware challenges missing credentials" {
  let app = @feather.App::new()
    .use(@feather.middleware_basic_auth(Map([("admin", "secret")])))
    .get("/private", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/private",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 401)
  assert_eq(
    response.headers.get("WWW-Authenticate"),
    Some("Basic realm=\"Restricted\""),
  )
  assert_eq(response.body, "401 Unauthorized")
}

///|
test "basic auth middleware accepts valid credentials" {
  let app = @feather.App::new()
    .use(@feather.middleware_basic_auth(Map([("admin", "secret")])))
    .get("/private", fn(ctx) { ctx.text(200, "welcome") })
  let token = @feather.base64_encode(@utf8.encode("admin:secret"))
  let response = app.respond({
    method: "GET",
    path: "/private",
    headers: Map([("Authorization", "Basic " + token)]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "welcome")
}

///|
test "basic auth middleware rejects wrong credentials" {
  let calls = Ref(0)
  let app = @feather.App::new()
    .use(@feather.middleware_basic_auth(Map([("admin", "secret")])))
    .get("/private", fn(ctx) {
      calls.val = calls.val + 1
      ctx.text(200, "welcome")
    })
  let wrong_user = @feather.base64_encode(@utf8.encode("root:secret"))
  let wrong_password = @feather.base64_encode(@utf8.encode("admin:nope"))
  for token in [wrong_user, wrong_password] {
    let response = app.respond({
      method: "GET",
      path: "/private",
      headers: Map([("Authorization", "Basic " + token)]),
      body: "",
    })
    assert_eq(response.status, 401)
  }
  assert_eq(calls.val, 0)
}

///|
test "basic auth middleware with predicate" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_basic_auth_with(
        fn(username, password) { username == "u" && password.length() == 4 },
        realm="Admin Area",
      ),
    )
    .get("/area", fn(ctx) { ctx.text(200, "inside") })
  let response = app.respond({
    method: "GET",
    path: "/area",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 401)
  assert_eq(
    response.headers.get("WWW-Authenticate"),
    Some("Basic realm=\"Admin Area\""),
  )
  let token = @feather.base64_encode(@utf8.encode("u:abcd"))
  let accepted = app.respond({
    method: "GET",
    path: "/area",
    headers: Map([("Authorization", "Basic " + token)]),
    body: "",
  })
  assert_eq(accepted.status, 200)
  assert_eq(accepted.body, "inside")
}

///|
test "basic auth middleware escapes realm quotes" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_basic_auth(
        Map([("admin", "secret")]),
        realm="say \"hi\"\\now",
      ),
    )
    .get("/private", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/private",
    headers: Map([]),
    body: "",
  })
  assert_eq(
    response.headers.get("WWW-Authenticate"),
    Some("Basic realm=\"say \\\"hi\\\"\\\\now\""),
  )
}

///|
test "basic auth challenge replaces a case-variant header" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("www-authenticate", "Old")
        next(ctx)
      }
    })
    .use(@feather.middleware_basic_auth(Map([("admin", "secret")])))
    .get("/private", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/private",
    headers: Map([]),
    body: "",
  })
  let mut count = 0
  for key, _ in response.headers {
    if key.view().equal_ignore_ascii_case("www-authenticate".view()) {
      count = count + 1
    }
  }
  assert_eq(count, 1)
  assert_eq(
    response.headers.get("WWW-Authenticate"),
    Some("Basic realm=\"Restricted\""),
  )
}
