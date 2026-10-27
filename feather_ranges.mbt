///|
/// Parse a non-negative decimal byte offset into `Int64`, returning `None` for
/// empty, non-numeric or out-of-range input.
fn parse_byte_offset(view : StringView) -> Int64? {
  let length = view.length()
  if length == 0 {
    return None
  }
  let mut value = 0L
  let mut i = 0
  while i < length {
    let digit = view.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    let digit64 = digit.to_int64()
    if value > (9223372036854775807L - digit64) / 10L {
      return None
    }
    value = value * 10L + digit64
    i = i + 1
  }
  Some(value)
}

///|
/// Whether `view` is a non-empty run of decimal digits. Used to distinguish a
/// syntactically valid but out-of-range byte offset from a malformed one.
fn is_decimal_offset(view : StringView) -> Bool {
  let length = view.length()
  if length == 0 {
    return false
  }
  let mut i = 0
  while i < length {
    let digit = view.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return false
    }
    i = i + 1
  }
  true
}

///|
pub fn parse_byte_range(value : String, total : Int64) -> ByteRange {
  let view = trim_ascii_space(value.view())
  if !starts_with_ignore_ascii_case(view, "bytes=".view()) {
    return ByteRangeFull
  }
  let spec = trim_ascii_space(view[6:])
  if spec.contains(",") {
    return ByteRangeFull
  }
  let dash = match spec.find("-") {
    Some(index) => index
    None => return ByteRangeFull
  }
  let start_text = trim_ascii_space(spec[:dash])
  let end_text = trim_ascii_space(spec[dash + 1:])
  if start_text.is_empty() {
    let suffix = match parse_byte_offset(end_text) {
      Some(suffix) => suffix
      // A numeric suffix larger than Int64 is still a valid suffix that
      // selects the whole representation, not malformed syntax to ignore.
      None =>
        if is_decimal_offset(end_text) {
          if total <= 0L {
            return ByteRangeInvalid
          }
          return ByteRangeSpec(0L, total - 1L)
        } else {
          return ByteRangeFull
        }
    }
    if suffix <= 0L || total <= 0L {
      return ByteRangeInvalid
    }
    let start = if suffix >= total { 0L } else { total - suffix }
    return ByteRangeSpec(start, total - 1L)
  }
  let start = match parse_byte_offset(start_text) {
    Some(start) => start
    // Any numeric start that does not fit in Int64 is beyond every possible
    // representation size, so the range is unsatisfiable rather than invalid
    // syntax.
    None =>
      if is_decimal_offset(start_text) {
        return ByteRangeInvalid
      } else {
        return ByteRangeFull
      }
  }
  if end_text.is_empty() {
    if start >= total {
      return ByteRangeInvalid
    }
    return ByteRangeSpec(start, total - 1L)
  }
  let end = match parse_byte_offset(end_text) {
    Some(end) => end
    // An overflowing last-byte position is clamped to the end below.
    None => if is_decimal_offset(end_text) { 9223372036854775807L } else {
      return ByteRangeFull
    }
  }
  if start > end {
    return ByteRangeFull
  }
  if start >= total {
    return ByteRangeInvalid
  }
  let end = if end >= total { total - 1L } else { end }
  ByteRangeSpec(start, end)
}

///|
/// Whether an `If-Range` condition still describes the buffered response, so a
/// `Range` request may be served partially. Entity tags use the strong
/// comparison function, so a weak tag never matches; an HTTP-date must match
/// `Last-Modified` exactly. With neither validator present the range cannot be
/// proven to apply to the current representation, so the full response is sent.
fn buffered_if_range_allows(
  if_range : String?,
  response : Response,
) -> Bool {
  let raw = match if_range {
    Some(value) => value
    None => return true
  }
  let token = trim_ascii_space(raw.view())
  let etag = match get_header_ignore_case(response.headers, "ETag") {
    Some(value) => value
    None => ""
  }
  if etag != "" &&
    !etag.view().has_prefix("W/") &&
    !token.has_prefix("W/") &&
    token == etag.view() {
    return true
  }
  match get_header_ignore_case(response.headers, "Last-Modified") {
    Some(value) =>
      match (parse_http_date_view(value.view()), parse_http_date_view(token)) {
        (Some(modified), Some(since)) => modified == since
        _ => false
      }
    None => false
  }
}

