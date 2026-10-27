///|
/// Context state key marking that the middleware chain called through to an
/// asynchronous endpoint (WebSocket, SSE or streaming response).
const ASYNC_CHAIN_PASS_KEY : String = "__feather_async_pass"

///|
/// Apply the ordinary dynamic-response pipeline (preconditions, compression,
/// generated ETags) to a context produced by a handler or middleware chain.
///
/// Async endpoint middleware can short-circuit with an ordinary response; it
/// must go through the same negotiation and validator stages as a normal route
/// instead of being written verbatim.
async fn finalize_dynamic_response(
  app : App,
  request : @http.Request,
  ctx : Context,
) -> Unit {
  if ctx.file_response() is None {
    let (input, allows_not_modified) = precondition_input_http(request)
    let (failed, remaining) = precheck_preconditions(
      input,
      allows_not_modified,
      ctx.response,
    )
    if !failed {
      let accept_encoding = accept_encoding_of(request)
      if !negotiate_existing_encoding(accept_encoding, ctx.response) {
        let (compress, min_size) = compression_settings(app, ctx)
        if compress {
          compress_response(accept_encoding, ctx.response, min_size)
        } else {
          reject_unacceptable_identity(accept_encoding, ctx.response)
        }
      }
      if response_etag_enabled(app, ctx) {
        apply_etag(ctx.response)
      }
      apply_preconditions_input(remaining, allows_not_modified, ctx.response)
    }
  }
}

///|
/// Apply a buffered-response `Range` request using the HTTP runtime's request
/// headers, mirroring `App::respond` for the server path.
fn apply_buffered_range_http(
  request : @http.Request,
  response : Response,
  head : Bool,
) -> Unit {
  apply_buffered_range_core(
    request_method_to_string(request.meth).view(),
    request.headers.get(header_range),
    request.headers.get(header_if_range),
    response,
    head,
  )
}

///|
/// Send the response a short-circuiting middleware produced for an
/// asynchronous endpoint, supporting both ordinary bodies and file responses.
async fn send_context_response(
  app : App,
  conn : @http.ServerConnection,
  ctx : Context,
  head : Bool,
  request : @http.Request,
) -> Unit {
  finalize_dynamic_response(app, request, ctx)
  let connect = request.meth is @http.Connect
  match ctx.file_response() {
    Some(file) => {
      let (compress, compress_min_size) = compression_settings(app, ctx)
      send_file_response(
        conn,
        ctx.response,
        file,
        head,
        request,
        connect~,
        auto_etag=response_file_etag_enabled(ctx),
        compress_enabled=compress,
        compress_min_size~,
      )
    }
    None => {
      apply_buffered_range_http(request, ctx.response, head)
      send_response(conn, ctx.response, head, connect~)
    }
  }
}

///|
/// Terminal of every asynchronous middleware chain: records in the request
/// state that the chain called through to the endpoint.
fn async_chain_terminal(ctx : Context) -> Unit raise {
  ctx.state.set(ASYNC_CHAIN_PASS_KEY, "1")
}

///|
/// The application-level asynchronous middleware chain.
fn App::async_middleware_chain(self : App) -> Handler {
  match self.async_chain {
    Some(chain) => chain
    None => {
      let chain = if self.middlewares.length() == 0 {
        async_chain_terminal
      } else {
        apply_middleware(self.middlewares, async_chain_terminal)
      }
      self.async_chain = Some(chain)
      chain
    }
  }
}

///|
/// Run an already-composed middleware chain before an asynchronous endpoint
/// starts.
///
/// Middleware that short-circuits (for example an authenticator) answers the
/// request instead of letting the endpoint start. Middleware that calls through
/// lets the endpoint proceed; headers and cookies it added to the response are
/// carried into SSE and streaming responses.
fn run_async_middleware_chain(chain : Handler, ctx : Context) -> Bool {
  // A previous chain (the application-level one) may have left its pass marker
  // behind; clear it so only a call-through in this chain counts.
  ctx.state.remove(ASYNC_CHAIN_PASS_KEY)
  let mut failed = false
  chain(ctx) catch {
    HttpError(status, message) => {
      error_response(ctx, status, message)
      failed = true
    }
    HttpErrorPayload(status, message, payload) => {
      error_response_with_payload(ctx, status, message, payload)
      failed = true
    }
    HttpProblem(status, type_name, title, detail, instance) => {
      problem_response(ctx, status, type_name, title, detail, instance)
      failed = true
    }
    err => {
      internal_error(ctx, "\{err}")
      failed = true
    }
  }
  !failed && ctx.state.get(ASYNC_CHAIN_PASS_KEY) is Some(_)
}

///|
/// Run the application middleware chain, then any middleware attached to the
/// matched asynchronous route (such as the mounted application's middleware).
/// Both chains were composed when the application or route was built. Returns
/// `true` when both chains called through.
fn App::run_async_middleware(
  self : App,
  ctx : Context,
  route_chain : Handler,
) -> Bool {
  if !run_async_middleware_chain(self.async_middleware_chain(), ctx) {
    return false
  }
  run_async_middleware_chain(route_chain, ctx)
}

///|
/// Whether a response header must not be carried into a streaming response,
/// because the runtime computes it from the chunked body instead.
fn is_stream_reserved_header(name : String) -> Bool {
  name.view().equal_ignore_ascii_case("content-length".view()) ||
  name.view().equal_ignore_ascii_case("transfer-encoding".view()) ||
  name.view().equal_ignore_ascii_case("connection".view())
}

