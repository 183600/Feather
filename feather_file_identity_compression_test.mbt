///|
async test "queued files replace an explicit identity coding when gzip is required" {
  let dir = @fs.tmpdir(prefix="feather-file-identity-coding")
  let payload = "queued file identity coding payload ".repeat(64)
  @fs.write_file(dir + "/report.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/download", fn(ctx) {
      ctx.file(200, dir + "/report.txt")
      ctx.set_header("Content-Encoding", "identity")
    })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([(accept_encoding_key, "gzip, identity;q=0")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), Some("gzip"))
    assert_eq(decode_gzip_body(client.read_all().binary()), @utf8.encode(payload))
  })
  @fs.rmdir(dir, recursive=true)
}
