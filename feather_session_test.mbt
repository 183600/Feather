///|
fn session_request(path : String, cookie? : String) -> @feather.Request {
  let headers : Map[String, String] = Map([])
  match cookie {
    Some(value) => headers.set("Cookie", value)
    None => ()
  }
  { method: "GET", path, headers, body: "" }
}

///|
test "session store creates unique ids and round trips data" {
  let store = @feather.SessionStore::new()
  let first = store.create()
  let second = store.create()
  assert_eq(first.id.length(), 32)
  assert_eq(second.id.length(), 32)
  assert_true(first.id != second.id)
  assert_true(store.get(first.id) is None)
  first.data.set("user", "alice")
  store.save(first)
  assert_eq(store.count(), 1)
  match store.get(first.id) {
    Some(found) => {
      assert_eq(found.id, first.id)
      assert_eq(found.data.get("user"), Some("alice"))
    }
    None => fail("expected saved session")
  }
  store.destroy(first.id)
  assert_true(store.get(first.id) is None)
  assert_eq(store.count(), 0)
}

///|
test "session store drops expired sessions on read" {
  let store = @feather.SessionStore::new(ttl=1000L)
  assert_eq(store.ttl(), 1000L)
  let session = store.create()
  store.save(session)
  assert_eq(store.count(), 1)
  session.expires_at = 0L
  assert_true(store.get(session.id) is None)
  assert_eq(store.count(), 0)
}

///|
test "session store sweep removes expired sessions" {
  let store = @feather.SessionStore::new(ttl=1000L)
  let session = store.create()
  store.save(session)
  session.expires_at = 0L
  store.sweep()
  assert_eq(store.count(), 0)
  let keep = store.create()
  store.save(keep)
  store.sweep()
  assert_eq(store.count(), 1)
  store.clear()
  assert_eq(store.count(), 0)
}

///|
test "session helpers are inert without middleware" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_true(ctx.session() is None)
  assert_eq(ctx.session_id(), None)
  assert_eq(ctx.session_get("x"), "")
  assert_eq(ctx.session_set("x", "1"), false)
  assert_eq(ctx.session_remove("x"), false)
  assert_eq(ctx.session_destroy(), false)
  assert_eq(ctx.session_regenerate(), false)
  assert_true(ctx.session() is None)
}

///|
test "session middleware saves writes and issues a cookie" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/login", fn(ctx) {
      assert_true(ctx.session_set("user", "alice"))
      ctx.text(200, "ok")
    })
    .get("/me", fn(ctx) { ctx.text(200, ctx.session_get("user")) })
  let login = app.respond(session_request("/login"))
  assert_eq(login.status, 200)
  assert_eq(login.cookies.length(), 1)
  let cookie = login.cookies[0]
  assert_eq(cookie.name, "feather_session")
  assert_eq(cookie.value.length(), 32)
  assert_eq(cookie.path, Some("/"))
  assert_eq(cookie.http_only, true)
  assert_eq(cookie.secure, false)
  assert_true(cookie.extensions.length() == 1)
  assert_eq(cookie.extensions[0], "SameSite=Lax")
  assert_eq(store.count(), 1)
  let me = app.respond(
    session_request("/me", cookie="feather_session=" + cookie.value),
  )
  assert_eq(me.status, 200)
  assert_eq(me.body, "alice")
  assert_eq(me.cookies.length(), 0)
}

///|
test "session middleware leaves read only requests untouched" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/me", fn(ctx) { ctx.text(200, ctx.session_get("user")) })
  let response = app.respond(session_request("/me"))
  assert_eq(response.status, 200)
  assert_eq(response.body, "")
  assert_eq(response.cookies.length(), 0)
  assert_eq(store.count(), 0)
}

///|
test "session middleware clears destroyed sessions" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/login", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, "ok")
    })
    .get("/logout", fn(ctx) {
      assert_true(ctx.session_destroy())
      ctx.text(200, "bye")
    })
  let login = app.respond(session_request("/login"))
  let id = login.cookies[0].value
  assert_eq(store.count(), 1)
  let logout = app.respond(
    session_request("/logout", cookie="feather_session=" + id),
  )
  assert_eq(logout.status, 200)
  assert_eq(logout.cookies.length(), 1)
  assert_eq(logout.cookies[0].value, "")
  assert_eq(logout.cookies[0].max_age, Some(0L))
  assert_eq(store.count(), 0)
}