///|
/// Copy the headers a middleware chain accumulated into a map suitable for a
/// `Stream`, dropping the framing headers the runtime owns.
fn stream_seed_headers(response : Response) -> Map[String, String] {
  let headers : Map[String, String] = Map(
    [],
    capacity=response.headers.length(),
  )
  for name, value in response.headers {
    if !is_stream_reserved_header(name) &&
      !name.view().equal_ignore_ascii_case("content-encoding".view()) &&
      !name.view().equal_ignore_ascii_case("content-range".view()) {
      headers.set(name, value)
    }
  }
  headers
}

///|
/// Whether an `Expect` field only names the one expectation this server
/// implements. Empty list entries are ignored, so a trailing comma does not
/// turn a valid `100-continue` into an unsupported expectation.
fn expectation_supported(value : StringView) -> Bool {
  for part in value.split(",") {
    let token = trim_ascii_space(part)
    if !token.is_empty() &&
      !token.equal_ignore_ascii_case("100-continue".view()) {
      return false
    }
  }
  true
}

///|
/// Whether an `Expect` field asks for the interim `100 Continue` response.
fn expects_continue(value : StringView) -> Bool {
  for part in value.split(",") {
    if trim_ascii_space(part).equal_ignore_ascii_case(
        "100-continue".view(),
      ) {
      return true
    }
  }
  false
}

///|
/// Answer an `Expect: 100-continue` handshake with the interim `100 Continue`
/// response (RFC 9110 §10.1.1), so clients that wait for it before uploading
/// a body are not left blocked until they time out. The final response is sent
/// as usual once the body has been read.
async fn send_continue_if_expected(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  match request.headers.get(header_expect) {
    Some(value) =>
      if expects_continue(value.view()) {
        conn.send_response(100, "Continue") catch {
          _ => ()
        }
        conn.end_response() catch {
          _ => ()
        }
      }
    None => ()
  }
}

///|
/// Whether a comma-separated field value contains `token` as a complete,
/// literal entry. Unlike `header_list_has_token`, `*` is not a wildcard here:
/// `Connection` lists concrete hop-by-hop options, so `Connection: *` does not
/// mean `close`.
fn header_list_has_exact_token(list : StringView, token : StringView) -> Bool {
  let length = list.length()
  let mut start = 0
  let mut i = 0
  while i <= length {
    if i == length || list.unsafe_get(i) == (',' : UInt16) {
      let entry = trim_ascii_space(list[start:i])
      if entry.equal_ignore_ascii_case(token) {
        return true
      }
      start = i + 1
    }
    i = i + 1
  }
  false
}

///|
/// Whether the request's `Connection` header asks for the connection to close
/// after this response. The runtime owns the connection loop, so the framework
/// closes the socket itself to make `Connection: close` effective.
fn request_wants_close(request : @http.Request) -> Bool {
  match request.headers.get(header_connection) {
    Some(value) =>
      header_list_has_exact_token(value.view(), "close".view())
    None => false
  }
}

///|
fn append_trailing_slash(path : String) -> String {
  // Insert the slash into the path component, before the first `?` or `#`.
  // The fragment delimiter may come first, in which case a `?` inside it is
  // part of the fragment and must not decide where the slash goes.
  let (head, tail) = match path_head_end(path) {
    Some(index) => (path[:index], path[index:])
    None => (path, "")
  }
  // A location that starts with `//` is a scheme-relative URL, so a request
  // target with duplicate leading slashes must not be echoed verbatim: a
  // browser would interpret the redirect as a different host. Collapse the
  // leading slashes to the origin-relative single slash the static lookup
  // already used.
  let view = head.view()
  let length = view.length()
  let mut first = 0
  while first < length && view.unsafe_get(first) == ('/' : UInt16) {
    first = first + 1
  }
  let normalized : String = if first == 0 {
    if length == 0 {
      ""
    } else {
      // A location is always origin-relative here. Prefixing the slash also
      // keeps an absolute-form request target (`GET http://host/path`) from
      // turning into an absolute redirect to that host.
      "/" + head.to_owned()
    }
  } else if first == length {
    "/"
  } else {
    "/" + view[first:].to_owned()
  }
  if normalized.has_suffix("/") {
    normalized + tail.to_owned()
  } else {
    normalized + "/" + tail.to_owned()
  }
}

///|
/// Read buffers used by `write_file_range`. The async runtime is single
/// threaded, so a plain array is safe.
let file_range_buffers : Array[FixedArray[Byte]] = []

///|
/// Maximum number of range buffers retained.
const FILE_RANGE_POOL_LIMIT : Int32 = 4

///|
/// Size of the range buffers.
const FILE_RANGE_CHUNK_SIZE : Int32 = 65536

///|
fn acquire_file_range_buffer() -> FixedArray[Byte] {
  match file_range_buffers.pop() {
    Some(buffer) => buffer
    None => FixedArray::make(FILE_RANGE_CHUNK_SIZE, b'\x00')
  }
}

///|
fn release_file_range_buffer(buffer : FixedArray[Byte]) -> Unit {
  if file_range_buffers.length() < FILE_RANGE_POOL_LIMIT {
    file_range_buffers.push(buffer)
  }
}

