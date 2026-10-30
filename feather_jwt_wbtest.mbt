///|
fn jwt_header() -> Json {
  Json::object({
    "alg": Json::string("HS256"),
    "typ": Json::string("JWT"),
  })
}

///|
fn jwt_token_with_header(header : Json, claims : Json, secret : String) -> String {
  let encoded_header = base64url_encode(
    encode_utf8_lossy(header.stringify().view()),
  )
  let encoded_claims = base64url_encode(
    encode_utf8_lossy(claims.stringify().view()),
  )
  let signing_input = encoded_header + "." + encoded_claims
  let signature = hmac_sha256(
    encode_utf8_lossy(secret.view()),
    encode_utf8_lossy(signing_input.view()),
  )
  signing_input + "." + base64url_encode(signature)
}

///|
fn jwt_token(claims : Json, secret : String) -> String {
  jwt_token_with_header(jwt_header(), claims, secret)
}

///|
fn jwt_claims(exp : Int64, subject : String) -> Json {
  Json::object({
    "sub": Json::string(subject),
    "exp": Json::number(exp.to_double()),
  })
}

///|
fn jwt_app(secret : String) -> App {
  App::new()
    .use(middleware_jwt_hs256(secret))
    .get("/me", fn(ctx) {
      let role = match ctx.jwt_claim("role") {
        Some(Json::String(role)) => role
        _ => ""
      }
      ctx.json_of(200, { "sub": ctx.jwt_subject(), "claim": role })
    })
}

///|
fn jwt_request(token : String) -> Request {
  {
    method: "GET",
    path: "/me",
    headers: Map([("Authorization", "Bearer " + token)]),
    body: "",
  }
}

///|
test "verify_jwt_hs256 accepts a valid token and exposes its claims" {
  let now = 1_700_000_000L
  let token = jwt_token_with_header(
    jwt_header(),
    Json::object({
      "sub": Json::string("alice"),
      "role": Json::string("admin"),
      "exp": Json::number((now + 60L).to_double()),
    }),
    "correct horse battery staple",
  )
  let jwt = verify_jwt_hs256(
    token,
    "correct horse battery staple",
    now=now,
  )
  assert_eq(jwt.subject(), "alice")
  assert_eq(jwt.string_claim("role"), Some("admin"))
  assert_eq(jwt.number_claim("exp"), Some((now + 60L).to_double()))
  assert_eq(jwt.claim("missing"), None)
  match jwt.header() {
    Json::Object(header) => assert_eq(
      header.get("alg"),
      Some(Json::string("HS256")),
    )
    _ => fail("expected an object header")
  }
}

