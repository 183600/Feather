///|
/// A runnable demo combining server-side sessions, a signed cookie and flash
/// messages. Start it with:
///
///   moon run examples/session_demo --target native
///
/// then open http://127.0.0.1:8000/.
const DEMO_SECRET : String = "feather-session-demo-secret"

///|
fn escape_html(value : String) -> String {
  let out = StringBuilder(size_hint=value.length())
  for ch in value.iter() {
    if ch == '&' {
      out.write_string("&amp;")
    } else if ch == '<' {
      out.write_string("&lt;")
    } else if ch == '>' {
      out.write_string("&gt;")
    } else if ch == '"' {
      out.write_string("&quot;")
    } else if ch == '\'' {
      out.write_string("&#39;")
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn render_home(ctx : @feather.Context) -> String {
  let out = StringBuilder(size_hint=4096)
  out.write_string(
    "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n",
  )
  out.write_string("<title>Feather session demo</title>\n</head>\n<body>\n")
  out.write_string("<h1>Feather session, signed cookie and flash</h1>\n")
  let messages = ctx.flash_take_all()
  if messages.length() > 0 {
    out.write_string("<ul class=\"flash\">\n")
    for category, items in messages {
      for message in items {
        out.write_string("<li class=\"")
        out.write_string(escape_html(category))
        out.write_string("\">")
        out.write_string(escape_html(message))
        out.write_string("</li>\n")
      }
    }
    out.write_string("</ul>\n")
  } else {
    out.write_string("<p>No flash messages pending.</p>\n")
  }
  let user = match ctx.session_get("user") {
    "" => "(not signed in)"
    name => escape_html(name)
  }
  let prefs = match ctx.signed_cookie("prefs", DEMO_SECRET) {
    Some(value) => escape_html(value)
    None => "(missing, expired, or tampered)"
  }
  out.write_string("<p>Session user: <strong>")
  out.write_string(user)
  out.write_string("</strong></p>\n<p>Signed cookie prefs: <code>")
  out.write_string(prefs)
  out.write_string("</code></p>\n")
  out.write_string(
    "<form method=\"post\" action=\"/login\">\n<label>Name <input name=\"name\" value=\"alice\"></label>\n<button type=\"submit\">Sign in</button>\n</form>\n",
  )
  out.write_string(
    "<form method=\"post\" action=\"/prefs\">\n<label>Theme <select name=\"theme\"><option>dark</option><option>light</option></select></label>\n<button type=\"submit\">Save signed cookie</button>\n</form>\n",
  )
  out.write_string(
    "<form method=\"post\" action=\"/logout\"><button type=\"submit\">Sign out</button></form>\n",
  )
  out.write_string("<p><a href=\"/visit\">Record another visit</a></p>\n")
  out.write_string("</body>\n</html>\n")
  out.to_string()
}

///|
async fn main {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .use(@feather.middleware_logger())
    .use(@feather.middleware_session(store))
    .get("/", fn(ctx) { ctx.html(200, render_home(ctx)) })
    .post("/login", fn(ctx) {
      let name = ctx.form_default("name", "guest")
      ignore(ctx.session_set("user", name))
      ctx.set_signed_cookie(
        "prefs",
        "theme=dark",
        DEMO_SECRET,
        path="/",
        max_age=86400L,
        http_only=true,
      )
      ignore(ctx.flash("Signed in as \{name}", category="notice"))
      ctx.redirect(303, "/")
    })
    .post("/prefs", fn(ctx) {
      let theme = ctx.form_default("theme", "dark")
      ignore(ctx.session_set("theme", theme))
      ctx.set_signed_cookie(
        "prefs",
        "theme=\{theme}",
        DEMO_SECRET,
        path="/",
        max_age=86400L,
        http_only=true,
      )
      ignore(ctx.flash("Saved theme \{theme}", category="notice"))
      ctx.redirect(303, "/")
    })
    .post("/logout", fn(ctx) {
      ctx.clear_signed_cookie("prefs", path="/")
      ignore(ctx.session_destroy())
      ctx.redirect(303, "/")
    })
    .get("/visit", fn(ctx) {
      let visits = match ctx.session_get_json("visits") {
        Some(value) =>
          if value is Number(number, ..) {
            number.to_int() + 1
          } else {
            1
          }
        None => 1
      }
      ignore(ctx.session_set_json("visits", Json::number(visits.to_double())))
      ignore(ctx.flash("Visit #\{visits} recorded", category="notice"))
      ctx.redirect(303, "/")
    })
  let addr = @socket.Addr::parse("127.0.0.1:8000")
  println("Feather session demo listening on http://127.0.0.1:8000")
  app.serve(addr)
}