///|
async fn write_file_range(
  conn : @http.ServerConnection,
  file : @fs.File,
  start : Int64,
  length : Int64,
) -> Unit {
  if length <= 0L {
    return
  }
  let chunk_size : Int32 = if length < FILE_RANGE_CHUNK_SIZE.to_int64() {
    length.to_int()
  } else {
    65536
  }
  let buffer = acquire_file_range_buffer()
  defer release_file_range_buffer(buffer)
  let mut remaining = length
  let mut position = start
  while remaining > 0 {
    let want : Int32 = if remaining < chunk_size.to_int64() {
      remaining.to_int()
    } else {
      chunk_size
    }
    let read = file.read_at(buffer, position~, len=want) catch { _ => 0 }
    if read <= 0 {
      break
    }
    conn.write(buffer.unsafe_reinterpret_as_bytes()[:read])
    remaining = remaining - read.to_int64()
    position = position + read.to_int64()
  }
}

///|
/// Read an entire regular file into memory. Returns `None` for a file too large
/// to address as a single MoonBit `Bytes` or when a read fails.
async fn read_file_bytes(file : @fs.File, size : Int64) -> Bytes? {
  if size < 0L || size > 2147483647L {
    return None
  }
  let length = size.to_int()
  if length == 0 {
    return Some(b"")
  }
  let buffer = FixedArray::make(length, b'\x00')
  let mut offset = 0
  while offset < length {
    let read = file.read_at(
      buffer,
      position=offset.to_int64(),
      len=length - offset,
    ) catch {
      _ => return None
    }
    if read <= 0 {
      return None
    }
    offset = offset + read
  }
  Some(buffer.unsafe_reinterpret_as_bytes())
}

///|
/// Write `length` bytes starting at `start` from an in-memory representation.
async fn write_bytes_range(
  conn : @http.ServerConnection,
  data : Bytes,
  start : Int64,
  length : Int64,
) -> Unit {
  if length <= 0L {
    return
  }
  let first = start.to_int()
  let count = length.to_int()
  conn.write(data[first:first + count])
}

///|
/// Open the `gzip` sibling of `file_path`, if it exists and is a regular file.
async fn open_precompressed_gzip(file_path : String) -> @fs.File? {
  let handle = Some(@fs.open(file_path + ".gz", mode=@fs.ReadOnly)) catch {
    _ => None
  }
  match handle {
    Some(handle) =>
      if handle.kind() is @fs.Directory {
        handle.close()
        None
      } else {
        Some(handle)
      }
    None => None
  }
}

///|
/// Append `value` to the `Vary` header without duplicating an existing entry.
fn add_vary_header(headers : @http.Headers, value : String) -> Unit {
  match headers.get(header_vary) {
    Some(existing) =>
      if trim_ascii_space(existing.view()).is_empty() {
        headers.set(header_vary, value)
      } else if !header_list_has_token(existing.view(), value.view()) {
        headers.set(header_vary, existing + ", " + value)
      }
    None => headers.set(header_vary, value)
  }
}

///|
/// Drop representation metadata for a status that cannot carry a body. A `304`
/// keeps its validators and coding because they describe the selected
/// representation, but `1xx`, `204` and `205` have no representation at all.
fn clear_bodyless_representation_headers(
  headers : @http.Headers,
  keep_validators~ : Bool = false,
) -> Unit {
  if !keep_validators {
    headers.remove(header_etag)
    headers.remove(header_last_modified)
    headers.remove(header_content_encoding)
  }
  headers.remove(header_content_type)
  headers.remove(header_content_disposition)
  headers.remove(header_content_range)
}

///|
/// Build the outgoing headers for a static response, seeding them with the
/// headers a request context accumulated. A `Set-Cookie` entry is dropped when
/// the response carries cookies, which are sent separately.
fn static_base_headers(
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  capacity : Int32,
) -> @http.Headers {
  let headers : @http.Headers = Map(
    [],
    capacity=extra_headers.length() + capacity,
  )
  for name, value in extra_headers {
    // Framing headers are recomputed for whatever this response turns out to
    // be; a middleware's body length must not leak into 304/416/redirects.
    if is_stream_reserved_header(name) {
      continue
    }
    // The static file, range and encoding are chosen here, so representation
    // metadata prepared for a different body must not leak in either.
    if name.view().equal_ignore_ascii_case("content-encoding".view()) ||
      name.view().equal_ignore_ascii_case("content-range".view()) {
      continue
    }
    if cookies.length() > 0 &&
      name.view().equal_ignore_ascii_case("set-cookie".view()) {
      continue
    }
    headers.set(header_key(name), value)
  }
  headers
}

///|
/// Headers for a static directory redirect. A redirect has no representation,
/// so a content type prepared for a file body must not leak into it.
fn static_redirect_headers(
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  location : String,
) -> @http.Headers {
  let headers = static_base_headers(extra_headers, cookies, 1)
  headers.remove(header_content_type)
  headers.remove(header_etag)
  headers.remove(header_last_modified)
  headers.remove(header_content_disposition)
  // A redirect has no body, so its length is always zero. Set it explicitly
  // instead of relying on the runtime's automatic framing: the runtime emits
  // that zero length for GET but suppresses it for HEAD, which would make a
  // HEAD redirect disagree with the matching GET.
  headers.set(header_content_length, "0")
  headers.set(header_location, location)
  headers
}

///|
async fn send_static_redirect(
  conn : @http.ServerConnection,
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  location : String,
  vary_encoding~ : Bool = false,
) -> Unit {
  let headers = static_redirect_headers(extra_headers, cookies, location)
  if vary_encoding {
    // A directory index that exists only as a precompressed sibling makes the
    // redirect itself depend on `Accept-Encoding`, matching the 404/200/304
    // variants caches may store for the same target.
    add_vary_header(headers, "Accept-Encoding")
  }
  send_with_date(
    conn,
    301,
    "Moved Permanently",
    headers,
    cookies~,
  )
  conn.end_response()
}

