///|
fn probe_request(method : String, headers : Map[String, String]) -> @feather.Request {
  { method, path: "/data", headers, body: "" }
}

///|
async test "probe range compression edge cases" {
  let body = "0123456789".repeat(64)
  let app = @feather.App::new().compress(min_size=0).get("/data", fn(ctx) {
    ctx.text(200, body)
  })
  let cases : Array[(String, Map[String, String])] = [
    ("malformed", Map([("Range", "garbage"), ("Accept-Encoding", "gzip")])),
    (
      "multi",
      Map([("Range", "bytes=0-1,3-4"), ("Accept-Encoding", "gzip")]),
    ),
    (
      "unsatisfiable",
      Map([("Range", "bytes=9999-"), ("Accept-Encoding", "gzip")]),
    ),
    (
      "if-range-mismatch",
      Map([
        ("Range", "bytes=4-6"),
        ("If-Range", "\"stale\""),
        ("Accept-Encoding", "gzip"),
      ]),
    ),
    (
      "head-range",
      Map([("Range", "bytes=4-6"), ("Accept-Encoding", "gzip")]),
    ),
  ]
  for entry in cases {
    let (name, headers) = entry
    let response = app.respond_async({
      method: if name == "head-range" { "HEAD" } else { "GET" },
      path: "/data",
      headers,
      body: "",
    })
    println(
      "async \{name}: status=\{response.status} ce=\{response.headers.get("Content-Encoding")} cr=\{response.headers.get("Content-Range")} len=\{response.body.length()}",
    )
  }
}

///|
test "probe offline identity refusal with buffered range" {
  let app = @feather.App::new().get("/data", fn(ctx) {
    ctx.text(200, "0123456789".repeat(64))
  })
  let response = app.respond(
    probe_request("GET", Map([
      ("Range", "bytes=4-6"),
      ("Accept-Encoding", "gzip, identity;q=0"),
    ])),
  )
  println(
    "offline refusal: status=\{response.status} ce=\{response.headers.get("Content-Encoding")} cr=\{response.headers.get("Content-Range")} body=\{response.body}",
  )
}

///|
async test "probe async identity refusal with buffered range" {
  let app = @feather.App::new().get("/data", fn(ctx) {
    ctx.text(200, "0123456789".repeat(64))
  })
  let response = app.respond_async(
    probe_request("GET", Map([
      ("Range", "bytes=4-6"),
      ("Accept-Encoding", "gzip, identity;q=0"),
    ])),
  )
  println(
    "async refusal: status=\{response.status} ce=\{response.headers.get("Content-Encoding")} cr=\{response.headers.get("Content-Range")} body=\{response.body}",
  )
}

///|
async test "probe async identity refusal with range and compression" {
  let app = @feather.App::new().compress(min_size=0).get("/data", fn(ctx) {
    ctx.text(200, "0123456789".repeat(64))
  })
  let response = app.respond_async(
    probe_request("GET", Map([
      ("Range", "bytes=4-6"),
      ("Accept-Encoding", "gzip, identity;q=0"),
    ])),
  )
  println(
    "async refusal compress: status=\{response.status} ce=\{response.headers.get("Content-Encoding")} cr=\{response.headers.get("Content-Range")} body=\{response.body}",
  )
}
