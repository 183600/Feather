///|
async test "body text decodes utf-16 byte order marks and endianness" {
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text())
  })
  with_server(app, client => {
    let cases : Array[(Bytes, String, String)] = [
      (b"\xff\xfeh\x00i\x00", "utf-16", "hi"),
      (b"\xfe\xff\x00h\x00i", "utf-16", "hi"),
      // RFC 2781 defaults to big-endian when no BOM is present.
      (b"\x00h\x00i", "utf-16", "hi"),
      (b"h\x00i\x00", "utf-16le", "hi"),
      (b"\x00h\x00i", "utf-16be", "hi"),
      (b"h\x00i\x00", "UTF16LE", "hi"),
      (b"\x00h\x00i", "utf-16be", "hi"),
    ]
    for pair in cases {
      let (payload, charset, expected) = pair
      let response = client.post(
        "/body",
        payload,
        extra_headers=Map([
          (
            @http.CaseInsensitiveString("Content-Type"),
            "text/plain; charset=" + charset,
          ),
        ]),
      )
      assert_eq(response.code, 200, msg=charset)
      assert_eq(client.read_all().text(), expected, msg=charset)
    }
  })
}

///|
async test "body text decodes utf-16 surrogate pairs and replaces bad units" {
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text())
  })
  with_server(app, client => {
    let cases : Array[(Bytes, String)] = [
      // U+1F600 is the surrogate pair D83D DE00.
      (b"\x3d\xd8\x00\xde", "\u{1F600}"),
      // A high surrogate without a low surrogate.
      (b"\x3d\xd8", "\u{FFFD}"),
      // A low surrogate on its own.
      (b"\x00\xde", "\u{FFFD}"),
      // An odd trailing byte cannot form a code unit.
      (b"h\x00i", "h\u{FFFD}"),
      // A bare BOM is consumed and yields an empty body.
      (b"\xff\xfe", ""),
    ]
    for pair in cases {
      let (payload, expected) = pair
      let response = client.post(
        "/body",
        payload,
        extra_headers=Map([
          (
            @http.CaseInsensitiveString("Content-Type"),
            "text/plain; charset=utf-16le",
          ),
        ]),
      )
      assert_eq(response.code, 200)
      assert_eq(client.read_all().text(), expected)
    }
  })
}

///|
async test "body text explicit utf-16 charset overrides the request header" {
  let app = @feather.App::new().post("/body", fn(ctx) {
    ctx.text(200, ctx.body_text(charset="utf-16le"))
  })
  with_server(app, client => {
    let response = client.post(
      "/body",
      b"h\x00i\x00",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "text/plain; charset=utf-16be",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "hi")
  })
}
