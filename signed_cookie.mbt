///|
/// SHA-256 round constants (FIPS 180-4, section 4.2.2).
let sha256_round_constants : Array[UInt] = [
  0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U,
  0x923f82a4U, 0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
  0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U,
  0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
  0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U,
  0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
  0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
  0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
  0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU,
  0x5b9cca4fU, 0x682e6ff3U, 0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
  0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
]

///|
/// SHA-256 initial hash values (FIPS 180-4, section 5.3.3).
let sha256_initial_state : Array[UInt] = [
  0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
  0x1f83d9abU, 0x5be0cd19U,
]

///|
fn rotr32(value : UInt, bits : Int) -> UInt {
  (value >> bits) | (value << (32 - bits))
}

///|
fn sha256_choose(x : UInt, y : UInt, z : UInt) -> UInt {
  (x & y) ^ (x.lnot() & z)
}

///|
fn sha256_majority(x : UInt, y : UInt, z : UInt) -> UInt {
  (x & y) ^ (x & z) ^ (y & z)
}

///|
fn sha256_sigma0(value : UInt) -> UInt {
  rotr32(value, 7) ^ rotr32(value, 18) ^ (value >> 3)
}

///|
fn sha256_sigma1(value : UInt) -> UInt {
  rotr32(value, 17) ^ rotr32(value, 19) ^ (value >> 10)
}

///|
fn sha256_big_sigma0(value : UInt) -> UInt {
  rotr32(value, 2) ^ rotr32(value, 13) ^ rotr32(value, 22)
}

///|
fn sha256_big_sigma1(value : UInt) -> UInt {
  rotr32(value, 6) ^ rotr32(value, 11) ^ rotr32(value, 25)
}

///|
fn read_uint32_be(data : Bytes, offset : Int) -> UInt {
  (data[offset].to_uint() << 24) |
    (data[offset + 1].to_uint() << 16) |
    (data[offset + 2].to_uint() << 8) |
    data[offset + 3].to_uint()
}

///|
fn sha256_compress(state : FixedArray[UInt], block : Bytes, offset : Int) -> Unit {
  let schedule = FixedArray::make(64, 0U)
  for i = 0; i < 16; i = i + 1 {
    schedule[i] = read_uint32_be(block, offset + i * 4)
  }
  for i = 16; i < 64; i = i + 1 {
    schedule[i] = schedule[i - 16] +
      sha256_sigma0(schedule[i - 15]) +
      schedule[i - 7] +
      sha256_sigma1(schedule[i - 2])
  }
  let mut a = state[0]
  let mut b = state[1]
  let mut c = state[2]
  let mut d = state[3]
  let mut e = state[4]
  let mut f = state[5]
  let mut g = state[6]
  let mut h = state[7]
  for i = 0; i < 64; i = i + 1 {
    let temp1 = h +
      sha256_big_sigma1(e) +
      sha256_choose(e, f, g) +
      sha256_round_constants[i] +
      schedule[i]
    let temp2 = sha256_big_sigma0(a) + sha256_majority(a, b, c)
    h = g
    g = f
    f = e
    e = d + temp1
    d = c
    c = b
    b = a
    a = temp1 + temp2
  }
  state[0] = state[0] + a
  state[1] = state[1] + b
  state[2] = state[2] + c
  state[3] = state[3] + d
  state[4] = state[4] + e
  state[5] = state[5] + f
  state[6] = state[6] + g
  state[7] = state[7] + h
}

