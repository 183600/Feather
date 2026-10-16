///|
fn zz_rand(state : Ref[Int]) -> Int {
  state.val = (state.val * 31 + 7) % 1000003
  state.val
}

///|
fn zz_rand_char(state : Ref[Int]) -> Char {
  let chars = [
    'a', 'Z', '0', ' ', '/', '+', '%', '?', '&', '=', '#', '.', '\\', '世', '-',
    '_', '~', ';', ':',
  ]
  chars[zz_rand(state) % chars.length()]
}

///|
test "zz-fuzz-roundtrip" {
  let state = Ref(42)
  let mut failures = 0
  for i = 0; i < 300; i = i + 1 {
    let mut s = ""
    let len = zz_rand(state) % 8
    for j = 0; j < len; j = j + 1 {
      s = s + zz_rand_char(state).to_string()
    }
    let encoded = @feather.url_encode(s)
    let decoded = @feather.url_decode(encoded)
    if decoded != s {
      failures = failures + 1
    }
  }
  assert_eq(failures, 0)
}

///|
test "zz-fuzz-static-escape" {
  let state = Ref(7)
  let app = @feather.App::new().static_files("/s", "/root")
  let mut failures = 0
  for i = 0; i < 300; i = i + 1 {
    let mut s = ""
    let len = zz_rand(state) % 6
    for j = 0; j < len; j = j + 1 {
      s = s + zz_rand_char(state).to_string()
    }
    let encoded = @feather.url_encode(s)
    let path = "/s/" + encoded
    match app.static_file_for(path) {
      Some(file) =>
        if !(file == "/root" || file.has_prefix("/root/")) {
          failures = failures + 1
        }
      None => ()
    }
  }
  assert_eq(failures, 0)
}

///|
test "zz-fuzz-param-roundtrip" {
  let state = Ref(99)
  let router = @feather.create_router()
  router.add_named_route("p", "GET", "/p/:v", fn(ctx) { ctx.text(200, "x") })
  let mut failures = 0
  for i = 0; i < 300; i = i + 1 {
    let mut s = ""
    let len = zz_rand(state) % 6
    for j = 0; j < len; j = j + 1 {
      s = s + zz_rand_char(state).to_string()
    }
    if s.contains("/") {
      continue
    }
    match router.url_for("p", params={ "v": s }) {
      Some(url) =>
        match router.route("GET", url) {
          @feather.RouteFound(route) =>
            match route.params.get("v") {
              Some(v) =>
                if @feather.url_decode(v) != s {
                  failures = failures + 1
                }
              None => failures = failures + 1
            }
          _ => failures = failures + 1
        }
      None => ()
    }
  }
  assert_eq(failures, 0)
}

///|
test "zz-fuzz-form-roundtrip" {
  let state = Ref(1234)
  let mut failures = 0
  for i = 0; i < 200; i = i + 1 {
    let mut s = ""
    let len = zz_rand(state) % 6
    for j = 0; j < len; j = j + 1 {
      s = s + zz_rand_char(state).to_string()
    }
    if s.contains("&") || s.contains("=") {
      continue
    }
    let body = "k=" + @feather.url_encode(s)
    let decoded = @feather.parse_urlencoded(body).get("k").unwrap_or("<missing>")
    if decoded != s {
      failures = failures + 1
    }
  }
  assert_eq(failures, 0)
}

///|
test "zz-fuzz-multipart" {
  let state = Ref(555)
  let mut failures = 0
  for i = 0; i < 100; i = i + 1 {
    let mut value = ""
    let len = zz_rand(state) % 6
    for j = 0; j < len; j = j + 1 {
      let c = zz_rand_char(state)
      if c != '\u{0}' && c != '\\' && c != '\r' && c != '\n' {
        value = value + c.to_string()
      }
    }
    let body = "--B\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n" +
      value +
      "\r\n--B--\r\n"
    let parts = @feather
      .parse_multipart(body, "multipart/form-data; boundary=B")
      .unwrap()
    if parts.length() != 1 || parts[0].data != value || parts[0].name != "a" {
      failures = failures + 1
    }
  }
  assert_eq(failures, 0)
}
