///|
test "typed session helpers are inert without middleware" {
  let ctx = @feather.create_context()
  assert_false(ctx.session_set_of("numbers", [1, 2, 3]))
  assert_eq(ctx.session_get_as("numbers"), (None : Array[Int]?))
}

///|
test "typed session helpers round trip a JSON value" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  assert_true(ctx.session_set_of("numbers", [1, 2, 3]))
  assert_eq(ctx.session_get_as("numbers"), (Some([1, 2, 3]) : Array[Int]?))
  // The untyped accessor still sees the same representation.
  assert_eq(
    ctx.session_get_json("numbers"),
    Some(@json.parse("[1,2,3]")),
  )
}

///|
test "typed session reads reject missing, malformed and mismatched values" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  assert_eq(ctx.session_get_as("missing"), (None : Array[Int]?))
  assert_true(ctx.session_set("text", "not json"))
  assert_eq(ctx.session_get_as("text"), (None : Array[Int]?))
  assert_true(ctx.session_set_of("text", "a string"))
  assert_eq(ctx.session_get_as("text"), (None : Array[Int]?))
  // A failed typed read does not consume or alter the stored JSON.
  assert_eq(ctx.session_get_json("text"), Some(@json.parse("\"a string\"")))
}

///|
test "typed session helpers persist through the middleware" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/write", fn(ctx) {
      assert_true(ctx.session_set_of("tags", ["a", "b"]))
      ctx.text(200, "written")
    })
    .get("/read", fn(ctx) {
      match ctx.session_get_as("tags") {
        Some(tags) => {
          let values : Array[String] = tags
          ctx.text(200, values.join(","))
        }
        None => ctx.text(200, "missing")
      }
    })
  let written = app.respond({
    method: "GET",
    path: "/write",
    headers: Map([]),
    body: "",
  })
  assert_eq(written.status, 200)
  assert_eq(written.cookies.length(), 1)
  let id = written.cookies[0].value
  let read = app.respond({
    method: "GET",
    path: "/read",
    headers: Map([("Cookie", "feather_session=" + id)]),
    body: "",
  })
  assert_eq(read.status, 200)
  assert_eq(read.body, "a,b")
}
