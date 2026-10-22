///|
async fn empty_identity_gunzip(data : Bytes) -> Bytes {
  let reader = @io.MemoryReader(async fn(writer) { writer.write(data) })
  defer reader.close()
  let decoder = @gzip.Decoder::Decoder(reader)
  decoder.read_all().binary()
}

///|
async test "empty dynamic bodies are gzipped when identity is refused" {
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/empty", fn(ctx) { ctx.text(200, "") })
  let response = app.respond_async({
    method: "GET",
    path: "/empty",
    headers: Map([("Accept-Encoding", "gzip, identity;q=0")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Content-Encoding"), Some("gzip"))
  let data = response.data.unwrap()
  assert_true(data.length() > 0)
  assert_eq(@utf8.decode_lossy(empty_identity_gunzip(data)), "")
}
