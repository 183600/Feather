///|
async test "stream add_cookie sends cookies with the response header" {
  let app = @feather.App::new().stream("/download", async fn(_ctx, stream) {
    stream.add_cookie(
      "download",
      "ready",
      path="/files",
      max_age=60L,
      same_site="Lax",
      http_only=true,
      secure=true,
    )
    stream.write("payload")
  })
  with_stream_server(app, client => {
    let response = client.get("/download")
    assert_eq(response.code, 200)
    assert_eq(response.cookies.length(), 1)
    let cookie = response.cookies[0]
    assert_eq(cookie.name, "download")
    assert_eq(cookie.value, "ready")
    assert_eq(cookie.path, Some("/files"))
    assert_eq(cookie.max_age, Some(60L))
    assert_eq(cookie.extensions, ["SameSite=Lax"])
    assert_true(cookie.http_only)
    assert_true(cookie.secure)
    assert_eq(client.read_all().text(), "payload")
  })
}

///|
async test "stream clear_cookie expires a cookie and ignores an empty name" {
  let app = @feather.App::new().stream("/logout", async fn(_ctx, stream) {
    stream.clear_cookie("session", path="/", partitioned=true)
    stream.add_cookie("\r\n", "forged")
    stream.write("bye")
  })
  with_stream_server(app, client => {
    let response = client.get("/logout")
    assert_eq(response.code, 200)
    assert_eq(response.cookies.length(), 1)
    let cookie = response.cookies[0]
    assert_eq(cookie.name, "session")
    assert_eq(cookie.value, "")
    assert_eq(cookie.path, Some("/"))
    assert_eq(cookie.max_age, Some(0L))
    assert_eq(cookie.extensions, ["Partitioned"])
    assert_eq(client.read_all().text(), "bye")
  })
}

///|
async test "stream cookies added after the first write are not sent" {
  let app = @feather.App::new().stream("/late", async fn(_ctx, stream) {
    stream.add_cookie("early", "1", path="/")
    stream.write("started")
    stream.add_cookie("late", "2", path="/")
  })
  with_stream_server(app, client => {
    let response = client.get("/late")
    assert_eq(response.code, 200)
    assert_eq(response.cookies.length(), 1)
    assert_eq(response.cookies[0].name, "early")
    assert_eq(response.cookies[0].value, "1")
    assert_eq(client.read_all().text(), "started")
  })
}