///|
test "session middleware replaces stale cookies" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/login", fn(ctx) {
      ignore(ctx.session_set("n", "1"))
      ctx.text(200, "ok")
    })
  let response = app.respond(
    session_request("/login", cookie="feather_session=deadbeef"),
  )
  assert_eq(response.cookies.length(), 1)
  assert_true(response.cookies[0].value != "deadbeef")
  assert_eq(response.cookies[0].value.length(), 32)
}

///|
test "session middleware persists writes when the handler fails" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/set-then-fail", fn(ctx) raise {
      ignore(ctx.session_set("user", "alice"))
      raise @feather.HttpError(500, "boom")
    })
  let response = app.respond(session_request("/set-then-fail"))
  assert_eq(response.status, 500)
  assert_eq(response.cookies.length(), 1)
  assert_eq(store.count(), 1)
  let stored = store.get(response.cookies[0].value).unwrap()
  assert_eq(stored.data.get("user"), Some("alice"))
}

///|
test "session middleware honors cookie options" {
  let store = @feather.SessionStore::new(ttl=3_600_000L)
  let app = @feather.App::new()
    .use(
      @feather.middleware_session(
        store,
        cookie="sid",
        path="/app",
        same_site="Strict",
        http_only=false,
        secure=true,
      ),
    )
    .get("/app/login", fn(ctx) {
      ignore(ctx.session_set("k", "v"))
      ctx.text(200, "ok")
    })
  let response = app.respond(session_request("/app/login"))
  assert_eq(response.cookies.length(), 1)
  let cookie = response.cookies[0]
  assert_eq(cookie.name, "sid")
  assert_eq(cookie.path, Some("/app"))
  assert_eq(cookie.http_only, false)
  assert_eq(cookie.secure, true)
  assert_eq(cookie.max_age, Some(3600L))
  assert_true(cookie.extensions.length() == 1)
  assert_eq(cookie.extensions[0], "SameSite=Strict")
}

///|
test "Context session remove deletes keys" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/set", fn(ctx) {
      ignore(ctx.session_set("a", "1"))
      ctx.text(200, ctx.session_id().unwrap())
    })
    .get("/remove", fn(ctx) {
      assert_true(ctx.session_remove("a"))
      assert_eq(ctx.session_remove("missing"), false)
      ctx.text(200, ctx.session_get("a"))
    })
  let login = app.respond(session_request("/set"))
  let id = login.cookies[0].value
  assert_eq(login.body, id)
  let removed = app.respond(
    session_request("/remove", cookie="feather_session=" + id),
  )
  assert_eq(removed.body, "")
  assert_eq(store.count(), 1)
}

///|
test "session middleware isolates sessions per cookie" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/login/:name", fn(ctx) {
      ignore(ctx.session_set("name", ctx.param("name")))
      ctx.text(200, ctx.session_id().unwrap())
    })
    .get("/name", fn(ctx) { ctx.text(200, ctx.session_get("name")) })
  let first = app.respond(session_request("/login/alice"))
  let second = app.respond(session_request("/login/bob"))
  assert_true(first.cookies[0].value != second.cookies[0].value)
  assert_eq(store.count(), 2)
  assert_eq(
    app
    .respond(
      session_request("/name", cookie="feather_session=" + first.cookies[0].value),
    )
    .body,
    "alice",
  )
  assert_eq(
    app
    .respond(
      session_request("/name", cookie="feather_session=" + second.cookies[0].value),
    )
    .body,
    "bob",
  )
}

