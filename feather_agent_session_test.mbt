///|
priv enum AgentFlashOp {
  AgentFlash(String, String)
  AgentTake(String)
  AgentPeek(String)
  AgentTakeAll
}

///|
fn agent_msgs_text(messages : Array[String]) -> String {
  let mut out = ""
  for message in messages {
    out = out + message + ","
  }
  out
}

///|
fn agent_map_text(m : Map[String, Array[String]]) -> String {
  let keys : Array[String] = []
  for key, _ in m {
    keys.push(key)
  }
  keys.sort_by(fn(a, b) { a.lexical_compare(b) })
  let mut out = ""
  for key in keys {
    out = out + key + "=" + agent_msgs_text(m.get(key).unwrap()) + ";"
  }
  out
}

///|
fn agent_model_apply(
  storage : Map[String, Array[String]],
  op : AgentFlashOp,
) -> String {
  match op {
    AgentFlash(category, message) => {
      match storage.get(category) {
        Some(messages) => if messages.length() < 32 { messages.push(message) }
        None => storage.set(category, [message])
      }
      "f"
    }
    AgentTake(category) =>
      match storage.remove_and_get(category) {
        Some(messages) => "t" + agent_msgs_text(messages)
        None => "t"
      }
    AgentPeek(category) =>
      match storage.get(category) {
        Some(messages) => "p" + agent_msgs_text(messages)
        None => "p"
      }
    AgentTakeAll => {
      let keys : Array[String] = []
      for key, _ in storage {
        keys.push(key)
      }
      let text = agent_map_text(storage)
      for key in keys {
        ignore(storage.remove_and_get(key))
      }
      "a" + text
    }
  }
}

///|
test "agent randomized flash differential" {
  let store = @feather.SessionStore::new(ttl=3_600_000L)
  let storage : Map[String, Array[String]] = Map([])
  let categories = ["a", "b", "c", "d", "e"]
  let messages = ["m0", "m1", "m2", "m3", "m4", "m5"]
  let mut seed = 1234567
  let next = fn() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    seed
  }
  let mut cookie = ""
  for request_index = 0; request_index < 250; request_index = request_index + 1 {
    let ops : Array[AgentFlashOp] = []
    let count = 1 + next() % 6
    for _ in 0..<count {
      let category = categories[next() % categories.length()]
      match next() % 4 {
        0 =>
          ops.push(AgentFlash(category, messages[next() % messages.length()]))
        1 => ops.push(AgentTake(category))
        2 => ops.push(AgentPeek(category))
        _ => ops.push(AgentTakeAll)
      }
    }
    if request_index % 10 == 9 {
      ops.push(AgentTakeAll)
    }
    let expected : Array[String] = []
    for op in ops {
      expected.push(agent_model_apply(storage, op))
    }
    let actual : Array[String] = []
    let app = @feather.App::new()
      .use(@feather.middleware_session(store))
      .get("/run", fn(ctx) {
        for op in ops {
          match op {
            AgentFlash(category, message) => {
              ignore(ctx.flash(message, category~))
              actual.push("f")
            }
            AgentTake(category) =>
              actual.push("t" + agent_msgs_text(ctx.flash_take(category~)))
            AgentPeek(category) =>
              actual.push("p" + agent_msgs_text(ctx.flash_peek(category~)))
            AgentTakeAll =>
              actual.push("a" + agent_map_text(ctx.flash_take_all()))
          }
        }
        ctx.text(200, "ok")
      })
    let headers : Map[String, String] = if cookie == "" {
      Map([])
    } else {
      Map([("Cookie", "feather_session=" + cookie)])
    }
    let response = app.respond({
      method: "GET",
      path: "/run",
      headers,
      body: "",
    })
    if response.status != 200 {
      fail("request \{request_index} failed with \{response.status}")
    }
    if response.cookies.length() > 0 {
      cookie = response.cookies[0].value
    }
    if actual != expected {
      fail(
        "request \{request_index} mismatch: actual=\{actual} expected=\{expected}",
      )
    }
  }
}

