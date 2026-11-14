///|
/// A parsed IP address.
///
/// An IPv4 address is stored in the low 32 bits of `lo`, which is also how an
/// IPv4-mapped IPv6 address (`::ffff:a.b.c.d`) is normalized, so the two forms
/// of the same address compare equal.
priv struct IpAddress {
  hi : UInt64
  lo : UInt64
  is_v4 : Bool
}

///|
/// A parsed address rule: the network address and the number of leading bits
/// that have to match.
priv struct IpRule {
  address : IpAddress
  prefix : Int32
}

///|
/// Parse an IPv4 address into its 32-bit value.
///
/// Octets with a leading zero are rejected: `010.0.0.1` is read as octal by
/// some resolvers, so accepting it would let a rule match an address the
/// client never claimed.
fn parse_ipv4_value(text : StringView) -> UInt64? {
  let parts : Array[StringView] = []
  for part in text.split(".") {
    parts.push(part)
  }
  if parts.length() != 4 {
    return None
  }
  let mut value = 0UL
  for part in parts {
    let length = part.length()
    if length == 0 || length > 3 {
      return None
    }
    if length > 1 && part.unsafe_get(0) == ('0' : UInt16) {
      return None
    }
    let mut octet = 0UL
    let mut i = 0
    while i < length {
      let digit = part.unsafe_get(i).to_int() - 48
      if digit < 0 || digit > 9 {
        return None
      }
      octet = octet * 10UL + digit.to_uint64()
      i = i + 1
    }
    if octet > 255UL {
      return None
    }
    value = (value << 8) | octet
  }
  Some(value)
}

///|
/// Parse the hexadecimal groups of one side of an IPv6 address.
fn parse_ipv6_groups(text : StringView) -> Array[UInt64]? {
  if text.is_empty() {
    return Some([])
  }
  let groups : Array[UInt64] = []
  for part in text.split(":") {
    let length = part.length()
    if length == 0 || length > 4 {
      return None
    }
    let mut value = 0UL
    let mut i = 0
    while i < length {
      let digit = hex_digit_value(part.unsafe_get(i))
      if digit < 0 {
        return None
      }
      value = value * 16UL + digit.to_uint64()
      i = i + 1
    }
    groups.push(value)
  }
  Some(groups)
}

///|
/// Parse an IPv6 address into its high and low 64-bit halves.
///
/// The address may use the `::` compression once and may end with a dotted-quad
/// IPv4 tail, which contributes the last two groups.
fn parse_ipv6_value(text : StringView) -> (UInt64, UInt64)? {
  let mut body = text
  let tail : Array[UInt64] = []
  if body.contains(".") {
    // The dotted-quad tail is the last part of the address and is preceded by
    // a colon; an address without one is not an IPv6 address at all.
    let split = match body.rev_find(":") {
      Some(index) => index
      None => return None
    }
    let value = match parse_ipv4_value(body[split + 1:]) {
      Some(value) => value
      None => return None
    }
    tail.push((value >> 16) & 0xFFFFUL)
    tail.push(value & 0xFFFFUL)
    body = body[:split]
  }
  let compressed = body.find("::")
  let head_text = match compressed {
    Some(index) => body[:index]
    None => body
  }
  let tail_text = match compressed {
    Some(index) => body[index + 2:]
    None => ""
  }
  let head = match parse_ipv6_groups(head_text) {
    Some(groups) => groups
    None => return None
  }
  let rest = match compressed {
    Some(_) =>
      match parse_ipv6_groups(tail_text) {
        Some(groups) => groups
        None => return None
      }
    None => []
  }
  let total = head.length() + rest.length() + tail.length()
  if compressed is None {
    if total != 8 {
      return None
    }
  } else if total > 7 {
    // `::` stands for at least one group of zeros.
    return None
  }
  let words : Array[UInt64] = []
  for word in head {
    words.push(word)
  }
  let mut zeros = 8 - total
  while zeros > 0 {
    words.push(0UL)
    zeros = zeros - 1
  }
  for word in rest {
    words.push(word)
  }
  for word in tail {
    words.push(word)
  }
  let hi = (words[0] << 48) | (words[1] << 32) | (words[2] << 16) | words[3]
  let lo = (words[4] << 48) | (words[5] << 32) | (words[6] << 16) | words[7]
  Some((hi, lo))
}

///|
/// Parse an IP address, either IPv4 or IPv6.
fn parse_ip_address(text : StringView) -> IpAddress? {
  if text.is_empty() {
    return None
  }
  if text.contains(":") {
    let (hi, lo) = match parse_ipv6_value(text) {
      Some(value) => value
      None => return None
    }
    // An IPv4-mapped address describes the same host as the IPv4 address it
    // embeds, so it is normalized to that form.
    if hi == 0UL && (lo >> 32) == 0xFFFFUL {
      return Some({ hi: 0UL, lo: lo & 0xFFFFFFFFUL, is_v4: true })
    }
    return Some({ hi, lo, is_v4: false })
  }
  if text.contains(".") {
    let value = match parse_ipv4_value(text) {
      Some(value) => value
      None => return None
    }
    return Some({ hi: 0UL, lo: value, is_v4: true })
  }
  None
}

///|
/// Parse the prefix length of a CIDR block.
fn parse_ip_prefix(text : StringView) -> Int32? {
  let length = text.length()
  if length == 0 || length > 3 {
    return None
  }
  let mut value = 0
  let mut i = 0
  while i < length {
    let digit = text.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    value = value * 10 + digit
    i = i + 1
  }
  Some(value)
}

