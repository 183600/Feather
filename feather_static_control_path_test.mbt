///|
test "static lookup rejects control characters in decoded paths" {
  let app = @feather.App::new().static_files("/assets", "/srv/public")
  for path in [
    "/assets/a%00b",
    "/assets/a%0Db",
    "/assets/a%0Ab",
    "/assets/a%09b",
    "/assets/a%1Fb",
    "/assets/a%7Fb",
    "/assets/a%0D%0AX-Injected:%20yes",
  ] {
    assert_eq(app.static_file_for(path), None, msg=path)
  }
  assert_eq(
    app.static_file_for("/assets/a%20b.txt"),
    Some("/srv/public/a b.txt"),
  )
  assert_eq(
    app.static_file_for("/assets/caf%C3%A9.txt"),
    Some("/srv/public/café.txt"),
  )
}
