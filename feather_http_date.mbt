///|
pub fn status_text(code : Int32) -> String {
  match code {
    100 => "Continue"
    101 => "Switching Protocols"
    102 => "Processing"
    103 => "Early Hints"
    200 => "OK"
    201 => "Created"
    202 => "Accepted"
    203 => "Non-Authoritative Information"
    204 => "No Content"
    205 => "Reset Content"
    206 => "Partial Content"
    207 => "Multi-Status"
    208 => "Already Reported"
    226 => "IM Used"
    300 => "Multiple Choices"
    301 => "Moved Permanently"
    302 => "Found"
    303 => "See Other"
    304 => "Not Modified"
    305 => "Use Proxy"
    307 => "Temporary Redirect"
    308 => "Permanent Redirect"
    400 => "Bad Request"
    401 => "Unauthorized"
    402 => "Payment Required"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    406 => "Not Acceptable"
    407 => "Proxy Authentication Required"
    408 => "Request Timeout"
    409 => "Conflict"
    410 => "Gone"
    411 => "Length Required"
    412 => "Precondition Failed"
    413 => "Payload Too Large"
    414 => "URI Too Long"
    415 => "Unsupported Media Type"
    416 => "Range Not Satisfiable"
    417 => "Expectation Failed"
    418 => "I'm a Teapot"
    421 => "Misdirected Request"
    422 => "Unprocessable Entity"
    423 => "Locked"
    424 => "Failed Dependency"
    425 => "Too Early"
    426 => "Upgrade Required"
    428 => "Precondition Required"
    429 => "Too Many Requests"
    431 => "Request Header Fields Too Large"
    451 => "Unavailable For Legal Reasons"
    500 => "Internal Server Error"
    501 => "Not Implemented"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    504 => "Gateway Timeout"
    505 => "HTTP Version Not Supported"
    506 => "Variant Also Negotiates"
    507 => "Insufficient Storage"
    508 => "Loop Detected"
    510 => "Not Extended"
    511 => "Network Authentication Required"
    _ => "Unknown"
  }
}

///|
/// Number of days in `month` (1-12) of `year`, or 0 for an invalid month.
fn days_in_month(year : Int64, month : Int32) -> Int32 {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 =>
      if year % 4L == 0L && (year % 100L != 0L || year % 400L == 0L) {
        29
      } else {
        28
      }
    _ => 0
  }
}

///|
fn days_from_civil(year : Int64, month : Int32, day : Int32) -> Int64 {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = if month > 2 { month - 3 } else { month + 9 }
  let doy = (153L * mp.to_int64() + 2L) / 5L + day.to_int64() - 1L
  let doe = yoe * 365L + yoe / 4L - yoe / 100L + doy
  era * 146097L + doe - 719468L
}

///|
fn civil_from_days(days : Int64) -> (Int64, Int32, Int32) {
  if days < -1000000000L || days > 1000000000L {
    return civil_from_days_wide(days)
  }
  let z = days.to_int() + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let day = doy - (153 * mp + 2) / 5 + 1
  let month = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = if month <= 2 { y + 1 } else { y }
  (year.to_int64(), month, day)
}

///|
fn civil_from_days_wide(days : Int64) -> (Int64, Int32, Int32) {
  let z = days + 719468L
  let era = (if z >= 0 { z } else { z - 146096L }) / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let day = (doy - (153L * mp + 2L) / 5L + 1L).to_int()
  let month = if mp < 10L { (mp + 3L).to_int() } else { (mp - 9L).to_int() }
  let year = if month <= 2 { y + 1L } else { y }
  (year, month, day)
}

///|
let http_weekdays : Array[String] = [
  "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
]

///|
let http_months : Array[String] = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

///|
/// Full weekday names accepted by the obsolete `rfc850-date` grammar.
let http_weekdays_full : Array[String] = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
]

