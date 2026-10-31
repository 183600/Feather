///|
fn multipart_charset_body(headers : String, payload : Bytes) -> Bytes {
  let prefix = @utf8.encode("--charset\r\n" + headers + "\r\n\r\n")
  let suffix = @utf8.encode("\r\n--charset--\r\n")
  let bytes : Array[Byte] = []
  for byte in prefix.iter() {
    bytes.push(byte)
  }
  for byte in payload.iter() {
    bytes.push(byte)
  }
  for byte in suffix.iter() {
    bytes.push(byte)
  }
  Bytes::from_array(bytes)
}

///|
async test "multipart fields decode a declared iso-8859-15 charset" {
  let app = @feather.App::new().post("/form", fn(ctx) raise {
    ctx.text(200, ctx.form("field"))
  })
  with_server(app, client => {
    let response = client.post(
      "/form",
      multipart_charset_body(
        "Content-Disposition: form-data; name=\"field\"\r\nContent-Type: text/plain; charset=iso-8859-15",
        b"caf\xa4",
      ),
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "multipart/form-data; boundary=charset",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "caf\u{20AC}")
  })
}

///|
async test "multipart fields fall back to lossy utf-8 for unknown charsets" {
  let app = @feather.App::new().post("/form", fn(ctx) raise {
    ctx.text(200, ctx.form("field"))
  })
  with_server(app, client => {
    let response = client.post(
      "/form",
      multipart_charset_body(
        "Content-Disposition: form-data; name=\"field\"\r\nContent-Type: text/plain; charset=gbk",
        b"caf\xff",
      ),
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "multipart/form-data; boundary=charset",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "caf\u{FFFD}")
  })
}

///|
async test "multipart file text uses its charset while bytes stay exact" {
  let app = @feather.App::new().post("/upload", fn(ctx) raise {
    match ctx.multipart_file("field") {
      Some(part) =>
        ctx.text(
          200,
          if part.data_bytes == b"caf\xe9" {
            part.data
          } else {
            "bytes-mismatch"
          },
        )
      None => ctx.text(400, "missing")
    }
  })
  with_server(app, client => {
    let response = client.post(
      "/upload",
      multipart_charset_body(
        "Content-Disposition: form-data; name=\"field\"; filename=\"a.txt\"\r\nContent-Type: text/plain; charset=windows-1252",
        b"caf\xe9",
      ),
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "multipart/form-data; boundary=charset",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "caf\u{E9}")
  })
}
