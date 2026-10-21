///|
fn body_request(body : String, headers : Map[String, String]) -> @feather.Request {
  { method: "POST", path: "/body", headers, body, }
}

///|
test "body text reads the request body as utf-8" {
  let ctx = @feather.Context::new(body_request("hello feather", Map([])))
  assert_eq(ctx.body_text(), "hello feather")
}

///|
async test "body text replaces invalid utf-8 sequences" {
  let payload : Bytes = b"ok\xff\xfe"
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text())
  })
  with_server(app, client => {
    let response = client.post("/body", payload)
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "ok��")
  })
}

///|
async test "body text decodes latin-1 bodies" {
  let payload : Bytes = b"caf\xe9"
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text(charset="iso-8859-1"))
  })
  with_server(app, client => {
    let response = client.post("/body", payload)
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "café")
  })
}

///|
async test "body text decodes ascii bodies and replaces the high bytes" {
  let payload : Bytes = b"a\xe9b"
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text(charset="us-ascii"))
  })
  with_server(app, client => {
    let response = client.post("/body", payload)
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "a�b")
  })
}

///|
async test "body text rejects an unsupported charset" {
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text(charset="gbk"))
  })
  with_server(app, client => {
    let response = client.post("/body", b"hello")
    assert_eq(response.code, 415)
  })
}

///|
async test "body text enforces the limit" {
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text(limit=4))
  })
  with_server(app, client => {
    let response = client.post("/body", b"hello")
    assert_eq(response.code, 413)
  })
}

///|
test "body text accepts a body within the limit" {
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text(limit=5))
  })
  let response = app.respond({
    method: "POST",
    path: "/body",
    headers: Map([]),
    body: "hello",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "hello")
}

///|
test "body charset reads the declared charset" {
  let ctx = @feather.Context::new(
    body_request(
      "hello",
      Map([("Content-Type", "text/plain; charset=iso-8859-1")]),
    ),
  )
  assert_eq(ctx.body_charset(), "iso-8859-1")
}

///|
test "body charset falls back to utf-8" {
  assert_eq(
    @feather.Context::new(body_request("hello", Map([]))).body_charset(),
    "utf-8",
  )
  assert_eq(
    @feather.Context::new(
      body_request("hello", Map([("Content-Type", "text/plain")])),
    ).body_charset(),
    "utf-8",
  )
}

///|
async test "body charset reports the charset of a server request" {
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_charset())
  })
  with_server(app, client => {
    let response = client.post(
      "/body",
      b"hello",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "text/plain; charset=iso-8859-1",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "iso-8859-1")
  })
}
