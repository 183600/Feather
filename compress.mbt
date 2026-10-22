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
/// Request state key recording a per-response compression decision.
const COMPRESSION_OVERRIDE_KEY : String = "__feather_response_compression"

///|
/// Force gzip compression for this response, even when application-wide
/// compression is disabled.
///
/// `min_size` is the smallest body, in bytes, that is worth compressing for
/// this response; it defaults to `0`, so any compressible body whose gzip form
/// is smaller is encoded. The request's `Accept-Encoding` is still honored and
/// `Vary: Accept-Encoding` is still added. Like application-wide compression,
/// this takes effect when the response is sent by the server or built with
/// `App::respond_async`; the synchronous `App::respond` facade never
/// compresses.
pub fn Context::compress(self : Context, min_size~ : Int32 = 0) -> Unit {
  let minimum = if min_size < 0 { 0 } else { min_size }
  self.state.set(COMPRESSION_OVERRIDE_KEY, "on:" + minimum.to_string())
}

///|
/// Disable gzip compression for this response, even when application-wide
/// compression is enabled.
///
/// The response is sent as-is and no `Vary: Accept-Encoding` is added by the
/// compression stage, because this representation does not depend on the
/// request's accepted encodings.
pub fn Context::no_compress(self : Context) -> Unit {
  self.state.set(COMPRESSION_OVERRIDE_KEY, "off")
}

///|
/// Whether this response should be compressed and the threshold to use,
/// honoring a per-response `Context::compress` / `Context::no_compress`
/// decision before the application-wide setting.
fn compression_settings(app : App, ctx : Context) -> (Bool, Int32) {
  match ctx.state.get(COMPRESSION_OVERRIDE_KEY) {
    Some(value) =>
      if value == "off" {
        (false, app.compress_min_size)
      } else if value.has_prefix("on:") {
        let minimum = match parse_int_value(value[3:].view()) {
          Some(size) => if size < 0 { 0 } else { size }
          None => 0
        }
        (true, minimum)
      } else {
        (app.compress_enabled, app.compress_min_size)
      }
    None => (app.compress_enabled, app.compress_min_size)
  }
}

