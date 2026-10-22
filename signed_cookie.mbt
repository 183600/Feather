///|
/// SHA-256 round constants (FIPS 180-4, section 4.2.2).
let sha256_round_constants : FixedArray[UInt32] = FixedArray::from_array([
  0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U,
  0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU,
  0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU,
  0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU, 0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
  0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU,
  0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
  0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U, 0x19a4c116U,
  0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
  0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U,
  0xc67178f2U,
])

///|
/// SHA-256 initial hash values (FIPS 180-4, section 5.3.3).
let sha256_initial_state : FixedArray[UInt32] = FixedArray::from_array([
  0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU, 0x1f83d9abU,
  0x5be0cd19U,
])

///|
#inline
fn rotr32(value : UInt32, bits : Int32) -> UInt32 {
  (value >> bits) | (value << (32 - bits))
}

///|
#inline
fn sha256_choose(x : UInt32, y : UInt32, z : UInt32) -> UInt32 {
  (x & y) ^ (x.lnot() & z)
}

///|
#inline
fn sha256_majority(x : UInt32, y : UInt32, z : UInt32) -> UInt32 {
  (x & y) ^ (x & z) ^ (y & z)
}

///|
#inline
fn sha256_sigma0(value : UInt32) -> UInt32 {
  rotr32(value, 7) ^ rotr32(value, 18) ^ (value >> 3)
}

///|
#inline
fn sha256_sigma1(value : UInt32) -> UInt32 {
  rotr32(value, 17) ^ rotr32(value, 19) ^ (value >> 10)
}

///|
#inline
fn sha256_big_sigma0(value : UInt32) -> UInt32 {
  rotr32(value, 2) ^ rotr32(value, 13) ^ rotr32(value, 22)
}

///|
#inline
fn sha256_big_sigma1(value : UInt32) -> UInt32 {
  rotr32(value, 6) ^ rotr32(value, 11) ^ rotr32(value, 25)
}

///|
#inline
fn read_uint32_be(data : Bytes, offset : Int32) -> UInt32 {
  (data.unsafe_get(offset).to_uint() << 24) |
  (data.unsafe_get(offset + 1).to_uint() << 16) |
  (data.unsafe_get(offset + 2).to_uint() << 8) |
  data.unsafe_get(offset + 3).to_uint()
}

///|
/// Message schedule for `sha256_compress`. The async runtime is single threaded
/// and compression never yields, so a shared scratch buffer is safe.
let sha256_schedule : FixedArray[UInt32] = FixedArray::make(64, 0U)

