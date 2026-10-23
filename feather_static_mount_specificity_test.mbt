///|
test "a wildcard static mount does not shadow a longer fixed prefix" {
  let app = @feather.App::new()
    .static_files("/assets", "/srv/assets")
    .static_files("/*rest", "/srv/root")
  assert_eq(
    app.static_file_for("/assets/app.js"),
    Some("/srv/assets/app.js"),
  )
  assert_eq(
    app.static_file_for("/other/app.js"),
    Some("/srv/root/other/app.js"),
  )
}

///|
test "a wildcard suffix does not outrank a mount with a longer fixed prefix" {
  let app = @feather.App::new()
    .static_files("/a/*rest", "/srv/a")
    .static_files("/a/b", "/srv/ab")
  assert_eq(
    app.static_file_for("/a/b/file.txt"),
    Some("/srv/ab/file.txt"),
  )
  assert_eq(
    app.static_file_for("/a/c/file.txt"),
    Some("/srv/a/c/file.txt"),
  )
  let deeper = @feather.App::new()
    .static_files("/a", "/srv/a-short")
    .static_files("/a/b/*rest", "/srv/ab-wildcard")
  assert_eq(
    deeper.static_file_for("/a/b/c.txt"),
    Some("/srv/ab-wildcard/c.txt"),
  )
}
