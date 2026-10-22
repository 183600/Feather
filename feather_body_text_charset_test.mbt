///|
async test "body text uses the charset declared by the request" {
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text())
  })
  with_server(app, client => {
    let response = client.post(
      "/body",
      b"caf\xe9",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "text/plain; charset=iso-8859-1",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "café")
  })
}

///|
async test "an explicit body text charset overrides the request header" {
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text(charset="us-ascii"))
  })
  with_server(app, client => {
    let response = client.post(
      "/body",
      b"caf\xe9",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "text/plain; charset=iso-8859-1",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "caf�")
  })
}

///|
async test "body text rejects an unsupported declared charset" {
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text())
  })
  with_server(app, client => {
    let response = client.post(
      "/body",
      b"hello",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "text/plain; charset=gbk",
        ),
      ]),
    )
    assert_eq(response.code, 415)
  })
}