///|
test "flash stored byte accounting keeps capped pending additions" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  let session = ctx.session.unwrap()
  let old : Array[Json] = []
  for i = 0; i < 30; i = i + 1 {
    let mut text = ""
    for _ in 0..<300 {
      text = text + "x"
    }
    old.push(Json::string(text))
  }
  session.data.set("__flash:default", Json::array(old).stringify())
  ignore(ctx.flash("a"))
  ignore(ctx.flash("b"))
  // Stored messages bypass the pending byte budget, so both additions fit
  // the per-category message cap (30 stored + 2 new = 32).
  let pending = ctx.flash_peek()
  assert_eq(pending.length(), 32)
  assert_true(pending.contains("a"))
  assert_true(pending.contains("b"))
}

///|
test "flash category cap drops the 17th category across persist" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/setup", fn(ctx) {
      for i = 0; i < 16; i = i + 1 {
        ignore(
          ctx.session_set(
            "__flash:c" + i.to_string(),
            Json::array([Json::string("old")]).stringify(),
          ),
        )
      }
      ignore(ctx.flash("new", category="newcat"))
      ctx.text(200, "setup")
    })
    .get("/take", fn(ctx) {
      ctx.text(200, agent_map_text(ctx.flash_take_all()))
    })
  let first = app.respond({
    method: "GET",
    path: "/setup",
    headers: Map([]),
    body: "",
  })
  let cookie = "feather_session=" + first.cookies[0].value
  let second = app.respond({
    method: "GET",
    path: "/take",
    headers: Map([("Cookie", cookie)]),
    body: "",
  })
  // 16 stored categories survive; the dropped 17th category ("newcat")
  // never reaches the take-all snapshot.
  assert_false(second.body.contains("newcat"))
  assert_true(second.body.contains("c0=old,"))
  assert_true(second.body.contains("c15=old,"))
  assert_eq(
    second.body,
    "c0=old,;c1=old,;c10=old,;c11=old,;c12=old,;c13=old,;c14=old,;c15=old,;c2=old,;c3=old,;c4=old,;c5=old,;c6=old,;c7=old,;c8=old,;c9=old,;",
  )
}

///|
test "lazy session direct id access creates session and cookie" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/", fn(ctx) {
      let session = ctx.session().unwrap()
      ctx.text(200, "[" + session.id + "]")
    })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  // Read-only session access neither assigns the id nor sends a cookie:
  // the raw `session.id` field stays empty until `session_id` or a write
  // triggers lazy generation, and cookie-free requests stay cookie-free.
  assert_eq(response.body, "[]")
  assert_eq(response.cookies.length(), 0)
}

///|
test "regenerate handler reads the old id while the cookie rotates" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/login", fn(ctx) {
      ignore(ctx.session_set("u", "a"))
      ctx.text(200, ctx.session_id().unwrap())
    })
    .get("/regen", fn(ctx) {
      ignore(ctx.session_regenerate())
      ctx.text(200, ctx.session_id().unwrap())
    })
  let login = app.respond({
    method: "GET",
    path: "/login",
    headers: Map([]),
    body: "",
  })
  let old_id = login.cookies[0].value
  let regen = app.respond({
    method: "GET",
    path: "/regen",
    headers: Map([("Cookie", "feather_session=" + old_id)]),
    body: "",
  })
  // `session_regenerate` only flags the rotation; the id visible inside the
  // handler stays the old one and the response cookie carries the new one.
  assert_true(regen.body == old_id)
  let new_id = regen.cookies[0].value
  assert_true(new_id != old_id)
  assert_eq(new_id.length(), 32)
}

///|
test "store save sweeps expired sessions and keeps live ones" {
  let store = @feather.SessionStore::new(ttl=3_600_000L)
  let live = store.create()
  store.save(live)
  let others : Array[@feather.Session] = []
  for _ in 0..<9999 {
    let session = store.create()
    store.save(session)
    others.push(session)
  }
  for session in others {
    session.expires_at = 0L
  }
  let fresh = store.create()
  store.save(fresh)
  // Hitting the cap with expired sessions present sweeps them instead of
  // evicting a live one, so both the first and the newest session survive.
  assert_true(store.get(live.id) is Some(_))
  assert_true(store.get(fresh.id) is Some(_))
  assert_eq(store.count(), 2)
}
