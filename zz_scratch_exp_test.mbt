///|
fn scratch_time_exp(name : String, iterations : Int, f : () -> Unit) -> Unit {
  for i = 0; i < 200; i = i + 1 {
    f()
  }
  let start = @async.now()
  for i = 0; i < iterations; i = i + 1 {
    f()
  }
  let elapsed = @async.now() - start
  let per_op = elapsed.to_double() * 1000000.0 / iterations.to_double()
  println("\{name}: \{per_op} ns/op")
}

///|
let exp_b64_table : Bytes = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
fn exp_base64_encode_buf(data : Bytes) -> String {
  let length = data.length()
  if length == 0 {
    return ""
  }
  let table = exp_b64_table
  let buf = @buffer.Buffer::Buffer(size_hint=(length + 2) / 3 * 4)
  let mut i = 0
  while i + 3 <= length {
    let value = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    buf.write_byte(table[(value >> 18) & 63])
    buf.write_byte(table[(value >> 12) & 63])
    buf.write_byte(table[(value >> 6) & 63])
    buf.write_byte(table[value & 63])
    i = i + 3
  }
  let remaining = length - i
  if remaining == 1 {
    let value = data[i].to_int() << 16
    buf.write_byte(table[(value >> 18) & 63])
    buf.write_byte(table[(value >> 12) & 63])
    buf.write_byte(b'=')
    buf.write_byte(b'=')
  } else if remaining == 2 {
    let value = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8)
    buf.write_byte(table[(value >> 18) & 63])
    buf.write_byte(table[(value >> 12) & 63])
    buf.write_byte(table[(value >> 6) & 63])
    buf.write_byte(b'=')
  }
  @utf8.decode_lossy(buf.to_bytes())
}

///|
fn exp_base64_encode_bytes(data : Bytes) -> String {
  let length = data.length()
  if length == 0 {
    return ""
  }
  let table = exp_b64_table
  let out_length = (length + 2) / 3 * 4
  let out = FixedArray::make(out_length, b'=')
  let mut i = 0
  let mut o = 0
  while i + 3 <= length {
    let value = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    out[o] = table[(value >> 18) & 63]
    out[o + 1] = table[(value >> 12) & 63]
    out[o + 2] = table[(value >> 6) & 63]
    out[o + 3] = table[value & 63]
    i = i + 3
    o = o + 4
  }
  let remaining = length - i
  if remaining == 1 {
    let value = data[i].to_int() << 16
    out[o] = table[(value >> 18) & 63]
    out[o + 1] = table[(value >> 12) & 63]
  } else if remaining == 2 {
    let value = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8)
    out[o] = table[(value >> 18) & 63]
    out[o + 1] = table[(value >> 12) & 63]
    out[o + 2] = table[(value >> 6) & 63]
  }
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes())
}

///|
let exp_weekdays : Array[String] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

///|
let exp_months : Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

///|
fn exp_write_two_digits(builder : StringBuilder, value : Int) -> Unit {
  if value < 10 {
    builder.write_char((48 + value).unsafe_to_char())
  } else {
    builder.write_char((48 + value / 10).unsafe_to_char())
    builder.write_char((48 + value % 10).unsafe_to_char())
  }
  ignore(value)
}

///|
fn exp_write_year(builder : StringBuilder, year : Int64) -> Unit {
  let value = year.to_int()
  builder.write_char((48 + value / 1000).unsafe_to_char())
  builder.write_char((48 + value / 100 % 10).unsafe_to_char())
  builder.write_char((48 + value / 10 % 10).unsafe_to_char())
  builder.write_char((48 + value % 10).unsafe_to_char())
}

///|
fn exp_date_builder2(builder : StringBuilder, unix_seconds : Int64) -> Unit {
  let mut days = unix_seconds / 86400L
  let mut time_of_day = unix_seconds - days * 86400L
  if time_of_day < 0L {
    days = days - 1L
    time_of_day = time_of_day + 86400L
  }
  let z = days.to_int() + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let day = doy - (153 * mp + 2) / 5 + 1
  let month = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = if month <= 2 { y + 1 } else { y }
  let mut weekday = (days + 4L) % 7L
  if weekday < 0L {
    weekday = weekday + 7L
  }
  let tod = time_of_day.to_int()
  let hour = tod / 3600
  let minute = tod % 3600 / 60
  let second = tod % 60
  builder.write_string(exp_weekdays[weekday.to_int()])
  builder.write_string(", ")
  exp_write_two_digits(builder, day)
  builder.write_char(' ')
  builder.write_string(exp_months[month - 1])
  builder.write_char(' ')
  exp_write_year(builder, year.to_int64())
  builder.write_char(' ')
  exp_write_two_digits(builder, hour)
  builder.write_char(':')
  exp_write_two_digits(builder, minute)
  builder.write_char(':')
  exp_write_two_digits(builder, second)
  builder.write_string(" GMT")
}

///|
fn exp_format_date(builder : StringBuilder, unix_seconds : Int64) -> String {
  exp_date_builder2(builder, unix_seconds)
  builder.to_string()
}

