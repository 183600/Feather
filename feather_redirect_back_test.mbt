///|
fn redirect_back_context(referer : String?, host : String?, proto : String?) -> @feather.Context {
  let headers : Map[String, String] = Map([])
  match referer {
    Some(value) => headers.set("Referer", value)
    None => ()
  }
  match host {
    Some(value) => headers.set("Host", value)
    None => ()
  }
  match proto {
    Some(value) => headers.set("X-Forwarded-Proto", value)
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
    Some("https"),
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
    Some("https"),
  )
  ctx.redirect_back()
  assert_eq(ctx.response.status, 303)
  assert_eq(ctx.response.headers.get("Location"), Some("/dashboard?tab=1"))
  let root = redirect_back_context(Some("https://example.com"), Some("example.com"), Some("https"))
  root.redirect_back()
  assert_eq(root.response.headers.get("Location"), Some("/"))
  let query = redirect_back_context(
    Some("https://example.com?page=2"),
    Some("example.com"),
    Some("https"),
  )
  query.redirect_back()
  assert_eq(query.response.headers.get("Location"), Some("/?page=2"))
}

///|
test "redirect back falls back for another origin or a missing referer" {
  let cross = redirect_back_context(
    Some("https://evil.com/dashboard"),
    Some("example.com"),
    Some("https"),
  )
  cross.redirect_back(fallback="/login")
  assert_eq(cross.response.status, 303)
  assert_eq(cross.response.headers.get("Location"), Some("/login"))
  let missing = redirect_back_context(None, Some("example.com"), Some("https"))
  missing.redirect_back(status=302, fallback="/home")
  assert_eq(missing.response.status, 302)
  assert_eq(missing.response.headers.get("Location"), Some("/home"))
  let empty = redirect_back_context(None, Some("example.com"), Some("https"))
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
    let ctx = redirect_back_context(Some(referer), Some("example.com"), Some("https"))
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
  let ctx = redirect_back_context(Some("/items/1"), None, Some("https"))
  ctx.redirect_back()
  assert_eq(ctx.response.status, 303)
  assert_eq(ctx.response.headers.get("Location"), Some("/items/1"))
}

///|
test "redirect back rejects percent-encoded protocol-relative targets" {
  // A same-host referer may contain percent escapes. Decoding them can turn a
  // harmless-looking local path into a protocol-relative or backslash target,
  // so those spellings must fall back just like their literal forms.
  for referer in [
    "/%2f%2fevil.com/dashboard",
    "/%2F%2Fevil.com/dashboard",
    "/%5cevil.com/dashboard",
    "/dashboard/%5Cevil.com",
    "/dashboard%00",
  ] {
    let ctx = redirect_back_context(Some(referer), Some("example.com"), Some("https"))
    ctx.redirect_back(fallback="/safe")
    assert_eq(ctx.response.headers.get("Location"), Some("/safe"), msg=referer)
  }
  // Ordinary percent escapes still round-trip unchanged.
  let escaped = redirect_back_context(
    Some("/caf%C3%A9/settings?tab=a%2Fb"),
    Some("example.com"),
    Some("https"),
  )
  escaped.redirect_back()
  assert_eq(
    escaped.response.headers.get("Location"),
    Some("/caf%C3%A9/settings?tab=a%2Fb"),
  )
}

///|
test "redirect back rejects referer with different port" {
  // Referer from HTTPS port 8443 should not match request on default HTTPS port 443
  let ctx = redirect_back_context(
    Some("https://example.com:8443/dashboard"),
    Some("example.com"),
    Some("https"),
  )
  ctx.redirect_back(fallback="/login")
  assert_eq(ctx.response.status, 303)
  assert_eq(ctx.response.headers.get("Location"), Some("/login"))
  // Referer from HTTP port 8080 should not match request on default HTTP port 80
  let ctx2 = redirect_back_context(
    Some("http://example.com:8080/dashboard"),
    Some("example.com"),
    Some("http"),
  )
  ctx2.redirect_back(fallback="/login")
  assert_eq(ctx2.response.status, 303)
  assert_eq(ctx2.response.headers.get("Location"), Some("/login"))
  // Same port should match
  let ctx3 = redirect_back_context(
    Some("https://example.com:8443/dashboard"),
    Some("example.com:8443"),
    Some("https"),
  )
  ctx3.redirect_back()
  assert_eq(ctx3.response.headers.get("Location"), Some("/dashboard"))
  let ctx4 = redirect_back_context(
    Some("http://example.com:8080/dashboard"),
    Some("example.com:8080"),
    Some("http"),
  )
  ctx4.redirect_back()
  assert_eq(ctx4.response.headers.get("Location"), Some("/dashboard"))
  // Default ports should match (HTTPS 443, HTTP 80)
  let ctx5 = redirect_back_context(
    Some("https://example.com/dashboard"),
    Some("example.com"),
    Some("https"),
  )
  ctx5.redirect_back()
  assert_eq(ctx5.response.headers.get("Location"), Some("/dashboard"))
  let ctx6 = redirect_back_context(
    Some("http://example.com/dashboard"),
    Some("example.com"),
    Some("http"),
  )
  ctx6.redirect_back()
  assert_eq(ctx6.response.headers.get("Location"), Some("/dashboard"))
}