///|
fn sha256_compress(
  state : FixedArray[UInt32],
  block : Bytes,
  offset : Int32,
) -> Unit {
  let schedule = sha256_schedule
  for i = 0; i < 16; i = i + 1 {
    schedule.unsafe_set(i, read_uint32_be(block, offset + i * 4))
  }
  for i = 16; i < 64; i = i + 1 {
    schedule.unsafe_set(
      i,
      schedule.unsafe_get(i - 16) +
      sha256_sigma0(schedule.unsafe_get(i - 15)) +
      schedule.unsafe_get(i - 7) +
      sha256_sigma1(schedule.unsafe_get(i - 2)),
    )
  }
  let mut a = state.unsafe_get(0)
  let mut b = state.unsafe_get(1)
  let mut c = state.unsafe_get(2)
  let mut d = state.unsafe_get(3)
  let mut e = state.unsafe_get(4)
  let mut f = state.unsafe_get(5)
  let mut g = state.unsafe_get(6)
  let mut h = state.unsafe_get(7)
  for i = 0; i < 64; i = i + 1 {
    let temp1 = h +
      sha256_big_sigma1(e) +
      sha256_choose(e, f, g) +
      sha256_round_constants.unsafe_get(i) +
      schedule.unsafe_get(i)
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
  state.unsafe_set(0, state.unsafe_get(0) + a)
  state.unsafe_set(1, state.unsafe_get(1) + b)
  state.unsafe_set(2, state.unsafe_get(2) + c)
  state.unsafe_set(3, state.unsafe_get(3) + d)
  state.unsafe_set(4, state.unsafe_get(4) + e)
  state.unsafe_set(5, state.unsafe_get(5) + f)
  state.unsafe_set(6, state.unsafe_get(6) + g)
  state.unsafe_set(7, state.unsafe_get(7) + h)
}

///|
/// Padding buffer for the final one or two blocks of `sha256`.
let sha256_tail_bytes : FixedArray[Byte] = FixedArray::make(128, b'\x00')

///|
/// Hash state for `sha256` / `hmac_sha256`. Compression never yields and the
/// async runtime is single threaded, matching the shared `sha256_schedule`
/// scratch above.
let sha256_work_state : FixedArray[UInt32] = FixedArray::make(8, 0U)

///|
/// Inner/outer key blocks for `hmac_sha256`, kept alongside the normalized key
/// they were derived from, plus the digest state after each block was
/// compressed.
let hmac_cached_key : Ref[Bytes?] = Ref(None)

///|
let hmac_inner_block : FixedArray[Byte] = FixedArray::make(64, b'\x00')

///|
let hmac_outer_block : FixedArray[Byte] = FixedArray::make(64, b'\x00')

///|
let hmac_inner_midstate : FixedArray[UInt32] = FixedArray::make(8, 0U)

///|
let hmac_outer_midstate : FixedArray[UInt32] = FixedArray::make(8, 0U)

///|
/// Inner-digest scratch for `hmac_sha256`.
let sha256_hmac_inner_digest : FixedArray[Byte] = FixedArray::make(32, b'\x00')

///|
fn sha256_state_reset(state : FixedArray[UInt32]) -> Unit {
  for i = 0; i < 8; i = i + 1 {
    state.unsafe_set(i, sha256_initial_state.unsafe_get(i))
  }
}

///|
/// Compress every full 64-byte block of `data` into `state`.
fn sha256_update(state : FixedArray[UInt32], data : Bytes) -> Unit {
  let full_blocks = data.length() / 64
  for block = 0; block < full_blocks; block = block + 1 {
    sha256_compress(state, data, block * 64)
  }
}

///|
/// Pad `data` and write the 32-byte digest of `state` into `out`. The
/// `prefix_length` bytes already compressed before `data` count toward the
/// message length encoded in the padding.
fn sha256_finish_into(
  state : FixedArray[UInt32],
  data : Bytes,
  prefix_length : Int32,
  out : FixedArray[Byte],
) -> Unit {
  let length = data.length()
  let full_blocks = length / 64
  let remainder = length - full_blocks * 64
  let tail_length = if remainder < 56 { 64 } else { 128 }
  let tail = sha256_tail_bytes
  for i = remainder; i < tail_length - 8; i = i + 1 {
    tail[i] = b'\x00'
  }
  for i = 0; i < remainder; i = i + 1 {
    tail[i] = data[full_blocks * 64 + i]
  }
  tail[remainder] = b'\x80'
  let bit_length = ((prefix_length + length).to_int64() * 8L).reinterpret_as_uint64()
  for i = 0; i < 8; i = i + 1 {
    let shift = (7 - i) * 8
    tail.unsafe_set(
      tail_length - 8 + i,
      ((bit_length >> shift) & 0xFFUL).reinterpret_as_int64().to_int().to_byte(),
    )
  }
  let tail_bytes = tail.unsafe_reinterpret_as_bytes()
  for block = 0; block < tail_length / 64; block = block + 1 {
    sha256_compress(state, tail_bytes, block * 64)
  }
  for i = 0; i < 8; i = i + 1 {
    let word = state.unsafe_get(i)
    out.unsafe_set(i * 4, ((word >> 24) & 0xFFU).reinterpret_as_int().to_byte())
    out.unsafe_set(
      i * 4 + 1,
      ((word >> 16) & 0xFFU).reinterpret_as_int().to_byte(),
    )
    out.unsafe_set(
      i * 4 + 2,
      ((word >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
    )
    out.unsafe_set(i * 4 + 3, (word & 0xFFU).reinterpret_as_int().to_byte())
  }
}

///|
/// Compute the SHA-256 digest of `data`, returning 32 bytes.
pub fn sha256(data : Bytes) -> Bytes {
  let state = sha256_work_state
  sha256_state_reset(state)
  sha256_update(state, data)
  let digest = FixedArray::make(32, b'\x00')
  sha256_finish_into(state, data, 0, digest)
  digest.unsafe_reinterpret_as_bytes()
}

///|
/// HMAC-SHA256 as specified by RFC 2104 and RFC 4231.
///
/// The inner and outer hashes are streamed into the shared `sha256_update` /
/// `sha256_finish_into` helpers.

///|
/// Fill `hmac_inner_block`/`hmac_outer_block` for `normalized` unless they
/// already correspond to it.
fn hmac_ensure_key_blocks(normalized : Bytes) -> Unit {
  match hmac_cached_key.val {
    Some(cached) => if constant_time_bytes_equal(cached, normalized) { return }
    None => ()
  }
  let key_length = normalized.length()
  for i = 0; i < 64; i = i + 1 {
    let byte = if i < key_length { normalized[i] } else { b'\x00' }
    hmac_inner_block[i] = byte ^ b'\x36'
    hmac_outer_block[i] = byte ^ b'\x5c'
  }
  let state = sha256_work_state
  sha256_state_reset(state)
  sha256_compress(state, hmac_inner_block.unsafe_reinterpret_as_bytes(), 0)
  for i = 0; i < 8; i = i + 1 {
    hmac_inner_midstate[i] = state[i]
  }
  sha256_state_reset(state)
  sha256_compress(state, hmac_outer_block.unsafe_reinterpret_as_bytes(), 0)
  for i = 0; i < 8; i = i + 1 {
    hmac_outer_midstate[i] = state[i]
  }
  let snapshot = FixedArray::make(key_length, b'\x00')
  for i = 0; i < key_length; i = i + 1 {
    snapshot[i] = normalized[i]
  }
  hmac_cached_key.val = Some(snapshot.unsafe_reinterpret_as_bytes())
}

///|
pub fn hmac_sha256(key : Bytes, message : Bytes) -> Bytes {
  let normalized = if key.length() > 64 { sha256(key) } else { key }
  hmac_ensure_key_blocks(normalized)
  let state = sha256_work_state
  for i = 0; i < 8; i = i + 1 {
    state[i] = hmac_inner_midstate[i]
  }
  sha256_update(state, message)
  sha256_finish_into(state, message, 64, sha256_hmac_inner_digest)
  for i = 0; i < 8; i = i + 1 {
    state[i] = hmac_outer_midstate[i]
  }
  let digest = FixedArray::make(32, b'\x00')
  sha256_finish_into(
    state,
    sha256_hmac_inner_digest.unsafe_reinterpret_as_bytes(),
    64,
    digest,
  )
  digest.unsafe_reinterpret_as_bytes()
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
    difference = difference | (left[i] ^ right[i]).to_int()
  }
  difference == 0
}

///|
/// URL-safe base64 alphabet (RFC 4648 §5), used by signed tokens.
let base64url_alphabet : Bytes = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

///|
/// Encode bytes with the URL-safe base64 alphabet, without padding.
fn base64url_encode(data : Bytes) -> String {
  let length = data.length()
  if length == 0 {
    return ""
  }
  let alphabet = base64url_alphabet
  let full_groups = length / 3
  let remainder = length - full_groups * 3
  let out_len = full_groups * 4 +
    (if remainder == 1 { 2 } else if remainder == 2 { 3 } else { 0 })
  let out = FixedArray::make(out_len, b'A')
  let mut i = 0
  let mut out_index = 0
  while i + 3 <= length {
    let value = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    out[out_index] = alphabet[(value >> 18) & 63]
    out[out_index + 1] = alphabet[(value >> 12) & 63]
    out[out_index + 2] = alphabet[(value >> 6) & 63]
    out[out_index + 3] = alphabet[value & 63]
    i = i + 3
    out_index = out_index + 4
  }
  if remainder == 1 {
    let value = data[i].to_int() << 16
    out[out_index] = alphabet[(value >> 18) & 63]
    out[out_index + 1] = alphabet[(value >> 12) & 63]
  } else if remainder == 2 {
    let value = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8)
    out[out_index] = alphabet[(value >> 18) & 63]
    out[out_index + 1] = alphabet[(value >> 12) & 63]
    out[out_index + 2] = alphabet[(value >> 6) & 63]
  }
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes())
}