///|
/// Add a response header only when the response does not already carry one,
/// so middleware-supplied representation headers survive static file serving
/// just as handler-supplied values survive `send_file_response`.
fn set_header_if_absent(
  headers : @http.Headers,
  name : @http.CaseInsensitiveString,
  value : String,
) -> Unit {
  if !headers.contains(name) {
    headers.set(name, value)
  }
}

///|
/// Send a plain-text error response for a static request, carrying the request
/// context's headers and cookies.
async fn send_static_error(
  conn : @http.ServerConnection,
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  head : Bool,
  code : Int32,
  body : String,
  precompressed : Bool,
  vary_encoding~ : Bool = false,
) -> Unit {
  let bytes = encode_utf8_lossy(body.view())
  let headers = static_base_headers(extra_headers, cookies, 2)
  // The error body is plain text, not the representation a middleware may have
  // prepared for a file response.
  headers.remove(header_content_encoding)
  headers.remove(header_content_range)
  // Validators supplied for the file must not describe the error body, or a
  // cache could reuse a 404/406/412 for a different representation.
  headers.remove(header_etag)
  headers.remove(header_last_modified)
  headers.remove(header_content_disposition)
  if precompressed || vary_encoding {
    // Whether this path resolves to a file depends on `Accept-Encoding`, so
    // caches must not reuse an identity error for a gzip-capable client.
    add_vary_header(headers, "Accept-Encoding")
  }
  headers.set(header_content_type, "text/plain; charset=utf-8")
  headers.set(header_content_length, bytes.length().to_string())
  send_with_date(conn, code, status_text(code), headers, cookies~)
  if !head {
    conn.write(bytes)
  }
  conn.end_response()
}

///|
/// Add the negotiation headers a static file response needs. `vary_encoding`
/// is set whenever the selected representation depends on `Accept-Encoding`,
/// including an on-the-fly gzip encoding from `App::compress`.
fn decorate_static_headers(
  headers : @http.Headers,
  vary_encoding : Bool,
  serving_gzip : Bool,
) -> Unit {
  if vary_encoding {
    add_vary_header(headers, "Accept-Encoding")
  }
  if serving_gzip {
    headers.set(header_content_encoding, "gzip")
  }
}

///|
/// Report whether `path` currently names a directory. A failed open is not a
/// directory, so the static handler can still produce the usual 404.
async fn static_target_is_directory(path : String) -> Bool {
  let file = @fs.open(path, mode=@fs.ReadOnly) catch { _ => return false }
  defer file.close()
  file.kind() is @fs.Directory
}

///|
/// Report whether `path` currently names a regular file. A failed open or a
/// directory is not a file, which lets directory redirects wait until the
/// configured index actually exists.
async fn static_target_is_regular_file(path : String) -> Bool {
  let file = @fs.open(path, mode=@fs.ReadOnly) catch { _ => return false }
  defer file.close()
  file.kind() is @fs.Regular
}

///|
/// Whether the configured directory index exists in any representation the
/// client can receive. A precompressed-only `index.html.gz` must still trigger
/// the canonical trailing-slash redirect for directory requests.
async fn static_index_available(
  directory : String,
  index : String,
  precompressed : Bool,
  accept_encoding : String?,
) -> Bool {
  if index == "" {
    return false
  }
  let index_path = join_fs_path(directory, index)
  if static_target_is_regular_file(index_path) {
    return true
  }
  if !precompressed {
    return false
  }
  // A request without `Accept-Encoding` accepts any content coding
  // (RFC 9110 §12.5.3), so a precompressed-only index is still a usable
  // representation when identity is absent.
  let accepts_gzip = match accept_encoding {
    Some(value) => accept_encoding_accepts_gzip(value)
    None => true
  }
  accepts_gzip && static_target_is_regular_file(index_path + ".gz")
}

