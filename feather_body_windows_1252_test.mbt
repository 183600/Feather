///|
fn windows_1252_context(payload : Bytes) -> @feather.Context {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/body",
    headers: Map([]),
    body: "",
  })
  ctx.state.set("__feather_raw_body", @feather.base64_encode(payload))
  ctx
}

///|
test "body text decodes the windows-1252 high range" {
  let payload : Bytes = b"\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f"
  let expected = "\u{20AC}\u{81}\u{201A}\u{192}\u{201E}\u{2026}\u{2020}\u{2021}\u{2C6}\u{2030}\u{160}\u{2039}\u{152}\u{8D}\u{17D}\u{8F}\u{90}\u{2018}\u{2019}\u{201C}\u{201D}\u{2022}\u{2013}\u{2014}\u{2DC}\u{2122}\u{161}\u{203A}\u{153}\u{9D}\u{17E}\u{178}"
  let ctx = windows_1252_context(payload)
  assert_eq(ctx.body_text(charset="windows-1252"), expected)
}

///|
test "body text decodes windows-1252 latin-1 and ascii ranges" {
  let ctx = windows_1252_context(b"A\xe9\xff")
  assert_eq(ctx.body_text(charset="windows-1252"), "A\u{E9}\u{FF}")
}

///|
async test "body text uses a declared windows-1252 charset" {
  let app = @feather.App::new().post("/body", fn(ctx) raise {
    ctx.text(200, ctx.body_text())
  })
  with_server(app, client => {
    let response = client.post(
      "/body",
      b"\x93quoted\x94",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "text/plain; charset=windows-1252",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "\u{201C}quoted\u{201D}")
  })
}

///|
test "body text accepts windows-1252 aliases case-insensitively" {
  let ctx = windows_1252_context(b"\x80")
  assert_eq(ctx.body_text(charset="CP1252"), "\u{20AC}")
  assert_eq(ctx.body_text(charset="x-cp1252"), "\u{20AC}")
  assert_eq(ctx.body_text(charset="Windows1252"), "\u{20AC}")
}