///|
/// Character code (0-255) to 6-bit value for URL-safe base64; `-`/`+` encode
/// 62 and `_`/`/` encode 63, other characters are `-1`.
let base64url_lookup : FixedArray[Int32] = {
  let table = FixedArray::make(256, -1)
  for i = 0; i < 26; i = i + 1 {
    table[65 + i] = i
    table[97 + i] = i + 26
  }
  for i = 0; i < 10; i = i + 1 {
    table[48 + i] = i + 52
  }
  table[43] = 62
  table[45] = 62
  table[47] = 63
  table[95] = 63
  table
}

///|
/// Decode URL-safe base64 text with optional padding. Returns `None` for
/// malformed input.
fn base64url_decode(text : String) -> Bytes? {
  base64url_decode_view(text.view())
}

///|
/// `base64url_decode` for a `StringView`.
fn base64url_decode_view(view : StringView) -> Bytes? {
  base64_decode_core(view, base64url_lookup)
}

///|
/// UTF-8 encoding of the most recent HMAC secret.
let last_secret_text : Ref[String?] = Ref(None)

///|
/// Encoded form matching `last_secret_text`.
let last_secret_bytes : Ref[Bytes?] = Ref(None)

///|
/// UTF-8 bytes of `secret`.
fn secret_utf8(secret : String) -> Bytes {
  match last_secret_text.val {
    Some(cached) =>
      if physical_equal(cached, secret) {
        match last_secret_bytes.val {
          Some(bytes) => return bytes
          None => ()
        }
      }
    None => ()
  }
  let bytes = encode_utf8_lossy(secret.view())
  last_secret_text.val = Some(secret)
  last_secret_bytes.val = Some(bytes)
  bytes
}