///|
/// Compute the SHA-256 digest of `data`, returning 32 bytes.
pub fn sha256(data : Bytes) -> Bytes {
  let state = FixedArray::make(8, 0U)
  for i = 0; i < 8; i = i + 1 {
    state[i] = sha256_initial_state[i]
  }
  let length = data.length()
  let full_blocks = length / 64
  for block = 0; block < full_blocks; block = block + 1 {
    sha256_compress(state, data, block * 64)
  }
  let remainder = length - full_blocks * 64
  let tail_length = if remainder < 56 { 64 } else { 128 }
  let tail = FixedArray::make(tail_length, b'\x00')
  for i = 0; i < remainder; i = i + 1 {
    tail[i] = data[full_blocks * 64 + i]
  }
  tail[remainder] = b'\x80'
  let bit_length = (length.to_int64() * 8L).reinterpret_as_uint64()
  for i = 0; i < 8; i = i + 1 {
    let shift = (7 - i) * 8
    tail[tail_length - 8 + i] = ((bit_length >> shift) & 0xFFUL)
      .reinterpret_as_int64()
      .to_int()
      .to_byte()
  }
  let tail_bytes = tail.unsafe_reinterpret_as_bytes()
  for block = 0; block < tail_length / 64; block = block + 1 {
    sha256_compress(state, tail_bytes, block * 64)
  }
  let digest = FixedArray::make(32, b'\x00')
  for i = 0; i < 8; i = i + 1 {
    let word = state[i]
    digest[i * 4] = ((word >> 24) & 0xFFU).reinterpret_as_int().to_byte()
    digest[i * 4 + 1] = ((word >> 16) & 0xFFU).reinterpret_as_int().to_byte()
    digest[i * 4 + 2] = ((word >> 8) & 0xFFU).reinterpret_as_int().to_byte()
    digest[i * 4 + 3] = (word & 0xFFU).reinterpret_as_int().to_byte()
  }
  digest.unsafe_reinterpret_as_bytes()
}

///|
/// HMAC-SHA256 as specified by RFC 2104 and RFC 4231.
pub fn hmac_sha256(key : Bytes, message : Bytes) -> Bytes {
  let normalized = if key.length() > 64 { sha256(key) } else { key }
  let pad = FixedArray::make(64, b'\x00')
  for i = 0; i < normalized.length(); i = i + 1 {
    pad[i] = normalized[i]
  }
  let inner = @buffer.Buffer::Buffer(size_hint=64 + message.length())
  for i = 0; i < 64; i = i + 1 {
    inner.write_byte(pad[i] ^ b'\x36')
  }
  inner.write_bytes(message)
  let inner_digest = sha256(inner.to_bytes())
  let outer = @buffer.Buffer::Buffer(size_hint=64 + 32)
  for i = 0; i < 64; i = i + 1 {
    outer.write_byte(pad[i] ^ b'\x5c')
  }
  outer.write_bytes(inner_digest)
  sha256(outer.to_bytes())
}

///|
/// Constant-time byte comparison, used to compare MACs without leaking their
/// contents through timing.
fn constant_time_bytes_equal(left : Bytes, right : Bytes) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for i = 0; i < left.length(); i = i + 1 {
    difference = difference | ((left[i] ^ right[i]).to_int())
  }
  difference == 0
}

///|
/// Encode bytes with the URL-safe base64 alphabet, without padding.
fn base64url_encode(data : Bytes) -> String {
  let standard = base64_encode(data)
  let view = standard.view()
  let builder = StringBuilder(size_hint=view.length())
  for i = 0; i < view.length(); i = i + 1 {
    let code = view.unsafe_get(i).to_int()
    if code == 43 {
      builder.write_char('-')
    } else if code == 47 {
      builder.write_char('_')
    } else if code == 61 {
      break
    } else {
      builder.write_char(code.unsafe_to_char())
    }
  }
  builder.to_string()
}

///|
/// Decode URL-safe base64 text with optional padding. Returns `None` for
/// malformed input.
fn base64url_decode(text : String) -> Bytes? {
  let view = text.view()
  let translated = FixedArray::make(view.length(), b'\x00')
  for i = 0; i < view.length(); i = i + 1 {
    let code = view.unsafe_get(i).to_int()
    if code == 45 {
      translated[i] = b'+'
    } else if code == 95 {
      translated[i] = b'/'
    } else {
      translated[i] = code.to_byte()
    }
  }
  base64_decode(@utf8.decode_lossy(translated.unsafe_reinterpret_as_bytes()))
}

///|
fn parse_decimal_int64(view : StringView) -> Int64? {
  let length = view.length()
  if length == 0 || length > 19 {
    return None
  }
  let mut value = 0L
  for i = 0; i < length; i = i + 1 {
    let code = view.unsafe_get(i).to_int()
    if code < 48 || code > 57 {
      return None
    }
    value = value * 10L + (code - 48).to_int64()
  }
  Some(value)
}

///|
fn signed_cookie_signing_input(
  name : String,
  encoded_value : String,
  expires_at : Int64,
) -> Bytes {
  @utf8.encode(name + "\n" + encoded_value + "." + expires_at.to_string())
}

