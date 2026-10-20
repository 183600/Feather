///|
/// A handle for writing a chunked response body from a handler registered with
/// `App::stream`.
///
/// Unlike ordinary handlers, which build a complete `Response` before the
/// server sends it, a streaming handler runs while the response is being
/// written, so it can push data to the client incrementally (progress
/// reporting, generated downloads, proxying, ...). Headers are configured with
/// `set_status` / `set_header` before the first write; the first write (or
/// `close`) sends them. Because no `Content-Length` is known up front, the body
/// uses HTTP/1.1 chunked transfer encoding.
pub struct Stream {
  conn : @http.ServerConnection
  mut closed : Bool
  mut started : Bool
  mut status : Int32
  headers : Map[String, String]
  priv cookies : Array[@http.Cookie]
}

///|
fn Stream::new(
  conn : @http.ServerConnection,
  status~ : Int32 = 200,
  headers~ : Map[String, String] = Map([]),
  cookies~ : Array[@http.Cookie] = [],
) -> Stream {
  {
    conn,
    closed: false,
    started: false,
    status,
    headers,
    cookies,
  }
}

///|
/// Whether the stream has been closed, either by `Stream::close` or because the
/// handler returned.
pub fn Stream::is_closed(self : Stream) -> Bool {
  self.closed
}

///|
/// Whether the response header has already been sent. Once the stream has
/// started, `set_status` and `set_header` no longer affect the response.
pub fn Stream::is_started(self : Stream) -> Bool {
  self.started
}

///|
/// Set the status code of the response. Ignored after the header was sent.
pub fn Stream::set_status(self : Stream, status : Int32) -> Unit {
  if !self.started {
    self.status = status
  }
}

///|
/// Set a response header. Ignored after the header was sent. The
/// `Content-Type` defaults to `text/plain; charset=utf-8` when none is set.
pub fn Stream::set_header(
  self : Stream,
  name : String,
  value : String,
) -> Unit {
  if !self.started {
    set_header_ignore_case(self.headers, name, value)
  }
}

///|
/// Send the response header. Called implicitly by the first write or by
/// `Stream::close`, so an empty stream still produces a valid response.
async fn Stream::start(self : Stream) -> Unit {
  if self.started {
    return
  }
  self.started = true
  let headers : @http.Headers = Map([], capacity=self.headers.length() + 1)
  for name, value in self.headers {
    if !is_stream_reserved_header(name) {
      headers.set(header_key(name), value)
    }
  }
  if !headers.contains(header_content_type) {
    headers.set(header_content_type, "text/plain; charset=utf-8")
  }
  if self.cookies.length() > 0 {
    headers.remove(header_set_cookie)
  }
  send_with_date(
    self.conn,
    self.status,
    status_text(self.status),
    headers,
    cookies=self.cookies,
  )
}

///|
/// Write a text chunk to the response body, sending the header first. The
/// chunk is flushed immediately so clients observe data as it is produced.
/// Writing after `close` is a no-op.
pub async fn Stream::write(self : Stream, data : String) -> Unit {
  self.write_bytes(@utf8.encode(data))
}

///|
/// Write a byte chunk to the response body, sending the header first. Field
/// arguments behave exactly as in `Stream::write`.
pub async fn Stream::write_bytes(self : Stream, data : Bytes) -> Unit {
  if self.closed || data.length() == 0 {
    return
  }
  self.start()
  self.conn.write(data)
  self.conn.flush()
}

///|
/// Write the remaining contents of `reader` to the response body, sending the
/// header first. This streams large files or generated payloads, and otherwise
/// behaves like `Stream::write_bytes`: writing after `close` is a no-op.
pub async fn Stream::write_reader(self : Stream, reader : &@io.Reader) -> Unit {
  if self.closed {
    return
  }
  self.start()
  self.conn.write_reader(reader)
  self.conn.flush()
}

///|
/// Write one compact JSON-encoded value to the response body, which is
/// convenient for streaming APIs that emit a sequence of JSON documents.
pub async fn[T : @json.ToJson] Stream::write_json(
  self : Stream,
  value : T,
) -> Unit {
  self.write(@json.to_json(value).stringify())
}

///|
/// Flush body bytes buffered by the runtime to the client. Writes are already
/// flushed, so this is only needed around raw connection output.
pub async fn Stream::flush(self : Stream) -> Unit {
  if !self.closed {
    self.conn.flush()
  }
}

///|
/// Abandon the stream before its header was sent, so the caller can answer with
/// an error response instead. Once the header was sent the bytes are already on
/// the wire; `abort` then just marks the stream closed.
fn Stream::abort(self : Stream) -> Unit {
  self.closed = true
  self.started = true
}

///|
/// Finish the response. The header is sent first when nothing was written, so
/// an empty stream still yields a valid `200 OK`. Calling `close` more than
/// once, or after the handler already returned, is a no-op.
pub async fn Stream::close(self : Stream) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.start()
  self.conn.flush()
  self.conn.end_response()
}