///|
fn parse_decimal_int64(view : StringView) -> Int64? {
  let length = view.length()
  if length == 0 || length > 19 {
    return None
  }
  let limit : UInt64 = 9223372036854775807UL
  let mut value = 0UL
  for i = 0; i < length; i = i + 1 {
    let code = view.unsafe_get(i).to_int()
    if code < 48 || code > 57 {
      return None
    }
    let digit = (code - 48).to_uint64()
    if value > (limit - digit) / 10UL {
      return None
    }
    value = value * 10UL + digit
  }
  Some(value.reinterpret_as_int64())
}

///|
fn signed_cookie_signing_input(
  name : String,
  encoded_value : StringView,
  expires_at : Int64,
) -> Bytes {
  let expiry = expires_at.to_string()
  let builder = StringBuilder(
    size_hint=name.length() + encoded_value.length() + expiry.length() + 2,
  )
  builder.write_string(name)
  builder.write_char('\n')
  builder.write_stringview(encoded_value)
  builder.write_char('.')
  builder.write_string(expiry)
  encode_utf8_lossy(builder.to_string().view())
}

///|
/// Most recently minted token and the inputs it was derived from.
let last_signed_token : Ref[(String, String, String, Int64, String)?] = Ref(
  None,
)

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
  match last_signed_token.val {
    Some((cached_secret, cached_name, cached_value, cached_deadline, token)) =>
      if cached_deadline == deadline &&
        cached_name == name &&
        cached_value == value &&
        cached_secret == secret {
        return token
      }
    None => ()
  }
  let encoded_value = base64url_encode(encode_utf8_lossy(value.view()))
  let mac = hmac_sha256(
    secret_utf8(secret),
    signed_cookie_signing_input(name, encoded_value.view(), deadline),
  )
  let token = encoded_value +
    "." +
    deadline.to_string() +
    "." +
    base64url_encode(mac)
  last_signed_token.val = Some((secret, name, value, deadline, token))
  token
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
  // The MAC only covers the canonical decimal expiry, so any other spelling of
  // the same deadline (leading zeros, ...) would otherwise verify.
  if deadline.to_string().view() != expiry_view {
    return None
  }
  // A negative deadline can only come from an overflow or an explicit
  // already-expired value. Treat it as expired instead of letting the
  // `deadline > 0` check below turn it into a never-expiring token.
  if deadline < 0L {
    return None
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
  let signature = match base64url_decode_view(signature_view) {
    Some(value) => value
    None => return None
  }
  if signature.length() != 32 {
    return None
  }
  // The decoder tolerates padding, `+`/`/` aliases, and non-zero trailing
  // bits, each of which would yield a different token text for the same MAC.
  // Require the canonical unpadded URL-safe spelling.
  if base64url_encode(signature).view() != signature_view {
    return None
  }
  let expected = hmac_sha256(
    secret_utf8(secret),
    signed_cookie_signing_input(name, encoded_value, deadline),
  )
  if !constant_time_bytes_equal(signature, expected) {
    return None
  }
  match base64url_decode_view(encoded_value) {
    Some(value) => Some(@utf8.decode_lossy(value))
    None => None
  }
}

