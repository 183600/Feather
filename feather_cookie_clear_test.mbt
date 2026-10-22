///|
test "clear_cookie keeps partitioned deletion attributes" {
  let ctx = @feather.create_context()
  ctx.set_cookie("sid", "v", path="/", secure=true, partitioned=true)
  ctx.clear_cookie("sid", path="/", secure=true, partitioned=true)
  let cookie = ctx.response.cookies[1]
  assert_eq(cookie.name, "sid")
  assert_eq(cookie.value, "")
  assert_eq(cookie.path, Some("/"))
  assert_eq(cookie.max_age, Some(0L))
  assert_true(cookie.secure)
  assert_true(cookie.extensions.contains("Partitioned"))
}

///|
test "clear_signed_cookie keeps partitioned deletion attributes" {
  let ctx = @feather.create_context()
  ctx.set_signed_cookie(
    "user",
    "alice",
    "secret",
    path="/",
    secure=true,
    partitioned=true,
  )
  ctx.clear_signed_cookie("user", path="/", secure=true, partitioned=true)
  let cookie = ctx.response.cookies[1]
  assert_eq(cookie.name, "user")
  assert_eq(cookie.value, "")
  assert_eq(cookie.max_age, Some(0L))
  assert_true(cookie.secure)
  assert_true(cookie.extensions.contains("Partitioned"))
}
