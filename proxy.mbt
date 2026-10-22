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
/// header, in the order the proxies processed the request, together with
/// whether any element carried a `for=` parameter.
///
/// The client-most proxy comes first, so the proxy closest to the application
/// is the last element. An element whose `for=` parameter carries no address
/// (obfuscated or unknown nodes) is kept as an empty placeholder so trusted
/// hop counting still lines up with the elements the proxies appended.
fn forwarded_for_values(header : StringView) -> (Array[String], Bool) {
  let values : Array[String] = []
  let mut saw_for = false
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
        Some(value) => {
          saw_for = true
          match normalize_forwarded_for(value.view()) {
            Some(address) => values.push(address)
            None => values.push("")
          }
        }
        None => values.push("")
      }
      start = i + 1
    }
    i = i + 1
  }
  if saw_for {
    (values, true)
  } else {
    ([], false)
  }
}

///|
/// The client addresses recorded by the proxies in front of the application,
/// closest proxy first.
///
/// The RFC 7239 `Forwarded` header wins over `X-Forwarded-For` whenever one of
/// its elements carries a `for=` parameter. Both list the client first and the
/// proxy closest to the application last, so the list is reversed to report the
/// closest proxy first. Empty entries are retained as placeholders so hop
/// counting is not shifted by a proxy that recorded no address.
fn forwarded_chain(ctx : Context) -> Array[String] {
  let forwarded = ctx.header("Forwarded")
  if forwarded != "" {
    let (values, saw_for) = forwarded_for_values(forwarded.view())
    if saw_for {
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
    chain.push(trim_ascii_space(parts[i]).to_owned())
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
/// trusts the whole chain and reports the original client. When the selected
/// hop recorded no address, the peer address is reported instead of trusting a
/// different, client-controlled entry.
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
  let address = chain[index]
  if address == "" {
    peer
  } else {
    address
  }
}