///|
fn parse_quality(value : StringView) -> Int32 {
  let length = value.length()
  if length == 0 {
    return 0
  }
  let mut index = 0
  let mut whole = 0
  while index < length {
    let digit = value.unsafe_get(index).to_int() - 48
    if digit < 0 || digit > 9 {
      break
    }
    whole = whole * 10 + digit
    if whole > 1 || index > 0 {
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
    while index < length {
      let digit = value.unsafe_get(index).to_int() - 48
      if digit < 0 || digit > 9 || scale == 0 {
        return 0
      }
      result = result + digit * scale
      scale = scale / 10
      index = index + 1
    }
  }
  if index != length || result > 1000 {
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
/// Same check as `accept_encoding_allows_gzip` for a header string.
fn accept_encoding_allows_gzip_cached(header : String) -> Bool {
  if trim_ascii_space(header.view()).is_empty() {
    return false
  }
  encoding_quality_from(encoding_entries_cached(header), "gzip".view()) > 0
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
  if has_ascii_upper(value) {
    let lower = value.to_lower().view()
    lower == ("application/json" : StringView) ||
    lower == ("application/javascript" : StringView) ||
    lower == ("application/xml" : StringView) ||
    lower == ("application/x-www-form-urlencoded" : StringView) ||
    lower.has_suffix("+json") ||
    lower.has_suffix("+xml")
  } else {
    value == ("application/json" : StringView) ||
    value == ("application/javascript" : StringView) ||
    value == ("application/xml" : StringView) ||
    value == ("application/x-www-form-urlencoded" : StringView) ||
    value.has_suffix("+json") ||
    value.has_suffix("+xml")
  }
}

///|
let header_accept_encoding : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Accept-Encoding",
)

///|
/// The `Accept-Encoding` header of a server request, or `None` when the
/// request carries none.
fn accept_encoding_of(request : @http.Request) -> String? {
  request.headers.get(header_accept_encoding)
}

///|
fn contains_ignore_ascii_case(
  haystack : StringView,
  needle : StringView,
) -> Bool {
  find_view_ignore_ascii_case(haystack, needle, 0) is Some(_)
}

///|
/// Append `Accept-Encoding` to the `Vary` header unless it is already listed.
fn add_vary_accept_encoding(response : Response) -> Unit {
  match get_header_ignore_case(response.headers, "Vary") {
    Some(existing) =>
      if !header_list_has_token(existing.view(), "accept-encoding".view()) {
        set_header_ignore_case(
          response.headers,
          "Vary",
          existing + ", Accept-Encoding",
        )
      }
    None => response.headers.set("Vary", "Accept-Encoding")
  }
}

///|
/// A `@io.Writer` that collects every written chunk in one growable buffer.
priv struct ChunkSink {
  buffer : @buffer.Buffer
}

///|
fn ChunkSink::new(size_hint : Int32) -> ChunkSink {
  { buffer: @buffer.Buffer::Buffer(size_hint~), }
}

///|
impl @io.Writer for ChunkSink with fn write_once(self, buf, offset~, len~) {
  if len > 0 {
    self.buffer.write_bytes(buf[offset:offset + len])
  }
  len
}

///|
fn ChunkSink::to_bytes(self : ChunkSink) -> Bytes {
  self.buffer.to_bytes()
}

///|
/// Input chunk size fed to the gzip encoder between scheduler yields.
const GZIP_CHUNK_SIZE : Int32 = 65536

///|
async fn gzip_compress(data : Bytes) -> Bytes {
  let length = data.length()
  let hint = if length < 2048 {
    1024
  } else if length < 524288 {
    length / 2
  } else {
    262144
  }
  let sink = ChunkSink::new(hint)
  let encoder = @gzip.Encoder::Encoder(sink)
  let mut offset = 0
  while offset < length {
    let remaining = length - offset
    let end = if remaining < GZIP_CHUNK_SIZE {
      length
    } else {
      offset + GZIP_CHUNK_SIZE
    }
    encoder.write(data[offset:end])
    offset = end
    if offset < length {
      @async.pause()
    }
  }
  encoder.end()
  sink.to_bytes()
}

///|
/// Compress the response body when the client accepts gzip.
///
/// `accept_encoding` is the `Accept-Encoding` header of the request, or
/// `None` when the request carries none. The body is left alone when the
/// response is not compressible, when the client does not accept gzip, or
/// when the compressed body would not be smaller than the original one.
async fn compress_response(
  accept_encoding : String?,
  response : Response,
  min_size : Int32,
) -> Unit {
  if response.status < 200 ||
    response.status == 204 ||
    response.status == 205 ||
    response.status == 304 ||
    response.status == 206 {
    return
  }
  // Without a compressible `Content-Type` there is nothing else to decide.
  let content_type = match
    get_header_ignore_case(response.headers, "Content-Type") {
    Some(value) => value.view()
    None => return
  }
  if !content_type_is_compressible(content_type) {
    return
  }
  if get_header_ignore_case(response.headers, "Content-Encoding") is Some(_) {
    return
  }
  if get_header_ignore_case(response.headers, "Content-Range") is Some(_) {
    return
  }
  match get_header_ignore_case(response.headers, "Cache-Control") {
    Some(control) =>
      if cache_control_has_directive(control.view(), "no-transform".view()) {
        return
      }
    None => ()
  }
  add_vary_accept_encoding(response)
  let accept_encoding = match accept_encoding {
    Some(value) => value
    None => return
  }
  if !accept_encoding_allows_gzip_cached(accept_encoding) {
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
  ignore(remove_header_ignore_case(response.headers, "Content-Length"))
  match get_header_ignore_case(response.headers, "ETag") {
    Some(existing) =>
      if !existing.has_prefix("W/") {
        set_header_ignore_case(response.headers, "ETag", "W/" + existing)
      }
    None => ()
  }
}

///|
pub fn Feather::compress(self : Feather, min_size~ : Int32 = 1024) -> Feather {
  ignore(self.app.compress(min_size~))
  self
}
