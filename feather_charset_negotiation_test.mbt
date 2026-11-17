///|
fn charset_ctx(header : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: if header == "" {
      Map([])
    } else {
      Map([("Accept-Charset", header)])
    },
    body: "",
  })
}

///|
test "accepts_charset treats a missing or empty header as accepting everything" {
  assert_true(charset_ctx("").accepts_charset("utf-8"))
  assert_true(charset_ctx("   ").accepts_charset("iso-8859-1"))
  assert_true(charset_ctx("").accepts_charset(""))
}

///|
test "accepts_charset matches names exactly and case insensitively" {
  assert_true(charset_ctx("utf-8").accepts_charset("utf-8"))
  assert_true(charset_ctx("UTF-8").accepts_charset("utf-8"))
  assert_false(charset_ctx("utf-8").accepts_charset("utf-16"))
  // Charset names are not hierarchical: a prefix does not match.
  assert_false(charset_ctx("utf").accepts_charset("utf-8"))
  assert_false(charset_ctx("utf-8").accepts_charset("utf"))
}

///|
test "accepts_charset honors quality values, wildcards and specificity" {
  assert_false(charset_ctx("utf-8;q=0").accepts_charset("utf-8"))
  assert_true(charset_ctx("utf-8;q=0.001").accepts_charset("utf-8"))
  assert_true(charset_ctx("*").accepts_charset("iso-8859-1"))
  assert_false(charset_ctx("*;q=0").accepts_charset("iso-8859-1"))
  // An explicit entry outranks the wildcard even when its quality is lower.
  assert_false(
    charset_ctx("utf-8;q=0, *;q=0.9").accepts_charset("utf-8"),
  )
  assert_true(
    charset_ctx("utf-8;q=0.2, *;q=0.9").accepts_charset("utf-8"),
  )
  assert_true(
    charset_ctx("utf-8;q=0, *;q=0.9").accepts_charset("iso-8859-1"),
  )
}

///|
test "preferred_charset picks the best offer and keeps server order on ties" {
  let ctx = charset_ctx("iso-8859-1;q=0.9, utf-8;q=0.8")
  assert_eq(ctx.preferred_charset(["utf-8", "iso-8859-1"]), Some("iso-8859-1"))
  let tied = charset_ctx("*")
  assert_eq(tied.preferred_charset(["utf-8", "iso-8859-1"]), Some("utf-8"))
  assert_eq(charset_ctx("").preferred_charset(["utf-8"]), Some("utf-8"))
  assert_eq(charset_ctx("").preferred_charset([]), None)
  assert_eq(charset_ctx("utf-8").preferred_charset(["iso-8859-1"]), None)
  assert_eq(charset_ctx("utf-8;q=0").preferred_charset(["utf-8"]), None)
}

///|
test "accepted_charsets ranks live entries and drops rejected ones" {
  assert_eq(charset_ctx("").accepted_charsets(), ["*"])
  assert_eq(charset_ctx("UTF-8, iso-8859-1").accepted_charsets(), [
    "utf-8", "iso-8859-1",
  ])
  assert_eq(
    charset_ctx("utf-8;q=0.5, iso-8859-1;q=0.9, utf-16;q=0")
      .accepted_charsets(),
    ["iso-8859-1", "utf-8"],
  )
  assert_eq(charset_ctx("utf-8;q=0").accepted_charsets(), [])
}

///|
test "accepted_languages ranks live ranges and drops rejected ones" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Accept-Language", "en-US, fr;q=0.8, de;q=0")]),
    body: "",
  })
  assert_eq(ctx.accepted_languages(), ["en-us", "fr"])
  let absent = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(absent.accepted_languages(), ["*"])
}