///|
/// Serve a static file, seeding every response with the headers and cookies a
/// request context accumulated (middleware and handler output), so static
/// responses carry the same security, CORS and session headers as dynamic
/// ones.
async fn serve_static_file(
  conn : @http.ServerConnection,
  file_path : String,
  head : Bool,
  request : @http.Request,
  cache_control : String,
  precompressed : Bool,
  redirect_directories : Bool,
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  response_started~ : Ref[Bool],
  index~ : String = "",
  redirect_root~ : Bool = false,
  auto_etag~ : Bool = true,
  compress_enabled~ : Bool = false,
  compress_min_size~ : Int32 = 1024,
  status_out? : Ref[Int32],
) -> Unit {
  // From here on every path writes a response header. Record that before the
  // first await so a timeout racing with file lookup or streaming closes the
  // connection instead of attempting a second (invalid) response.
  response_started.val = true
  let record_status = fn(code : Int32) -> Unit {
    match status_out {
      Some(out) => out.val = code
      None => ()
    }
  }
  let accept_encoding = request.headers.get(header_accept_encoding)
  let refuses_identity = match accept_encoding {
    Some(value) => accept_encoding_refuses_identity(value)
    None => false
  }
  let mut gzip_handle : @fs.File? = None
  let base : @fs.File? = Some(@fs.open(file_path, mode=@fs.ReadOnly)) catch {
    _ => {
      // A mount may ship only the precompressed sibling of an asset, so probe
      // it before reporting the source file as missing.
      if precompressed {
        // Identity is unavailable here, so gzip only has to be acceptable.
        // A request without `Accept-Encoding` accepts every coding
        // (RFC 9110 §12.5.3), which lets a gzip-only asset be served instead
        // of reporting a spurious 404.
        let accepts_gzip = match accept_encoding {
          Some(value) => accept_encoding_accepts_gzip(value)
          None => true
        }
        if accepts_gzip {
          gzip_handle = open_precompressed_gzip(file_path)
        }
      }
      if gzip_handle is None {
        if refuses_identity {
          // A gzip-only asset still exists even when the client accepts no
          // coding for it, so distinguish that from a genuinely missing file.
          let sibling_exists = if precompressed {
            match open_precompressed_gzip(file_path) {
              Some(handle) => {
                handle.close()
                true
              }
              None => false
            }
          } else {
            false
          }
          if sibling_exists {
            record_status(406)
            send_static_error(
              conn,
              extra_headers,
              cookies,
              head,
              406,
              "406 Not Acceptable",
              precompressed,
              vary_encoding=true,
            )
          } else {
            record_status(404)
            send_static_error(
              conn, extra_headers, cookies, head, 404, "404 Not Found", precompressed,
            )
          }
        } else {
          record_status(404)
          send_static_error(
            conn, extra_headers, cookies, head, 404, "404 Not Found", precompressed,
          )
        }
        return
      }
      None
    }
  }
  match base {
    Some(handle) =>
      if handle.kind() is @fs.Directory {
        handle.close()
        // Only redirect to the canonical directory URL once the configured
        // index exists, so a missing index reports 404 directly instead of
        // redirecting to another 404.
        if !redirect_directories ||
          !static_index_available(
            file_path, index, precompressed, accept_encoding,
          ) {
          // The directory exists but its identity index does not. When only a
          // precompressed index is available and the client refuses every
          // coding the server can produce, report 406 just like the canonical
          // trailing-slash URL does instead of claiming the directory is gone.
          let precompressed_index_exists = precompressed &&
            index != "" &&
            static_target_is_regular_file(
              join_fs_path(file_path, index) + ".gz",
            )
          if precompressed_index_exists && refuses_identity {
            record_status(406)
            send_static_error(
              conn,
              extra_headers,
              cookies,
              head,
              406,
              "406 Not Acceptable",
              precompressed,
              vary_encoding=true,
            )
          } else {
            record_status(404)
            send_static_error(
              conn, extra_headers, cookies, head, 404, "404 Not Found", precompressed,
            )
          }
          return
        }
        let location = append_trailing_slash(request.path)
        // The redirect target may already be the requested path when the
        // resolved index is itself a directory (for example a directory named
        // `index.html`). Redirecting there would loop forever, so report the
        // missing file instead.
        if location == request.path {
          record_status(404)
          send_static_error(
            conn,
            extra_headers,
            cookies,
            head,
            404,
            "404 Not Found",
            precompressed,
          )
          return
        }
        record_status(301)
        send_static_redirect(
          conn, extra_headers, cookies, location, vary_encoding=precompressed,
        )
        return
      }
    None => ()
  }
  if redirect_root {
    // The mount root (`/assets`) is a directory request too: redirect it to
    // the canonical `/assets/` spelling before serving its index. Doing this
    // after opening the file keeps a missing index a 404 rather than a
    // redirect to another 404.
    let location = append_trailing_slash(request.path)
    if location != request.path {
      // The file was only opened to prove that the index exists; the redirect
      // itself serves no bytes, so release both probe handles before
      // returning instead of leaving them open for the life of the process.
      match base {
        Some(handle) => handle.close()
        None => ()
      }
      match gzip_handle {
        Some(handle) => handle.close()
        None => ()
      }
      record_status(301)
      send_static_redirect(
        conn, extra_headers, cookies, location, vary_encoding=precompressed,
      )
      return
    }
  }
  if precompressed && gzip_handle is None {
    match base {
      Some(_) =>
        match accept_encoding {
          Some(value) =>
            if accept_encoding_allows_gzip_cached(value) {
              // The probe always runs: a `.gz` sibling may appear (or vanish)
              // while the server is running, so a remembered miss would keep
              // serving the identity representation even after a deploy added
              // the precompressed file.
              gzip_handle = open_precompressed_gzip(file_path)
            }
          None => ()
        }
      None => ()
    }
  }
  let serving_gzip = gzip_handle is Some(_)
  let file = match gzip_handle {
    Some(handle) => {
      match base {
        Some(base_file) => base_file.close()
        None => ()
      }
      handle
    }
    None =>
      match base {
        Some(base_file) => base_file
        None => {
          record_status(404)
          send_static_error(
            conn, extra_headers, cookies, head, 404, "404 Not Found", precompressed,
          )
          return
        }
      }
  }
  defer file.close()
  let size = file.size() catch {
    _ => {
      record_status(500)
      send_static_error(
        conn, extra_headers, cookies, head, 500, "500 Internal Server Error", precompressed,
      )
      return
    }
  }
  let mtime = file.mtime() catch { _ => (0L, 0) }
  let (mtime_secs, mtime_nanos) = mtime
  let (etag, last_modified, content_type_value) = file_validators(
    file_path,
    size,
    mtime_secs,
    mtime_nanos,
    cache_key=file_path,
    gzip=serving_gzip,
  )
  // A precompressed sibling is already the negotiated representation. Without
  // one, `App::compress` can still gzip an eligible static file on the fly;
  // this keeps static responses subject to the same application-wide
  // compression setting as dynamic ones.
  let mut compressed_body : Bytes? = None
  let mut dynamic_gzip = false
  let effective_cache_control = match
    get_header_ignore_case(extra_headers, "Cache-Control") {
    Some(value) => value
    None => cache_control
  }
  let no_transform = cache_control_has_directive(
    effective_cache_control.view(),
    "no-transform".view(),
  )
  // Middleware may override the file's media type, and compression depends on
  // the representation's actual type, not the extension-derived default.
  let effective_content_type = match
    get_header_ignore_case(extra_headers, "Content-Type") {
    Some(value) => value
    None => content_type_value
  }
  let dynamic_eligible = !serving_gzip &&
    compress_enabled &&
    !no_transform &&
    content_type_is_compressible(effective_content_type.view())
  if dynamic_eligible {
    match accept_encoding {
      Some(value) =>
        if accept_encoding_allows_gzip_cached(value) &&
          (
            refuses_identity ||
            size >= (if compress_min_size > 0 {
              compress_min_size.to_int64()
            } else {
              0L
            })
          ) {
          match read_file_bytes(file, size) {
            Some(raw) => {
              let compressed : Bytes? = Some(gzip_compress(raw)) catch {
                _ => None
              }
              match compressed {
                Some(bytes) =>
                  // Like dynamic compression, keep the identity
                  // representation when gzip would not shrink it, unless the
                  // client explicitly refused identity.
                  if refuses_identity || bytes.length() < raw.length() {
                    compressed_body = Some(bytes)
                    dynamic_gzip = true
                  }
                None => ()
              }
            }
            None => ()
          }
        }
      None => ()
    }
  }
  let serving_selected_gzip = serving_gzip || dynamic_gzip
  if !serving_selected_gzip && refuses_identity {
    // There is no acceptable representation: no precompressed sibling, no
    // on-the-fly encoding, and the client explicitly rejected identity.
    record_status(406)
    send_static_error(
      conn,
      extra_headers,
      cookies,
      head,
      406,
      "406 Not Acceptable",
      precompressed,
      vary_encoding=true,
    )
    return
  }
  // `Vary` describes the representation-selection process, not just this
  // response. This URL can answer 406 when the client refuses identity, even
  // with application compression off and no precompressed sibling, so a shared
  // cache must not reuse a 200 across different `Accept-Encoding` values.
  let vary_encoding = true
  // A dynamic gzip representation is semantically equivalent to the source
  // file but has different bytes, so its generated validator must be weak.
  let generated_etag = if auto_etag {
    if dynamic_gzip { "W/" + etag } else { etag }
  } else {
    ""
  }
  // Capture the validator supplied by middleware before compression weakens
  // it, so a satisfied strong `If-Match` is not re-checked against `W/...`.
  let handler_etag = get_header_ignore_case(extra_headers, "ETag").unwrap_or(
    "",
  )
  // A gzipped body is only weakly equivalent to the source file when the
  // framework produced it by transforming that file. Weaken a middleware-
  // supplied strong validator in that case, matching the dynamic compression
  // stage, so it cannot be reused for the identity bytes. A precompressed
  // sibling also selects a different representation, so the same rule applies.
  if serving_selected_gzip {
    match get_header_ignore_case(extra_headers, "ETag") {
      Some(value) =>
        if !value.has_prefix("W/") {
          set_header_ignore_case(extra_headers, "ETag", "W/" + value)
        }
      None => ()
    }
  }
  let etag_key = header_etag
  let last_modified_key = header_last_modified
  let cache_control_key = header_cache_control
  // A middleware may override the validators the static file would otherwise
  // advertise. Preconditions must be evaluated against the values the response
  // actually carries, matching `send_file_response`.
  let effective_etag = match get_header_ignore_case(extra_headers, "ETag") {
    Some(value) => value
    None => generated_etag
  }
  let effective_mtime = match
    get_header_ignore_case(extra_headers, "Last-Modified") {
    Some(value) =>
      match parse_http_date_view(trim_ascii_space(value.view())) {
        Some(seconds) => seconds
        None => mtime_secs
      }
    None => mtime_secs
  }
  let (precondition_input, allows_not_modified) = precondition_input_http(
    request,
  )
  let remaining_preconditions = drop_satisfied_if_match(
    precondition_input, handler_etag,
  )
  match
    evaluate_preconditions_input(
      remaining_preconditions,
      effective_etag,
      Some(effective_mtime),
      allows_not_modified,
    ) {
    PreconditionFailed => {
      record_status(412)
      send_static_error(
        conn,
        extra_headers,
        cookies,
        head,
        412,
        "412 Precondition Failed",
        precompressed,
        vary_encoding=vary_encoding,
      )
      return
    }
    PreconditionNotModified => {
      record_status(304)
      let headers = static_base_headers(extra_headers, cookies, 2)
      // A 304 carries no body, so the framing and content type a middleware
      // seeded for a body response must not leak into it.
      headers.remove(header_content_type)
      headers.remove(header_content_length)
      headers.remove(header_content_disposition)
      if generated_etag != "" {
        set_header_if_absent(headers, etag_key, generated_etag)
      }
      set_header_if_absent(headers, last_modified_key, last_modified)
      if cache_control != "" {
        set_header_if_absent(headers, cache_control_key, cache_control)
      }
      decorate_static_headers(
        headers, vary_encoding, serving_selected_gzip,
      )
      send_with_date(conn, 304, "Not Modified", headers, cookies~)
      conn.end_response()
      return
    }
    PreconditionPass => ()
  }
  let representation_size = match compressed_body {
    Some(bytes) => bytes.length().to_int64()
    None => size
  }
  let range = if head {
    ByteRangeFull
  } else {
    match request.headers.get(header_range) {
      Some(value) =>
        if if_range_allows(request, effective_etag, effective_mtime) {
          parse_byte_range(value, representation_size)
        } else {
          ByteRangeFull
        }
      None => ByteRangeFull
    }
  }
  let content_type_key = header_content_type
  let content_length_key = header_content_length
  let content_range_key = header_content_range
  let accept_ranges_key = header_accept_ranges
  match range {
    ByteRangeInvalid => {
      record_status(416)
      let headers = static_base_headers(extra_headers, cookies, 2)
      headers.remove(content_type_key)
      headers.remove(header_content_disposition)
      // A 416 has no selected representation, so the file's validators must
      // not be attached to this empty error response.
      headers.remove(header_etag)
      headers.remove(header_last_modified)
      headers.set(
        content_range_key,
        "bytes */" + representation_size.to_string(),
      )
      headers.set(accept_ranges_key, "bytes")
      decorate_static_headers(headers, vary_encoding, false)
      send_with_date(conn, 416, "Range Not Satisfiable", headers, cookies~)
      conn.end_response()
    }
    ByteRangeSpec(start, end) => {
      record_status(206)
      let length = end - start + 1L
      let headers = static_base_headers(extra_headers, cookies, 6)
      set_header_if_absent(headers, content_type_key, content_type_value)
      headers.set(content_length_key, length.to_string())
      headers.set(
        content_range_key,
        "bytes " +
        start.to_string() +
        "-" +
        end.to_string() +
        "/" +
        representation_size.to_string(),
      )
      if generated_etag != "" {
        set_header_if_absent(headers, etag_key, generated_etag)
      }
      set_header_if_absent(headers, last_modified_key, last_modified)
      headers.set(accept_ranges_key, "bytes")
      if cache_control != "" {
        set_header_if_absent(headers, cache_control_key, cache_control)
      }
      decorate_static_headers(
        headers, vary_encoding, serving_selected_gzip,
      )
      send_with_date(conn, 206, "Partial Content", headers, cookies~)
      if !head {
        match compressed_body {
          Some(bytes) => write_bytes_range(conn, bytes, start, length)
          None => write_file_range(conn, file, start, length)
        }
      }
      conn.end_response()
    }
    ByteRangeFull => {
      record_status(200)
      let headers = static_base_headers(extra_headers, cookies, 5)
      set_header_if_absent(headers, content_type_key, content_type_value)
      headers.set(content_length_key, representation_size.to_string())
      if generated_etag != "" {
        set_header_if_absent(headers, etag_key, generated_etag)
      }
      set_header_if_absent(headers, last_modified_key, last_modified)
      headers.set(accept_ranges_key, "bytes")
      if cache_control != "" {
        set_header_if_absent(headers, cache_control_key, cache_control)
      }
      decorate_static_headers(
        headers, vary_encoding, serving_selected_gzip,
      )
      send_with_date(conn, 200, "OK", headers, cookies~)
      if !head {
        match compressed_body {
          Some(bytes) => write_bytes_range(conn, bytes, 0L, representation_size)
          None => write_file_range(conn, file, 0L, size)
        }
      }
      conn.end_response()
    }
  }
}