///|
test "verify_jwt_hs256 rejects a token signed with another secret" {
  let now = 1_700_000_000L
  let token = jwt_token(jwt_claims(now + 60L, "alice"), "right")
  let rejected = try {
    ignore(verify_jwt_hs256(token, "wrong", now=now))
    false
  } catch {
    JwtInvalidSignature => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "verify_jwt_hs256 rejects algorithms other than HS256" {
  let now = 1_700_000_000L
  let token = jwt_token_with_header(
    Json::object({ "alg": Json::string("none") }),
    jwt_claims(now + 60L, "alice"),
    "secret",
  )
  let rejected = try {
    ignore(verify_jwt_hs256(token, "secret", now=now))
    false
  } catch {
    JwtUnsupportedAlgorithm(algorithm) => algorithm == "none"
    _ => false
  }
  assert_true(rejected)
}

///|
test "verify_jwt_hs256 enforces exp and nbf with leeway" {
  let now = 1_700_000_000L
  let expired = jwt_token(jwt_claims(now - 5L, "alice"), "secret")
  let expired_rejected = try {
    ignore(verify_jwt_hs256(expired, "secret", now=now))
    false
  } catch {
    JwtExpired => true
    _ => false
  }
  assert_true(expired_rejected)
  // Five seconds of skew is enough to accept the same token.
  let accepted = verify_jwt_hs256(
    expired,
    "secret",
    leeway=10,
    now=now,
  )
  assert_eq(accepted.subject(), "alice")

  let future = jwt_token(
    Json::object({
      "sub": Json::string("alice"),
      "exp": Json::number((now + 60L).to_double()),
      "nbf": Json::number((now + 10L).to_double()),
    }),
    "secret",
  )
  let future_rejected = try {
    ignore(verify_jwt_hs256(future, "secret", now=now))
    false
  } catch {
    JwtNotYetValid => true
    _ => false
  }
  assert_true(future_rejected)
  let future_accepted = verify_jwt_hs256(
    future,
    "secret",
    leeway=20,
    now=now,
  )
  assert_eq(future_accepted.subject(), "alice")
}

///|
test "verify_jwt_hs256 requires exp by default but can opt out" {
  let now = 1_700_000_000L
  let token = jwt_token(
    Json::object({ "sub": Json::string("alice") }),
    "secret",
  )
  let missing_exp = try {
    ignore(verify_jwt_hs256(token, "secret", now=now))
    false
  } catch {
    JwtInvalidClaim(name) => name.contains("exp")
    _ => false
  }
  assert_true(missing_exp)
  let accepted = verify_jwt_hs256(
    token,
    "secret",
    now=now,
    require_exp=false,
  )
  assert_eq(accepted.subject(), "alice")
}

///|
test "verify_jwt_hs256 rejects malformed compact serializations" {
  let now = 1_700_000_000L
  let tokens = [
    "", "one", "one.two", "one.two.three.four", "a.b.c",
    "!!!.e30.c2ln", "e30.!!!.c2ln",
  ]
  for token in tokens {
    let rejected = try {
      ignore(verify_jwt_hs256(token, "secret", now=now))
      false
    } catch {
      JwtMalformed(_) | JwtUnsupportedAlgorithm(_) | JwtInvalidSignature => true
      _ => false
    }
    assert_true(rejected, msg=token)
  }
}

///|
test "verify_jwt_hs256 rejects non-object payloads and bad time claims" {
  let now = 1_700_000_000L
  let array_payload = jwt_token(Json::array([Json::number(1.0)]), "secret")
  let array_rejected = try {
    ignore(verify_jwt_hs256(array_payload, "secret", now=now))
    false
  } catch {
    JwtMalformed(_) => true
    _ => false
  }
  assert_true(array_rejected)

  let string_exp = jwt_token(
    Json::object({
      "exp": Json::string("tomorrow"),
      "sub": Json::string("alice"),
    }),
    "secret",
  )
  let exp_rejected = try {
    ignore(verify_jwt_hs256(string_exp, "secret", now=now))
    false
  } catch {
    JwtInvalidClaim(name) => name.contains("exp")
    _ => false
  }
  assert_true(exp_rejected)
}

///|
test "verify_jwt_hs256 rejects a critical header extension" {
  let now = 1_700_000_000L
  let token = jwt_token_with_header(
    Json::object({
      "alg": Json::string("HS256"),
      "crit": Json::array([Json::string("exp")]),
    }),
    jwt_claims(now + 60L, "alice"),
    "secret",
  )
  let rejected = try {
    ignore(verify_jwt_hs256(token, "secret", now=now))
    false
  } catch {
    JwtMalformed(message) => message.contains("critical")
    _ => false
  }
  assert_true(rejected)
}

///|
test "jwt middleware authenticates a valid bearer token" {
  let now = @async.now() / 1000L
  let token = jwt_token(
    Json::object({
      "sub": Json::string("alice"),
      "role": Json::string("admin"),
      "exp": Json::number((now + 60L).to_double()),
    }),
    "secret",
  )
  let response = jwt_app("secret").respond(jwt_request(token))
  assert_eq(response.status, 200)
  assert_true(response.body.contains("\"sub\":\"alice\""))
  assert_true(response.body.contains("\"claim\":\"admin\""))
}

///|
test "jwt middleware challenges missing and invalid tokens" {
  let app = jwt_app("secret")
  let no_token = app.respond({
    method: "GET",
    path: "/me",
    headers: Map([]),
    body: "",
  })
  assert_eq(no_token.status, 401)
  assert_eq(no_token.body, "401 Unauthorized")
  assert_eq(
    no_token.headers.get("WWW-Authenticate"),
    Some("Bearer realm=\"Restricted\""),
  )

  let now = @async.now() / 1000L
  let token = jwt_token(jwt_claims(now + 60L, "alice"), "other-secret")
  let bad_signature = app.respond(jwt_request(token))
  assert_eq(bad_signature.status, 401)
  assert_eq(
    bad_signature.headers.get("WWW-Authenticate"),
    Some("Bearer realm=\"Restricted\""),
  )
  assert_eq(bad_signature.headers.get("Content-Type"), Some("text/plain; charset=utf-8"))
}

///|
test "jwt middleware records failure categories for logs" {
  let now = @async.now() / 1000L
  let seen = Ref("")
  let app = App::new()
    .use(fn(next) {
      fn(ctx) raise {
        next(ctx)
        seen.val = ctx.jwt_error()
      }
    })
    .use(middleware_jwt_hs256("secret"))
    .get("/me", fn(ctx) { ctx.text(200, ctx.jwt_subject()) })
  let expired = jwt_token(jwt_claims(now - 60L, "alice"), "secret")
  let response = app.respond(jwt_request(expired))
  assert_eq(response.status, 401)
  assert_eq(seen.val, "expired")
  assert_eq(response.body, "401 Unauthorized")
  assert_false(response.body.contains("expired"))
}

///|
test "jwt middleware uses a custom realm and rejects expired tokens" {
  let now = @async.now() / 1000L
  let app = App::new()
    .use(middleware_jwt_hs256("secret", realm="Private API"))
    .get("/me", fn(ctx) { ctx.text(200, ctx.jwt_subject()) })
  let expired = jwt_token(jwt_claims(now - 60L, "alice"), "secret")
  let response = app.respond(jwt_request(expired))
  assert_eq(response.status, 401)
  assert_eq(
    response.headers.get("WWW-Authenticate"),
    Some("Bearer realm=\"Private API\""),
  )
}

///|
test "verify_jwt_hs256 validates issuer and string audience" {
  let now = 1_700_000_000L
  let token = jwt_token_with_header(
    jwt_header(),
    Json::object({
      "sub": Json::string("alice"),
      "exp": Json::number((now + 60L).to_double()),
      "iss": Json::string("https://issuer.example"),
      "aud": Json::string("feather-api"),
    }),
    "secret",
  )
  let accepted = verify_jwt_hs256(
    token,
    "secret",
    now=now,
    issuer="https://issuer.example",
    audience="feather-api",
  )
  assert_eq(accepted.subject(), "alice")
  let wrong_issuer = try {
    ignore(
      verify_jwt_hs256(
        token,
        "secret",
        now=now,
        issuer="https://other.example",
      ),
    )
    false
  } catch {
    JwtInvalidClaim(message) => message.contains("issuer")
    _ => false
  }
  assert_true(wrong_issuer)
  let wrong_audience = try {
    ignore(
      verify_jwt_hs256(token, "secret", now=now, audience="another-api"),
    )
    false
  } catch {
    JwtInvalidClaim(message) => message.contains("audience")
    _ => false
  }
  assert_true(wrong_audience)
}

///|
test "verify_jwt_hs256 accepts an audience array and rejects malformed claims" {
  let now = 1_700_000_000L
  let token = jwt_token(
    Json::object({
      "sub": Json::string("alice"),
      "exp": Json::number((now + 60L).to_double()),
      "aud": Json::array([
        Json::string("web"),
        Json::string("feather-api"),
      ]),
    }),
    "secret",
  )
  let accepted = verify_jwt_hs256(
    token,
    "secret",
    now=now,
    audience="feather-api",
  )
  assert_eq(accepted.subject(), "alice")
  let missing = jwt_token(jwt_claims(now + 60L, "alice"), "secret")
  let rejected = try {
    ignore(verify_jwt_hs256(missing, "secret", now=now, audience="feather-api"))
    false
  } catch {
    JwtInvalidClaim(message) => message.contains("aud")
    _ => false
  }
  assert_true(rejected)
  let malformed = jwt_token(
    Json::object({
      "sub": Json::string("alice"),
      "exp": Json::number((now + 60L).to_double()),
      "aud": Json::number(42.0),
    }),
    "secret",
  )
  let malformed_rejected = try {
    ignore(
      verify_jwt_hs256(
        malformed,
        "secret",
        now=now,
        audience="feather-api",
      ),
    )
    false
  } catch {
    JwtInvalidClaim(message) => message.contains("aud")
    _ => false
  }
  assert_true(malformed_rejected)
}

///|
test "jwt middleware enforces configured issuer and audience" {
  let secret = "correct horse battery staple"
  let now = @async.now() / 1000L
  let app = App::new()
    .use(
      middleware_jwt_hs256(
        secret,
        issuer="https://issuer.example",
        audience="feather-api",
      ),
    )
    .get("/me", fn(ctx) { ctx.text(200, ctx.jwt_subject()) })
  let valid_token = jwt_token(
    Json::object({
      "sub": Json::string("alice"),
      "exp": Json::number((now + 60L).to_double()),
      "iss": Json::string("https://issuer.example"),
      "aud": Json::string("feather-api"),
    }),
    secret,
  )
  let accepted = app.respond(jwt_request(valid_token))
  assert_eq(accepted.status, 200)
  assert_eq(accepted.body, "alice")
  let wrong_issuer_token = jwt_token(
    Json::object({
      "sub": Json::string("alice"),
      "exp": Json::number((now + 60L).to_double()),
      "iss": Json::string("https://other.example"),
      "aud": Json::string("feather-api"),
    }),
    secret,
  )
  let rejected = app.respond(jwt_request(wrong_issuer_token))
  assert_eq(rejected.status, 401)
  assert_eq(rejected.body, "401 Unauthorized")
}

///|
test "jwt middleware exposes the protected header and its parameters" {
  let now = @async.now() / 1000L
  let app = App::new()
    .use(middleware_jwt_hs256("secret"))
    .get("/me", fn(ctx) {
      let alg = match ctx.jwt_header_parameter("alg") {
        Some(Json::String(value)) => value
        _ => ""
      }
      let kid = match ctx.jwt_header_parameter("kid") {
        Some(Json::String(value)) => value
        _ => ""
      }
      let object_header = match ctx.jwt_header() {
        Some(Json::Object(_)) => true
        _ => false
      }
      let missing = ctx.jwt_header_parameter("missing") is None
      ctx.text(200, "\{alg}:\{kid}:\{object_header}:\{missing}")
    })
  let token = jwt_token_with_header(
    Json::object({
      "alg": Json::string("HS256"),
      "typ": Json::string("JWT"),
      "kid": Json::string("key-1"),
    }),
    jwt_claims(now + 60L, "alice"),
    "secret",
  )
  let response = app.respond(jwt_request(token))
  assert_eq(response.status, 200)
  assert_eq(response.body, "HS256:key-1:true:true")
}