///|
/// Whether `name` is one of the three-letter weekday abbreviations or one of
/// the full names used by `rfc850-date`, matched case-insensitively.
fn is_http_weekday(name : StringView) -> Bool {
  let length = name.length()
  if length == 3 {
    for weekday in http_weekdays {
      if name.equal_ignore_ascii_case(weekday.view()) {
        return true
      }
    }
  } else {
    for weekday in http_weekdays_full {
      if name.equal_ignore_ascii_case(weekday.view()) {
        return true
      }
    }
  }
  false
}

///|
fn write_two_digits(builder : StringBuilder, value : Int32) -> Unit {
  if value >= 0 && value < 100 {
    if value < 10 {
      builder.write_char('0')
    } else {
      builder.write_char((48 + value / 10).unsafe_to_char())
    }
    builder.write_char((48 + value % 10).unsafe_to_char())
  } else if value < 10 {
    builder.write_char('0')
    builder.write_string(value.to_string())
  } else {
    builder.write_string(value.to_string())
  }
}

///|
fn write_year(builder : StringBuilder, year : Int64) -> Unit {
  if year >= 0L && year < 10000L {
    let value = year.to_int()
    builder.write_char((48 + value / 1000).unsafe_to_char())
    builder.write_char((48 + value / 100 % 10).unsafe_to_char())
    builder.write_char((48 + value / 10 % 10).unsafe_to_char())
    builder.write_char((48 + value % 10).unsafe_to_char())
  } else {
    builder.write_string(year.to_string())
  }
}

///|
pub fn format_http_date(unix_seconds : Int64) -> String {
  // HTTP-date spells the year with exactly four digits. Clamp values outside
  // the proleptic Gregorian years 0000..9999 so this infallible formatter never
  // emits a date that `parse_http_date` (or an HTTP recipient) must reject.
  let min_seconds = days_from_civil(0L, 1, 1) * 86400L
  let max_seconds = days_from_civil(9999L, 12, 31) * 86400L + 86399L
  let unix_seconds = if unix_seconds < min_seconds {
    min_seconds
  } else if unix_seconds > max_seconds {
    max_seconds
  } else {
    unix_seconds
  }
  let mut days = unix_seconds / 86400L
  let mut time_of_day = unix_seconds - days * 86400L
  if time_of_day < 0L {
    days = days - 1L
    time_of_day = time_of_day + 86400L
  }
  let (year, month, day) = civil_from_days(days)
  let mut weekday = (days + 4L) % 7L
  if weekday < 0L {
    weekday = weekday + 7L
  }
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  if time_of_day >= 0L && time_of_day < 86400L {
    let tod = time_of_day.to_int()
    hour = tod / 3600
    minute = tod % 3600 / 60
    second = tod % 60
  } else {
    hour = (time_of_day / 3600L).to_int()
    minute = (time_of_day % 3600L / 60L).to_int()
    second = (time_of_day % 60L).to_int()
  }
  let builder = StringBuilder(size_hint=29)
  builder.write_string(http_weekdays[weekday.to_int()])
  builder.write_string(", ")
  write_two_digits(builder, day)
  builder.write_char(' ')
  builder.write_string(http_months[month - 1])
  builder.write_char(' ')
  write_year(builder, year)
  builder.write_char(' ')
  write_two_digits(builder, hour)
  builder.write_char(':')
  write_two_digits(builder, minute)
  builder.write_char(':')
  write_two_digits(builder, second)
  builder.write_string(" GMT")
  builder.to_string()
}

///|
fn parse_decimal(view : StringView) -> Int32? {
  let length = view.length()
  if length == 0 {
    return None
  }
  let mut value = 0
  let mut i = 0
  while i < length {
    let digit = view.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    value = value * 10 + digit
    if value > 100000000 {
      return None
    }
    i = i + 1
  }
  Some(value)
}

///|
fn month_from_name(name : StringView) -> Int32? {
  let length = name.length()
  if length != 3 {
    return None
  }
  for i, month in http_months {
    // RFC 9110's HTTP-date grammar uses case-insensitive ABNF literals, so a
    // recipient must accept `nov` as well as `Nov` (and any other casing).
    if name.equal_ignore_ascii_case(month.view()) {
      return Some(i + 1)
    }
  }
  None
}

