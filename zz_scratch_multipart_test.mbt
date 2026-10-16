///|
fn zz_multipart_serialize(
  boundary : String,
  parts : Array[(String, String, String, String)],
  crlf : Bool,
) -> String {
  let nl = if crlf { "\r\n" } else { "\n" }
  let builder = StringBuilder::new()
  for part in parts {
    let (name, filename, content_type, data) = part
    builder.write_string("--" + boundary + nl)
    if filename == "" {
      builder.write_string("Content-Disposition: form-data; name=\"" + name + "\"" + nl)
    } else {
      builder.write_string(
        "Content-Disposition: form-data; name=\"" +
        name +
        "\"; filename=\"" +
        filename +
        "\"" +
        nl,
      )
    }
    if content_type != "" {
      builder.write_string("Content-Type: " + content_type + nl)
    }
    builder.write_string(nl)
    builder.write_string(data)
    builder.write_string(nl)
  }
  builder.write_string("--" + boundary + "--" + nl)
  builder.to_string()
}

///|
test "zz-fuzz-multipart-roundtrip" {
  let state = Ref(777)
  let names = ["a", "field", "file", "x-y", "名"]
  let data_pool = [
    "", "hello", "a\r\nb", "a\nb", "中文", "  spaced  ", "line1\r\nline2\r\n",
    "{\"json\":true}", "a=b&c=d",
  ]
  let mut failures = 0
  for i = 0; i < 300; i = i + 1 {
    let boundary = "B" + (zz_rand(state) % 100).to_string()
    let part_count = 1 + zz_rand(state) % 3
    let parts : Array[(String, String, String, String)] = []
    for j = 0; j < part_count; j = j + 1 {
      let name = names[zz_rand(state) % names.length()]
      let filename = if zz_rand(state) % 2 == 0 {
        ""
      } else {
        "f" + (zz_rand(state) % 10).to_string() + ".txt"
      }
      let content_type = if filename == "" {
        ""
      } else {
        "text/plain"
      }
      let data = data_pool[zz_rand(state) % data_pool.length()]
      parts.push((name, filename, content_type, data))
    }
    let crlf = zz_rand(state) % 4 != 0
    let body = zz_multipart_serialize(boundary, parts, crlf)
    let content_type = "multipart/form-data; boundary=" + boundary
    let parsed = @feather.parse_multipart(body, content_type)
    match parsed {
      None => {
        failures = failures + 1
        println("parse returned None for boundary \{boundary}")
      }
      Some(parsed_parts) => {
        if parsed_parts.length() != parts.length() {
          failures = failures + 1
          println(
            "part count \{parsed_parts.length()} != \{parts.length()} (crlf=\{crlf}, boundary=\{boundary})",
          )
        } else {
          for j = 0; j < parts.length(); j = j + 1 {
            let (name, filename, content_type, data) = parts[j]
            let got = parsed_parts[j]
            if got.name != name ||
              got.filename != filename ||
              got.content_type != content_type ||
              got.data != data {
              failures = failures + 1
              if failures < 10 {
                println(
                  "part \{j} mismatch: want \{name}/\{filename}/\{content_type}/\{data}, got \{got.name}/\{got.filename}/\{got.content_type}/\{got.data}",
                )
              }
            }
          }
        }
      }
    }
  }
  assert_eq(failures, 0)
}
