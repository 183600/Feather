///|
async fn raw_get_without_accept_encoding(
  conn : @socket.Tcp,
  path : String,
  accept_encoding? : String,
) -> (String, Bytes) {
  let accept = match accept_encoding {
    Some(value) => "Accept-Encoding: " + value + "\r\n"
    None => ""
  }
  conn.write(
    @utf8.encode(
      "GET " +
      path +
      " HTTP/1.1\r\nHost: test\r\n" +
      accept +
      "Connection: close\r\n\r\n",
    ),
  )
  let buffer = @buffer.Buffer::Buffer(size_hint=1024)
  let mut done = false
  while !done {
    match conn.read_some() {
      Some(chunk) => buffer.write_bytes(chunk)
      None => done = true
    }
  }
  let all = buffer.to_bytes()
  let mut split = all.length()
  let mut i = 0
  while i + 3 < all.length() {
    if all[i] == b'\r' &&
      all[i + 1] == b'\n' &&
      all[i + 2] == b'\r' &&
      all[i + 3] == b'\n' {
      split = i
      break
    }
    i = i + 1
  }
  let head = @utf8.decode_lossy(all[:split])
  let body : Bytes = if split < all.length() {
    all[split + 4:].to_owned()
  } else {
    b""
  }
  (head, body)
}

///|
async test "gzip-only static files are served when the request omits Accept-Encoding" {
  let dir = @fs.tmpdir(prefix="feather-gz-only-no-header")
  let plain = "only the compressed sibling exists without a header\n".repeat(32)
  let encoded = gzip_encode_for_test(@utf8.encode(plain))
  @fs.write_file(dir + "/app.js.gz", encoded)
  let app = @feather.App::new().static_files("/assets", dir, precompressed=true)
  with_raw_server(app, conn => {
    let (head, body) = raw_get_without_accept_encoding(conn, "/assets/app.js")
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
    assert_true(head.to_lower().contains("content-encoding: gzip"), msg=head)
    assert_true(head.to_lower().contains("vary: accept-encoding"), msg=head)
    let decoded = gunzip_for_test(body)
    assert_eq(@utf8.decode_lossy(decoded), plain)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "gzip-only directory indexes redirect when the request omits Accept-Encoding" {
  let dir = @fs.tmpdir(prefix="feather-gz-only-index-no-header")
  @fs.mkdir(dir + "/guide")
  let encoded = gzip_encode_for_test(@utf8.encode("compressed guide index\n"))
  @fs.write_file(dir + "/guide/index.html.gz", encoded)
  let app = @feather.App::new().static_files("/assets", dir, precompressed=true)
  with_raw_server(app, conn => {
    let (head, _body) = raw_get_without_accept_encoding(conn, "/assets/guide")
    assert_true(head.has_prefix("HTTP/1.1 301"), msg=head)
    assert_true(
      head.to_lower().contains("location: /assets/guide/"),
      msg=head,
    )
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "a gzip-only directory index reports 406 when identity is refused" {
  let dir = @fs.tmpdir(prefix="feather-gz-only-index-refused")
  @fs.mkdir(dir + "/guide")
  let encoded = gzip_encode_for_test(@utf8.encode("compressed guide index\n"))
  @fs.write_file(dir + "/guide/index.html.gz", encoded)
  let app = @feather.App::new().static_files("/assets", dir, precompressed=true)
  with_raw_server(app, conn => {
    let (head, _body) = raw_get_without_accept_encoding(
      conn,
      "/assets/guide",
      accept_encoding="identity;q=0",
    )
    assert_true(head.has_prefix("HTTP/1.1 406"), msg=head)
    assert_true(head.to_lower().contains("vary: accept-encoding"), msg=head)
  })
  @fs.rmdir(dir, recursive=true)
}
