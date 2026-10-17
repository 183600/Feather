///|
fn old_hex_digit(value : Int) -> Int {
  if value >= 48 && value <= 57 {
    value - 48
  } else if value >= 65 && value <= 70 {
    value - 55
  } else if value >= 97 && value <= 102 {
    value - 87
  } else {
    -1
  }
}

///|
fn old_decode_url_impl(source : StringView, plus_as_space : Bool) -> String {
  let length = source.length()
  let mut needs_decoding = false
  let mut ascii_only = true
  let mut high_byte = false
  let mut i = 0
  while i < length {
    let value = source.unsafe_get(i).to_int()
    if value > 127 {
      ascii_only = false
    } else if value == 37 {
      needs_decoding = true
      if i + 2 < length {
        let high = old_hex_digit(source.unsafe_get(i + 1).to_int())
        let low = old_hex_digit(source.unsafe_get(i + 2).to_int())
        if high >= 8 && low >= 0 {
          high_byte = true
        }
      }
    } else if value == 43 && plus_as_space {
      needs_decoding = true
    }
    i = i + 1
  }
  if !needs_decoding {
    return source.to_owned()
  }
  if ascii_only && !high_byte {
    let builder = StringBuilder(size_hint=length)
    let mut i = 0
    while i < length {
      let value = source.unsafe_get(i).to_int()
      if value == 37 {
        if i + 2 < length {
          let high = old_hex_digit(source.unsafe_get(i + 1).to_int())
          let low = old_hex_digit(source.unsafe_get(i + 2).to_int())
          if high >= 0 && low >= 0 {
            builder.write_char((high * 16 + low).unsafe_to_char())
            i = i + 3
            continue
          }
        }
        builder.write_char('%')
        i = i + 1
      } else if value == 43 && plus_as_space {
        builder.write_char(' ')
        i = i + 1
      } else {
        let run_start = i
        i = i + 1
        while i < length {
          let next = source.unsafe_get(i).to_int()
          if next == 37 || (next == 43 && plus_as_space) {
            break
          }
          i = i + 1
        }
        builder.write_stringview(source[run_start:i])
      }
    }
    return builder.to_string()
  }
  let buffer = @buffer.Buffer::Buffer(size_hint=length)
  let mut i = 0
  if ascii_only {
    while i < length {
      let code = source.unsafe_get(i).to_int()
      if code == 37 && i + 2 < length {
        let high = old_hex_digit(source.unsafe_get(i + 1).to_int())
        let low = old_hex_digit(source.unsafe_get(i + 2).to_int())
        if high >= 0 && low >= 0 {
          buffer.write_byte((high * 16 + low).to_byte())
          i = i + 3
          continue
        }
        buffer.write_byte(code.to_byte())
      } else if code == 43 && plus_as_space {
        buffer.write_byte(b' ')
      } else {
        buffer.write_byte(code.to_byte())
      }
      i = i + 1
    }
  } else {
    let bytes = @utf8.encode(source)
    while i < bytes.length() {
      let byte = bytes[i]
      if byte == b'%' && i + 2 < bytes.length() {
        let high = old_hex_digit(bytes[i + 1].to_int())
        let low = old_hex_digit(bytes[i + 2].to_int())
        if high >= 0 && low >= 0 {
          buffer.write_byte((high * 16 + low).to_byte())
          i = i + 2
        } else {
          buffer.write_byte(byte)
        }
      } else if byte == b'+' && plus_as_space {
        buffer.write_byte(b' ')
      } else {
        buffer.write_byte(byte)
      }
      i = i + 1
    }
  }
  @utf8.decode_lossy(buffer.to_bytes())
}

///|
fn new_decode_url_bytes(bytes : BytesView, plus_as_space : Bool) -> String {
  let length = bytes.length()
  let out = FixedArray::make(length, b' ')
  let mut out_index = 0
  let mut i = 0
  while i < length {
    let byte = bytes[i].to_int()
    if byte == 37 && i + 2 < length {
      let high = old_hex_digit(bytes[i + 1].to_int())
      let low = old_hex_digit(bytes[i + 2].to_int())
      if high >= 0 && low >= 0 {
        out[out_index] = (high * 16 + low).to_byte()
        out_index = out_index + 1
        i = i + 3
        continue
      }
    } else if byte == 43 && plus_as_space {
      out[out_index] = b' '
      out_index = out_index + 1
      i = i + 1
      continue
    }
    out[out_index] = byte.to_byte()
    out_index = out_index + 1
    i = i + 1
  }
  let out_length = out_index
  @utf8.decode_lossy(Bytes::from_fixedarray(out, len=out_length))
}

