///|
/// Regression test for the `uint32` typed accessors: values are capped at the
/// `UInt32` range even though the helpers return `UInt64`.
fn uint32_param(value : String) -> UInt64? raise {
  let router = @feather.create_router()
  router.add_route("GET", "/items/:id", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/items/" + value,
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  ctx.param_uint32("id")
}

///|
test "param_uint32 stays within the 32-bit unsigned range" {
  assert_eq(uint32_param("42"), Some(42UL))
  assert_eq(uint32_param("00042"), Some(42UL))
  assert_eq(uint32_param("4294967295"), Some(4294967295UL))
  assert_eq(uint32_param("4294967296"), None)
  assert_eq(uint32_param("99999999999999999999"), None)
  assert_eq(uint32_param("abc"), None)
  assert_eq(uint32_param("missing"), None)
}

///|
test "query_uint32 and its default respect the 32-bit boundary" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/?exact=4294967295&over=4294967296&bad=12x",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.query_uint32("exact"), Some(4294967295UL))
  assert_eq(ctx.query_uint32("over"), None)
  assert_eq(ctx.query_uint32("bad"), None)
  assert_eq(ctx.query_uint32("missing"), None)
  assert_eq(ctx.query_uint32_default("exact", 7UL), 4294967295UL)
  assert_eq(ctx.query_uint32_default("over", 7UL), 7UL)
}

///|
test "header_uint32 rejects values outside the 32-bit range" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("X-Exact", " 4294967295 "),
      ("X-Over", "4294967296"),
    ]),
    body: "",
  })
  assert_eq(ctx.header_uint32("X-Exact"), Some(4294967295UL))
  assert_eq(ctx.header_uint32("X-Over"), None)
  assert_eq(ctx.header_uint32_default("X-Over", 9UL), 9UL)
  assert_eq(ctx.header_uint32_default("missing", 9UL), 9UL)
}
