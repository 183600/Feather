///|
fn make_multipart_upload(
  filename : String,
  content : Bytes,
  name~ : String = "file",
  content_type~ : String = "application/octet-stream",
) -> Bytes {
  let boundary = "TESTBOUNDARY"
  let builder = StringBuilder()
  builder.write_string("--")
  builder.write_string(boundary)
  builder.write_string("\r\n")
  builder.write_string("Content-Disposition: form-data; name=\"")
  builder.write_string(name)
  builder.write_string("\"; filename=\"")
  builder.write_string(filename)
  builder.write_string("\"\r\n")
  builder.write_string("Content-Type: ")
  builder.write_string(content_type)
  builder.write_string("\r\n\r\n")
  let header = builder.to_string()
  let raw_body = @utf8.decode_lossy(content)
  let footer = "\r\n--" + boundary + "--\r\n"
  let body = header + raw_body + footer
  let ct = "multipart/form-data; boundary=" + boundary
  let full = @utf8.encode(body)
  let header_bytes = @utf8.encode(ct)
  let result : Array[Byte] = []
  for b in header_bytes.iter() {
    result.push(b)
  }
  result.push(13)
  result.push(10)
  for b in full.iter() {
    result.push(b)
  }
  Bytes::from_array(result)
}

///|
test "sanitize_filename handles various edge cases" {
  assert_eq(sanitize_filename("normal.txt"), "normal.txt")
  assert_eq(sanitize_filename("path/to/file.txt"), "file.txt")
  assert_eq(sanitize_filename("path\\to\\file.txt"), "file.txt")
  assert_eq(sanitize_filename("../../etc/passwd"), "passwd")
  assert_eq(sanitize_filename("..\\windows\\system32"), "system32")
  assert_eq(sanitize_filename("file\x00name.txt"), "filename.txt")
  assert_eq(sanitize_filename(""), "")
  assert_eq(sanitize_filename("."), "")
  assert_eq(sanitize_filename(".."), "")
  assert_eq(sanitize_filename("   "), "")
  assert_eq(sanitize_filename("file name.txt"), "file name.txt")
  assert_eq(sanitize_filename("file/name.txt"), "name.txt")
}