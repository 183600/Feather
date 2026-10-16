///|
fn zz_ref_decode(source : StringView, plus_as_space : Bool) -> String {
  let bytes = @utf8.encode(source)
  let buffer = @buffer.Buffer::Buffer(size_hint=bytes.length())
  let mut i = 0
  while i < bytes.length() {
    let byte = bytes[i]
    if byte == b'%' && i + 2 < bytes.length() {
      let hd = fn(c : Int) -> Int {
        if c >= 48 && c <= 57 {
          c - 48
        } else if c >= 65 && c <= 70 {
          c - 55
        } else if c >= 97 && c <= 102 {
          c - 87
        } else {
          -1
        }
      }
      let high = hd(bytes[i + 1].to_int())
      let low = hd(bytes[i + 2].to_int())
      if high >= 0 && low >= 0 {
        buffer.write_byte((high * 16 + low).to_byte())
        i = i + 3
        continue
      }
    }
    if byte == b'+' && plus_as_space {
      buffer.write_byte(b' ')
    } else {
      buffer.write_byte(byte)
    }
    i = i + 1
  }
  @utf8.decode_lossy(buffer.to_bytes())
}

///|
test "zz-fuzz-decode-reference" {
  let chars = [
    'a', 'Z', '0', ' ', '/', '+', '%', '?', '&', '=', '#', '.', '\\', '世', '-',
    'A', 'F', 'f', '9', 'g', '~',
  ]
  let state = Ref(31337)
  let mut failures = 0
  for i = 0; i < 2000; i = i + 1 {
    let mut s = ""
    let len = zz_rand(state) % 10
    for j = 0; j < len; j = j + 1 {
      s = s + chars[zz_rand(state) % chars.length()].to_string()
    }
    let got = @feather.url_decode(s)
    let want = zz_ref_decode(s.view(), true)
    if got != want {
      failures = failures + 1
      if failures < 10 {
        println("decode mismatch: \{s} -> got \{got}, want \{want}")
      }
    }
  }
  assert_eq(failures, 0)
}

///|
test "zz-fuzz-encode-reference" {
  let chars = [
    'a', 'Z', '0', ' ', '/', '+', '%', '?', '&', '=', '#', '.', '\\', '世', '-',
    '~', '_', ':',
  ]
  let state = Ref(4242)
  let mut failures = 0
  for i = 0; i < 2000; i = i + 1 {
    let mut s = ""
    let len = zz_rand(state) % 8
    for j = 0; j < len; j = j + 1 {
      s = s + chars[zz_rand(state) % chars.length()].to_string()
    }
    let encoded = @feather.url_encode(s)
    let expected_buffer = StringBuilder::new()
    for byte in @utf8.encode(s) {
      let value = byte.to_int()
      let unreserved = (value >= 48 && value <= 57) ||
        (value >= 65 && value <= 90) ||
        (value >= 97 && value <= 122) ||
        value == 45 ||
        value == 46 ||
        value == 95 ||
        value == 126
      if unreserved {
        expected_buffer.write_char(value.unsafe_to_char())
      } else {
        let hex = "0123456789ABCDEF"
        expected_buffer.write_char('%')
        expected_buffer.write_char(hex[value / 16].unsafe_to_char())
        expected_buffer.write_char(hex[value % 16].unsafe_to_char())
      }
    }
    let expected = expected_buffer.to_string()
    if encoded != expected {
      failures = failures + 1
      if failures < 10 {
        println("encode mismatch: \{s} -> got \{encoded}, want \{expected}")
      }
    }
    if @feather.url_decode(encoded) != s {
      failures = failures + 1
      if failures < 20 {
        println("encode roundtrip mismatch: \{s} -> \{encoded}")
      }
    }
  }
  assert_eq(failures, 0)
}
