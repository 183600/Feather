///|
fn redirect_back_context(referer : String?, host : String?) -> @feather.Context {
  let headers : Map[String, String] = Map([])
  match referer {
    Some(value) => headers.set("Referer", value)
    None => ()
  }
  match host {
    Some(value) => headers.set("Host", value)
    None => ()
  }
  @feather.Context::new({
    method: "POST",
    path: "/submit",
    headers,
    body: "",
  })
}

///|
test "redirect back replays a local referer path and query" {
  let ctx = redirect_back_context(
    Some("/dashboard?tab=1#top"),
    Some("example.com"),
  )
  ctx.redirect_back()
  assert_eq(ctx.response.status, 303)
  assert_eq(ctx.response.headers.get("Location"), Some("/dashboard?tab=1"))
  assert_eq(ctx.response.body, "")
}

///|
test "redirect back reduces a same-host absolute referer to a local path" {
  let ctx = redirect_back_context(
    Some("https://Example.COM:8443/dashboard?tab=1#frag"),
    Some("example.com:8443"),
  )
  ctx.redirect_back()
  assert_eq(ctx.response.status, 303)
  assert_eq(ctx.response.headers.get("Location"), Some("/dashboard?tab=1"))
  let root = redirect_back_context(Some("https://example.com"), Some("example.com"))
  root.redirect_back()
  assert_eq(root.response.headers.get("Location"), Some("/"))
  let query = redirect_back_context(
    Some("https://example.com?page=2"),
    Some("example.com"),
  )
  query.redirect_back()
  assert_eq(query.response.headers.get("Location"), Some("/?page=2"))
}

///|
test "redirect back falls back for another origin or a missing referer" {
  let cross = redirect_back_context(
    Some("https://evil.com/dashboard"),
    Some("example.com"),
  )
  cross.redirect_back(fallback="/login")
  assert_eq(cross.response.status, 303)
  assert_eq(cross.response.headers.get("Location"), Some("/login"))
  let missing = redirect_back_context(None, Some("example.com"))
  missing.redirect_back(status=302, fallback="/home")
  assert_eq(missing.response.status, 302)
  assert_eq(missing.response.headers.get("Location"), Some("/home"))
  let empty = redirect_back_context(None, Some("example.com"))
  empty.redirect_back(fallback="")
  assert_eq(empty.response.headers.get("Location"), Some("/"))
}

///|
test "redirect back rejects protocol relative and malformed targets" {
  let referers = [
    "//evil.com/dashboard",
    "/\\evil.com/dashboard",
    "https://example.com//evil.com/dashboard",
    "https://example.com/\\evil.com/dashboard",
    "javascript:alert(1)",
    "https://example.com.evil.com/dashboard",
    "https://user@example.com/dashboard",
    "https://example.com:bad/dashboard",
    "/dashboard\r\nX-Injected: yes",
  ]
  for referer in referers {
    let ctx = redirect_back_context(Some(referer), Some("example.com"))
    ctx.redirect_back(fallback="/safe")
    assert_eq(ctx.response.status, 303)
    assert_eq(
      ctx.response.headers.get("Location"),
      Some("/safe"),
    )
  }
}

///|
test "redirect back accepts a local referer without a host header" {
  let ctx = redirect_back_context(Some("/items/1"), None)
  ctx.redirect_back()
  assert_eq(ctx.response.status, 303)
  assert_eq(ctx.response.headers.get("Location"), Some("/items/1"))
}
