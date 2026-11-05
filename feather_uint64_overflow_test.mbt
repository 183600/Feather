///|
/// Regression test for `parse_uint64_value`: a 20-digit value above
/// `UInt64` max must be rejected instead of wrapping around.
fn uint64_param(value : String) -> UInt64? raise {
  let router = @feather.create_router()
  router.add_route("GET", "/items/:id", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/items/" + value,
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  ctx.param_uint64("id")
}

///|
test "param_uint64 rejects values above the 64-bit unsigned range" {
  assert_eq(uint64_param("42"), Some(42UL))
  assert_eq(uint64_param("00042"), Some(42UL))
  assert_eq(
    uint64_param("18446744073709551615"),
    Some(18446744073709551615UL),
  )
  // One above the maximum must not wrap around to a small value.
  assert_eq(uint64_param("18446744073709551616"), None)
  assert_eq(uint64_param("99999999999999999999"), None)
  assert_eq(uint64_param("184467440737095516160"), None)
  assert_eq(uint64_param("abc"), None)
  assert_eq(uint64_param("+"), None)
  assert_eq(uint64_param("missing"), None)
}

///|
test "query_uint64 rejects values above the 64-bit unsigned range" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/?big=18446744073709551616&exact=18446744073709551615",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.query_uint64("big"), None)
  assert_eq(ctx.query_uint64("exact"), Some(18446744073709551615UL))
  assert_eq(ctx.query_uint64("missing"), None)
}

///|
test "header_uint64 rejects values above the 64-bit unsigned range" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("X-Uint", "18446744073709551616")]),
    body: "",
  })
  assert_eq(ctx.header_uint64("X-Uint"), None)
}
