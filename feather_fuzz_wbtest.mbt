///|
priv struct FuzzRng {
  mut state : Int64
}

///|
fn FuzzRng::new(seed : Int64) -> FuzzRng {
  { state: seed }
}

///|
fn FuzzRng::next(self : FuzzRng) -> Int {
  self.state = (self.state * 6364136223846793005L +
    1442695040888963407L) &
    9223372036854775807L
  ((self.state >> 16) % 1000003L).to_int()
}

///|
fn FuzzRng::below(self : FuzzRng, n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    self.next() % n
  }
}

///|
fn fuzz_pick(rng : FuzzRng, pool : Array[String]) -> String {
  pool[rng.below(pool.length())]
}

///|
fn fuzz_random_string(rng : FuzzRng, pool : Array[String], max_len : Int) -> String {
  let builder = StringBuilder()
  let count = rng.below(max_len + 1)
  for i = 0; i < count; i = i + 1 {
    builder.write_string(fuzz_pick(rng, pool))
  }
  builder.to_string()
}

///|
fn fuzz_random_segments(
  rng : FuzzRng,
  pool : Array[String],
  max_len : Int,
) -> Array[String] {
  let out : Array[String] = []
  let count = rng.below(max_len + 1)
  for i = 0; i < count; i = i + 1 {
    out.push(fuzz_pick(rng, pool))
  }
  out
}

///|
fn fuzz_join_segments(segments : Array[String], leading : Bool) -> String {
  let builder = StringBuilder()
  if leading {
    builder.write_char('/')
  }
  for i = 0; i < segments.length(); i = i + 1 {
    if i > 0 {
      builder.write_char('/')
    }
    builder.write_string(segments[i])
  }
  builder.to_string()
}

