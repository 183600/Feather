///|
test "multipart does not end a part at a bare carriage return after the boundary" {
  // Only CRLF (and the lenient bare LF) line endings terminate a delimiter.
  // A data byte sequence that merely starts with the boundary text and is
  // followed by a lone CR is part of the part payload, not a separator.
  let body = "--B\r\n" +
    "Content-Disposition: form-data; name=\"data\"\r\n\r\n" +
    "one\n--B\rstill data\r\n--B--\r\n"
  let parts = @feather.parse_multipart(
    body,
    "multipart/form-data; boundary=B",
  )
  assert_true(parts is Some(_), msg="payload was rejected")
  let parsed = parts.unwrap()
  assert_eq(parsed.length(), 1)
  assert_eq(parsed[0].data, "one\n--B\rstill data")
}

///|
test "multipart keeps whitespace between a boundary and a would-be close delimiter in the payload" {
  let body = "--B\r\n" +
    "Content-Disposition: form-data; name=\"data\"\r\n\r\n" +
    "hello\r\n--B \t--\r\nstill payload\r\n--B--\r\n"
  let parts = @feather.parse_multipart(
    body,
    "multipart/form-data; boundary=B",
  )
  assert_true(parts is Some(_), msg="payload was rejected")
  let parsed = parts.unwrap()
  assert_eq(parsed.length(), 1)
  assert_eq(parsed[0].data, "hello\r\n--B \t--\r\nstill payload")
}

///|
test "multipart payload may start with the boundary spelling" {
  // The CRLF that ends the blank header/body separator must not combine with
  // a payload that starts with the boundary spelling into a phantom part
  // delimiter. Only a delimiter after the payload starts a new part.
  let body = "--B\r\n" +
    "Content-Disposition: form-data; name=\"data\"\r\n\r\n" +
    "--B\r\nstill payload\r\n--B--\r\n"
  let parts = @feather.parse_multipart(
    body,
    "multipart/form-data; boundary=B",
  )
  assert_true(parts is Some(_), msg="payload was rejected")
  let parsed = parts.unwrap()
  assert_eq(parsed.length(), 1)
  assert_eq(parsed[0].data, "--B\r\nstill payload")
}