///|
fn parse_time_of_day(time : StringView) -> Int64? {
  let first_colon = match time.find(":") {
    Some(index) => index
    None => return None
  }
  let second_colon = match time[first_colon + 1:].find(":") {
    Some(index) => first_colon + 1 + index
    None => return None
  }
  let hour_text = time[:first_colon]
  let minute_text = time[first_colon + 1:second_colon]
  let second_text = time[second_colon + 1:]
  // HTTP-date's time-of-day grammar is fixed-width: `HH:MM:SS`. A one- or
  // three-digit field is malformed and must be ignored rather than treated as
  // a validator.
  if hour_text.length() != 2 ||
    minute_text.length() != 2 ||
    second_text.length() != 2 {
    return None
  }
  let hour = match parse_decimal(hour_text) {
    Some(hour) => hour
    None => return None
  }
  let minute = match parse_decimal(minute_text) {
    Some(minute) => minute
    None => return None
  }
  let second = match parse_decimal(second_text) {
    Some(second) => second
    None => return None
  }
  if hour > 23 || minute > 59 || second > 60 {
    return None
  }
  Some((hour * 3600 + minute * 60 + second).to_int64())
}

///|
fn imf_fixdate_two_digits(view : StringView, at : Int32) -> Int32 {
  let a = view.unsafe_get(at).to_int() - 48
  let b = view.unsafe_get(at + 1).to_int() - 48
  if a < 0 || a > 9 || b < 0 || b > 9 {
    return -1
  }
  a * 10 + b
}

///|
fn imf_fixdate_four_digits(view : StringView, at : Int32) -> Int32 {
  let a = view.unsafe_get(at).to_int() - 48
  let b = view.unsafe_get(at + 1).to_int() - 48
  let c = view.unsafe_get(at + 2).to_int() - 48
  let d = view.unsafe_get(at + 3).to_int() - 48
  if a < 0 || a > 9 || b < 0 || b > 9 || c < 0 || c > 9 || d < 0 || d > 9 {
    return -1
  }
  a * 1000 + b * 100 + c * 10 + d
}

///|
/// Parse the fixed-layout IMF-fixdate form (`Sun, 15 Jun 2025 10:20:30 GMT`)
/// without tokenizing, falling back to the general path on any deviation.
fn parse_imf_fixdate(view : StringView) -> Int64? {
  if view.length() != 29 {
    return None
  }
  if view.unsafe_get(3) != (',' : UInt16) ||
    view.unsafe_get(4) != (' ' : UInt16) ||
    view.unsafe_get(7) != (' ' : UInt16) ||
    view.unsafe_get(11) != (' ' : UInt16) ||
    view.unsafe_get(16) != (' ' : UInt16) ||
    view.unsafe_get(19) != (':' : UInt16) ||
    view.unsafe_get(22) != (':' : UInt16) ||
    view.unsafe_get(25) != (' ' : UInt16) {
    return None
  }
  // The tokenizing parser takes the RFC 1123 branch only when the first
  // whitespace-delimited token contains the comma, so a weekday with an
  // embedded space must fall back rather than parse.
  let mut weekday_start = 0
  while weekday_start < 4 && view.unsafe_get(weekday_start) == (' ' : UInt16) {
    weekday_start = weekday_start + 1
  }
  let mut weekday_end = weekday_start
  while weekday_end < 4 && view.unsafe_get(weekday_end) != (' ' : UInt16) {
    weekday_end = weekday_end + 1
  }
  if weekday_end != 4 || !is_http_weekday(view[:3]) {
    return None
  }
  // HTTP-date carries the GMT zone; anything else is not a valid date.
  if !view[26:29].equal_ignore_ascii_case("GMT".view()) {
    return None
  }
  let day = imf_fixdate_two_digits(view, 5)
  let month = match month_from_name(view[8:11]) {
    Some(month) => month
    None => return None
  }
  let year = imf_fixdate_four_digits(view, 12)
  let hour = imf_fixdate_two_digits(view, 17)
  let minute = imf_fixdate_two_digits(view, 20)
  let second = imf_fixdate_two_digits(view, 23)
  if day < 0 || year < 0 || hour < 0 || minute < 0 || second < 0 {
    return None
  }
  if day < 1 ||
    day > days_in_month(year.to_int64(), month) ||
    hour > 23 ||
    minute > 59 ||
    second > 60 {
    return None
  }
  Some(
    days_from_civil(year.to_int64(), month, day) * 86400L +
    (hour * 3600 + minute * 60 + second).to_int64(),
  )
}

