///|
fn test_hex(data : Bytes) -> String {
  let digits = "0123456789abcdef"
  let builder = StringBuilder(size_hint=data.length() * 2)
  for i = 0; i < data.length(); i = i + 1 {
    let byte = data[i].to_int()
    builder.write_char(digits.view().unsafe_get(byte >> 4).unsafe_to_char())
    builder.write_char(digits.view().unsafe_get(byte & 15).unsafe_to_char())
  }
  builder.to_string()
}

///|
fn repeated_byte(byte : Byte, count : Int) -> Bytes {
  FixedArray::make(count, byte).unsafe_reinterpret_as_bytes()
}

///|
fn counting_bytes(count : Int) -> Bytes {
  let out = FixedArray::make(count, b'\x00')
  for i = 0; i < count; i = i + 1 {
    out[i] = (i + 1).to_byte()
  }
  out.unsafe_reinterpret_as_bytes()
}

///|
test "sha256 matches the NIST short-message vectors" {
  assert_eq(
    test_hex(sha256(b"")),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    test_hex(sha256(b"abc")),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    test_hex(sha256(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
  assert_eq(
    test_hex(
      sha256(
        b"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
      ),
    ),
    "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
  )
}

///|
test "sha256 handles block-boundary padding lengths" {
  assert_eq(
    test_hex(sha256(repeated_byte(b'a', 55))),
    "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
  )
  assert_eq(
    test_hex(sha256(repeated_byte(b'a', 56))),
    "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
  )
  assert_eq(
    test_hex(sha256(repeated_byte(b'a', 64))),
    "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
  )
}

///|
test "sha256 processes inputs larger than one block" {
  let message = repeated_byte(b'a', 1_000_000)
  assert_eq(
    test_hex(sha256(message)),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
  )
}

///|
test "hmac_sha256 matches RFC 4231 test case 1" {
  let digest = hmac_sha256(repeated_byte(b'\x0b', 20), b"Hi There")
  assert_eq(
    test_hex(digest),
    "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
  )
}

///|
test "hmac_sha256 matches RFC 4231 test case 2" {
  let digest = hmac_sha256(b"Jefe", b"what do ya want for nothing?")
  assert_eq(
    test_hex(digest),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  )
}

///|
test "hmac_sha256 matches RFC 4231 test case 3" {
  let digest = hmac_sha256(repeated_byte(b'\xaa', 20), repeated_byte(b'\xdd', 50))
  assert_eq(
    test_hex(digest),
    "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe",
  )
}

///|
test "hmac_sha256 matches RFC 4231 test case 4" {
  let digest = hmac_sha256(counting_bytes(25), repeated_byte(b'\xcd', 50))
  assert_eq(
    test_hex(digest),
    "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b",
  )
}

///|
test "hmac_sha256 hashes oversized keys like RFC 4231 test case 6" {
  let digest = hmac_sha256(
    repeated_byte(b'\xaa', 131),
    b"Test Using Larger Than Block-Size Key - Hash Key First",
  )
  assert_eq(
    test_hex(digest),
    "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
  )
}

///|
test "hmac_sha256 matches RFC 4231 test case 7" {
  let digest = hmac_sha256(
    repeated_byte(b'\xaa', 131),
    b"This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.",
  )
  assert_eq(
    test_hex(digest),
    "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2",
  )
}

///|
test "base64url encoding omits padding and uses the URL-safe alphabet" {
  assert_eq(base64url_encode(b""), "")
  assert_eq(base64url_encode(b"f"), "Zg")
  assert_eq(base64url_encode(b"fo"), "Zm8")
  assert_eq(base64url_encode(b"foo"), "Zm9v")
  assert_eq(base64url_encode(b"hello world/+"), "aGVsbG8gd29ybGQvKw")
  let all = FixedArray::make(256, b'\x00')
  for i = 0; i < 256; i = i + 1 {
    all[i] = i.to_byte()
  }
  let encoded = base64url_encode(all.unsafe_reinterpret_as_bytes())
  assert_eq(encoded.view().find("+"), None)
  assert_eq(encoded.view().find("/"), None)
  assert_eq(encoded.view().find("="), None)
  assert_eq(base64url_decode(encoded), Some(all.unsafe_reinterpret_as_bytes()))
}

///|
test "base64url decoding accepts padded and unpadded input" {
  assert_eq(base64url_decode(""), Some(b""))
  assert_eq(base64url_decode("Zm9v"), Some(b"foo"))
  assert_eq(base64url_decode("Zg=="), Some(b"f"))
  assert_eq(base64url_decode("Zg"), Some(b"f"))
  assert_eq(base64url_decode("a-_"), Some(b"k\xef"))
  assert_eq(base64url_decode("****"), None)
  assert_eq(base64url_decode("Zg==="), None)
  assert_eq(base64url_decode("Zg="), None)
}

///|
test "base64url decoding rejects non-ascii aliases" {
  assert_eq(base64url_decode("\u{141}"), None)
  assert_eq(base64url_decode("A\u{141}"), None)
}

///|
test "verify_signed_cookie_token rejects a signed but undecodable value" {
  let encoded_value = "***"
  let mac = hmac_sha256(
    @utf8.encode("s3cret"),
    signed_cookie_signing_input("user", encoded_value, 0L),
  )
  let token = encoded_value + ".0." + base64url_encode(mac)
  assert_eq(verify_signed_cookie_token("s3cret", "user", token), None)
}

///|
test "parse_decimal_int64 accepts only canonical digit runs" {
  assert_eq(parse_decimal_int64("0"), Some(0L))
  assert_eq(parse_decimal_int64("1728000000"), Some(1_728_000_000L))
  assert_eq(parse_decimal_int64(""), None)
  assert_eq(parse_decimal_int64("1a"), None)
  assert_eq(parse_decimal_int64("-1"), None)
  assert_eq(parse_decimal_int64("1 "), None)
  assert_eq(parse_decimal_int64("12345678901234567890123"), None)
}
