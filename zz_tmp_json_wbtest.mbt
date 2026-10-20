///|
test "tmp json text differential" {
  let values : Array[String] = [
    "", "plain", "a\"b", "a\\b", "line\nbreak", "tab\there", "nul\u{0}", "unit\u{1}",
    "bell\u{7}", "del\u{7f}", "报告", "😀", "slash/a", "ctrl\u{1f}",
  ]
  let keys : Array[String] = ["k", "", "a\"b", "ctl\u{1}\u{2}", "报告"]
  for k in keys {
    for v in values {
      let data : Map[String, String] = Map([(k, v)])
      let ctx = Context::new({
        method: "GET",
        path: "/",
        headers: Map([]),
        body: "",
      })
      ctx.json(200, data)
      let expected = json_object(data).stringify()
      if ctx.response.body != expected {
        fail(
          "mismatch key=\{k} value=\{v}: \{ctx.response.body} vs \{expected}",
        )
      }
    }
  }
  let multi : Map[String, String] = Map([("a", "1"), ("b", "2"), ("c", "3")])
  let ctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  ctx.json(200, multi)
  assert_eq(ctx.response.body, json_object(multi).stringify())
}

///|
test "tmp json random differential" {
  let alphabet : Array[String] = [
    "a", "Z", "\"", "\\", "/", "\n", "\r", "\t", "\b", "\u{000b}", "\u{000c}", "\u{0000}",
    "\u{0001}", "\u{001f}", "\u{007f}", "\u{0080}", "\u{00e9}", "\u{2028}", "\u{2029}",
    "报", "😀",
  ]
  let mut seed = 987654321
  let next = fn() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    seed
  }
  for _ in 0..<20000 {
    let key_len = next() % 6
    let value_len = next() % 8
    let key_builder = StringBuilder::new()
    for _ in 0..<key_len {
      key_builder.write_string(alphabet[next() % alphabet.length()])
    }
    let value_builder = StringBuilder::new()
    for _ in 0..<value_len {
      value_builder.write_string(alphabet[next() % alphabet.length()])
    }
    let key = key_builder.to_string()
    let value = value_builder.to_string()
    let data : Map[String, String] = Map([(key, value)])
    let ctx = Context::new({
      method: "GET",
      path: "/",
      headers: Map([]),
      body: "",
    })
    ctx.json(200, data)
    let expected = json_object(data).stringify()
    if ctx.response.body != expected {
      fail(
        "mismatch key=\{key} value=\{value}: \{ctx.response.body} vs \{expected}",
      )
    }
  }
}
