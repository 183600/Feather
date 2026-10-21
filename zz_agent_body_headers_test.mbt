///|
fn zz_agent_stale_header_ctx() -> @feather.Context {
  let ctx = @feather.create_context()
  ctx.set_header("Content-Length", "999")
  ctx.set_header("Content-Encoding", "gzip")
  ctx.set_header("Content-Range", "bytes 0-1/2")
  ctx
}

///|
fn zz_agent_has_stale(ctx : @feather.Context) -> Bool {
  ctx.response.headers.get("Content-Length") is Some(_) ||
  ctx.response.headers.get("Content-Encoding") is Some(_) ||
  ctx.response.headers.get("Content-Range") is Some(_)
}

///|
test "zz agent dynamic text drops stale body headers" {
  let ctx = zz_agent_stale_header_ctx()
  ctx.text(200, "hello")
  assert_false(zz_agent_has_stale(ctx))
}

///|
test "zz agent dynamic html drops stale body headers" {
  let ctx = zz_agent_stale_header_ctx()
  ctx.html(200, "<p>hello</p>")
  assert_false(zz_agent_has_stale(ctx))
}

///|
test "zz agent dynamic json drops stale body headers" {
  let ctx = zz_agent_stale_header_ctx()
  ctx.json(200, Map([("ok", "1")]))
  assert_false(zz_agent_has_stale(ctx))
}

///|
test "zz agent dynamic bytes drops stale body headers" {
  let ctx = zz_agent_stale_header_ctx()
  ctx.bytes(200, b"\x01\x02")
  assert_false(zz_agent_has_stale(ctx))
}

///|
test "zz agent file drops stale body headers" {
  let ctx = zz_agent_stale_header_ctx()
  ctx.file(200, "/tmp/zz-agent.txt")
  assert_false(zz_agent_has_stale(ctx))
}

///|
async test "zz agent static 416 does not advertise a coding for empty body" {
  let dir = @fs.tmpdir(prefix="feather-416-encoding")
  @fs.write_file(dir + "/asset.txt", "0123456789")
  @fs.write_file(dir + "/asset.txt.gz", b"\x1f\x8b\x08\x00\x00\x00\x00\x00")
  let app = @feather.App::new().static_files("/", dir, precompressed=true)
  with_server(app, client => {
    let response = client.get(
      "/asset.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=99-"),
        (@http.CaseInsensitiveString("Accept-Encoding"), "gzip"),
      ]),
    )
    assert_eq(response.code, 416)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
