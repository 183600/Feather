///|
/// Context state key holding the number of trusted proxy hops configured
/// with `App::trust_proxy`.
const TRUST_PROXY_HOPS_KEY : String = "__feather_trust_proxy_hops"

///|
/// Helpers for the proxies that may sit in front of the application.
///
/// `App::trust_proxy` tells the framework how many of those proxies are
/// trusted, so `Context::ip` can report the address of the real client
/// instead of the address of the closest proxy.

///|
/// The `for=` node identifiers of every element of an RFC 7239 `Forwarded`
/// header, in the order the proxies processed the request.
///
/// The client-most proxy comes first, so the proxy closest to the application
/// is the last element. Elements whose `for=` parameter carries no address
/// (obfuscated or unknown nodes) are skipped.
fn forwarded_for_values(header : StringView) -> Array[String] {
  let values : Array[String] = []
  let length = header.length()
  let mut start = 0
  let mut i = 0
  let mut in_quotes = false
  while i <= length {
    let unit = if i < length { header.unsafe_get(i) } else { (',' : UInt16) }
    if in_quotes && unit == ('\\' : UInt16) && i + 1 < length {
      i = i + 2
      continue
    }
    if unit == ('"' : UInt16) {
      in_quotes = !in_quotes
    } else if unit == (',' : UInt16) && !in_quotes {
      match forwarded_element_param(header[start:i], "for".view()) {
        Some(value) =>
          match normalize_forwarded_for(value.view()) {
            Some(address) => values.push(address)
            None => ()
          }
        None => ()
      }
      start = i + 1
    }
    i = i + 1
  }
  values
}

///|
/// The client addresses recorded by the proxies in front of the application,
/// closest proxy first.
///
/// The RFC 7239 `Forwarded` header wins over `X-Forwarded-For`. Both list the
/// client first and the proxy closest to the application last, so the list is
/// reversed to report the closest proxy first. An empty list means that no
/// proxy recorded an address.
fn forwarded_chain(ctx : Context) -> Array[String] {
  let forwarded = ctx.header("Forwarded")
  if forwarded != "" {
    let values = forwarded_for_values(forwarded.view())
    if !values.is_empty() {
      return reverse_strings(values)
    }
  }
  let header = ctx.header("X-Forwarded-For")
  if header == "" {
    return []
  }
  let parts : Array[StringView] = []
  for part in header.view().split(",") {
    parts.push(part)
  }
  let chain : Array[String] = []
  let mut i = parts.length() - 1
  while i >= 0 {
    let value = trim_ascii_space(parts[i])
    if !value.is_empty() {
      chain.push(value.to_owned())
    }
    i = i - 1
  }
  chain
}

///|
/// A copy of `values` in reverse order.
fn reverse_strings(values : Array[String]) -> Array[String] {
  let reversed : Array[String] = []
  let mut i = values.length() - 1
  while i >= 0 {
    reversed.push(values[i])
    i = i - 1
  }
  reversed
}

///|
/// The address the application should treat as the client's, given the number
/// of trusted proxy hops.
///
/// The peer address comes first, followed by the addresses the proxies
/// recorded, closest proxy first. `hops` counts the trusted hops, so one
/// trusted proxy reports the address that proxy saw, and a negative count
/// trusts the whole chain and reports the original client.
fn trusted_client_address(
  peer : String,
  chain : Array[String],
  hops : Int32,
) -> String {
  if hops == 0 || chain.is_empty() {
    return peer
  }
  let last = chain.length() - 1
  let index = if hops < 0 || hops >= chain.length() { last } else { hops - 1 }
  chain[index]
}
