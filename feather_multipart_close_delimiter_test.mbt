///|
test "multipart bodies require a close delimiter" {
  let content_type = "multipart/form-data; boundary=B"
  assert_eq(
    @feather.parse_multipart(
      "--B\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nx",
      content_type,
    ),
    None,
  )
  assert_eq(@feather.parse_multipart("--B", content_type), None)
  assert_eq(@feather.parse_multipart("--B\r\n", content_type), None)
  let closed = @feather.parse_multipart(
    "--B\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nx\r\n--B--",
    content_type,
  )
  assert_true(closed is Some(_))
  assert_eq(closed.unwrap()[0].data, "x")
}