///|
/// Context state key the static middleware chain sets when the request falls
/// through to the file.
const STATIC_CHAIN_PASS_KEY : String = "__feather_static_pass"

///|
/// Extra budget for static requests before a very small request timeout fires,
/// so opening and statting the file cannot abort before the status line is
/// written. The body transfer itself remains subject to the configured
/// timeout.
const STATIC_TIMEOUT_HEADROOM : Int32 = 50

///|
/// How long a graceful shutdown keeps serving (answering `503`) after all
/// in-flight requests have finished, so idle kept-alive connections have a
/// chance to observe the drain before the server task is cancelled.
const GRACEFUL_DRAIN_SETTLE_MS : Int32 = 250

///|
/// Serve a static mount after running the application middleware chain.
///
/// The chain wraps the static lookup: middleware that short-circuits (for
/// example an authenticator) decides the response, while middleware that calls
/// through gets its response headers and cookies merged into the file response.
async fn handle_static(
  app : App,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
  file_path : String,
  cache_control : String,
  precompressed : Bool,
  mount : StaticMount,
  head : Bool,
  response_started~ : Ref[Bool],
) -> Unit {
  if app.middlewares.length() == 0 && mount.middlewares.length() == 0 {
    // The middleware-free fast path skips `request_from_http`, but the body
    // still has to be consumed under the application-wide limit: a static
    // request must not smuggle an unbounded body past `App::max_body_size`
    // just because no handler ever asks for it.
    let coding = match request.headers.get(header_content_encoding) {
      Some(value) => request_body_coding(value.view())
      None => RequestBodyIdentity
    }
    // Reject an unsupported coding before reading the body, exactly like the
    // dynamic path. Otherwise a chunked upload that exceeds the body limit on
    // a static URL would be reported as 413 instead of the 415 that names the
    // real problem, and the server would waste time reading a body it cannot
    // decode anyway.
    if coding is RequestBodyUnsupported {
      send_error_and_close(
        conn, 415, "415 Unsupported Media Type", head,
      )
      return
    }
    let read_limit = match coding {
      RequestBodyGzip => gzip_body_read_limit(app.max_body_size)
      _ => app.max_body_size
    }
    let raw_body = read_body_bytes(body, read_limit) catch {
      PayloadTooLarge => {
        send_error_and_close(conn, 413, "413 Payload Too Large", head)
        return
      }
      _ => {
        send_error_and_close(conn, 500, "500 Internal Server Error", head)
        return
      }
    }
    // The dynamic path decodes a single gzip pass before applying the limit to
    // the expanded bytes. The fast path must do the same, otherwise a small
    // compressed body could bypass `App::max_body_size` on a static URL.
    match coding {
      RequestBodyGzip => {
        ignore(
          decode_gzip_body(raw_body, app.max_body_size) catch {
            PayloadTooLarge => {
              send_error_and_close(conn, 413, "413 Payload Too Large", head)
              return
            }
            MalformedRequestBody => {
              send_simple(conn, 400, "400 Bad Request", head)
              return
            }
            _ => {
              send_error_and_close(
                conn, 500, "500 Internal Server Error", head,
              )
              return
            }
          },
        )
      }
      RequestBodyIdentity => ()
      RequestBodyUnsupported => ()
    }
    serve_static_file(
      conn,
      file_path,
      head,
      request,
      cache_control,
      precompressed,
      !mount.index.is_empty(),
      Map([]),
      [],
      response_started~,
      redirect_root=static_root_needs_slash(request.path, mount),
      index=mount.index,
      compress_enabled=app.compress_enabled,
      compress_min_size=app.compress_min_size,
    )
    return
  }
  let (req, raw_body) = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_error_and_close(conn, 413, "413 Payload Too Large", head)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", head)
      return
    }
    UnsupportedRequestBodyCoding => {
      send_error_and_close(conn, 415, "415 Unsupported Media Type", head)
      return
    }
    _ => {
      send_error_and_close(conn, 500, "500 Internal Server Error", head)
      return
    }
  }
  let ctx = app.context_for_request(req)
  defer ctx.run_cleanups()
  attach_raw_body(ctx, raw_body)
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  bind_static_mount_params(ctx, request.path, mount)
  let chain = if mount.middlewares.length() == 0 {
    match app.static_chain {
      Some(chain) => chain
      None => {
        let terminal : Handler = fn(ctx) {
          ctx.state.set(STATIC_CHAIN_PASS_KEY, "1")
        }
        let chain = apply_middleware(app.middlewares, terminal)
        app.static_chain = Some(chain)
        chain
      }
    }
  } else {
    match mount.chain {
      Some(chain) => chain
      None => {
        let terminal : Handler = fn(ctx) {
          ctx.state.set(STATIC_CHAIN_PASS_KEY, "1")
        }
        let chain = apply_middleware(
          app.middlewares,
          apply_middleware(mount.middlewares, terminal),
        )
        mount.chain = Some(chain)
        chain
      }
    }
  }
  let mut failed = false
  chain(ctx) catch {
    HttpError(status, message) => {
      error_response(ctx, status, message)
      failed = true
    }
    HttpErrorPayload(status, message, payload) => {
      error_response_with_payload(ctx, status, message, payload)
      failed = true
    }
    HttpProblem(status, type_name, title, detail, instance) => {
      problem_response(ctx, status, type_name, title, detail, instance)
      failed = true
    }
    err => {
      internal_error(ctx, "\{err}")
      failed = true
    }
  }
  if !failed && ctx.state.get(STATIC_CHAIN_PASS_KEY) is Some(_) {
    let (compress, min_size) = compression_settings(app, ctx)
    let static_status = Ref(200)
    serve_static_file(
      conn,
      file_path,
      head,
      request,
      cache_control,
      precompressed,
      !mount.index.is_empty(),
      ctx.response.headers,
      ctx.response.cookies,
      response_started~,
      redirect_root=static_root_needs_slash(request.path, mount),
      index=mount.index,
      auto_etag=response_file_etag_enabled(ctx),
      compress_enabled=compress,
      compress_min_size=min_size,
      status_out=static_status,
    )
    // The file was written directly to the connection. Record the status on
    // the context so loggers and request cleanups see the response that was
    // actually sent rather than the default 200 from before file lookup.
    ctx.response.status = static_status.val
  } else {
    // The middleware chain produced a complete response (or an error), and the
    // branch below writes it under the request timeout. Mark the response as
    // started before the first write so a late timeout closes the connection
    // instead of trying to send a second response on it.
    response_started.val = true
    match ctx.file_response() {
      Some(file) => {
        let (compress, min_size) = compression_settings(app, ctx)
        send_file_response(
          conn,
          ctx.response,
          file,
          head,
          request,
          auto_etag=response_file_etag_enabled(ctx),
          compress_enabled=compress,
          compress_min_size=min_size,
        )
      }
      None => {
        let (input, allows_not_modified) = precondition_input_http(request)
        let (failed, remaining) = precheck_preconditions(
          input,
          allows_not_modified,
          ctx.response,
        )
        if !failed {
          let accept_encoding = accept_encoding_of(request)
          if !negotiate_existing_encoding(accept_encoding, ctx.response) {
            let (compress, min_size) = compression_settings(app, ctx)
            if compress {
              compress_response(accept_encoding, ctx.response, min_size)
            } else {
              reject_unacceptable_identity(accept_encoding, ctx.response)
            }
          }
          if response_etag_enabled(app, ctx) {
            apply_etag(ctx.response)
          }
          apply_preconditions_input(
            remaining,
            allows_not_modified,
            ctx.response,
          )
        }
        apply_buffered_range_http(request, ctx.response, head)
        send_response(conn, ctx.response, head)
      }
    }
  }
}

