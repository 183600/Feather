///|
async fn decode_gzip_for_test(data : Bytes) -> Bytes {
  let reader = @io.MemoryReader(async fn(writer) {
    writer.write(data)
  })
  defer reader.close()
  let decoder = @gzip.Decoder::Decoder(reader)
  decoder.read_all().binary()
}

///|
test "parse quality values" {
  assert_eq(parse_quality("1".view()), 1000)
  assert_eq(parse_quality("0".view()), 0)
  assert_eq(parse_quality("0.5".view()), 500)
  assert_eq(parse_quality("0.001".view()), 1)
  assert_eq(parse_quality("1.000".view()), 1000)
  assert_eq(parse_quality("2".view()), 0)
  assert_eq(parse_quality("".view()), 0)
  assert_eq(parse_quality("abc".view()), 0)
}

///|
test "accept encoding gzip negotiation" {
  assert_true(accept_encoding_allows_gzip("gzip".view()))
  assert_true(accept_encoding_allows_gzip("gzip, deflate, br".view()))
  assert_true(accept_encoding_allows_gzip("deflate, gzip;q=1.0".view()))
  assert_true(accept_encoding_allows_gzip("*".view()))
  assert_true(accept_encoding_allows_gzip("GZIP".view()))
  assert_true(accept_encoding_allows_gzip("identity;q=0, *;q=0.5".view()))
  assert_false(accept_encoding_allows_gzip("".view()))
  assert_false(accept_encoding_allows_gzip("deflate".view()))
  assert_false(accept_encoding_allows_gzip("identity".view()))
  assert_false(accept_encoding_allows_gzip("gzip;q=0".view()))
  assert_false(accept_encoding_allows_gzip("gzip;q=0.0".view()))
  assert_false(accept_encoding_allows_gzip("gzip;q=0, *;q=1".view()))
  assert_false(accept_encoding_allows_gzip("gzip ; q = 0".view()))
}

///|
test "compressible content types" {
  assert_true(content_type_is_compressible("text/plain; charset=utf-8".view()))
  assert_true(content_type_is_compressible("text/html".view()))
  assert_true(content_type_is_compressible("application/json".view()))
  assert_true(content_type_is_compressible("APPLICATION/JSON".view()))
  assert_true(content_type_is_compressible("application/vnd.api+json".view()))
  assert_true(content_type_is_compressible("application/xml".view()))
  assert_true(content_type_is_compressible("image/svg+xml".view()))
  assert_true(content_type_is_compressible("application/javascript".view()))
  assert_false(content_type_is_compressible("image/png".view()))
  assert_false(content_type_is_compressible("application/octet-stream".view()))
  assert_false(content_type_is_compressible("".view()))
  assert_false(content_type_is_compressible("application/zip; x=1".view()))
}

///|
test "compressible content types require the exact registered media type" {
  assert_false(content_type_is_compressible("application/jsonx".view()))
  assert_false(content_type_is_compressible("application/javascriptx".view()))
  assert_false(content_type_is_compressible("application/xmlx".view()))
  assert_false(content_type_is_compressible("application/x-www-form-urlencodedx".view()))
  assert_false(content_type_is_compressible("image/svg+xmlish".view()))
  assert_true(
    content_type_is_compressible("Text/Plain; Charset=UTF-8".view()),
  )
  assert_true(content_type_is_compressible("application/vnd.x+json".view()))
  assert_true(content_type_is_compressible("application/atom+xml".view()))
}

///|
test "contains ignore ascii case" {
  assert_true(contains_ignore_ascii_case("Accept-Encoding".view(), "encoding".view()))
  assert_true(contains_ignore_ascii_case("origin".view(), "ORIGIN".view()))
  assert_true(contains_ignore_ascii_case("".view(), "".view()))
  assert_false(contains_ignore_ascii_case("origin".view(), "encoding".view()))
  assert_false(contains_ignore_ascii_case("or".view(), "origin".view()))
}

///|
test "add vary accept encoding keeps a single header entry" {
  let response : Response = {
    status: 200,
    headers: Map([("vary", "Origin")]),
    body: "",
    data: None,
    cookies: [],
  }
  add_vary_accept_encoding(response)
  assert_eq(
    get_header_ignore_case(response.headers, "Vary"),
    Some("Origin, Accept-Encoding"),
  )
  assert_eq(response.headers.length(), 1)
}

///|
test "add vary accept encoding skips an existing token" {
  let response : Response = {
    status: 200,
    headers: Map([("Vary", "accept-encoding, Origin")]),
    body: "",
    data: None,
    cookies: [],
  }
  add_vary_accept_encoding(response)
  assert_eq(
    get_header_ignore_case(response.headers, "Vary"),
    Some("accept-encoding, Origin"),
  )
  assert_eq(response.headers.length(), 1)
}

///|
async test "compression drops a differently-cased Content-Length" {
  let request : @http.Request = {
    meth: @http.Get,
    path: "/big",
    headers: Map([
      (@http.CaseInsensitiveString("Accept-Encoding"), "gzip"),
    ]),
  }
  let response : Response = {
    status: 200,
    headers: Map([
      ("content-length", "999999"),
      ("Content-Type", "text/plain; charset=utf-8"),
    ]),
    body: "compress me ".repeat(200),
    data: None,
    cookies: [],
  }
  compress_response(request, response, 16)
  assert_eq(get_header_ignore_case(response.headers, "Content-Encoding"), Some("gzip"))
  assert_eq(get_header_ignore_case(response.headers, "Content-Length"), None)
}

///|
async test "gzip compress round trips" {
  let payload = @utf8.encode("hello compressible world ".repeat(200))
  let compressed = gzip_compress(payload)
  assert_true(compressed.length() > 0)
  assert_true(compressed.length() < payload.length())
  assert_eq(decode_gzip_for_test(compressed), payload)
}

///|
async test "gzip compress empty input round trips" {
  let payload = b""
  let compressed = gzip_compress(payload)
  assert_eq(decode_gzip_for_test(compressed), payload)
}
