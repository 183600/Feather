///|
test "header integer accessors parse signed values and trim whitespace" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("X-Count", " 42 "),
      ("X-Plus", "+7"),
      ("X-Negative", "-8"),
      ("X-Overflow", "2147483648"),
      ("X-Bad", "12x"),
      ("X-Empty", ""),
      ("X-Int64-Max", "9223372036854775807"),
      ("X-Int64-Min", "-9223372036854775808"),
      ("X-Int64-Overflow", "9223372036854775808"),
    ]),
    body: "",
  })
  assert_eq(ctx.header_int("x-count"), Some(42))
  assert_eq(ctx.header_int("X-PLUS"), Some(7))
  assert_eq(ctx.header_int("X-Negative"), Some(-8))
  assert_eq(ctx.header_int("X-Overflow"), None)
  assert_eq(ctx.header_int("X-Bad"), None)
  assert_eq(ctx.header_int("X-Empty"), None)
  assert_eq(ctx.header_int("X-Missing"), None)
  assert_eq(ctx.header_int64("X-Int64-Max"), Some(9223372036854775807L))
  assert_eq(
    ctx.header_int64("X-Int64-Min"),
    Some(-9223372036854775807L - 1L),
  )
  assert_eq(ctx.header_int64("X-Int64-Overflow"), None)
  assert_eq(ctx.header_int64("X-Bad"), None)
}

///|
test "header boolean and float accessors use the shared typed parsers" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("X-True", "true"),
      ("X-False", "0"),
      ("X-One", " 1 "),
      ("X-Bool-Bad", "yes"),
      ("X-Ratio", " 1.25 "),
      ("X-Exponent", "-2e3"),
      ("X-Nan", "nan"),
      ("X-Inf", "inf"),
      ("X-Underscore", "1_000"),
      ("X-Float-Bad", "1.2.3"),
    ]),
    body: "",
  })
  assert_eq(ctx.header_bool("X-True"), Some(true))
  assert_eq(ctx.header_bool("x-false"), Some(false))
  assert_eq(ctx.header_bool("X-One"), Some(true))
  assert_eq(ctx.header_bool("X-Bool-Bad"), None)
  assert_eq(ctx.header_bool("X-Missing"), None)
  assert_eq(ctx.header_float("X-Ratio"), Some(1.25))
  assert_eq(ctx.header_float("X-Exponent"), Some(-2000.0))
  assert_eq(ctx.header_float("X-Nan"), None)
  assert_eq(ctx.header_float("X-Inf"), None)
  assert_eq(ctx.header_float("X-Underscore"), None)
  assert_eq(ctx.header_float("X-Float-Bad"), None)
  assert_eq(ctx.header_float("X-Missing"), None)
}
