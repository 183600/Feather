///|
fn tmp_old_find_part(
  view : StringView,
  crlf_delimiter : StringView,
  lf_delimiter : StringView,
  crlf_table : Array[Int32],
  lf_table : Array[Int32],
  start : Int32,
) -> Int32? {
  let lf = find_terminated_delimiter(view, lf_delimiter, lf_table, start)
  let crlf = find_terminated_delimiter(view, crlf_delimiter, crlf_table, start)
  match lf {
    Some(lf_index) =>
      match crlf {
        Some(crlf_index) =>
          Some(if crlf_index < lf_index { crlf_index } else { lf_index })
        None => Some(lf_index)
      }
    None => crlf
  }
}

///|
test "tmp find_part_delimiter differential" {
  let crlf = "\r\n--X"
  let lf = "\n--X"
  let crlf_table = delimiter_match_table(crlf.view())
  let lf_table = delimiter_match_table(lf.view())
  let chars : Array[UInt16] = [
    '\r'.to_int().to_uint().to_uint16(),
    '\n'.to_int().to_uint().to_uint16(),
    '-'.to_int().to_uint().to_uint16(),
    'X'.to_int().to_uint().to_uint16(),
  ]
  let mut total = 0
  for len = 0; len <= 8; len = len + 1 {
    let max = 1 << (len * 2)
    for mask = 0; mask < max; mask = mask + 1 {
      let out = FixedArray::make(len, b'\x00')
      let mut m = mask
      for i = 0; i < len; i = i + 1 {
        out[i] = chars[m & 3].to_byte()
        m = m >> 2
      }
      let s = @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes())
      let view = s.view()
      let new = find_part_delimiter(
        view,
        crlf.view(),
        lf.view(),
        crlf_table,
        lf_table,
        0,
      )
      let old = tmp_old_find_part(
        view,
        crlf.view(),
        lf.view(),
        crlf_table,
        lf_table,
        0,
      )
      total = total + 1
      if new != old {
        fail("mismatch for \{s}: new=\{new} old=\{old}")
      }
    }
  }
  assert_true(total > 0)
}

///|
fn tmp_old_parse_urlencoded(source : String) -> Map[String, String] {
  let view = source.view()
  let length = view.length()
  let result : Map[String, String] = Map([])
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    let mut eq = -1
    while end < length {
      let code = view.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) && eq < 0 {
        eq = end
      }
      end = end + 1
    }
    if end > pos {
      if eq >= 0 {
        result.set(decode_url(view[pos:eq]), decode_url(view[eq + 1:end]))
      } else {
        result.set(decode_url(view[pos:end]), "")
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  result
}

///|
test "tmp urlencoded differential" {
  let alphabet : Array[String] = [
    "a", "b", "%", "+", "=", "&", " ", "%20", "%2B", "%zz", "%4", "\u{00e9}", "?",
  ]
  let mut seed = 123456789
  let next = fn() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    seed
  }
  for _ in 0..<20000 {
    let len = next() % 12
    let builder = StringBuilder::new()
    for _ in 0..<len {
      builder.write_string(alphabet[next() % alphabet.length()])
    }
    let source = builder.to_string()
    let expected = tmp_old_parse_urlencoded(source)
    let actual = parse_urlencoded(source)
    if actual != expected {
      fail("mismatch for \{source}: \{actual} vs \{expected}")
    }
  }
}

///|
test "tmp sha and hmac vectors" {
  assert_eq(base64_encode(sha256(@utf8.encode("abc"))), "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=")
  let long = StringBuilder::new()
  for _ in 0..<1000000 {
    long.write_char('a')
  }
  assert_eq(base64_encode(sha256(@utf8.encode(long.to_string()))), "zcduXJkU+5KBocfihNc+Z/GAmkiklyAOBG05zMcRLNA=")
  assert_eq(base64_encode(hmac_sha256(@utf8.encode("key"), @utf8.encode("The quick brown fox jumps over the lazy dog"))), "97yD9DBThCSxMpjmqm+xQ+9NWaFJRhdZl0edvC0aPNg=")
  let key = StringBuilder::new()
  for _ in 0..<100 {
    key.write_char('k')
  }
  let msg = StringBuilder::new()
  for _ in 0..<300 {
    msg.write_char('m')
  }
  assert_eq(base64_encode(hmac_sha256(@utf8.encode(key.to_string()), @utf8.encode(msg.to_string()))), "CRQUDeZ6doBJj/eYCYLUWy+YHXF105ef7S4QBf4Ytqg=")
}
