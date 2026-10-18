///|
/// A handle for writing a single server-sent events stream.
///
/// An `Sse` is passed to handlers registered with `App::sse` after the
/// `200 OK` response header has been sent. Each `send` writes one event
/// (`event:` / `id:` / `retry:` / `data:` fields followed by a blank line)
/// and flushes it immediately, so clients receive events as they happen.
/// `comment` writes a keep-alive comment line, which is also useful for
/// dispatching periodic heartbeats through proxies.
pub struct Sse {
  conn : @http.ServerConnection
  mut closed : Bool
}

///|
fn Sse::new(conn : @http.ServerConnection) -> Sse {
  { conn, closed: false, }
}

///|
/// Whether the stream has been closed by `Sse::close` or the handler returned.
pub fn Sse::is_closed(self : Sse) -> Bool {
  self.closed
}

///|
/// Write the `data` field lines for one event, splitting the payload on line
/// breaks so multi-line data keeps its shape for SSE clients.
fn write_sse_data(builder : StringBuilder, data : String) -> Unit {
  let view = data.view()
  let length = view.length()
  if length == 0 {
    builder.write_string("data: \n")
    return
  }
  let mut start = 0
  let mut i = 0
  while i < length {
    let code = view.unsafe_get(i)
    if code == ('\n' : UInt16) || code == ('\r' : UInt16) {
      builder.write_string("data: ")
      builder.write_stringview(view[start:i])
      builder.write_char('\n')
      if code == ('\r' : UInt16) &&
        i + 1 < length &&
        view.unsafe_get(i + 1) == ('\n' : UInt16) {
        i = i + 1
      }
      start = i + 1
    }
    i = i + 1
  }
  if start < length {
    builder.write_string("data: ")
    builder.write_stringview(view[start:])
    builder.write_char('\n')
  }
}

///|
/// Strip carriage returns and line feeds from a single-line SSE field so a
/// caller-supplied value cannot inject extra fields or forge a whole event.
fn sanitize_sse_field(value : String) -> String {
  let view = value.view()
  let length = view.length()
  let mut i = 0
  let mut needs_clean = false
  while i < length {
    let code = view.unsafe_get(i)
    if code == ('\n' : UInt16) || code == ('\r' : UInt16) {
      needs_clean = true
      break
    }
    i = i + 1
  }
  if !needs_clean {
    return value
  }
  let builder = StringBuilder(size_hint=length)
  let mut index = 0
  while index < length {
    let code = view.unsafe_get(index)
    if code != ('\n' : UInt16) && code != ('\r' : UInt16) {
      builder.write_char(code.unsafe_to_char())
    }
    index = index + 1
  }
  builder.to_string()
}

///|
/// Send one event. `event` names the event type (clients listen with
/// `addEventListener`), `id` sets the last event id used for reconnection
/// (`Last-Event-ID`), and `retry` is the reconnection delay in milliseconds.
/// Sending after `close` is a no-op, so handlers can stop cleanly.
pub async fn Sse::send(
  self : Sse,
  data : String,
  event? : String,
  id? : String,
  retry? : Int32,
) -> Unit {
  if self.closed {
    return
  }
  let builder = StringBuilder(size_hint=data.length() + 32)
  match event {
    Some(name) => {
      let clean = sanitize_sse_field(name)
      if clean != "" {
        builder.write_string("event: ")
        builder.write_string(clean)
        builder.write_char('\n')
      }
    }
    None => ()
  }
  match id {
    Some(value) => {
      let clean = sanitize_sse_field(value)
      if clean != "" {
        builder.write_string("id: ")
        builder.write_string(clean)
        builder.write_char('\n')
      }
    }
    None => ()
  }
  match retry {
    Some(millis) =>
      if millis >= 0 {
        builder.write_string("retry: ")
        builder.write_string(millis.to_string())
        builder.write_char('\n')
      }
    None => ()
  }
  write_sse_data(builder, data)
  builder.write_char('\n')
  self.conn.write_string(builder.to_string())
  self.conn.flush()
}

///|
/// Send one event whose data is the JSON encoding of `value`, for streaming
/// typed payloads (`Sse::send_json(event="tick", value)`). Field arguments
/// behave exactly as in `Sse::send`.
pub async fn[T : @json.ToJson] Sse::send_json(
  self : Sse,
  value : T,
  event? : String,
  id? : String,
  retry? : Int32,
) -> Unit {
  self.send(@json.to_json(value).stringify(), event?, id?, retry?)
}

///|
/// Write a comment line (`: text`). Comments are ignored by clients and are
/// the usual way to keep an idle connection alive through proxies.
pub async fn Sse::comment(self : Sse, text : String) -> Unit {
  if self.closed {
    return
  }
  let builder = StringBuilder(size_hint=text.length() + 4)
  for line in text.view().split("\n") {
    let trimmed = trim_ascii_space(line)
    builder.write_char(':')
    if !trimmed.is_empty() {
      builder.write_char(' ')
      builder.write_stringview(trimmed)
    }
    builder.write_char('\n')
  }
  self.conn.write_string(builder.to_string())
  self.conn.flush()
}

///|
/// Finish the stream: flush pending events and end the response. Calling
/// `close` more than once, or after the handler already returned, is a no-op.
pub async fn Sse::close(self : Sse) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.conn.flush()
  self.conn.end_response()
}
