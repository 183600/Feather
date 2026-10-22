///|
async test "an empty first stream write starts the response" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.write_bytes(b"")
    assert_true(stream.is_started())
    stream.set_status(500)
    stream.set_header("X-Late", "no")
    stream.write("ok")
  })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(@http.CaseInsensitiveString("X-Late")), None)
    assert_eq(client.read_all().text(), "ok")
  })
}

///|
async test "streams do not write bodies for bodyless statuses" {
  let app = @feather.App::new().stream("/no-content", async fn(_ctx, stream) {
    stream.set_status(204)
    stream.write("illegal")
  })
  with_stream_server(app, client => {
    let response = client.get("/no-content")
    assert_eq(response.code, 204)
    assert_eq(client.read_all().text(), "")
  })
}