///|
fn fuzz_map_eq(a : Map[String, String], b : Map[String, String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for key, value in a {
    match b.get(key) {
      Some(other) => if value != other { return false }
      None => return false
    }
  }
  true
}

///|
fn fuzz_ref_match(
  pattern : String,
  path : Array[String],
) -> (Map[String, String], String, String)? {
  let patterns : Array[StringView] = []
  for segment in pattern.view().split("/") {
    if !segment.is_empty() {
      patterns.push(segment)
    }
  }
  let params : Map[String, String] = Map([], capacity=4)
  let mut wildcard_name = ""
  let mut wildcard_value = ""
  let mut pi = 0
  let mut si = 0
  while pi < patterns.length() {
    let segment = patterns[pi]
    if segment.has_prefix(":") {
      if si >= path.length() {
        return None
      }
      params.set(segment[1:].to_owned(), path[si])
      si = si + 1
    } else if segment.has_prefix("*") {
      wildcard_name = segment[1:].to_owned()
      let builder = StringBuilder()
      for i = si; i < path.length(); i = i + 1 {
        if i > si {
          builder.write_char('/')
        }
        builder.write_string(path[i])
      }
      wildcard_value = builder.to_string()
      if wildcard_name != "" {
        params.set(wildcard_name, wildcard_value)
      }
      si = path.length()
      break
    } else {
      if si >= path.length() || path[si] != segment.to_owned() {
        return None
      }
      si = si + 1
    }
    pi = pi + 1
  }
  if si != path.length() {
    return None
  }
  Some((params, wildcard_value, wildcard_name))
}

///|
test "fuzz router dispatch matches reference matcher" {
  let rng = FuzzRng::new(20261016L)
  let tails : Array[String] = [
    "", "/:p", "/:p/:q", "/s/:p", "/s/*w", "/*w", "/:p/*w", "/:z", "/s/*",
  ]
  let routes : Array[(String, String)] = []
  let route_count = 12
  for i = 0; i < route_count; i = i + 1 {
    let meth = if i % 2 == 0 { "GET" } else { "POST" }
    let pattern = "/r" +
      i.to_string() +
      tails[rng.below(tails.length())]
    routes.push((meth, pattern))
  }
  let router = create_router()
  for route in routes {
    let (meth, pattern) = route
    router.add_route(meth, pattern, fn(ctx) { ctx.text(200, "ok") })
  }
  let segment_pool : Array[String] = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9", "r10", "r11", "s", "x", "y", "z", "1", "a"]
  let iterations = 3000
  for iter = 0; iter < iterations; iter = iter + 1 {
    let segments = fuzz_random_segments(rng, segment_pool, 4)
    let path = fuzz_join_segments(segments, true)
    let meth = fuzz_pick(rng, ["GET", "POST", "PUT"])
    let expected = {
      let mut found : (Map[String, String], String, String)? = None
      for route in routes {
        let (route_meth, pattern) = route
        if route_meth == meth {
          let m = fuzz_ref_match(pattern, segments)
          if m is Some(_) {
            found = m
            break
          }
        }
      }
      found
    }
    let expected_allowed = {
      let allowed : Array[String] = []
      for route in routes {
        let (route_meth, pattern) = route
        if fuzz_ref_match(pattern, segments) is Some(_) {
          let mut seen = false
          for existing in allowed {
            if existing == route_meth {
              seen = true
            }
          }
          if !seen {
            allowed.push(route_meth)
          }
        }
      }
      allowed
    }
    // route() must agree with the reference matcher.
    match router.route(meth, path) {
      RouteFound(found) =>
        match expected {
          Some((params, wildcard, wildcard_name)) => {
            if !fuzz_map_eq(found.params, params) {
              fail(
                "route params mismatch for \{meth} \{path}: \{found.params} vs \{params}",
              )
            }
            assert_eq(found.wildcard, wildcard)
            assert_eq(found.wildcard_name, wildcard_name)
          }
          None =>
            fail("route unexpectedly matched \{meth} \{path} -> \{found.path}")
        }
      RouteMethodNotAllowed(_) =>
        if expected is Some(_) {
          fail("route reported 405 for \{meth} \{path}")
        }
      RouteNotFound =>
        if expected is Some(_) {
          fail("route missed \{meth} \{path}")
        }
    }
    // dispatch() must agree with route().
    let ctx = Context::new({
      method: meth,
      path,
      headers: Map([]),
      body: "",
    })
    router.dispatch(ctx)
    let response = ctx.response
    match expected {
      Some((params, _, _)) => {
        assert_eq(response.status, 200)
        if !fuzz_map_eq(ctx.params(), params) {
          fail(
            "dispatch params mismatch for \{meth} \{path}: \{ctx.params()} vs \{params}",
          )
        }
        for key, value in params {
          assert_eq(ctx.param(key), value)
        }
      }
      None =>
        if expected_allowed.length() > 0 {
          if response.status != 405 {
            fail(
              "dispatch expected 405 for \{meth} \{path}, got \{response.status}",
            )
          }
        } else if response.status != 404 {
          fail(
            "dispatch expected 404 for \{meth} \{path}, got \{response.status}",
          )
        }
    }
  }
}

///|
test "fuzz format and parse http date round trip" {
  let rng = FuzzRng::new(77L)
  let cases : Array[Int64] = [0L, 1L, 951782400L, 4102444800L, 253402300799L]
  for value in cases {
    let formatted = format_http_date(value)
    assert_eq(parse_http_date(formatted), Some(value))
  }
  for iter = 0; iter < 4000; iter = iter + 1 {
    let value = (rng.next().to_int64() * 65536L) % 253402300799L
    let value = if value < 0L { -value } else { value }
    let formatted = format_http_date(value)
    match parse_http_date(formatted) {
      Some(parsed) =>
        if parsed != value {
          fail(
            "date round trip failed for \{value}: \{formatted} -> \{parsed}",
          )
        }
      None => fail("date round trip failed to parse \{formatted}")
    }
  }
}

///|
test "fuzz url encode decode round trip" {
  let rng = FuzzRng::new(4242L)
  let pool : Array[String] = [
    "a", "Z", "0", "-", ".", "_", "~", " ", "%", "+", "/", "?", "&", "=", "#",
    "中", "世", "é", "😀", ":p", "*w",
  ]
  for iter = 0; iter < 4000; iter = iter + 1 {
    let value = fuzz_random_string(rng, pool, 8)
    let encoded = url_encode(value)
    let decoded = url_decode(encoded)
    if decoded != value {
      fail("url round trip failed: \{value} -> \{encoded} -> \{decoded}")
    }
  }
}

///|
fn fuzz_make_multipart(
  boundary : String,
  parts : Array[(String, String)],
  nl : String,
  preamble : String,
) -> String {
  let builder = StringBuilder()
  builder.write_string(preamble)
  for part in parts {
    let (name, data) = part
    builder.write_string("--")
    builder.write_string(boundary)
    builder.write_string(nl)
    builder.write_string("Content-Disposition: form-data; name=\"")
    builder.write_string(name)
    builder.write_string("\"")
    builder.write_string(nl)
    builder.write_string(nl)
    builder.write_string(data)
    builder.write_string(nl)
  }
  builder.write_string("--")
  builder.write_string(boundary)
  builder.write_string("--")
  builder.write_string(nl)
  builder.to_string()
}

///|
test "fuzz multipart parse round trip" {
  let rng = FuzzRng::new(999L)
  let pools : Array[Array[String]] = [
    ["a", "b", "1", "2", " ", ":", "="],
    ["x", "+", ".", "u", "-", "_"],
    ["中", "文", "é"],
    ["!", "@", "$", "^"],
  ]
  for iter = 0; iter < 1500; iter = iter + 1 {
    let boundary = "B" + rng.next().to_string()
    let nl = if iter % 2 == 0 { "\r\n" } else { "\n" }
    let parts : Array[(String, String)] = []
    let count = rng.below(4)
    for i = 0; i < count; i = i + 1 {
      let name = "field" + i.to_string()
      let data = fuzz_random_string(rng, pools[rng.below(pools.length())], 10)
      parts.push((name, data))
    }
    let preamble = if iter % 7 == 0 { "preamble" + nl } else { "" }
    let body = fuzz_make_multipart(boundary, parts, nl, preamble)
    let content_type = "multipart/form-data; boundary=" + boundary
    match parse_multipart(body, content_type) {
      Some(parsed) => {
        if parsed.length() != parts.length() {
          fail(
            "multipart part count mismatch: \{parsed.length()} vs \{parts.length()} for \{body}",
          )
        }
        for i = 0; i < parts.length(); i = i + 1 {
          let (name, data) = parts[i]
          if parsed[i].name != name || parsed[i].data != data {
            fail(
              "multipart part mismatch at \{i}: (\{parsed[i].name}, \{parsed[i].data}) vs (\{name}, \{data})",
            )
          }
        }
      }
      None => fail("multipart parse returned None for \{body}")
    }
  }
}
