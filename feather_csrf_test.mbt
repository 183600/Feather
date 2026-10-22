///|
fn csrf_test_handler(store : @feather.SessionStore) -> @feather.Handler {
  @feather.apply_middleware(
    [@feather.middleware_session(store), @feather.middleware_csrf()],
    fn(ctx) { ctx.text(200, "ok") },
  )
}

///|
fn csrf_request(
  method : String,
  headers : Map[String, String],
  body : String,
) -> @feather.Context {
  @feather.Context::new({ method, path: "/submit", headers, body, })
}

///|
test "csrf rejects unsafe requests without a token" {
  let store = @feather.SessionStore::new()
  let handler = csrf_test_handler(store)
  let ctx = csrf_request("POST", Map([]), "")
  handler(ctx)
  assert_eq(ctx.response.status, 403)
  assert_eq(ctx.response.body, "403 Forbidden")
}

///|
test "csrf rejects unsafe requests when the session has no token" {
  let store = @feather.SessionStore::new()
  let session = store.create()
  store.save(session)
  let handler = csrf_test_handler(store)
  let ctx = csrf_request(
    "POST",
    Map([
      ("Cookie", "feather_session=" + session.id),
      ("X-CSRF-Token", "some-token"),
    ]),
    "",
  )
  handler(ctx)
  assert_eq(ctx.response.status, 403)
}

///|
test "csrf accepts a matching header token" {
  let store = @feather.SessionStore::new()
  let session = store.create()
  session.data.set("_csrf", "token-value")
  store.save(session)
  let handler = csrf_test_handler(store)
  let ctx = csrf_request(
    "POST",
    Map([
      ("Cookie", "feather_session=" + session.id),
      ("X-CSRF-Token", "token-value"),
    ]),
    "",
  )
  handler(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "ok")
}

///|
test "csrf rejects a mismatched token" {
  let store = @feather.SessionStore::new()
  let session = store.create()
  session.data.set("_csrf", "token-value")
  store.save(session)
  let handler = csrf_test_handler(store)
  let ctx = csrf_request(
    "DELETE",
    Map([
      ("Cookie", "feather_session=" + session.id),
      ("X-CSRF-Token", "token-valuf"),
    ]),
    "",
  )
  handler(ctx)
  assert_eq(ctx.response.status, 403)
}

///|
test "csrf accepts a urlencoded form field" {
  let store = @feather.SessionStore::new()
  let session = store.create()
  session.data.set("_csrf", "token-value")
  store.save(session)
  let handler = csrf_test_handler(store)
  let ctx = csrf_request(
    "PATCH",
    Map([
      ("Cookie", "feather_session=" + session.id),
      ("Content-Type", "application/x-www-form-urlencoded"),
    ]),
    "name=feather&_csrf=token-value",
  )
  handler(ctx)
  assert_eq(ctx.response.status, 200)
}

///|
test "csrf accepts a multipart form field" {
  let store = @feather.SessionStore::new()
  let session = store.create()
  session.data.set("_csrf", "token-value")
  store.save(session)
  let handler = csrf_test_handler(store)
  let body = "--B\r\nContent-Disposition: form-data; name=\"_csrf\"\r\n\r\ntoken-value\r\n--B--\r\n"
  let ctx = csrf_request(
    "PUT",
    Map([
      ("Cookie", "feather_session=" + session.id),
      ("Content-Type", "multipart/form-data; boundary=B"),
    ]),
    body,
  )
  handler(ctx)
  assert_eq(ctx.response.status, 200)
}

///|
test "csrf prefers the header over the form field" {
  let store = @feather.SessionStore::new()
  let session = store.create()
  session.data.set("_csrf", "token-value")
  store.save(session)
  let handler = csrf_test_handler(store)
  let ctx = csrf_request(
    "POST",
    Map([
      ("Cookie", "feather_session=" + session.id),
      ("X-CSRF-Token", "wrong"),
      ("Content-Type", "application/x-www-form-urlencoded"),
    ]),
    "_csrf=token-value",
  )
  handler(ctx)
  assert_eq(ctx.response.status, 403)
}

///|
test "csrf lets safe methods through and creates tokens on demand" {
  let store = @feather.SessionStore::new()
  let handler = @feather.apply_middleware(
    [@feather.middleware_session(store), @feather.middleware_csrf()],
    fn(ctx) {
      let token = ctx.csrf_token()
      assert_eq(token.length(), 32)
      assert_eq(ctx.csrf_token(), token)
      ctx.text(200, token)
    },
  )
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/form",
    headers: Map([]),
    body: "",
  })
  handler(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body.length(), 32)
  assert_eq(store.count(), 1)
  let session = ctx.session().unwrap()
  assert_eq(session.data.get("_csrf"), Some(ctx.response.body))
}

