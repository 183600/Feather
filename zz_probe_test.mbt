async test "probe existing encoding non compressible" {
  let app = @feather.App::new().compress()
  let response = app.respond_async({
    method: "GET",
    path: "/image",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  ignore(response)
}

async test "probe handler br on image" {
  let app = @feather.App::new().get("/image", fn(ctx) {
    ctx.bytes(200, b"\x89PNG\r\n\x1a\n", content_type="image/png")
    ctx.set_header("Content-Encoding", "br")
  })
  let response = app.respond_async({
    method: "GET",
    path: "/image",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  println("status=\{response.status} ce=\{response.headers.get("Content-Encoding")} vary=\{response.headers.get("Vary")}")
}
