///|
test "zz-etag-list-parsing" {
  let make = fn(header) {
    Context::new({
      method: "GET",
      path: "/",
      headers: Map([("If-None-Match", header)]),
      body: "",
    })
  }
  let single = make("\"a,b\"")
  assert_true(single.fresh("\"a,b\""))
  assert_true(single.fresh("W/\"a,b\""))
  assert_false(single.fresh("\"a,c\""))
  let listed = make("\"x\", W/\"a,b\"")
  assert_true(listed.fresh("\"a,b\""))
  assert_true(listed.fresh("\"x\""))
  assert_false(listed.fresh("\"a\""))
  let spaced = make("\"x\" ,\t\"a,b\"")
  assert_true(spaced.fresh("\"a,b\""))
  assert_true(make(" * ").fresh("\"a,b\""))
  assert_false(make("*x").fresh("\"a,b\""))
  assert_false(make("\"a,b").fresh("\"a,b\""))
}

///|
test "zz-multipart-transport-padding" {
  let body = "--B \r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--B--\r\n"
  let parts = match parse_multipart(body, "multipart/form-data; boundary=B") {
    Some(parts) => parts
    None => fail("expected parts")
  }
  assert_eq(parts.length(), 1)
  if parts.length() == 1 {
    assert_eq(parts[0].name, "a")
    assert_eq(parts[0].data, "1")
  }
  let two = "--B\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--B \t\r\nContent-Disposition: form-data; name=\"b\"\r\n\r\n2\r\n--B--\r\n"
  let parts = match parse_multipart(two, "multipart/form-data; boundary=B") {
    Some(parts) => parts
    None => fail("expected parts")
  }
  assert_eq(parts.length(), 2)
  if parts.length() == 2 {
    assert_eq(parts[1].name, "b")
    assert_eq(parts[1].data, "2")
  }
}

///|
test "zz-multipart-padding-lf-and-close" {
  let lf = "--B \t\nContent-Disposition: form-data; name=\"a\"\n\n1\n--B \t\nContent-Disposition: form-data; name=\"b\"\n\n2\n--B-- \t\nepilogue"
  let parts = match parse_multipart(lf, "multipart/form-data; boundary=B") {
    Some(parts) => parts
    None => fail("expected parts")
  }
  assert_eq(parts.length(), 2)
  if parts.length() == 2 {
    assert_eq(parts[0].data, "1")
    assert_eq(parts[1].data, "2")
  }
  let no_pad_close = "--B\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--B--"
  let parts = match parse_multipart(no_pad_close, "multipart/form-data; boundary=B") {
    Some(parts) => parts
    None => fail("expected parts")
  }
  assert_eq(parts.length(), 1)
  if parts.length() == 1 {
    assert_eq(parts[0].data, "1")
  }
}
