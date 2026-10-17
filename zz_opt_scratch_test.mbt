///|
fn opt_ctx_new(cap_headers : Int, cap_state : Int, cap_json : Int) -> Context {
  {
    request: {
      method: "GET",
      path: "/api/users",
      headers: Map([("Accept", "application/json")]),
      body: "",
    },
    response: {
      status: 200,
      headers: Map([], capacity=cap_headers),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map([], capacity=cap_state),
    json_state: Map([], capacity=cap_json),
    cleanups: [],
    file: None,
    session: None,
  }
}

///|
let opt_unreserved_table : FixedArray[Bool] = {
  let table : FixedArray[Bool] = FixedArray::make(128, false)
  for code = 0; code < 128; code = code + 1 {
    if (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 45 ||
      code == 46 ||
      code == 95 ||
      code == 126 {
      table[code] = true
    }
  }
  table
}

///|
fn opt_is_url_unreserved(value : Int32) -> Bool {
  value < 128 && opt_unreserved_table[value]
}

///|
fn opt_hex_byte(value : Int) -> Byte {
  if value < 10 {
    (b'0'.to_int() + value).to_byte()
  } else {
    (b'A'.to_int() + (value - 10)).to_byte()
  }
}

///|
fn opt_percent_to(out : FixedArray[Byte], offset : Int, value : Int) -> Unit {
  out[offset] = b'%'
  out[offset + 1] = opt_hex_byte(value / 16)
  out[offset + 2] = opt_hex_byte(value % 16)
}

///|
fn opt_url_encode(source : String) -> String {
  let view = source.view()
  let length = view.length()
  let mut start = 0
  while start < length && opt_is_url_unreserved(view.unsafe_get(start).to_int()) {
    start = start + 1
  }
  if start == length {
    return source
  }
  let mut out_len = start
  let mut i = start
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code < 0x80 {
      out_len = out_len + (if opt_is_url_unreserved(code) { 1 } else { 3 })
    } else if code < 0x800 {
      out_len = out_len + 6
    } else if code >= 0xD800 && code <= 0xDBFF && i + 1 < length {
      let low = view.unsafe_get(i + 1).to_int()
      if low >= 0xDC00 && low <= 0xDFFF {
        out_len = out_len + 12
        i = i + 2
        continue
      }
      out_len = out_len + 9
    } else {
      out_len = out_len + 9
    }
    i = i + 1
  }
  let out = FixedArray::make(out_len, b' ')
  let mut p = 0
  while p < start {
    out[p] = view.unsafe_get(p).to_int().to_byte()
    p = p + 1
  }
  let mut out_index = start
  let mut j = start
  while j < length {
    let code = view.unsafe_get(j).to_int()
    if code < 0x80 {
      if opt_is_url_unreserved(code) {
        out[out_index] = code.to_byte()
        out_index = out_index + 1
      } else {
        opt_percent_to(out, out_index, code)
        out_index = out_index + 3
      }
    } else if code < 0x800 {
      opt_percent_to(out, out_index, 0xC0 | (code >> 6))
      opt_percent_to(out, out_index + 3, 0x80 | (code & 0x3F))
      out_index = out_index + 6
    } else if code >= 0xD800 && code <= 0xDBFF {
      if j + 1 < length {
        let low = view.unsafe_get(j + 1).to_int()
        if low >= 0xDC00 && low <= 0xDFFF {
          let scalar = ((code - 0xD800) << 10) + (low - 0xDC00) + 0x10000
          opt_percent_to(out, out_index, 0xF0 | (scalar >> 18))
          opt_percent_to(out, out_index + 3, 0x80 | ((scalar >> 12) & 0x3F))
          opt_percent_to(out, out_index + 6, 0x80 | ((scalar >> 6) & 0x3F))
          opt_percent_to(out, out_index + 9, 0x80 | (scalar & 0x3F))
          out_index = out_index + 12
          j = j + 2
          continue
        }
      }
      opt_percent_to(out, out_index, 0xEF)
      opt_percent_to(out, out_index + 3, 0xBF)
      opt_percent_to(out, out_index + 6, 0xBD)
      out_index = out_index + 9
    } else if code >= 0xDC00 && code <= 0xDFFF {
      opt_percent_to(out, out_index, 0xEF)
      opt_percent_to(out, out_index + 3, 0xBF)
      opt_percent_to(out, out_index + 6, 0xBD)
      out_index = out_index + 9
    } else {
      opt_percent_to(out, out_index, 0xE0 | (code >> 12))
      opt_percent_to(out, out_index + 3, 0x80 | ((code >> 6) & 0x3F))
      opt_percent_to(out, out_index + 6, 0x80 | (code & 0x3F))
      out_index = out_index + 9
    }
    j = j + 1
  }
  @utf8.decode_lossy(Bytes::from_array(out[:out_index]))
}

///|
test "opt-ctx-new-c4" (b : @bench.T) {
  b.bench(() => {
    b.keep(opt_ctx_new(4, 4, 0))
  })
}

///|
test "opt-ctx-new-c2" (b : @bench.T) {
  b.bench(() => {
    b.keep(opt_ctx_new(2, 2, 0))
  })
}

///|
test "opt-ctx-new-c0" (b : @bench.T) {
  b.bench(() => {
    b.keep(opt_ctx_new(0, 0, 0))
  })
}

///|
test "opt-url-encode-table" (b : @bench.T) {
  let source = "hello world/foo bar?baz=qux&name=\u{4e16}\u{754c}"
  b.bench(() => {
    b.keep(opt_url_encode(source))
  })
}

///|
test "opt-url-encode-current" (b : @bench.T) {
  let source = "hello world/foo bar?baz=qux&name=\u{4e16}\u{754c}"
  b.bench(() => {
    b.keep(url_encode(source))
  })
}

///|
test "opt-cookie-copy" (b : @bench.T) {
  let ctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      (
        "Cookie",
        "session=abcdef123456; theme=dark; lang=en-US; tracking=xyz987654321",
      ),
    ]),
    body: "",
  })
  b.bench(() => {
    b.keep(ctx.cookies())
  })
}
