///|
fn isolation_context(
  path : String,
  headers : Map[String, String],
  body : String,
) -> @feather.Context {
  @feather.Context::new({ method: "POST", path, headers, body, })
}

///|
test "queries returns a copy that cannot corrupt the parse cache" {
  let ctx = isolation_context("/?a=1&b=2", Map([]), "")
  let first = ctx.queries()
  first.set("a", "mutated")
  first.set("c", "new")
  assert_eq(ctx.query("a"), "1")
  assert_eq(ctx.query("c"), "")
  let second = ctx.queries()
  assert_eq(second.get("a"), Some("1"))
  assert_eq(second.get("b"), Some("2"))
  assert_eq(second.get("c"), None)
}

///|
test "query_values returns a copy that cannot corrupt the parse cache" {
  let ctx = isolation_context("/?tag=a&tag=b", Map([]), "")
  let first = ctx.query_values("tag")
  assert_eq(first.length(), 2)
  first[0] = "mutated"
  first.push("extra")
  let second = ctx.query_values("tag")
  assert_eq(second.length(), 2)
  assert_eq(second[0], "a")
  assert_eq(second[1], "b")
}

///|
test "form_map returns a copy that cannot corrupt the parse cache" {
  let ctx = isolation_context(
    "/submit",
    Map([("Content-Type", "application/x-www-form-urlencoded")]),
    "a=1&b=2",
  )
  let first = ctx.form_map()
  first.set("a", "mutated")
  first.set("c", "new")
  assert_eq(ctx.form("a"), "1")
  assert_eq(ctx.form("c"), "")
  let second = ctx.form_map()
  assert_eq(second.get("a"), Some("1"))
  assert_eq(second.get("b"), Some("2"))
  assert_eq(second.get("c"), None)
}

///|
test "form_values returns a copy that cannot corrupt the parse cache" {
  let ctx = isolation_context(
    "/submit",
    Map([("Content-Type", "application/x-www-form-urlencoded")]),
    "tag=a&tag=b",
  )
  let first = ctx.form_values("tag")
  assert_eq(first.length(), 2)
  first[0] = "mutated"
  first.push("extra")
  let second = ctx.form_values("tag")
  assert_eq(second.length(), 2)
  assert_eq(second[0], "a")
  assert_eq(second[1], "b")
}
