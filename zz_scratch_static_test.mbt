///|
fn zz_ref_join_fs(a : String, b : String) -> String {
  if b == "" {
    a
  } else if a == "" {
    b
  } else if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn zz_ref_static(
  mounts : Array[(String, String, String)],
  path : String,
) -> String? {
  let view = match path.find("?") {
    Some(i) => path[:i]
    None => path.view()
  }
  let mut best : (String, String, String)? = None
  let mut best_length = -1
  for mount in mounts {
    let (prefix, _root, _index) = mount
    let prefix_view = prefix.view()
    let matched = if prefix == "" {
      true
    } else {
      view == prefix_view ||
      (view.length() > prefix.length() &&
        view[:prefix.length()] == prefix_view &&
        view[prefix.length():].has_prefix("/"))
    }
    if matched && prefix.length() > best_length {
      best = Some(mount)
      best_length = prefix.length()
    }
  }
  match best {
    None => None
    Some(mount) => {
      let (prefix, root, index) = mount
      let relative : StringView = if prefix == "" {
        view
      } else if view == prefix.view() {
        ""
      } else {
        view[prefix.length() + 1:]
      }
      let plus_safe = StringBuilder::new()
      for c in relative {
        if c == '+' {
          plus_safe.write_string("%2B")
        } else {
          plus_safe.write_char(c)
        }
      }
      let decoded = @feather.url_decode(plus_safe.to_string())
      if decoded.contains("\\") || decoded.contains("\u{0}") {
        return None
      }
      let segments : Array[StringView] = []
      let decoded_view = decoded.view()
      for segment in decoded_view.split("/") {
        if segment.is_empty() || segment == "." {
          continue
        }
        if segment == ".." {
          return None
        }
        segments.push(segment)
      }
      let builder = StringBuilder::new()
      for i = 0; i < segments.length(); i = i + 1 {
        if i > 0 {
          builder.write_string("/")
        }
        builder.write_stringview(segments[i])
      }
      let clean = builder.to_string()
      if clean == "" || decoded_view.has_suffix("/") {
        Some(zz_ref_join_fs(zz_ref_join_fs(root, clean), index))
      } else {
        Some(zz_ref_join_fs(root, clean))
      }
    }
  }
}

///|
test "zz-fuzz-static-reference" {
  let mounts = [
    ("", "/srv/www", "index.html"),
    ("/assets", "/srv/public", "index.html"),
    ("/assets/img", "/srv/img", "home.html"),
    ("/deep/nested/mount", "/srv/deep", "index.html"),
  ]
  let app = @feather.App::new()
    .static_files("", "/srv/www")
    .static_files("/assets", "/srv/public")
    .static_files("/assets/img", "/srv/img", index="home.html")
    .static_files("/deep/nested/mount", "/srv/deep")
  let chars = [
    'a', 'b', '/', '.', '%', '2', 'e', 'F', '\\', '+', '?', '=', '中', '0',
  ]
  let state = Ref(8888)
  let mut failures = 0
  let paths = [
    "/", "/assets", "/assets/", "/assets/a", "/assets/a/b.c", "/assets//a",
    "/assets/./a", "/assets/a/../b", "/assets/%2e%2e/x", "/assets/a%2Fb",
    "/assets/img/logo.png", "/assets/img", "/assets/img/",
    "/deep/nested/mount/x", "/deep/nested/x", "/a%20b", "/%E4%B8%AD",
    "/assets/x?v=1", "/assets?x=1", "/assets/a+b", "/assets/%C3%A9",
  ]
  for i = 0; i < 500; i = i + 1 {
    let mut s = "/"
    let len = zz_rand(state) % 8
    for j = 0; j < len; j = j + 1 {
      s = s + chars[zz_rand(state) % chars.length()].to_string()
    }
    paths.push(s)
  }
  for path in paths {
    let got = app.static_file_for(path)
    let want = zz_ref_static(mounts, path)
    if got != want {
      failures = failures + 1
      if failures < 15 {
        println("static mismatch: \{path} -> got \{got}, want \{want}")
      }
    }
  }
  assert_eq(failures, 0)
}
