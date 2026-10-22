///|
async test "logger reports the real static response status" {
  let dir = @fs.tmpdir(prefix="feather-static-logger")
  @fs.write_file(dir + "/asset.txt", "logged static body")
  let lines : Array[String] = []
  let app = @feather.App::new()
    .use(@feather.middleware_logger(log=line => lines.push(line)))
    .static_files("/assets", dir)
  with_server(app, client => {
    let ok = client.get("/assets/asset.txt")
    assert_eq(ok.code, 200)
    ignore(client.read_all())
    let missing = client.get("/assets/missing.txt")
    assert_eq(missing.code, 404)
    ignore(client.read_all())
    let ranged = client.get(
      "/assets/asset.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=0-3"),
      ]),
    )
    assert_eq(ranged.code, 206)
    ignore(client.read_all())
  })
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "[200] GET /assets/asset.txt")
  assert_eq(lines[1], "[404] GET /assets/missing.txt")
  assert_eq(lines[2], "[206] GET /assets/asset.txt")
  @fs.rmdir(dir, recursive=true)
}