///|
fn new_decode_url_impl(source : StringView, plus_as_space : Bool) -> String {
  let length = source.length()
  let mut ascii_only = true
  let mut needs_decoding = false
  let mut i = 0
  while i < length {
    let value = source.unsafe_get(i).to_int()
    if value > 127 {
      ascii_only = false
    } else if value == 37 || (value == 43 && plus_as_space) {
      needs_decoding = true
      break
    }
    i = i + 1
  }
  if !needs_decoding {
    return source.to_owned()
  }
  if !ascii_only {
    return new_decode_url_bytes(@utf8.encode(source), plus_as_space)
  }
  let out = FixedArray::make(length, b' ')
  let mut out_index = 0
  let mut j = 0
  while j < length {
    let code = source.unsafe_get(j).to_int()
    if code == 37 && j + 2 < length {
      let high = old_hex_digit(source.unsafe_get(j + 1).to_int())
      let low = old_hex_digit(source.unsafe_get(j + 2).to_int())
      if high >= 0 && low >= 0 {
        out[out_index] = (high * 16 + low).to_byte()
        out_index = out_index + 1
        j = j + 3
        continue
      }
    } else if code == 43 && plus_as_space {
      out[out_index] = b' '
      out_index = out_index + 1
      j = j + 1
      continue
    } else if code > 127 {
      return new_decode_url_bytes(@utf8.encode(source), plus_as_space)
    }
    out[out_index] = code.to_byte()
    out_index = out_index + 1
    j = j + 1
  }
  let out_length = out_index
  @utf8.decode_lossy(Bytes::from_fixedarray(out, len=out_length))
}

///|
fn fz2_hash(state : Array[Int], salt : Int) -> Int {
  state[0] = ((state[0].to_int64() * 48271L + 1L) % 2147483647L).to_int()
  (state[0] + salt) % 1000003
}

///|
fn fz2_char(state : Array[Int], alphabet : Array[Char]) -> Char {
  alphabet[fz2_hash(state, 0) % alphabet.length()]
}

///|
fn fz2_string(state : Array[Int], alphabet : Array[Char], max_length : Int) -> String {
  let builder = StringBuilder()
  let length = fz2_hash(state, 7) % (max_length + 1)
  for i = 0; i < length; i = i + 1 {
    builder.write_char(fz2_char(state, alphabet))
  }
  builder.to_string()
}

///|
fn fz2_fail(message : String) -> Unit {
  println(message)
  abort(message)
}

///|
fn fz2_lone() -> String {
  let builder = StringBuilder()
  builder.write_char((0xD800).unsafe_to_char())
  builder.write_char((0xDC00).unsafe_to_char())
  builder.to_string()
}

///|
test "tmp-url-fuzz" {
  let fixed : Array[String] = [
    "",
    "%",
    "%%",
    "%4",
    "%41",
    "%ZZ",
    "%zz",
    "a",
    "+",
    "a+b",
    "%20+%2B",
    "%C3%A9",
    "%E4%B8%96%E7%95%8C",
    "\u{4e16}",
    "\u{4e16}%20",
    "%20\u{4e16}",
    "a%20\u{4e16}b",
    "\u{4e16}a%20b",
    "%80",
    "%FF%FE",
    "%C3",
    "%E4%B8",
    "%00",
    "%0A",
    "a%2Fb%3Fc",
    fz2_lone(),
    "a" + fz2_lone() + "%20",
    "%20" + fz2_lone(),
    fz2_lone() + "%20",
    "%%41%",
    "%41%4",
    "hello%20world%21",
  ]
  for sample in fixed {
    for plus in [true, false] {
      let reference = old_decode_url_impl(sample.view(), plus)
      let got = new_decode_url_impl(sample.view(), plus)
      if reference != got {
        fz2_fail(
          "fixed mismatch plus=\{plus} sample=[\{sample}]: ref=[\{reference}] got=[\{got}]",
        )
      }
    }
  }
  let state : Array[Int] = [246813579]
  let alphabet : Array[Char] = [
    'a', 'z', '0', '9', '%', '+', ' ', '/', '?', '=', '&', 'F', 'f', 'C', '3',
    'E', '4', '\u{4e16}', '\u{e9}', '\u{20ac}', '\u{1F600}', '\u{fffd}', 'g',
  ]
  for round = 0; round < 4000; round = round + 1 {
    let sample = fz2_string(state, alphabet, 24)
    for plus in [true, false] {
      let reference = old_decode_url_impl(sample.view(), plus)
      let got = new_decode_url_impl(sample.view(), plus)
      if reference != got {
        fz2_fail(
          "mismatch plus=\{plus} sample=[\{sample}]: ref=[\{reference}] got=[\{got}]",
        )
      }
    }
    let via_public = url_decode(sample)
    let reference = old_decode_url_impl(sample.view(), true)
    if via_public != reference {
      fz2_fail(
        "public mismatch sample=[\{sample}]: ref=[\{reference}] got=[\{via_public}]",
      )
    }
    if !sample.contains("&") && !sample.contains(";") && !sample.contains("=") {
      let decoded_map = parse_urlencoded("v=" + sample)
      let expected = old_decode_url_impl(sample.view(), true)
      match decoded_map.get("v") {
        Some(value) =>
          if value != expected {
            fz2_fail(
              "urlencoded mismatch sample=[\{sample}]: ref=[\{expected}] got=[\{value}]",
            )
          }
        None => fz2_fail("urlencoded missing value for sample=[\{sample}]")
      }
    }
  }
  println("url fuzz done")
}
