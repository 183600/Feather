///|
/// Enable gzip compression for responses whose body is at least `min_size`
/// bytes and whose content type is compressible.
///
/// Compression is negotiated per request via `Accept-Encoding`. When enabled,
/// `Vary: Accept-Encoding` is added to compressible responses so shared caches
/// keep the encodings apart.
pub fn App::compress(self : App, min_size~ : Int32 = 1024) -> App {
  self.compress_enabled = true
  self.compress_min_size = if min_size < 0 { 0 } else { min_size }
  self
}

///|
fn parse_quality(value : StringView) -> Int {
  let length = value.length()
  let mut index = 0
  let mut whole = 0
  while index < length {
    let digit = value.unsafe_get(index).to_int() - 48
    if digit < 0 || digit > 9 {
      break
    }
    whole = whole * 10 + digit
    if whole > 1 {
      return 0
    }
    index = index + 1
  }
  if index == 0 {
    return 0
  }
  let mut result = whole * 1000
  if index < length && value.unsafe_get(index) == ('.' : UInt16) {
    index = index + 1
    let mut scale = 100
    while index < length && scale > 0 {
      let digit = value.unsafe_get(index).to_int() - 48
      if digit < 0 || digit > 9 {
        break
      }
      result = result + digit * scale
      scale = scale / 10
      index = index + 1
    }
  }
  if result > 1000 {
    return 0
  }
  result
}

///|
/// Check whether `Accept-Encoding` allows the `gzip` coding.
///
/// A coding is allowed when its quality value is positive, or when it is not
/// mentioned but `*` has a positive quality value. An empty header allows
/// nothing, matching the caller which only consults a present header.
fn accept_encoding_allows_gzip(header : StringView) -> Bool {
  if trim_ascii_space(header).is_empty() {
    return false
  }
  accept_encoding_quality(header, "gzip".view()) > 0
}

///|
fn content_type_is_compressible(content_type : StringView) -> Bool {
  let mut end = content_type.length()
  let mut i = 0
  while i < end {
    if content_type.unsafe_get(i) == (';' : UInt16) {
      end = i
      break
    }
    i = i + 1
  }
  let value = trim_ascii_space(content_type[:end])
  if value.is_empty() {
    return false
  }
  if starts_with_ignore_ascii_case(value, "text/".view()) {
    return true
  }
  let lower = if has_ascii_upper(value) {
    value.to_lower().view()
  } else {
    value
  }
  lower.has_prefix("application/json") ||
  lower.has_prefix("application/javascript") ||
  lower.has_prefix("application/xml") ||
  lower.has_prefix("application/x-www-form-urlencoded") ||
  lower.has_prefix("image/svg+xml") ||
  lower.has_suffix("+json") ||
  lower.has_suffix("+xml")
}

let header_accept_encoding : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Accept-Encoding",
)

///|
fn contains_ignore_ascii_case(haystack : StringView, needle : StringView) -> Bool {
  find_view_ignore_ascii_case(haystack, needle, 0) is Some(_)
}

///|
fn add_vary_accept_encoding(response : Response) -> Unit {
  match get_header_ignore_case(response.headers, "Vary") {
    Some(existing) =>
      if !contains_ignore_ascii_case(existing.view(), "accept-encoding".view()) {
        response.headers.set("Vary", existing + ", Accept-Encoding")
      }
    None => response.headers.set("Vary", "Accept-Encoding")
  }
}

///|
async fn gzip_compress(data : Bytes) -> Bytes {
  let reader = @io.MemoryReader(async fn(writer) {
    let encoder = @gzip.Encoder::Encoder(writer)
    encoder.write(data)
    encoder.end()
  })
  defer reader.close()
  reader.read_all().binary()
}

///|
async fn compress_response(
  request : @http.Request,
  response : Response,
  min_size : Int32,
) -> Unit {
  if response.status < 200 || response.status == 204 || response.status == 304 {
    return
  }
  if get_header_ignore_case(response.headers, "Content-Encoding") is Some(_) {
    return
  }
  match get_header_ignore_case(response.headers, "Cache-Control") {
    Some(control) =>
      if contains_ignore_ascii_case(control.view(), "no-transform".view()) {
        return
      }
    None => ()
  }
  let content_type = match get_header_ignore_case(response.headers, "Content-Type") {
    Some(value) => value.view()
    None => return
  }
  if !content_type_is_compressible(content_type) {
    return
  }
  add_vary_accept_encoding(response)
  let accept_encoding = match request.headers.get(header_accept_encoding) {
    Some(value) => value
    None => return
  }
  if !accept_encoding_allows_gzip(accept_encoding.view()) {
    return
  }
  let body_bytes = match response.data {
    Some(data) => data
    None =>
      if response.body.is_empty() {
        return
      } else {
        @utf8.encode(response.body)
      }
  }
  if body_bytes.length() < min_size {
    return
  }
  let compressed = gzip_compress(body_bytes)
  if compressed.length() >= body_bytes.length() {
    return
  }
  response.body = ""
  response.data = Some(compressed)
  response.headers.set("Content-Encoding", "gzip")
  response.headers.remove("Content-Length")
}

///|
pub fn Feather::compress(self : Feather, min_size~ : Int32 = 1024) -> Feather {
  ignore(self.app.compress(min_size~))
  self
}
