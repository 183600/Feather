///|
fn accept_ctx(accept : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: if accept == "" {
      Map([])
    } else {
      Map([("Accept", accept)])
    },
    body: "",
  })
}

///|
test "accepts treats a missing accept header as accepting everything" {
  assert_true(accept_ctx("").accepts("application/json"))
  assert_true(accept_ctx("").accepts("text/html"))
}

///|
test "accepts matches exact media types case insensitively" {
  assert_true(accept_ctx("application/json").accepts("application/json"))
  assert_true(accept_ctx("Application/JSON").accepts("application/json"))
  assert_false(accept_ctx("application/json").accepts("text/html"))
}

///|
test "accepts understands wildcard media ranges" {
  assert_true(accept_ctx("*/*").accepts("application/json"))
  assert_true(accept_ctx("text/*").accepts("text/html"))
  assert_false(accept_ctx("text/*").accepts("application/json"))
  assert_true(accept_ctx("text/html, */*;q=0.1").accepts("application/xml"))
}

///|
test "accepts honors quality values" {
  assert_false(accept_ctx("application/json;q=0").accepts("application/json"))
  assert_true(accept_ctx("application/json;q=0.001").accepts("application/json"))
  assert_false(accept_ctx("*/*;q=0").accepts("text/html"))
}

///|
test "accepts prefers the most specific matching range" {
  let header = "application/json;q=0, */*;q=0.9"
  assert_false(accept_ctx(header).accepts("application/json"))
  assert_true(accept_ctx(header).accepts("text/html"))
  let wildcard_off = "text/html, */*;q=0"
  assert_true(accept_ctx(wildcard_off).accepts("text/html"))
  assert_false(accept_ctx(wildcard_off).accepts("application/json"))
}

///|
test "accepts ignores media type parameters on the offer" {
  assert_true(
    accept_ctx("text/html").accepts("text/html; charset=utf-8"),
  )
  assert_true(accept_ctx("application/json").accepts("application/json"))
}

///|
test "accepts tolerates malformed headers" {
  assert_true(accept_ctx("garbage").accepts("text/html"))
  assert_true(accept_ctx(",,,").accepts("text/html"))
}

///|
test "accepts understands wildcards in the offered media type" {
  assert_true(accept_ctx("text/html").accepts("*/*"))
  assert_true(accept_ctx("text/html").accepts("text/*"))
  assert_true(accept_ctx("Text/HTML").accepts("text/*"))
  assert_false(accept_ctx("application/json").accepts("text/*"))
  assert_true(accept_ctx("application/json").accepts("application/*"))
  assert_false(accept_ctx("text/html;q=0").accepts("text/*"))
  assert_true(accept_ctx("text/html;q=0, text/*;q=0.5").accepts("text/*"))
  assert_false(accept_ctx("*/*;q=0").accepts("*/*"))
  assert_true(accept_ctx("*/*;q=0.2").accepts("application/*"))
  assert_true(accept_ctx("application/json, text/html").accepts("*/*"))
  assert_true(accept_ctx("").accepts("text/*"))
}

///|
test "preferred_type treats wildcard offers as patterns" {
  let ctx = accept_ctx("application/json;q=0.8, text/html;q=0.9")
  assert_eq(ctx.preferred_type(["application/*", "text/*"]), Some("text/*"))
  assert_eq(ctx.preferred_type(["image/*", "audio/*"]), None)
  let json_ctx = accept_ctx("application/json")
  assert_eq(json_ctx.preferred_type(["application/*"]), Some("application/*"))
}

///|
test "preferred_type picks the best matching offer" {
  let ctx = accept_ctx("text/html;q=0.9, application/json;q=0.8")
  assert_eq(ctx.preferred_type(["application/json", "text/html"]), Some("text/html"))
  assert_eq(
    ctx.preferred_type(["text/plain", "application/xml"]),
    None,
  )
}

///|
test "preferred_type keeps server order on quality ties" {
  let ctx = accept_ctx("*/*")
  assert_eq(
    ctx.preferred_type(["application/json", "text/html"]),
    Some("application/json"),
  )
  let specific = accept_ctx("text/html, application/json")
  assert_eq(
    specific.preferred_type(["application/json", "text/html"]),
    Some("application/json"),
  )
}

///|
test "preferred_type skips rejected offers" {
  let ctx = accept_ctx("application/json;q=0, text/*")
  assert_eq(
    ctx.preferred_type(["application/json", "text/html"]),
    Some("text/html"),
  )
  assert_eq(
    ctx.preferred_type(["application/json", "image/png"]),
    None,
  )
  assert_eq(
    accept_ctx("").preferred_type([]),
    None,
  )
}

///|
fn encoding_ctx(accept_encoding : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: if accept_encoding == "" {
      Map([])
    } else {
      Map([("Accept-Encoding", accept_encoding)])
    },
    body: "",
  })
}

///|
test "accepts_encoding treats a missing header as accepting everything" {
  assert_true(encoding_ctx("").accepts_encoding("gzip"))
  assert_true(encoding_ctx("").accepts_encoding("br"))
  assert_true(encoding_ctx("gzip, identity").accepts_encoding("gzip"))
  assert_true(encoding_ctx("gzip, identity").accepts_encoding("identity"))
}

///|
test "accepts_encoding rejects codings that are not listed" {
  assert_false(encoding_ctx("identity").accepts_encoding("gzip"))
  assert_false(encoding_ctx("gzip;q=0").accepts_encoding("gzip"))
  assert_true(encoding_ctx("gzip;q=0.5").accepts_encoding("gzip"))
  assert_true(encoding_ctx("*").accepts_encoding("br"))
  assert_false(encoding_ctx("*;q=0").accepts_encoding("br"))
  assert_true(encoding_ctx("*;q=0, br;q=0.5").accepts_encoding("br"))
  assert_true(encoding_ctx("GZIP").accepts_encoding("gzip"))
}

///|
test "accepts_encoding treats identity as acceptable by default" {
  assert_true(encoding_ctx("gzip").accepts_encoding("identity"))
  assert_true(encoding_ctx("gzip, br").accepts_encoding("identity"))
  assert_true(encoding_ctx("").accepts_encoding("identity"))
  assert_false(encoding_ctx("gzip, identity;q=0").accepts_encoding("identity"))
  assert_false(encoding_ctx("*;q=0").accepts_encoding("identity"))
  assert_true(encoding_ctx("gzip, *;q=0.5").accepts_encoding("identity"))
  assert_false(encoding_ctx("identity;q=0, *;q=0.8").accepts_encoding("identity"))
}

///|
test "preferred_encoding picks the best coding and honors server order" {
  let ctx = encoding_ctx("br;q=0.9, gzip;q=0.8")
  assert_eq(ctx.preferred_encoding(["gzip", "br"]), Some("br"))
  assert_eq(ctx.preferred_encoding(["deflate"]), None)
  let tied = encoding_ctx("gzip, br")
  assert_eq(tied.preferred_encoding(["gzip", "br"]), Some("gzip"))
  assert_eq(encoding_ctx("").preferred_encoding([]), None)
  assert_eq(
    encoding_ctx("gzip;q=0, *;q=0.5").preferred_encoding(["gzip", "deflate"]),
    Some("deflate"),
  )
}
