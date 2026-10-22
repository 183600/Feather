///|
async test "if-range accepts an epoch last-modified validator" {
  let range_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
    "Range",
  )
  let if_range_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
    "If-Range",
  )
  let dir = @fs.tmpdir(prefix="feather-if-range-epoch")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new().get("/download", fn(ctx) {
    ctx.set_header("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT")
    ctx.file(200, dir + "/digits.txt")
  })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([
        (range_key, "bytes=0-1"),
        (if_range_key, "Thu, 01 Jan 1970 00:00:00 GMT"),
      ]),
    )
    assert_eq(response.code, 206)
    assert_eq(client.read_all().text(), "01")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "static if-range accepts an epoch last-modified validator" {
  let range_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
    "Range",
  )
  let if_range_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
    "If-Range",
  )
  let dir = @fs.tmpdir(prefix="feather-static-if-range-epoch")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new().static_files_with(
    "/assets",
    dir,
    [
      fn(next) {
        fn(ctx) {
          ctx.set_header("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT")
          next(ctx)
        }
      },
    ],
  )
  with_server(app, client => {
    let response = client.get(
      "/assets/digits.txt",
      extra_headers=Map([
        (range_key, "bytes=0-1"),
        (if_range_key, "Thu, 01 Jan 1970 00:00:00 GMT"),
      ]),
    )
    assert_eq(response.code, 206)
    assert_eq(client.read_all().text(), "01")
  })
  @fs.rmdir(dir, recursive=true)
}
