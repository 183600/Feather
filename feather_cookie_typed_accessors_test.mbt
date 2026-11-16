///|
test "Context cookie typed accessors" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      (
        "Cookie",
        "hits=7; total=9007199254740993; flag=true; off=1; ratio=2.5; " +
        "u32=4294967295; u32over=4294967296; u64=18446744073709551615; " +
        "i64max=9223372036854775807; i64min=-9223372036854775808; " +
        "bad=abc; nan=nan; inf=inf; empty=",
      ),
    ]),
    body: "",
  })
  assert_eq(ctx.cookie_int("hits"), Some(7))
  assert_eq(ctx.cookie_int("missing"), None)
  assert_eq(ctx.cookie_int("bad"), None)
  assert_eq(ctx.cookie_int("empty"), None)
  assert_eq(ctx.cookie_int64("i64max"), Some(9223372036854775807L))
  assert_eq(ctx.cookie_int64("i64min"), Some(-9223372036854775808L))
  assert_eq(ctx.cookie_int64("total"), Some(9007199254740993L))
  assert_eq(ctx.cookie_int64("hits"), Some(7L))
  assert_eq(ctx.cookie_bool("flag"), Some(true))
  assert_eq(ctx.cookie_bool("off"), Some(true))
  assert_eq(ctx.cookie_bool("bad"), None)
  assert_eq(ctx.cookie_uint32("u32"), Some(4294967295UL))
  assert_eq(ctx.cookie_uint32("u32over"), None)
  assert_eq(ctx.cookie_uint64("u64"), Some(18446744073709551615UL))
  assert_eq(ctx.cookie_uint64("u32over"), Some(4294967296UL))
  assert_eq(ctx.cookie_float("ratio"), Some(2.5))
  assert_eq(ctx.cookie_float("nan"), None)
  assert_eq(ctx.cookie_float("inf"), None)
  assert_eq(ctx.cookie_float("bad"), None)
}

///|
test "cookie typed accessors fall back to defaults" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "hits=7; ratio=2.5; flag=maybe")]),
    body: "",
  })
  assert_eq(ctx.cookie_int_default("hits", 1), 7)
  assert_eq(ctx.cookie_int_default("missing", 1), 1)
  assert_eq(ctx.cookie_int64_default("missing", 2L), 2L)
  assert_eq(ctx.cookie_bool_default("flag", true), true)
  assert_eq(ctx.cookie_bool_default("missing", false), false)
  assert_eq(ctx.cookie_uint32_default("missing", 3UL), 3UL)
  assert_eq(ctx.cookie_uint64_default("missing", 4UL), 4UL)
  assert_eq(ctx.cookie_float_default("ratio", 0.5), 2.5)
  assert_eq(ctx.cookie_float_default("missing", 0.5), 0.5)
}

///|
test "cookie typed accessors read only the request header" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  ctx.set_cookie("session_hits", "42")
  // A queued response cookie does not become readable on the request side.
  assert_eq(ctx.cookie("session_hits"), None)
  assert_eq(ctx.cookie_int("session_hits"), None)
  assert_eq(ctx.cookie_int_default("session_hits", 0), 0)
}
