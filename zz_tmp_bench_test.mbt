///|
test "tmp-format-http-date" (b : @bench.T) {
  b.bench(() => {
    b.keep(@feather.format_http_date(1750000000L))
  })
}

///|
test "tmp-parse-http-date" (b : @bench.T) {
  b.bench(() => {
    b.keep(@feather.parse_http_date("Tue, 15 Jun 2025 10:00:00 GMT"))
  })
}

///|
test "tmp-status-text" (b : @bench.T) {
  b.bench(() => {
    b.keep(@feather.status_text(404))
  })
}

///|
test "tmp-mime-noext" (b : @bench.T) {
  b.bench(() => {
    b.keep(@feather.mime_type_for("/assets/app"))
  })
}

///|
test "tmp-base64-encode" (b : @bench.T) {
  let data = @utf8.encode("hello world, this is a test payload for base64")
  b.bench(() => {
    b.keep(@feather.base64_encode(data))
  })
}

///|
test "tmp-base64-decode" (b : @bench.T) {
  b.bench(() => {
    b.keep(@feather.base64_decode("aGVsbG8gd29ybGQsIHRoaXMgaXMgYSB0ZXN0IHBheWxvYWQgZm9yIGJhc2U2NA=="))
  })
}