///|
/// Parse one address rule: a plain address or a CIDR block.
fn parse_ip_rule(text : StringView) -> IpRule? {
  let trimmed = trim_ascii_space(text)
  match trimmed.find("/") {
    Some(index) => {
      let address = match parse_ip_address(trimmed[:index]) {
        Some(address) => address
        None => return None
      }
      let prefix = match parse_ip_prefix(trimmed[index + 1:]) {
        Some(prefix) => prefix
        None => return None
      }
      let max = if address.is_v4 { 32 } else { 128 }
      if prefix > max {
        return None
      }
      Some({ address, prefix })
    }
    None => {
      let address = match parse_ip_address(trimmed) {
        Some(address) => address
        None => return None
      }
      Some({
        address,
        prefix: if address.is_v4 { 32 } else { 128 },
      })
    }
  }
}

///|
/// Parse the rules of a filter, dropping the entries that are not valid
/// addresses or blocks.
fn parse_ip_rules(entries : Array[String]) -> Array[IpRule] {
  let rules : Array[IpRule] = []
  for entry in entries {
    match parse_ip_rule(entry.view()) {
      Some(rule) => rules.push(rule)
      None => ()
    }
  }
  rules
}

///|
/// Whether the first `prefix` bits of two 128-bit addresses are equal.
fn ip_prefix_match(
  hi : UInt64,
  lo : UInt64,
  base_hi : UInt64,
  base_lo : UInt64,
  prefix : Int32,
) -> Bool {
  if prefix <= 0 {
    return true
  }
  if prefix <= 64 {
    let mask = 0xFFFFFFFFFFFFFFFFUL << (64 - prefix)
    return (hi & mask) == (base_hi & mask)
  }
  if hi != base_hi {
    return false
  }
  let low_prefix = prefix - 64
  if low_prefix >= 64 {
    return lo == base_lo
  }
  let mask = 0xFFFFFFFFFFFFFFFFUL << (64 - low_prefix)
  (lo & mask) == (base_lo & mask)
}

///|
/// Whether the first `prefix` bits of two 32-bit addresses are equal.
fn ip_prefix_match_32(
  value : UInt64,
  base : UInt64,
  prefix : Int32,
) -> Bool {
  if prefix <= 0 {
    return true
  }
  if prefix >= 32 {
    return value == base
  }
  let mask = 0xFFFFFFFFUL << (32 - prefix)
  (value & mask) == (base & mask)
}

///|
/// Whether an address belongs to a rule.
///
/// An IPv4 address never belongs to an IPv6 block and the other way round, so
/// a rule cannot match an address of another family by accident.
fn ip_rule_matches(rule : IpRule, address : IpAddress) -> Bool {
  if rule.address.is_v4 != address.is_v4 {
    return false
  }
  if rule.address.is_v4 {
    ip_prefix_match_32(address.lo, rule.address.lo, rule.prefix)
  } else {
    ip_prefix_match(
      address.hi,
      address.lo,
      rule.address.hi,
      rule.address.lo,
      rule.prefix,
    )
  }
}

///|
/// The client address of a request, without the brackets of an IPv6 literal
/// and without an IPv4 port.
fn ip_client_address(ctx : Context) -> String {
  let raw = trim_ascii_space(ctx.ip().view())
  if raw.is_empty() {
    return ""
  }
  if raw.unsafe_get(0) == ('[' : UInt16) {
    return match raw.find("]") {
      Some(index) => raw[1:index].to_owned()
      None => ""
    }
  }
  match raw.find(":") {
    Some(index) =>
      match raw[index + 1:].find(":") {
        // More than one colon: the address is an IPv6 literal.
        Some(_) => raw.to_owned()
        None =>
          if raw.contains(".") {
            raw[:index].to_owned()
          } else {
            raw.to_owned()
          }
      }
    None => raw.to_owned()
  }
}

///|
/// Middleware that filters requests by the client's IP address.
///
/// `allow` lists the addresses and networks that may reach the handler: a
/// client whose address is in none of them is rejected with `403 Forbidden`
/// before the handler runs. An empty `allow` list rejects every request.
/// `deny` lists the addresses and networks that are always rejected, even when
/// they are also covered by `allow`.
///
/// An entry is either a plain address (`192.0.2.1`, `2001:db8::1`) or a CIDR
/// block (`192.0.2.0/24`, `2001:db8::/32`). Entries that are not valid
/// addresses or blocks are ignored, so an allowlist whose entries are all
/// invalid rejects every request instead of opening the filter, and an
/// address of the other family never matches a rule.
///
/// The client address is the one `Context::ip` reports, which is the peer
/// address of the connection unless the application trusts proxies with
/// `App::trust_proxy`. The forwarded headers are not consulted directly, so a
/// client cannot choose its own address.
pub fn middleware_ip_filter(
  allow? : Array[String],
  deny? : Array[String],
) -> Middleware {
  let allowed = match allow {
    Some(entries) => Some(parse_ip_rules(entries))
    None => None
  }
  let denied = match deny {
    Some(entries) => parse_ip_rules(entries)
    None => []
  }
  fn(next) {
    fn(ctx) raise {
      let raw = ip_client_address(ctx)
      let address = parse_ip_address(raw.view())
      let mut rejected = false
      if address is Some(client) {
        for rule in denied {
          if ip_rule_matches(rule, client) {
            rejected = true
            break
          }
        }
      }
      if !rejected {
        match allowed {
          Some(rules) => {
            let mut matched = false
            if address is Some(client) {
              for rule in rules {
                if ip_rule_matches(rule, client) {
                  matched = true
                  break
                }
              }
            }
            // An address that cannot be parsed is never covered by a rule, so
            // an allowlist rejects it as well.
            rejected = !matched
          }
          None => ()
        }
      }
      if rejected {
        clear_replaced_representation_headers(ctx.response.headers)
        ctx.text(403, "403 Forbidden")
      } else {
        next(ctx)
      }
    }
  }
}