///|
/// Apply a `Range` request to a fully buffered dynamic response.
///
/// Static files have always supported byte ranges; this gives ordinary
/// handlers, middleware short-circuits and streaming/SSE/WebSocket middleware
/// responses the same treatment when the body is already in memory. Only a
/// successful `GET` is eligible, so a `HEAD` keeps advertising the full
/// representation and other methods are untouched. `If-Range` is evaluated
/// against the response's own validators before the range is used.
///
/// A satisfiable range becomes `206 Partial Content` with the sliced bytes and
/// a `Content-Range`; an unsatisfiable one becomes `416 Range Not Satisfiable`
/// describing the full length. A malformed or multi-range request is ignored
/// (the full representation is sent), which RFC 9110 permits.
fn apply_buffered_range_core(
  method : StringView,
  range : String?,
  if_range : String?,
  response : Response,
  head : Bool,
) -> Unit {
  if head || !method.equal_ignore_ascii_case("GET".view()) {
    return
  }
  if response.status != 200 {
    return
  }
  let range_value = match range {
    Some(value) => value
    None => return
  }
  if get_header_ignore_case(response.headers, "Content-Range") is Some(_) {
    return
  }
  if !buffered_if_range_allows(if_range, response) {
    return
  }
  let original_is_bytes = response.data is Some(_)
  let data = match response.data {
    Some(data) => data
    None => encode_utf8_lossy(response.body.view())
  }
  let total = data.length().to_int64()
  match parse_byte_range(range_value, total) {
    ByteRangeFull =>
      set_header_ignore_case(response.headers, "Accept-Ranges", "bytes")
    ByteRangeInvalid => {
      response.status = 416
      clear_replaced_body_headers(response.headers)
      clear_replaced_representation_headers(response.headers)
      set_header_ignore_case(
        response.headers,
        "Content-Type",
        "text/plain; charset=utf-8",
      )
      set_header_ignore_case(
        response.headers,
        "Content-Range",
        "bytes */" + total.to_string(),
      )
      set_header_ignore_case(response.headers, "Accept-Ranges", "bytes")
      response.body = "416 Range Not Satisfiable"
      response.data = None
    }
    ByteRangeSpec(start, end) => {
      let first = start.to_int()
      let sliced = data[first:end.to_int() + 1].to_bytes()
      response.status = 206
      // The framing header still describes the full representation. The
      // server recomputes it while writing, but the offline facade returns
      // this response directly, so a length seeded by middleware must not
      // claim more bytes than the partial body carries.
      ignore(remove_header_ignore_case(response.headers, "Content-Length"))
      if original_is_bytes {
        response.data = Some(sliced)
        response.body = ""
      } else {
        // A range can split a multi-byte UTF-8 sequence. Keep the exact bytes
        // in that case; only a slice that is still valid text can travel in
        // `Response.body`, whose server encoding must reproduce the same bytes.
        let text : String? = Some(@utf8.decode(sliced)) catch {
          @utf8.Malformed(_) => None
        }
        match text {
          Some(text) => {
            response.body = text
            response.data = None
          }
          None => {
            response.body = ""
            response.data = Some(sliced)
          }
        }
      }
      set_header_ignore_case(
        response.headers,
        "Content-Range",
        "bytes " +
        start.to_string() +
        "-" +
        end.to_string() +
        "/" +
        total.to_string(),
      )
      set_header_ignore_case(response.headers, "Accept-Ranges", "bytes")
    }
  }
}

///|
/// Apply a byte range from a framework `Request` to a buffered response.
fn apply_buffered_range(
  request : Request,
  response : Response,
  head : Bool,
) -> Unit {
  apply_buffered_range_core(
    request.method.view(),
    get_header_ignore_case(request.headers, "Range"),
    get_header_ignore_case(request.headers, "If-Range"),
    response,
    head,
  )
}

///|
fn normalize_prefix(prefix : String) -> String {
  let view = clean_path_view(prefix)
  let builder = StringBuilder(size_hint=view.length() + 1)
  let mut has_segment = false
  for segment in view.split("/") {
    if segment.is_empty() {
      continue
    }
    builder.write_char('/')
    builder.write_stringview(segment)
    has_segment = true
  }
  if !has_segment {
    return ""
  }
  builder.to_string()
}

///|
/// Whether `path` is `prefix` itself or lies below it as a whole path segment.
///
/// Both sides are compared using the router's segment model: empty segments
/// from repeated or leading slashes are ignored and each segment is decoded the
/// same way a static route segment is. That keeps a scoped middleware attached
/// to `/admin` from being skipped by a request for `/ad%6Din/panel` or
/// `//admin/panel`, which the router still resolves to the same route. Only
/// whole segments are decoded, so an encoded slash stays inside its segment
/// instead of creating a new one.
fn path_is_within_prefix(path : StringView, prefix : StringView) -> Bool {
  let prefix_segments = split_segments(prefix)
  if prefix_segments.length() == 0 {
    return true
  }
  let path_segments = split_segments(path)
  if path_segments.length() < prefix_segments.length() {
    return false
  }
  for i = 0; i < prefix_segments.length(); i = i + 1 {
    if normalize_static_route_segment(path_segments[i]) !=
      normalize_static_route_segment(prefix_segments[i]) {
      return false
    }
  }
  true
}

