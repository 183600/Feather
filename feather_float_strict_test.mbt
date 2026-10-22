///|
test "float accessors reject repeated signs and underscores" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/?plus=%2B%2B1&mixed=%2B-1&under=1_0&space=%201&tail=1%20",
    headers: Map([("Content-Type", "application/x-www-form-urlencoded")]),
    body: "plus=%2B%2B1&mixed=%2B-1&under=1_0&space=%201&tail=1%20",
  })
  for name in ["plus", "mixed", "under", "space", "tail"] {
    assert_eq(ctx.query_float(name), None, msg="query " + name)
    assert_eq(ctx.form_float(name), None, msg="form " + name)
  }
}

///|
test "param_float rejects repeated signs and underscores" {
  let router = @feather.create_router()
  router.add_route("GET", "/n/:v", fn(ctx) { ctx.text(200, "ok") })
  for value in ["%2B%2B1", "%2B-1", "1_0", "%201", "1%20"] {
    let ctx = @feather.Context::new({
      method: "GET",
      path: "/n/" + value,
      headers: Map([]),
      body: "",
    })
    router.dispatch(ctx)
    assert_eq(ctx.param_float("v"), None, msg=value)
  }
}

///|
test "float accessors keep valid decimal spellings" {
  for pair in [
    (".5", 0.5),
    ("-0.5", -0.5),
    ("5.", 5.0),
    ("1e2", 100.0),
    ("-1E-3", -0.001),
    ("%2B0.25", 0.25),
  ] {
    let (value, expected) = pair
    let ctx = @feather.Context::new({
      method: "GET",
      path: "/?v=" + value,
      headers: Map([]),
      body: "",
    })
    assert_eq(ctx.query_float("v"), Some(expected), msg=value)
  }
}
