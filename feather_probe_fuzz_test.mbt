///|
test "probe multipart boundary-like payloads round trip" {
  let payloads = [
    "", "x", "x\r\n", "\r\n", "\r\n\r\n", "x\n", "x\n\n",
    "x\r\n--Bx", "x\r\n--B-", "x\r\n--B--x", "x\r\n--B\rx",
    "x\n--Bx", "x\n--B-", "x\r\n--Bx\r\n", "\r\n--Bx",
    "--B--x", "x--B", "x\n--B--x\ny",
  ]
  for data in payloads {
    let body = "--B\r\n" +
      "Content-Disposition: form-data; name=\"f\"\r\n\r\n" +
      data +
      "\r\n--B--\r\n"
    let parsed = @feather.parse_multipart(
      body,
      "multipart/form-data; boundary=B",
    )
    assert_true(parsed is Some(_), msg=data)
    let parts = parsed.unwrap()
    assert_eq(parts.length(), 1, msg=data)
    assert_eq(parts[0].data, data, msg=data)
  }
}

///|
test "probe http date round trip with clamping" {
  let min = -719528L * 86400L
  let max = 253402300799L
  let values = [
    -9223372036854775807L - 1L, -922337203685477580L, -1000000L, -86401L,
    -86400L, -1L, 0L, 1L, 86399L, 86400L, 253402300799L,
    253402300800L, 9223372036854775807L,
  ]
  for value in values {
    let formatted = @feather.format_http_date(value)
    let expected = if value < min { min } else if value > max { max } else { value }
    assert_eq(@feather.parse_http_date(formatted), Some(expected), msg=formatted)
  }
}