///|
test "scratch-experiments" {
  let data = @utf8.encode("hello world, this is a test payload for base64")
  let expect = base64_encode(data)
  println("b64 builder = \{expect}")
  println("b64 bytes   = \{exp_base64_encode_bytes(data)}")
  println("b64 buf     = \{exp_base64_encode_buf(data)}")
  scratch_time_exp("b64-current", 1000000, fn() {
    ignore(base64_encode(data))
  })
  scratch_time_exp("b64-buffer", 1000000, fn() {
    ignore(exp_base64_encode_buf(data))
  })
  scratch_time_exp("b64-bytes", 1000000, fn() {
    ignore(exp_base64_encode_bytes(data))
  })
  scratch_time_exp("date-current", 500000, fn() {
    ignore(format_http_date(1750000000L))
  })
  scratch_time_exp("date-builder-reuse", 500000, fn() {
    let sb = StringBuilder(size_hint=29)
    ignore(exp_format_date(sb, 1750000000L))
  })
  scratch_time_exp("date-bytes", 500000, fn() {
    ignore(exp_format_date_bytes(1750000000L))
  })
  scratch_time_exp("url-enc-current", 1000000, fn() {
    ignore(url_encode("hello world/foo bar?baz=qux&name=\u{4e16}\u{754c}"))
  })
  scratch_time_exp("url-enc-bytes", 1000000, fn() {
    ignore(exp_url_encode("hello world/foo bar?baz=qux&name=\u{4e16}\u{754c}"))
  })
  scratch_time_exp("url-dec-current", 1000000, fn() {
    ignore(url_decode("name=%E4%B8%96%E7%95%8C+test%20foo%2Fbar&x=1"))
  })
  scratch_time_exp("url-dec-bytes", 1000000, fn() {
    ignore(exp_url_decode("name=%E4%B8%96%E7%95%8C+test%20foo%2Fbar&x=1"))
  })
  let hctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  scratch_time_exp("handler-text", 1000000, fn() {
    hctx.text(200, "hello")
  })
  scratch_time_exp("handler-json-empty", 1000000, fn() {
    hctx.json_value(200, Json::object(Map([])))
  })
  let json_app = App::new()
  ignore(json_app.get("/api/users", fn(ctx) { ctx.json_value(200, Json::object(Map([]))) }))
  let jreq : Request = {
    method: "GET",
    path: "/api/users",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  ignore(json_app.respond(jreq))
  scratch_time_exp("respond-json-1route", 200000, fn() {
    ignore(json_app.respond(jreq))
  })
  scratch_time_exp("json-empty-obj-alloc", 1000000, fn() {
    ignore(Json::object(Map([])))
  })
  let empty_obj = Json::object(Map([]))
  scratch_time_exp("json-empty-stringify", 1000000, fn() {
    ignore(empty_obj.stringify())
  })
  scratch_time_exp("json-empty-fast", 1000000, fn() {
    ignore("{}")
  })
  let two_map : Map[String, Json] = Map([("a", Json::number(1.0)), ("b", Json::string("x"))])
  let two_obj = Json::object(two_map)
  scratch_time_exp("json-two-stringify", 1000000, fn() {
    ignore(two_obj.stringify())
  })
  scratch_time_exp("map-default-alloc", 1000000, fn() {
    let m : Map[String, String] = Map([])
    m.set("a", "b")
    ignore(m)
  })
  scratch_time_exp("map-cap4-alloc", 1000000, fn() {
    let m : Map[String, String] = Map([], capacity=4)
    m.set("a", "b")
    ignore(m)
  })
  scratch_time_exp("map-cap0-alloc", 1000000, fn() {
    let m : Map[String, String] = Map([], capacity=0)
    m.set("a", "b")
    ignore(m)
  })
  scratch_time_exp("map-cap1-alloc", 1000000, fn() {
    let m : Map[String, String] = Map([], capacity=1)
    m.set("a", "b")
    ignore(m)
  })
}

///|
fn exp_is_unreserved(value : Int32) -> Bool {
  (value >= 48 && value <= 57) ||
  (value >= 65 && value <= 90) ||
  (value >= 97 && value <= 122) ||
  value == 45 ||
  value == 46 ||
  value == 95 ||
  value == 126
}

///|
let exp_hex : Bytes = b"0123456789ABCDEF"

///|
fn exp_url_encode(source : String) -> String {
  let view = source.view()
  let length = view.length()
  let mut start = 0
  while start < length && exp_is_unreserved(view.unsafe_get(start).to_int()) {
    start = start + 1
  }
  if start == length {
    return source
  }
  let buf = @buffer.Buffer::Buffer(size_hint=length + 8)
  let mut p = 0
  while p < start {
    buf.write_byte(view.unsafe_get(p).to_int().to_byte())
    p = p + 1
  }
  let mut i = start
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code < 0x80 {
      if exp_is_unreserved(code) {
        buf.write_byte(code.to_byte())
      } else {
        buf.write_byte(b'%')
        buf.write_byte(exp_hex[code / 16])
        buf.write_byte(exp_hex[code % 16])
      }
    } else if code < 0x800 {
      buf.write_byte(b'%')
      buf.write_byte(exp_hex[(0xC0 | (code >> 6)) / 16])
      buf.write_byte(exp_hex[(0xC0 | (code >> 6)) % 16])
      buf.write_byte(b'%')
      buf.write_byte(exp_hex[(0x80 | (code & 0x3F)) / 16])
      buf.write_byte(exp_hex[(0x80 | (code & 0x3F)) % 16])
    } else if code >= 0xD800 && code <= 0xDBFF {
      if i + 1 < length {
        let low = view.unsafe_get(i + 1).to_int()
        if low >= 0xDC00 && low <= 0xDFFF {
          let scalar = ((code - 0xD800) << 10) + (low - 0xDC00) + 0x10000
          for shift in [18, 12, 6, 0] {
            let v = if shift == 18 { 0xF0 | (scalar >> 18) } else { 0x80 | ((scalar >> shift) & 0x3F) }
            buf.write_byte(b'%')
            buf.write_byte(exp_hex[v / 16])
            buf.write_byte(exp_hex[v % 16])
          }
          i = i + 2
          continue
        }
      }
      for v in [0xEF, 0xBF, 0xBD] {
        buf.write_byte(b'%')
        buf.write_byte(exp_hex[v / 16])
        buf.write_byte(exp_hex[v % 16])
      }
    } else if code >= 0xDC00 && code <= 0xDFFF {
      for v in [0xEF, 0xBF, 0xBD] {
        buf.write_byte(b'%')
        buf.write_byte(exp_hex[v / 16])
        buf.write_byte(exp_hex[v % 16])
      }
    } else {
      for shift in [12, 6, 0] {
        let v = if shift == 12 { 0xE0 | (code >> 12) } else { 0x80 | ((code >> shift) & 0x3F) }
        buf.write_byte(b'%')
        buf.write_byte(exp_hex[v / 16])
        buf.write_byte(exp_hex[v % 16])
      }
    }
    i = i + 1
  }
  @utf8.decode_lossy(buf.to_bytes())
}