///|
test "csrf supports custom field, header and key names" {
  let store = @feather.SessionStore::new()
  let session = store.create()
  session.data.set("xsrf", "custom-token")
  store.save(session)
  let handler = @feather.apply_middleware(
    [
      @feather.middleware_session(store),
      @feather.middleware_csrf(field="xsrf", header="X-XSRF-Token", key="xsrf"),
    ],
    fn(ctx) { ctx.text(200, "ok") },
  )
  let accepted = csrf_request(
    "POST",
    Map([
      ("Cookie", "feather_session=" + session.id),
      ("X-XSRF-Token", "custom-token"),
    ]),
    "",
  )
  handler(accepted)
  assert_eq(accepted.response.status, 200)
  let default_header = csrf_request(
    "POST",
    Map([
      ("Cookie", "feather_session=" + session.id),
      ("X-CSRF-Token", "custom-token"),
    ]),
    "",
  )
  handler(default_header)
  assert_eq(default_header.response.status, 403)
}

///|
test "csrf without session middleware rejects unsafe requests" {
  let handler = @feather.apply_middleware([@feather.middleware_csrf()], fn(
    ctx,
  ) {
    ctx.text(200, "ok")
  })
  let unsafe = csrf_request("POST", Map([("X-CSRF-Token", "token")]), "")
  handler(unsafe)
  assert_eq(unsafe.response.status, 403)
  let safe = csrf_request("GET", Map([]), "")
  handler(safe)
  assert_eq(safe.response.status, 200)
  assert_eq(safe.response.body, "ok")
  assert_eq(safe.csrf_token(), "")
}

///|
test "csrf token is destroyed with the session" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .use(@feather.middleware_csrf())
    .post("/logout", fn(ctx) {
      ignore(ctx.session_destroy())
      ctx.text(200, "bye")
    })
    .post("/submit", fn(ctx) { ctx.text(200, "saved") })
  let session = store.create()
  session.data.set("_csrf", "token-value")
  store.save(session)
  let headers = Map([
    ("Cookie", "feather_session=" + session.id),
    ("X-CSRF-Token", "token-value"),
  ])
  let logout = app.respond({
    method: "POST",
    path: "/logout",
    headers,
    body: "",
  })
  assert_eq(logout.status, 200)
  assert_eq(store.count(), 0)
  let submit = app.respond({
    method: "POST",
    path: "/submit",
    headers,
    body: "",
  })
  assert_eq(submit.status, 403)
}

///|
test "session regeneration rotates the default csrf token" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/rotate", fn(ctx) {
      let before = ctx.csrf_token()
      assert_true(ctx.session_regenerate())
      let after = ctx.csrf_token()
      assert_true(before != after)
      ctx.text(200, after)
    })
  let session = store.create()
  session.data.set("_csrf", "old-token")
  store.save(session)
  let old_id = session.id
  let response = app.respond({
    method: "GET",
    path: "/rotate",
    headers: Map([("Cookie", "feather_session=" + old_id)]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_true(response.body != "old-token")
  assert_eq(response.cookies.length(), 1)
  let new_id = response.cookies[0].value
  assert_true(new_id != old_id)
  assert_true(store.get(old_id) is None)
  assert_eq(store.get(new_id).unwrap().data.get("_csrf"), Some(response.body))
}

///|
test "csrf_rotate clears a custom token key" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/rotate", fn(ctx) {
      let before = ctx.csrf_token(key="xsrf")
      assert_true(ctx.csrf_rotate(key="xsrf"))
      let after = ctx.csrf_token(key="xsrf")
      assert_true(before != after)
      ctx.text(200, after)
    })
  let session = store.create()
  session.data.set("xsrf", "old-custom-token")
  session.data.set("_csrf", "keep-default")
  store.save(session)
  let response = app.respond({
    method: "GET",
    path: "/rotate",
    headers: Map([("Cookie", "feather_session=" + session.id)]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_true(response.body != "old-custom-token")
  let saved = store.get(response.cookies[0].value).unwrap()
  assert_eq(saved.data.get("xsrf"), Some(response.body))
  assert_eq(saved.data.get("_csrf"), Some("keep-default"))
}

///|
async test "server csrf flow with header token" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .use(@feather.middleware_csrf())
    .get("/token", fn(ctx) {
      ctx.text(200, ctx.session_id().unwrap() + ":" + ctx.csrf_token())
    })
    .post("/submit", fn(ctx) { ctx.text(200, "saved") })
  with_server(app, client => {
    let token_response = client.get("/token")
    assert_eq(token_response.code, 200)
    let payload = client.read_all().text()
    let index = payload.find(":").unwrap()
    let id = payload[:index].to_owned()
    let token = payload[index + 1:].to_owned()
    assert_eq(token.length(), 32)
    let accepted = client.post(
      "/submit",
      "",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Cookie"), "feather_session=" + id),
        (@http.CaseInsensitiveString("X-CSRF-Token"), token),
      ]),
    )
    assert_eq(accepted.code, 200)
    assert_eq(client.read_all().text(), "saved")
    let rejected = client.post(
      "/submit",
      "",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Cookie"), "feather_session=" + id),
      ]),
    )
    assert_eq(rejected.code, 403)
    assert_eq(client.read_all().text(), "403 Forbidden")
  })
}
