///|
async fn decode_gzip_for_test(data : Bytes) -> Bytes {
  let reader = @io.MemoryReader(async fn(writer) { writer.write(data) })
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
  assert_true(accept_encoding_allows_gzip("gzip;q=0.5".view()))
  assert_true(accept_encoding_allows_gzip("gzip;q=1, identity;q=0.1".view()))
  assert_true(accept_encoding_allows_gzip("*;q=0.5".view()))
  assert_false(accept_encoding_allows_gzip("gzip;q=0.1, identity;q=1".view()))
  assert_false(
    accept_encoding_allows_gzip("gzip;q=0.1, identity;q=1, br;q=1".view()),
  )
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
  assert_false(
    content_type_is_compressible("application/x-www-form-urlencodedx".view()),
  )
  assert_false(content_type_is_compressible("image/svg+xmlish".view()))
  assert_true(content_type_is_compressible("Text/Plain; Charset=UTF-8".view()))
  assert_true(content_type_is_compressible("application/vnd.x+json".view()))
  assert_true(content_type_is_compressible("application/atom+xml".view()))
}

///|
fn find_view_ignore_ascii_case(
  haystack : StringView,
  needle : StringView,
  start : Int32,
) -> Int32? {
  let length = needle.length()
  if length == 0 {
    return Some(start)
  }
  let last = haystack.length() - length
  let first = needle.unsafe_get(0).to_int()
  let lower_first = if first >= 65 && first <= 90 { first + 32 } else { first }
  let mut i = start
  while i <= last {
    let value = haystack.unsafe_get(i).to_int()
    let first_matches = if value == first {
      true
    } else {
      let lower_value = if value >= 65 && value <= 90 {
        value + 32
      } else {
        value
      }
      lower_value == lower_first
    }
    if first_matches {
      let mut j = 1
      let mut matched = true
      while j < length {
        let left = haystack.unsafe_get(i + j).to_int()
        let right = needle.unsafe_get(j).to_int()
        if left != right {
          let lower_left = if left >= 65 && left <= 90 {
            left + 32
          } else {
            left
          }
          let lower_right = if right >= 65 && right <= 90 {
            right + 32
          } else {
            right
          }
          if lower_left != lower_right {
            matched = false
            break
          }
        }
        j = j + 1
      }
      if matched {
        return Some(i)
      }
    }
    i = i + 1
  }
  None
}

///|
fn accept_encoding_allows_gzip(header : StringView) -> Bool {
  if trim_ascii_space(header).is_empty() {
    return false
  }
  encoding_entries_prefer_gzip(parse_encoding_entries(header))
}

///|
fn contains_ignore_ascii_case(
  haystack : StringView,
  needle : StringView,
) -> Bool {
  find_view_ignore_ascii_case(haystack, needle, 0) is Some(_)
}

///|
test "contains ignore ascii case" {
  assert_true(
    contains_ignore_ascii_case("Accept-Encoding".view(), "encoding".view()),
  )
  assert_true(contains_ignore_ascii_case("origin".view(), "ORIGIN".view()))
  assert_true(contains_ignore_ascii_case("".view(), "".view()))
  assert_false(contains_ignore_ascii_case("origin".view(), "encoding".view()))
  assert_false(contains_ignore_ascii_case("or".view(), "origin".view()))
}

///|
test "accept encoding gzip negotiation (moved from compress.mbt)" {
  assert_true(accept_encoding_allows_gzip("gzip".view()))
  assert_true(accept_encoding_allows_gzip("gzip, deflate, br".view()))
  assert_true(accept_encoding_allows_gzip("deflate, gzip;q=1.0".view()))
  assert_true(accept_encoding_allows_gzip("*".view()))
  assert_true(accept_encoding_allows_gzip("GZIP".view()))
  assert_true(accept_encoding_allows_gzip("identity;q=0, *;q=0.5".view()))
  assert_true(accept_encoding_allows_gzip("gzip;q=0.5".view()))
  assert_true(accept_encoding_allows_gzip("gzip;q=1, identity;q=0.1".view()))
  assert_true(accept_encoding_allows_gzip("*;q=0.5".view()))
  assert_false(accept_encoding_allows_gzip("gzip;q=0.1, identity;q=1".view()))
  assert_false(
    accept_encoding_allows_gzip("gzip;q=0.1, identity;q=1, br;q=1".view()),
  )
  assert_false(accept_encoding_allows_gzip("".view()))
  assert_false(accept_encoding_allows_gzip("deflate".view()))
  assert_false(accept_encoding_allows_gzip("identity".view()))
  assert_false(accept_encoding_allows_gzip("gzip;q=0".view()))
  assert_false(accept_encoding_allows_gzip("gzip;q=0.0".view()))
  assert_false(accept_encoding_allows_gzip("gzip;q=0, *;q=1".view()))
  assert_false(accept_encoding_allows_gzip("gzip ; q = 0".view()))
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
  compress_response(Some("gzip"), response, 16)
  assert_eq(
    get_header_ignore_case(response.headers, "Content-Encoding"),
    Some("gzip"),
  )
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