///|
/// The current Gregorian year, used to expand the obsolete two-digit years of
/// `rfc850-date` values.
fn http_current_year() -> Int64 {
  let (year, _, _) = civil_from_days(@async.now() / 86_400_000L)
  year
}

///|
/// Expand an `rfc850-date` two-digit year as RFC 9110 §5.6.7 requires: a
/// timestamp that would appear more than 50 years in the future is read as the
/// most recent year in the past with the same last two digits.
fn expand_two_digit_year(two_digit : Int32) -> Int64 {
  let current = http_current_year()
  let candidate = current / 100L * 100L + two_digit.to_int64()
  if candidate > current + 50L {
    candidate - 100L
  } else {
    candidate
  }
}

///|
/// Expand an `rfc850-date` two-digit year using the full timestamp.
///
/// RFC 9110 §5.6.7 applies the 50-year rule to the timestamp, not merely to
/// the year: `31-Dec-76` is already more than 50 years in the future when
/// today is in October 2026, even though 2076 is only exactly 50 years ahead.
fn expand_two_digit_year_for_date(
  two_digit : Int32,
  month : Int32,
  day : Int32,
  seconds_of_day : Int64,
) -> Int64 {
  let now = @async.now() / 1000L
  let now_days = now / 86400L
  let now_time_of_day = now - now_days * 86400L
  let (current_year, current_month, current_day) = civil_from_days(now_days)
  let candidate = current_year / 100L * 100L + two_digit.to_int64()
  let threshold = days_from_civil(
    current_year + 50L,
    current_month,
    current_day,
  ) *
  86400L +
  now_time_of_day
  let candidate_seconds = days_from_civil(candidate, month, day) * 86400L +
    seconds_of_day
  if candidate_seconds > threshold {
    candidate - 100L
  } else {
    candidate
  }
}

///|
pub fn parse_http_date(value : String) -> Int64? {
  parse_http_date_view(value.view())
}

