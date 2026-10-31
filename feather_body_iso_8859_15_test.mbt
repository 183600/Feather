///|
fn iso_8859_15_context(payload : Bytes) -> @feather.Context {
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
test "body text decodes the iso-8859-15 replacement positions" {
  let payload : Bytes = b"A\xa4\xa6\xa8\xb4\xb8\xbc\xbd\xbe\xff"
  let expected = "A\u{20AC}\u{160}\u{161}\u{17D}\u{17E}\u{152}\u{153}\u{178}\u{FF}"
  let ctx = iso_8859_15_context(payload)
  assert_eq(ctx.body_text(charset="iso-8859-15"), expected)
}

///|
test "body text keeps the iso-8859-1 positions shared with iso-8859-15" {
  let ctx = iso_8859_15_context(b"\x00\x7f\x80\xa0\xa5\xbf\xc0\xe9")
  assert_eq(
    ctx.body_text(charset="latin9"),
    "\u{0}\u{7F}\u{80}\u{A0}\u{A5}\u{BF}\u{C0}\u{E9}",
  )
}

///|
test "body text accepts iso-8859-15 aliases case-insensitively" {
  let ctx = iso_8859_15_context(b"\xa4")
  assert_eq(ctx.body_text(charset="ISO8859-15"), "\u{20AC}")
  assert_eq(ctx.body_text(charset="iso_8859-15"), "\u{20AC}")
  assert_eq(ctx.body_text(charset="ISO885915"), "\u{20AC}")
  assert_eq(ctx.body_text(charset="csisolatin9"), "\u{20AC}")
  assert_eq(ctx.body_text(charset="Latin9"), "\u{20AC}")
  assert_eq(ctx.body_text(charset="L9"), "\u{20AC}")
}

///|
async test "body text uses a declared iso-8859-15 charset" {
  let app = @feather.App::new().post("/body", fn(ctx) raise {
    ctx.text(200, ctx.body_text())
  })
  with_server(app, client => {
    let response = client.post(
      "/body",
      b"caf\xa4",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "text/plain; charset=iso-8859-15",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "caf\u{20AC}")
  })
}