///|
fn exp_hex_digit(value : Int) -> Int {
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
fn exp_url_decode(source : String) -> String {
  let view = source.view()
  let length = view.length()
  let buf = @buffer.Buffer::Buffer(size_hint=length)
  let mut i = 0
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code == 37 && i + 2 < length {
      let high = exp_hex_digit(view.unsafe_get(i + 1).to_int())
      let low = exp_hex_digit(view.unsafe_get(i + 2).to_int())
      if high >= 0 && low >= 0 {
        buf.write_byte((high * 16 + low).to_byte())
        i = i + 3
        continue
      }
      buf.write_byte(code.to_byte())
    } else if code == 43 {
      buf.write_byte(b' ')
    } else if code < 0x100 {
      buf.write_byte(code.to_byte())
    } else {
      buf.write_string(view[i:i + 1].to_owned())
    }
    i = i + 1
  }
  @utf8.decode_lossy(buf.to_bytes())
}

///|
fn exp_format_date_bytes(unix_seconds : Int64) -> String {
  let out = FixedArray::make(29, b' ')
  let mut days = unix_seconds / 86400L
  let mut time_of_day = unix_seconds - days * 86400L
  if time_of_day < 0L {
    days = days - 1L
    time_of_day = time_of_day + 86400L
  }
  let z = days.to_int() + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let day = doy - (153 * mp + 2) / 5 + 1
  let month = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = if month <= 2 { y + 1 } else { y }
  let mut weekday = (days + 4L) % 7L
  if weekday < 0L {
    weekday = weekday + 7L
  }
  let tod = time_of_day.to_int()
  let hour = tod / 3600
  let minute = tod % 3600 / 60
  let second = tod % 60
  let day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  let month_names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  let dn = day_names[weekday.to_int()]
  out[0] = dn.view().unsafe_get(0).to_int().to_byte()
  out[1] = dn.view().unsafe_get(1).to_int().to_byte()
  out[2] = dn.view().unsafe_get(2).to_int().to_byte()
  out[3] = b','
  out[4] = b' '
  out[5] = (48 + day / 10).to_byte()
  out[6] = (48 + day % 10).to_byte()
  out[7] = b' '
  let mn = month_names[month - 1]
  out[8] = mn.view().unsafe_get(0).to_int().to_byte()
  out[9] = mn.view().unsafe_get(1).to_int().to_byte()
  out[10] = mn.view().unsafe_get(2).to_int().to_byte()
  out[11] = b' '
  out[12] = (48 + year / 1000).to_byte()
  out[13] = (48 + year / 100 % 10).to_byte()
  out[14] = (48 + year / 10 % 10).to_byte()
  out[15] = (48 + year % 10).to_byte()
  out[16] = b' '
  out[17] = (48 + hour / 10).to_byte()
  out[18] = (48 + hour % 10).to_byte()
  out[19] = b':'
  out[20] = (48 + minute / 10).to_byte()
  out[21] = (48 + minute % 10).to_byte()
  out[22] = b':'
  out[23] = (48 + second / 10).to_byte()
  out[24] = (48 + second % 10).to_byte()
  out[25] = b' '
  out[26] = b'G'
  out[27] = b'M'
  out[28] = b'T'
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes())
}
