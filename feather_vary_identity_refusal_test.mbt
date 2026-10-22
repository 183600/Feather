///|
let vary_refusal_accept_encoding : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Accept-Encoding",
)

///|
let vary_refusal_vary : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Vary",
)

///|
async test "static identity 200 varies even when compression is disabled" {
  let dir = @fs.tmpdir(prefix="feather-static-vary-refusal")
  @fs.write_file(dir + "/asset.txt", "identity body")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let accepted = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(vary_refusal_accept_encoding, "gzip")]),
    )
    assert_eq(accepted.code, 200)
    assert_eq(
      accepted.headers.get(vary_refusal_vary).unwrap_or("").contains(
        "Accept-Encoding",
      ),
      true,
    )
    assert_eq(client.read_all().text(), "identity body")
    let refused = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(vary_refusal_accept_encoding, "identity;q=0")]),
    )
    assert_eq(refused.code, 406)
    assert_eq(client.read_all().text(), "406 Not Acceptable")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "queued file identity 200 varies even when compression is disabled" {
  let dir = @fs.tmpdir(prefix="feather-file-vary-refusal")
  @fs.write_file(dir + "/report.txt", "report body")
  let app = @feather.App::new().get("/report", fn(ctx) {
    ctx.file(200, dir + "/report.txt")
  })
  with_server(app, client => {
    let accepted = client.get(
      "/report",
      extra_headers=Map([(vary_refusal_accept_encoding, "gzip")]),
    )
    assert_eq(accepted.code, 200)
    assert_eq(
      accepted.headers.get(vary_refusal_vary).unwrap_or("").contains(
        "Accept-Encoding",
      ),
      true,
    )
    assert_eq(client.read_all().text(), "report body")
    let refused = client.get(
      "/report",
      extra_headers=Map([(vary_refusal_accept_encoding, "identity;q=0")]),
    )
    assert_eq(refused.code, 406)
    assert_eq(client.read_all().text(), "406 Not Acceptable")
  })
  @fs.rmdir(dir, recursive=true)
}
