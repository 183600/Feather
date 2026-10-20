///|
test "flash requires a session" {
  let ctx = @feather.create_context()
  assert_false(ctx.flash("hello"))
  assert_eq(ctx.flash_take().length(), 0)
  assert_eq(ctx.flash_peek().length(), 0)
  assert_eq(ctx.flash_take_all().length(), 0)
}

///|
test "flash queues messages until taken" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  assert_true(ctx.flash("first"))
  assert_true(ctx.flash("second"))
  assert_eq(ctx.flash_peek(), ["first", "second"])
  assert_eq(ctx.flash_take(), ["first", "second"])
  assert_eq(ctx.flash_peek().length(), 0)
  assert_eq(ctx.flash_take().length(), 0)
}

///|
test "flash categories are independent" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  assert_true(ctx.flash("bad", category="error"))
  assert_true(ctx.flash("fine"))
  assert_eq(ctx.flash_take(category="error"), ["bad"])
  assert_eq(ctx.flash_peek(), ["fine"])
  assert_eq(ctx.flash_take(), ["fine"])
}

///|
test "flash_take_all drains every category" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  ignore(ctx.flash("a", category="notice"))
  ignore(ctx.flash("b", category="error"))
  ignore(ctx.flash("c", category="error"))
  let all = ctx.flash_take_all()
  assert_eq(all.get("notice"), Some(["a"]))
  assert_eq(all.get("error"), Some(["b", "c"]))
  assert_eq(ctx.flash_take_all().length(), 0)
}

///|
test "flash decodes messages containing separators and quotes" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  let tricky = "a,b\"c\n\\ {} []"
  ignore(ctx.flash(tricky))
  assert_eq(ctx.flash_take(), [tricky])
}

///|
test "flash survives session serialization between requests" {
  let store = @feather.SessionStore::new()
  let app = @feather
    .App::new()
    .use(@feather.middleware_session(store))
    .post("/login", fn(ctx) {
      ignore(ctx.flash("welcome back"))
      ctx.redirect(303, "/")
    })
    .get("/", fn(ctx) { ctx.json_of(200, ctx.flash_take()) })
  let login = app.respond({
    method: "POST",
    path: "/login",
    headers: Map([]),
    body: "",
  })
  assert_eq(login.status, 303)
  assert_eq(login.cookies.length(), 1)
  let cookie = login.cookies[0].name + "=" + login.cookies[0].value
  let home = app.respond({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", cookie)]),
    body: "",
  })
  assert_eq(home.status, 200)
  assert_eq(home.body, "[\"welcome back\"]")
  let again = app.respond({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", cookie)]),
    body: "",
  })
  assert_eq(again.body, "[]")
}

///|
test "flash_take_all omits categories without messages" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  let session = ctx.session.unwrap()
  session.data.set("__flash:error", "[]")
  ignore(ctx.flash("saved", category="notice"))
  let all = ctx.flash_take_all()
  assert_true(all.get("error") is None)
  assert_eq(all.get("notice"), Some(["saved"]))
}

///|
test "flash per request byte cap counts additions only" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  let session = ctx.session.unwrap()
  let stored : Array[Json] = []
  for _ in 0..<30 {
    stored.push(Json::string("x".repeat(300)))
  }
  session.data.set("__flash:default", Json::array(stored).stringify())
  assert_true(ctx.flash("a"))
  assert_true(ctx.flash("b"))
  let peeked = ctx.flash_peek()
  assert_eq(peeked.length(), 32)
  assert_eq(peeked[30], "a")
  assert_eq(peeked[31], "b")
  let taken = ctx.flash_take()
  assert_eq(taken.length(), 32)
  assert_eq(taken[30], "a")
  assert_eq(taken[31], "b")
  assert_eq(ctx.flash_take().length(), 0)
}

///|
test "flash category cap counts categories already stored" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  let session = ctx.session.unwrap()
  for i = 0; i < 16; i = i + 1 {
    session.data.set(
      "__flash:c" + i.to_string(),
      Json::array([Json::string("old")]).stringify(),
    )
  }
  assert_true(ctx.flash("new", category="newcat"))
  assert_eq(ctx.flash_peek(category="newcat").length(), 0)
  assert_true(ctx.flash("more", category="c0"))
  let existing = ctx.flash_peek(category="c0")
  assert_eq(existing.length(), 2)
  assert_eq(existing[0], "old")
  assert_eq(existing[1], "more")
}