///|
test "session middleware regenerates ids while keeping data" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/login", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      assert_true(ctx.session_regenerate())
      ctx.text(200, ctx.session_id().unwrap())
    })
    .get("/me", fn(ctx) { ctx.text(200, ctx.session_get("user")) })
  let login = app.respond(session_request("/login"))
  let id = login.cookies[0].value
  assert_eq(login.body, id)
  assert_eq(store.count(), 1)
  assert_eq(store.get(id).unwrap().data.get("user"), Some("alice"))
  let again = app.respond(
    session_request("/login", cookie="feather_session=" + id),
  )
  let rotated = again.cookies[0].value
  assert_true(rotated != id)
  assert_true(store.get(id) is None)
  assert_eq(store.count(), 1)
  assert_eq(store.get(rotated).unwrap().data.get("user"), Some("alice"))
  let me = app.respond(
    session_request("/me", cookie="feather_session=" + rotated),
  )
  assert_eq(me.body, "alice")
}

///|
async test "server sessions survive across requests" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/login", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, ctx.session_id().unwrap())
    })
    .get("/me", fn(ctx) { ctx.text(200, ctx.session_get("user")) })
  with_server(app, client => {
    let login = client.get("/login")
    assert_eq(login.code, 200)
    let id = client.read_all().text()
    assert_eq(id.length(), 32)
    assert_eq(store.count(), 1)
    let me = client.get(
      "/me",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Cookie"), "feather_session=" + id),
      ]),
    )
    assert_eq(me.code, 200)
    assert_eq(client.read_all().text(), "alice")
  })
}

///|
test "session json helpers round trip structured values" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  assert_eq(ctx.session_get_json("user"), None)
  assert_false(ctx.session_set_json("user", Json::object({ "name": "alice" })))
  ctx.session = Some(store.create())
  assert_true(
    ctx.session_set_json("user", Json::object({ "name": "alice", "admin": true })),
  )
  let user = ctx.session_get_json("user").unwrap()
  assert_eq(user.value("name"), Some(Json::string("alice")))
  assert_eq(user.value("admin"), Some(Json::boolean(true)))
  assert_eq(ctx.session_get_json("missing"), None)
  let session = ctx.session.unwrap()
  session.data.set("broken", "{not json")
  assert_eq(ctx.session_get_json("broken"), None)
}

///|
test "session json helpers persist through the middleware" {
  let store = @feather.SessionStore::new()
  let app = @feather
    .App::new()
    .use(@feather.middleware_session(store))
    .get("/set", fn(ctx) {
      ignore(ctx.session_set_json("cart", Json::array([Json::number(1.0)])))
      ctx.text(200, "set")
    })
    .get("/get", fn(ctx) {
      match ctx.session_get_json("cart") {
        Some(cart) => ctx.json_value(200, cart)
        None => ctx.text(404, "empty")
      }
    })
  let set = app.respond(session_request("/set"))
  assert_eq(set.cookies.length(), 1)
  let cookie = "feather_session=" + set.cookies[0].value
  let get = app.respond(session_request("/get", cookie=cookie))
  assert_eq(get.status, 200)
  assert_eq(get.body, "[1]")
}

///|
test "session writes refresh the cookie on later requests" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/set", fn(ctx) {
      ignore(ctx.session_set("u", "a"))
      ctx.text(200, "set")
    })
    .get("/touch", fn(ctx) {
      ignore(ctx.session_set("u", "b"))
      ctx.text(200, "touch")
    })
    .get("/read", fn(ctx) { ctx.text(200, ctx.session_get("u")) })
  let first = app.respond(session_request("/set"))
  let id = first.cookies[0].value
  let touch = app.respond(
    session_request("/touch", cookie="feather_session=" + id),
  )
  assert_eq(touch.cookies.length(), 1)
  assert_eq(touch.cookies[0].value, id)
  let read = app.respond(
    session_request("/read", cookie="feather_session=" + id),
  )
  assert_eq(read.cookies.length(), 0)
  assert_eq(read.body, "b")
}

///|
test "session destroy clears a cookie with no live session" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/logout", fn(ctx) {
      assert_true(ctx.session_destroy())
      ctx.text(200, "bye")
    })
  let response = app.respond(
    session_request("/logout", cookie="feather_session=deadbeef"),
  )
  assert_eq(response.cookies.length(), 1)
  assert_eq(response.cookies[0].value, "")
  assert_eq(response.cookies[0].max_age, Some(0L))
}
