///|
let static_identity_ae : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Accept-Encoding",
)

///|
let static_identity_vary : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Vary",
)

///|
async test "static identity refusal without gzip yields 406" {
  let dir = @fs.tmpdir(prefix="feather-static-identity")
  @fs.write_file(dir + "/asset.txt", "identity body")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let refused = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(static_identity_ae, "identity;q=0")]),
    )
    assert_eq(refused.code, 406)
    assert_eq(
      refused.headers.get(static_identity_vary).unwrap_or("").contains(
        "Accept-Encoding",
      ),
      true,
    )
    assert_eq(client.read_all().text(), "406 Not Acceptable")
    let identity_preferred = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(static_identity_ae, "gzip;q=0.2")]),
    )
    assert_eq(identity_preferred.code, 200)
    assert_eq(client.read_all().text(), "identity body")
    let missing = client.get(
      "/assets/missing.txt",
      extra_headers=Map([(static_identity_ae, "identity;q=0")]),
    )
    assert_eq(missing.code, 404)
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "precompressed static identity refusal selects gzip or 406" {
  let dir = @fs.tmpdir(prefix="feather-static-identity-gzip")
  @fs.write_file(dir + "/asset.txt", "identity body")
  @fs.write_file(dir + "/asset.txt.gz", b"gzip bytes")
  let app = @feather.App::new().static_files(
    "/assets",
    dir,
    precompressed=true,
  )
  with_server(app, client => {
    let accepted = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(static_identity_ae, "gzip;q=0.5, identity;q=0")]),
    )
    assert_eq(accepted.code, 200)
    assert_eq(
      accepted.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    ignore(client.read_all())
    let refused = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(static_identity_ae, "identity;q=0")]),
    )
    assert_eq(refused.code, 406)
    assert_eq(client.read_all().text(), "406 Not Acceptable")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "gzip-only static file reports 406 when identity is refused" {
  let dir = @fs.tmpdir(prefix="feather-static-identity-gzip-only")
  @fs.write_file(dir + "/asset.txt.gz", b"gzip bytes")
  let app = @feather.App::new().static_files(
    "/assets",
    dir,
    precompressed=true,
  )
  with_server(app, client => {
    let refused = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(static_identity_ae, "identity;q=0")]),
    )
    assert_eq(refused.code, 406)
    assert_eq(client.read_all().text(), "406 Not Acceptable")
    let unusable = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(static_identity_ae, "identity")]),
    )
    assert_eq(unusable.code, 404)
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "queued file responses honor identity refusal" {
  let dir = @fs.tmpdir(prefix="feather-file-identity")
  @fs.write_file(dir + "/report.txt", "report body")
  let app = @feather.App::new()
    .get("/report", fn(ctx) {
      ctx.file(200, dir + "/report.txt")
    })
    .get("/missing-file", fn(ctx) {
      ctx.file(200, dir + "/absent.txt")
    })
  with_server(app, client => {
    let refused = client.get(
      "/report",
      extra_headers=Map([(static_identity_ae, "identity;q=0")]),
    )
    assert_eq(refused.code, 406)
    assert_eq(
      refused.headers.get(static_identity_vary).unwrap_or("").contains(
        "Accept-Encoding",
      ),
      true,
    )
    assert_eq(client.read_all().text(), "406 Not Acceptable")
    let identity_preferred = client.get(
      "/report",
      extra_headers=Map([(static_identity_ae, "gzip;q=0.2")]),
    )
    assert_eq(identity_preferred.code, 200)
    assert_eq(client.read_all().text(), "report body")
    let missing = client.get(
      "/missing-file",
      extra_headers=Map([(static_identity_ae, "identity;q=0")]),
    )
    assert_eq(missing.code, 404)
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
