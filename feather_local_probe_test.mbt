///|
test "local probe base64 roundtrip" {
  let mut state = 123456789UL
  for len = 0; len < 300; len = len + 1 {
    let data = FixedArray::make(len, b'\x00')
    for i = 0; i < len; i = i + 1 {
      state = (state * 6364136223846793005UL + 1442695040888963407UL)
      data[i] = (state >> 33).to_int().to_byte()
    }
    let bytes = data.unsafe_reinterpret_as_bytes()
    let text = @feather.base64_encode(bytes)
    assert_eq(@feather.base64_decode(text), Some(bytes), msg="len=\{len}")
  }
}

///|
test "local probe url roundtrip" {
  let mut state = 987654321UL
  for iter = 0; iter < 3000; iter = iter + 1 {
    let len = (state % 20UL).to_int()
    let builder = StringBuilder()
    for i = 0; i < len; i = i + 1 {
      state = (state * 6364136223846793005UL + 1442695040888963407UL)
      let scalar = ((state >> 20) & 0x1FFFFFUL).to_int() % 0x110000
      if scalar < 0xD800 || scalar > 0xDFFF {
        builder.write_char(scalar.unsafe_to_char())
      } else {
        builder.write_char('a')
      }
    }
    let text = builder.to_string()
    let encoded = @feather.url_encode(text)
    assert_eq(@feather.url_decode(encoded), text, msg="iter=\{iter}")
  }
}

///|
test "local probe http date roundtrip random" {
  let min = -719528L * 86400L
  let max = 253402300799L
  let mut state = 42UL
  for iter = 0; iter < 20000; iter = iter + 1 {
    state = (state * 6364136223846793005UL + 1442695040888963407UL)
    let raw = (state >> 1).to_int64() - 4611686018427387904L
    let clamped = if raw < min { min } else if raw > max { max } else { raw }
    let text = @feather.format_http_date(raw)
    assert_eq(@feather.parse_http_date(text), Some(clamped), msg=text)
  }
}
