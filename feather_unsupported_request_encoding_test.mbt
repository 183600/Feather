///|
async test "unsupported request content codings are rejected with 415" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    ctx.text(200, "handler:" + ctx.request.body)
  })
  with_server(app, client => {
    let response = client.post(
      "/echo",
      "not-brotli",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Content-Encoding"), "br"),
      ]),
    )
    assert_eq(response.code, 415)
    assert_eq(client.read_all().text(), "415 Unsupported Media Type")
  })
}

///|
async test "repeated gzip request codings are rejected with 415" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_server(app, client => {
    let response = client.post(
      "/echo",
      gzip_bytes("H4sIAAAAAAACA8tLzE21TUtNLMlILQIAbKbcFwwAAAA="),
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Encoding"),
          "gzip, gzip",
        ),
      ]),
    )
    assert_eq(response.code, 415)
    assert_eq(client.read_all().text(), "415 Unsupported Media Type")
  })
}

///|
async test "identity may accompany a gzip request coding" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_server(app, client => {
    let response = client.post(
      "/echo",
      gzip_bytes("H4sIAAAAAAACA8tLzE21TUtNLMlILQIAbKbcFwwAAAA="),
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Encoding"),
          "identity, gzip",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "name=feather")
  })
}

///|
async test "identity request coding leaves the body untouched" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_server(app, client => {
    let response = client.post(
      "/echo",
      "plain",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Content-Encoding"), "identity"),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "plain")
  })
}

///|
async test "static fast paths reject unsupported request codings too" {
  let dir = @fs.tmpdir(prefix="feather-static-body-coding")
  @fs.write_file(dir + "/asset.txt", "asset")
  let app = @feather.App::new().static_files("/assets", dir)
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /assets/asset.txt HTTP/1.1\r\nHost: test\r\nContent-Encoding: deflate\r\nContent-Length: 10\r\nConnection: close\r\n\r\ncompressed",
      ),
    )
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 415"), msg=head)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "streaming endpoints reject unsupported request codings" {
  let app = @feather.App::new().stream("/stream", async fn(_ctx, out) {
    out.write("unexpected")
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /stream HTTP/1.1\r\nHost: test\r\nContent-Encoding: compress\r\nContent-Length: 4\r\nConnection: close\r\n\r\nbody",
      ),
    )
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 415"), msg=head)
  })
}