///|
const MAX_SIGNED_COOKIE_DELTA_SECONDS : Int64 = 9223372036854775L

///|
const MAX_SIGNED_COOKIE_DEADLINE : Int64 = 9223372036854775807L

///|
fn signed_cookie_deadline(seconds : Int64, base : Int64) -> Int64 {
  if seconds <= 0L {
    return -1L
  }
  if seconds > MAX_SIGNED_COOKIE_DELTA_SECONDS {
    return MAX_SIGNED_COOKIE_DEADLINE
  }
  let delta = seconds * 1000L
  if delta > MAX_SIGNED_COOKIE_DEADLINE - base {
    return MAX_SIGNED_COOKIE_DEADLINE
  }
  base + delta
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
  expires? : Int64,
  domain? : String,
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
) -> Unit {
  // `set_cookie` stores the sanitized name, and the MAC must cover that exact
  // name so `signed_cookie` can verify the cookie the client actually sends
  // back, whichever spelling the caller uses.
  let cookie_name = sanitize_cookie_token(name, true)
  if cookie_name == "" {
    return
  }
  let by_max_age = match max_age {
    Some(seconds) => Some(signed_cookie_deadline(seconds, @async.now()))
    None => None
  }
  let by_expires = match expires {
    Some(seconds) => Some(signed_cookie_deadline(seconds, 0L))
    None => None
  }
  let expires_at = match (by_max_age, by_expires) {
    (Some(a), Some(b)) => Some(if a < b { a } else { b })
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
  // `0` is the token's "no expiry" sentinel, but an explicit epoch expiry (or
  // an overflowed deadline) must not turn into a token that never expires.
  let token = match expires_at {
    Some(deadline) =>
      if deadline <= 0L {
        signed_cookie_token(secret, cookie_name, value, expires_at=-1L)
      } else {
        signed_cookie_token(secret, cookie_name, value, expires_at=deadline)
      }
    None => signed_cookie_token(secret, cookie_name, value)
  }
  self.set_cookie(
    cookie_name,
    token,
    path?,
    max_age?,
    expires?,
    domain?,
    same_site?,
    http_only~,
    secure~,
    partitioned~,
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
  let cookie_name = sanitize_cookie_token(name, true)
  if cookie_name == "" {
    return None
  }
  match self.cookie(cookie_name) {
    Some(token) => verify_signed_cookie_token(secret, cookie_name, token)
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
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
) -> Unit {
  self.clear_cookie(
    name,
    path?,
    domain?,
    same_site?,
    http_only~,
    secure~,
    partitioned~,
  )
}
