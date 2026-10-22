///|
fn gzip_limit_payload() -> Bytes {
  let out = FixedArray::make(1000, b'\x00')
  let mut state = 17
  for i = 0; i < out.length(); i = i + 1 {
    state = state * 1664525 + 1013904223
    out[i] = ((state >> 16) & 255).to_byte()
  }
  out.unsafe_reinterpret_as_bytes()
}

///|
async fn write_gzip_request(
  conn : @socket.Tcp,
  method : String,
  path : String,
  compressed : Bytes,
) -> Unit {
  conn.write(
    @utf8.encode(
      method +
      " " +
      path +
      " HTTP/1.1\r\nHost: test\r\nContent-Encoding: gzip\r\nContent-Length: " +
      compressed.length().to_string() +
      "\r\nConnection: close\r\n\r\n",
    ),
  )
  conn.write(compressed)
}

///|
async test "dynamic gzip body limit applies to the decoded representation" {
  let payload = gzip_limit_payload()
  let compressed = gzip_encode_for_test(payload)
  // The compressed framing is slightly larger than this incompressible body,
  // which is exactly the case the body limit must not reject.
  assert_true(compressed.length() > payload.length())
  let app = @feather.App::new()
    .max_body_size(payload.length())
    .post("/echo", fn(ctx) {
      ctx.text(200, ctx.body_bytes().length().to_string())
    })
  with_raw_server(app, conn => {
    write_gzip_request(conn, "POST", "/echo", compressed)
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
  })
}

///|
async test "static gzip body limit applies to the decoded representation" {
  let payload = gzip_limit_payload()
  let compressed = gzip_encode_for_test(payload)
  assert_true(compressed.length() > payload.length())
  let dir = @fs.tmpdir(prefix="feather-gzip-decoded-limit")
  @fs.write_file(dir + "/hello.txt", "hello")
  let app = @feather.App::new()
    .max_body_size(payload.length())
    .static_files("/assets", dir)
  with_raw_server(app, conn => {
    write_gzip_request(conn, "GET", "/assets/hello.txt", compressed)
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
  })
  @fs.rmdir(dir, recursive=true)
}
