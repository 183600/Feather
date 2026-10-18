///|
fn scratch_hex(data : Bytes) -> String {
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
fn scratch_repeat(byte : Byte, count : Int) -> Bytes {
  FixedArray::make(count, byte).unsafe_reinterpret_as_bytes()
}

///|
test "scratch sha256 boundaries" {
  assert_eq(
    scratch_hex(sha256(scratch_repeat(b'a', 63))),
    "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34",
  )
  assert_eq(
    scratch_hex(sha256(scratch_repeat(b'a', 64))),
    "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
  )
  assert_eq(
    scratch_hex(sha256(scratch_repeat(b'a', 65))),
    "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0",
  )
  assert_eq(
    scratch_hex(sha256(scratch_repeat(b'a', 119))),
    "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb",
  )
  assert_eq(
    scratch_hex(sha256(scratch_repeat(b'a', 120))),
    "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c",
  )
  assert_eq(
    scratch_hex(sha256(scratch_repeat(b'a', 127))),
    "c57e9278af78fa3cab38667bef4ce29d783787a2f731d4e12200270f0c32320a",
  )
  assert_eq(
    scratch_hex(sha256(scratch_repeat(b'a', 128))),
    "6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e",
  )
  assert_eq(
    scratch_hex(sha256(scratch_repeat(b'a', 129))),
    "c12cb024a2e5551cca0e08fce8f1c5e314555cc3fef6329ee994a3db752166ae",
  )
  assert_eq(
    scratch_hex(sha256(scratch_repeat(b'a', 191))),
    "311834ddbafe20677dddbf9f4beb2b5b0b9e6ee97dddb70fce4e8f62c1b7518d",
  )
  assert_eq(
    scratch_hex(sha256(scratch_repeat(b'a', 192))),
    "7cee24628d290c16183532716cc5a8a889bc951b4b0a1507c32b8e29cee01052",
  )
}

///|
test "scratch hmac key lengths" {
  assert_eq(
    scratch_hex(hmac_sha256(scratch_repeat(b'k', 64), b"msg")),
    "d62ad25bb128e96ab6ef43464aaf2bb91b5b85f013381e9ba6be747e8d0911b2",
  )
  assert_eq(
    scratch_hex(hmac_sha256(scratch_repeat(b'k', 65), b"msg")),
    "c65585780e821bd312cfaa440c33cb28d6af6b323d4977ae83934834ce589e38",
  )
}

///|
test "scratch sha256 called twice agrees" {
  let first = sha256(b"hello")
  let second = sha256(b"hello")
  assert_eq(first, second)
}