///|
/// Sign `value` for the cookie called `name` with `secret`, producing a token
/// that `verify_signed_cookie_token` can check.
///
/// The token has the shape `base64url(value).expires_at.base64url(mac)`. The
/// MAC covers the cookie name so a token minted for one cookie cannot be
/// replayed as the value of another. `expires_at` is an absolute deadline in
/// milliseconds since the Unix epoch; `0` (the default) means the token never
/// expires. Treat `secret` as a password: keep it private, give it high
/// entropy, and do not rotate it without invalidating existing tokens.
pub fn signed_cookie_token(
  secret : String,
  name : String,
  value : String,
  expires_at? : Int64,
) -> String {
  let deadline = match expires_at {
    Some(value) => value
    None => 0L
  }
  let encoded_value = base64url_encode(@utf8.encode(value))
  let mac = hmac_sha256(
    @utf8.encode(secret),
    signed_cookie_signing_input(name, encoded_value, deadline),
  )
  encoded_value + "." + deadline.to_string() + "." + base64url_encode(mac)
}

///|
/// Verify a token produced by `signed_cookie_token` and return the original
/// value, or `None` when the token is malformed, tampered with, or expired.
///
/// `now` overrides the current time (milliseconds since the Unix epoch); it is
/// mainly useful in tests and clock-sensitive code.
pub fn verify_signed_cookie_token(
  secret : String,
  name : String,
  token : String,
  now? : Int64,
) -> String? {
  let view = token.view()
  let first_dot = match view.find(".") {
    Some(index) => index
    None => return None
  }
  let rest = view[first_dot + 1:]
  let second_dot = match rest.find(".") {
    Some(index) => index
    None => return None
  }
  let encoded_value = view[:first_dot]
  let expiry_view = rest[:second_dot]
  let signature_view = rest[second_dot + 1:]
  match signature_view.find(".") {
    Some(_) => return None
    None => ()
  }
  let deadline = match parse_decimal_int64(expiry_view) {
    Some(value) => value
    None => return None
  }
  if deadline > 0L {
    let current = match now {
      Some(value) => value
      None => @async.now()
    }
    if current >= deadline {
      return None
    }
  }
  let encoded_value_owned = encoded_value.to_owned()
  let expected = hmac_sha256(
    @utf8.encode(secret),
    signed_cookie_signing_input(name, encoded_value_owned, deadline),
  )
  let signature = match base64url_decode(signature_view.to_owned()) {
    Some(value) => value
    None => return None
  }
  if !constant_time_bytes_equal(signature, expected) {
    return None
  }
  match base64url_decode(encoded_value_owned) {
    Some(value) => Some(@utf8.decode_lossy(value))
    None => None
  }
}

///|
/// Set a cookie whose value is signed with `secret`.
///
/// The cookie is readable by the client (base64 is not encryption), but it
/// cannot be modified without invalidating the signature, which makes it a
/// good fit for small pieces of trusted state such as a user id or a feature
/// flag. Reading it back is `Context::signed_cookie`.
///
/// When `max_age` (in seconds) is given it is both sent to the browser as
/// `Max-Age` and used to embed an expiry deadline in the signed token, so an
/// old token stops validating even if its signature is still intact.
pub fn Context::set_signed_cookie(
  self : Context,
  name : String,
  value : String,
  secret : String,
  path? : String,
  max_age? : Int64,
  domain? : String,
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
) -> Unit {
  let expires_at = match max_age {
    Some(seconds) => Some(@async.now() + seconds * 1000L)
    None => None
  }
  let token = signed_cookie_token(secret, name, value, expires_at?)
  self.set_cookie(
    name,
    token,
    path?,
    max_age?,
    domain?,
    same_site?,
    http_only~,
    secure~,
  )
}

///|
/// Read a cookie written by `Context::set_signed_cookie`, returning `None`
/// when the cookie is missing, altered, or expired.
pub fn Context::signed_cookie(
  self : Context,
  name : String,
  secret : String,
) -> String? {
  match self.cookie(name) {
    Some(token) => verify_signed_cookie_token(secret, name, token)
    None => None
  }
}

///|
/// Clear a signed cookie previously set with `Context::set_signed_cookie`.
pub fn Context::clear_signed_cookie(
  self : Context,
  name : String,
  path? : String,
  domain? : String,
) -> Unit {
  self.clear_cookie(name, path?, domain?)
}
