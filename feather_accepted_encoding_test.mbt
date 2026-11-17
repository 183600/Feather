///|
fn accepted_encoding_ctx(header : String?) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: match header {
      Some(value) => Map([("Accept-Encoding", value)])
      None => Map([])
    },
    body: "",
  })
}

///|
test "accepted_encodings distinguishes missing from empty headers" {
  assert_eq(accepted_encoding_ctx(None).accepted_encodings(), ["*"])
  assert_eq(accepted_encoding_ctx(Some("")).accepted_encodings(), [])
  assert_eq(accepted_encoding_ctx(Some("   ")).accepted_encodings(), [])
}

///|
test "accepted_encodings ranks live entries and drops rejected ones" {
  assert_eq(
    accepted_encoding_ctx(Some("gzip, br;q=0.5, identity;q=0")).accepted_encodings(),
    ["gzip", "br"],
  )
  assert_eq(
    accepted_encoding_ctx(Some("BR;q=0.8, gzip;q=0.4, *;q=0.1")).accepted_encodings(),
    ["br", "gzip", "*"],
  )
  assert_eq(accepted_encoding_ctx(Some("gzip;q=0")).accepted_encodings(), [])
}
