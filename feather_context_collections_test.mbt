///|
fn query_context(query : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/search?" + query,
    headers: Map([]),
    body: "",
  })
}

///|
fn form_context(body : String, content_type : String) -> @feather.Context {
  @feather.Context::new({
    method: "POST",
    path: "/submit",
    headers: Map([("Content-Type", content_type)]),
    body,
  })
}

///|
test "has query distinguishes absent and empty parameters" {
  let ctx = query_context("empty=&flag&tag=a&tag=b&q=hello+world")
  assert_true(ctx.has_query("empty"))
  assert_true(ctx.has_query("flag"))
  assert_true(ctx.has_query("tag"))
  assert_true(ctx.has_query("q"))
  assert_false(ctx.has_query("missing"))
  assert_false(ctx.has_query(""))
  assert_eq(ctx.query("q"), "hello world")
}

///|
test "has query matches raw and decoded names like query does" {
  let ctx = query_context("a+b=plus&raw%2Bkey=encoded")
  assert_true(ctx.has_query("a b"))
  assert_true(ctx.has_query("a+b"))
  assert_true(ctx.has_query("raw+key"))
  assert_true(ctx.has_query("raw%2Bkey"))
  assert_false(ctx.has_query("other"))
}

///|
test "query all preserves repeated values and query order" {
  let ctx = query_context("tag=a&q=x&tag=b&empty=")
  let all = ctx.query_all()
  assert_eq(all.get("tag").unwrap().join("|"), "a|b")
  assert_eq(all.get("q").unwrap().join("|"), "x")
  assert_eq(all.get("empty").unwrap().length(), 1)
  assert_eq(all.get("empty").unwrap()[0], "")
  assert_false(all.contains("missing"))
}

///|
test "query all returns copies that cannot corrupt the parse cache" {
  let ctx = query_context("tag=a&tag=b")
  let first = ctx.query_all()
  first.get("tag").unwrap().push("mutated")
  first.set("new", ["value"])
  let second = ctx.query_all()
  assert_eq(second.get("tag").unwrap().join("|"), "a|b")
  assert_false(second.contains("new"))
  assert_eq(ctx.query_values("tag").join("|"), "a|b")
}

///|
test "has form follows the form content type and distinguishes empty values" {
  let form = form_context("empty=&flag&tag=a&tag=b", "application/x-www-form-urlencoded")
  assert_true(form.has_form("empty"))
  assert_true(form.has_form("flag"))
  assert_true(form.has_form("tag"))
  assert_false(form.has_form("missing"))
  assert_false(form.has_form(""))

  let json = form_context("flag", "application/json")
  assert_false(json.has_form("flag"))
}

///|
test "form all preserves repeated values and rejects other content types" {
  let form = form_context(
    "tag=a&q=x&tag=b&empty=",
    "application/x-www-form-urlencoded; charset=utf-8",
  )
  let all = form.form_all()
  assert_eq(all.get("tag").unwrap().join("|"), "a|b")
  assert_eq(all.get("q").unwrap().join("|"), "x")
  assert_eq(all.get("empty").unwrap().join("|"), "")

  let json = form_context("tag=a", "application/json")
  assert_eq(json.form_all().length(), 0)
}

///|
test "form all returns copies that cannot corrupt the parse cache" {
  let ctx = form_context(
    "tag=a&tag=b",
    "application/x-www-form-urlencoded",
  )
  let first = ctx.form_all()
  first.get("tag").unwrap().push("mutated")
  let second = ctx.form_all()
  assert_eq(second.get("tag").unwrap().join("|"), "a|b")
  assert_eq(ctx.form_values("tag").join("|"), "a|b")
}

///|
test "has param detects captured route parameters including empty wildcards" {
  let app = @feather.App::new()
    .get("/users/:id", fn(ctx) {
      ctx.text(
        200,
        ctx.has_param("id").to_string() +
        ":" +
        ctx.has_param("missing").to_string(),
      )
    })
    .get("/files/*path", fn(ctx) {
      ctx.text(
        200,
        ctx.has_param("path").to_string() + ":" + ctx.param("path"),
      )
    })

  let user = app.respond({
    method: "GET",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(user.body, "true:false")

  let wildcard = app.respond({
    method: "GET",
    path: "/files/",
    headers: Map([]),
    body: "",
  })
  assert_eq(wildcard.body, "true:")
}