///|
/// `parse_http_date` for a view.
fn parse_http_date_view(view : StringView) -> Int64? {
  match parse_imf_fixdate(view) {
    Some(seconds) => return Some(seconds)
    None => ()
  }
  let length = view.length()
  // Count tokens to reject RFC-850 / asctime dates with unusual whitespace.
  let mut token_count = 0
  let mut probe = 0
  while probe < length {
    while probe < length && view.unsafe_get(probe) == (' ' : UInt16) {
      probe = probe + 1
    }
    if probe >= length {
      break
    }
    token_count = token_count + 1
    while probe < length && view.unsafe_get(probe) != (' ' : UInt16) {
      probe = probe + 1
    }
  }
  if token_count < 4 {
    return None
  }
  let parts : FixedArray[StringView] = FixedArray::make(6, "")
  let mut count = 0
  let mut i = 0
  while i < length && count < 6 {
    while i < length && view.unsafe_get(i) == (' ' : UInt16) {
      i = i + 1
    }
    if i >= length {
      break
    }
    let start = i
    while i < length && view.unsafe_get(i) != (' ' : UInt16) {
      i = i + 1
    }
    parts[count] = view[start:i]
    count = count + 1
  }
  if count < 4 {
    return None
  }
  let mut day = 0
  let mut month = 0
  let mut year = 0L
  let mut two_digit_year : Int32? = None
  let mut time = parts[0]
  if parts[1].contains("-") {
    let weekday = parts[0]
    if !weekday.has_suffix(",") ||
      !is_http_weekday(weekday[:weekday.length() - 1]) {
      return None
    }
    let date = parts[1]
    let first_dash = match date.find("-") {
      Some(index) => index
      None => return None
    }
    let second_dash = match date[first_dash + 1:].find("-") {
      Some(index) => first_dash + 1 + index
      None => return None
    }
    // HTTP-date spells the day with exactly two digits in both IMF-fixdate
    // and rfc850-date; a short token is a malformed date, not a validator.
    if first_dash != 2 {
      return None
    }
    day = match parse_decimal(date[:first_dash]) {
      Some(day) => day
      None => return None
    }
    month = match month_from_name(date[first_dash + 1:second_dash]) {
      Some(month) => month
      None => return None
    }
    let year_text = date[second_dash + 1:]
    let parsed_year = match parse_decimal(year_text) {
      Some(year) => year
      None => return None
    }
    if year_text.length() == 2 {
      // The final expansion depends on the full date and time, which is parsed
      // below; start from the current-century candidate here.
      let current = http_current_year()
      year = current / 100L * 100L + parsed_year.to_int64()
      two_digit_year = Some(parsed_year)
    } else if year_text.length() == 4 {
      year = parsed_year.to_int64()
    } else {
      return None
    }
    if token_count != 4 || !parts[3].equal_ignore_ascii_case("GMT".view()) {
      return None
    }
    time = parts[2]
  } else if parts[0].contains(",") {
    if count < 6 || token_count != 6 {
      return None
    }
    let weekday = parts[0]
    // The IMF-fixdate and RFC 1123 grammars spell the day-name with exactly
    // three letters; the full weekday names belong only to rfc850-date.
    if !weekday.has_suffix(",") ||
      weekday.length() != 4 ||
      !is_http_weekday(weekday[:3]) {
      return None
    }
    // IMF-fixdate uses a fixed two-digit day. The tokenizing fallback is only
    // for tolerated whitespace variations, not for malformed field widths.
    if parts[1].length() != 2 {
      return None
    }
    day = match parse_decimal(parts[1]) {
      Some(day) => day
      None => return None
    }
    month = match month_from_name(parts[2]) {
      Some(month) => month
      None => return None
    }
    // Both the IMF-fixdate and the legacy RFC 1123 form spell the year with
    // exactly four digits; a longer or zero-padded token is not an HTTP-date
    // and must not be mistaken for a far-future validator.
    if parts[3].length() != 4 {
      return None
    }
    year = match parse_decimal(parts[3]) {
      Some(year) => year.to_int64()
      None => return None
    }
    if !parts[5].equal_ignore_ascii_case("GMT".view()) {
      return None
    }
    time = parts[4]
  } else {
    if count < 5 || token_count != 5 {
      return None
    }
    // asctime-date also uses the three-letter day-name, not the full name
    // accepted by the obsolete rfc850-date form.
    if parts[0].length() != 3 || !is_http_weekday(parts[0]) {
      return None
    }
    month = match month_from_name(parts[1]) {
      Some(month) => month
      None => return None
    }
    // asctime pads a one-digit day with an extra space, so its token has one
    // or two digits; longer tokens are not part of the grammar.
    if parts[2].length() < 1 || parts[2].length() > 2 {
      return None
    }
    day = match parse_decimal(parts[2]) {
      Some(day) => day
      None => return None
    }
    time = parts[3]
    if parts[4].length() != 4 {
      return None
    }
    year = match parse_decimal(parts[4]) {
      Some(year) => year.to_int64()
      None => return None
    }
  }
  let seconds_of_day = match parse_time_of_day(time) {
    Some(seconds) => seconds
    None => return None
  }
  match two_digit_year {
    Some(two_digit) =>
      year = expand_two_digit_year_for_date(
        two_digit, month, day, seconds_of_day,
      )
    None => ()
  }
  if day < 1 || day > days_in_month(year, month) {
    return None
  }
  Some(days_from_civil(year, month, day) * 86400L + seconds_of_day)
}

