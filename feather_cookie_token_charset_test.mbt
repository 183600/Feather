///|
test "cookie names drop every HTTP token separator" {
  for pair in [
    ("a/b", "ab"),
    ("a:b", "ab"),
    ("a(b)c", "abc"),
    ("a<b>c", "abc"),
    ("a@b", "ab"),
    ("a,b", "ab"),
    ("a;b", "ab"),
    ("a\\b", "ab"),
    ("a\"b", "ab"),
    ("a[b]c", "abc"),
    ("a?b", "ab"),
    ("a{b}c", "abc"),
    ("a=b", "ab"),
    ("a b", "ab"),
    ("a\tb", "ab"),
  ] {
    let (name, expected) = pair
    let ctx = @feather.create_context()
    ctx.set_cookie(name, "v")
    assert_eq(
      ctx.response.headers.get("Set-Cookie"),
      Some(expected + "=v"),
      msg=name,
    )
  }
}

///|
test "cookie values drop header separators but keep spaces and equals" {
  let ctx = @feather.create_context()
  ctx.set_cookie("sid", "a b\tc,d;e\"f\\g")
  assert_eq(ctx.response.headers.get("Set-Cookie"), Some("sid=a bcdefg"))
  let padded = @feather.create_context()
  padded.set_cookie("token", "YWJjZA==")
  assert_eq(
    padded.response.headers.get("Set-Cookie"),
    Some("token=YWJjZA=="),
  )
  let equal = @feather.create_context()
  equal.set_cookie("token", "a=b=c")
  assert_eq(equal.response.headers.get("Set-Cookie"), Some("token=a=b=c"))
}

///|
test "cookie lookup uses the same sanitized name as set_cookie" {
  let ctx = @feather.create_context()
  ctx.set_cookie("a/b", "value")
  assert_eq(ctx.response.headers.get("Set-Cookie"), Some("ab=value"))
  let reader = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "ab=value")]),
    body: "",
  })
  assert_eq(reader.cookie("a/b"), Some("value"))
}

///|
test "parsing ignores cookie names outside the token grammar" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "good=1; bad/name=2; good=3")]),
    body: "",
  })
  assert_eq(ctx.cookies().get("good"), Some("1"))
  assert_eq(ctx.cookies().get("bad/name"), None)
  assert_eq(ctx.cookie("bad/name"), None)
}
