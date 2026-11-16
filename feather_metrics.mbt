///|
/// The content type of the Prometheus text exposition format.
pub const METRICS_CONTENT_TYPE : String = "text/plain; version=0.0.4; charset=utf-8"

///|
/// The route label used for requests that did not match an ordinary route,
/// such as a `404` or a `405` answer.
pub const METRICS_UNMATCHED_ROUTE : String = "unmatched"

///|
/// The route label used for requests that were served by a static file mount.
pub const METRICS_STATIC_ROUTE : String = "static"

///|
/// The name of the request counter in the exposition.
pub const METRICS_REQUESTS_METRIC : String = "feather_http_requests_total"

///|
/// The name of the request duration summary in the exposition.
pub const METRICS_DURATION_METRIC : String = "feather_http_request_duration_milliseconds"

///|
/// One recorded series: the requests and the total time spent serving them for
/// a method, a route pattern and a response status.
pub(all) struct MetricsSeries {
  method : String
  route : String
  status : Int32
  count : Int64
  duration_sum : Int64
} derive(Debug)

///|
pub impl Show for MetricsSeries with fn to_string(self) {
  "@feather.MetricsSeries(\{self.method}, \{self.route}, \{self.status}, count=\{self.count}, duration_sum=\{self.duration_sum})"
}

///|
pub extend MetricsSeries with Show::{output, to_string}

///|
pub extend MetricsSeries with Debug::{to_repr}

///|
/// One application-defined metric family registered on a [`Metrics`]
/// registry: either a counter accumulated with `Metrics::counter_add` or a
/// gauge set with `Metrics::gauge_set`, plus the optional `# HELP` text
/// installed with `Metrics::set_help`.
pub(all) struct MetricsCustomFamily {
  /// `0` for a counter, `1` for a gauge.
  kind : Int32
  help : String
  counter : Int64
  gauge : Double
} derive(Debug)

///|
pub impl Show for MetricsCustomFamily with fn to_string(self) {
  let kind = if self.kind == 0 { "counter" } else { "gauge" }
  "@feather.MetricsCustomFamily(\{kind}, help=\{self.help}, counter=\{self.counter}, gauge=\{self.gauge})"
}

///|
pub extend MetricsCustomFamily with Show::{output, to_string}

///|
pub extend MetricsCustomFamily with Debug::{to_repr}

///|
/// Request counters and latency sums, grouped by request method, route pattern
/// and response status.
///
/// The registry is bounded by the number of routes an application registers:
/// the route pattern is the registered one (`/users/:id`), not the concrete
/// request target, so a client cannot create a new series for every id it
/// asks for. Requests that did not match a route are grouped under
/// [`METRICS_UNMATCHED_ROUTE`], and requests served by a static file mount
/// under [`METRICS_STATIC_ROUTE`].
///
/// Besides the built-in HTTP families, an application can expose its own
/// counters and gauges with `Metrics::counter_add` and `Metrics::gauge_set`,
/// rendered in the same exposition document.
pub(all) struct Metrics {
  series : Map[String, MetricsSeries]
  custom : Map[String, MetricsCustomFamily]
} derive(Debug)

///|
pub impl Show for Metrics with fn to_string(self) {
  "@feather.Metrics(series=\{self.series.length()})"
}

///|
pub extend Metrics with Show::{output, to_string}

///|
pub extend Metrics with Debug::{to_repr}

///|
/// Create an empty metrics registry.
pub fn Metrics::new() -> Metrics {
  { series: Map([], capacity=16), custom: Map([], capacity=8) }
}

///|
/// The number of series the registry holds.
pub fn Metrics::series_count(self : Metrics) -> Int32 {
  self.series.length()
}

///|
/// The total number of recorded requests.
pub fn Metrics::total(self : Metrics) -> Int64 {
  let mut total = 0L
  for _, series in self.series {
    total = total + series.count
  }
  total
}

///|
/// The number of recorded requests for one method, route and status.
pub fn Metrics::count(
  self : Metrics,
  method : String,
  route : String,
  status : Int32,
) -> Int64 {
  match self.series.get(metrics_series_key(method, route, status)) {
    Some(series) => series.count
    None => 0L
  }
}

///|
/// The total time, in milliseconds, spent serving the requests of one method,
/// route and status.
pub fn Metrics::duration_sum(
  self : Metrics,
  method : String,
  route : String,
  status : Int32,
) -> Int64 {
  match self.series.get(metrics_series_key(method, route, status)) {
    Some(series) => series.duration_sum
    None => 0L
  }
}

///|
/// Sanitize a metric name so the exposition stays valid: Prometheus metric
/// names accept `[a-zA-Z_:]` for the first character and `[a-zA-Z0-9_:]`
/// afterwards; every other character is replaced with `_`.
fn metrics_sanitize_name(name : String) -> String {
  let length = name.length()
  let builder = StringBuilder(size_hint=length + 1)
  let mut index = 0
  while index < length {
    let code = name.unsafe_get(index).to_int()
    let valid = if index == 0 {
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 95 ||
      code == 58
    } else {
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) ||
      code == 95 ||
      code == 58
    }
    if valid {
      builder.write_char(name.unsafe_get(index).unsafe_to_char())
    } else {
      builder.write_char('_')
    }
    index = index + 1
  }
  let clean = builder.to_string()
  if clean == "" {
    // An empty (or all-invalid) name would render an invalid exposition;
    // fall back to a valid bare-underscore name instead.
    return "_"
  }
  clean
}

///|
/// Store one application-defined family, creating it when absent. `make`
/// builds a fresh family for a name that is not registered yet.
fn Metrics::custom_family(
  self : Metrics,
  name : String,
  kind : Int32,
  make : () -> MetricsCustomFamily,
) -> String {
  let clean = metrics_sanitize_name(name)
  match self.custom.get(clean) {
    Some(_) => ()
    None => self.custom.set(clean, make())
  }
  clean
}

///|
/// Add `value` (1 by default) to the application-defined counter `name`,
/// creating the counter family on first use. The name is sanitized before it
/// is stored, so `counter_add("cache-hits")` and `Metrics::counter("cache_hits")`
/// refer to the same family.
pub fn Metrics::counter_add(
  self : Metrics,
  name : String,
  value? : Int64,
) -> Unit {
  let clean = self.custom_family(name, 0, fn() {
    { kind: 0, help: "", counter: 0L, gauge: 0.0 }
  })
  match self.custom.get(clean) {
    Some(family) =>
      if family.kind == 0 {
        self.custom.set(
          clean,
          { ..family, counter: family.counter + value.unwrap_or(1L) },
        )
      }
    None => ()
  }
}

///|
/// The current value of the application-defined counter `name`, or `0` when
/// the counter was never added to.
pub fn Metrics::counter(self : Metrics, name : String) -> Int64 {
  match self.custom.get(metrics_sanitize_name(name)) {
    Some(family) => if family.kind == 0 { family.counter } else { 0L }
    None => 0L
  }
}

///|
/// Set the application-defined gauge `name` to `value`, creating the gauge
/// family on first use. A value that is not finite (`nan`/`inf`) is ignored,
/// because the exposition format cannot represent it.
pub fn Metrics::gauge_set(self : Metrics, name : String, value : Double) -> Unit {
  if value.is_nan() || value.is_inf() {
    return
  }
  let clean = self.custom_family(name, 1, fn() {
    { kind: 1, help: "", counter: 0L, gauge: 0.0 }
  })
  match self.custom.get(clean) {
    Some(family) =>
      if family.kind == 1 {
        self.custom.set(clean, { ..family, gauge: value })
      }
    None => ()
  }
}

///|
/// The current value of the application-defined gauge `name`, or `0.0` when
/// the gauge was never set.
pub fn Metrics::gauge(self : Metrics, name : String) -> Double {
  match self.custom.get(metrics_sanitize_name(name)) {
    Some(family) => if family.kind == 1 { family.gauge } else { 0.0 }
    None => 0.0
  }
}

///|
/// Set the `# HELP` text of the family `name`, which must already exist (be
/// created by `Metrics::counter_add` or `Metrics::gauge_set` first); a help
/// text for an unknown name is ignored.
pub fn Metrics::set_help(self : Metrics, name : String, help : String) -> Unit {
  let clean = metrics_sanitize_name(name)
  match self.custom.get(clean) {
    Some(family) => self.custom.set(clean, { ..family, help })
    None => ()
  }
}

///|
/// Whether the registry holds any application-defined family.
fn Metrics::has_custom(self : Metrics) -> Bool {
  self.custom.length() > 0
}

///|
/// The application-defined families, ordered by sanitized name so the
/// exposition is stable between scrapes.
fn Metrics::sorted_custom(self : Metrics) -> Array[(String, MetricsCustomFamily)] {
  let entries : Array[(String, MetricsCustomFamily)] = []
  for name, family in self.custom {
    entries.push((name, family))
  }
  entries.sort_by(fn(a, b) { a.0.lexical_compare(b.0) })
  entries
}

///|
/// Render the application-defined families in the exposition format, after
/// the built-in HTTP families.
fn Metrics::render_custom(
  self : Metrics,
  buf : StringBuilder,
) -> Unit {
  for entry in self.sorted_custom() {
    let (name, family) = entry
    if family.help != "" {
      buf.write_string("# HELP ")
      buf.write_string(name)
      buf.write_char(' ')
      buf.write_string(family.help)
      buf.write_char('\n')
    }
    buf.write_string("# TYPE ")
    buf.write_string(name)
    buf.write_char(' ')
    if family.kind == 0 {
      buf.write_string("counter\n")
      buf.write_string(name)
      buf.write_char(' ')
      buf.write_object(family.counter)
      buf.write_char('\n')
    } else {
      buf.write_string("gauge\n")
      buf.write_string(name)
      buf.write_char(' ')
      buf.write_object(family.gauge)
      buf.write_char('\n')
    }
  }
}

///|
/// Record one request.
pub fn Metrics::record(
  self : Metrics,
  method : String,
  route : String,
  status : Int32,
  duration_ms : Int64,
) -> Unit {
  let key = metrics_series_key(method, route, status)
  match self.series.get(key) {
    Some(series) =>
      self.series.set(key, {
        method: series.method,
        route: series.route,
        status: series.status,
        count: series.count + 1,
        duration_sum: series.duration_sum + duration_ms,
      })
    None =>
      self.series.set(key, {
        method,
        route,
        status,
        count: 1L,
        duration_sum: duration_ms,
      })
  }
}

///|
/// The recorded series, ordered by method, route and status so the exposition
/// is stable between scrapes.
fn Metrics::sorted_series(self : Metrics) -> Array[MetricsSeries] {
  let entries : Array[MetricsSeries] = []
  for _, series in self.series {
    entries.push(series)
  }
  entries.sort_by(fn(a, b) {
    let by_method = a.method.lexical_compare(b.method)
    if by_method != 0 {
      return by_method
    }
    let by_route = a.route.lexical_compare(b.route)
    if by_route != 0 {
      return by_route
    }
    a.status.compare(b.status)
  })
  entries
}

///|
/// Render the registry in the Prometheus text exposition format.
///
/// The document holds two built-in metric families: a counter of the handled
/// requests and a summary of the time spent handling them, both labelled with
/// the request method, the route pattern and the response status. Any
/// application-defined families registered with `Metrics::counter_add`,
/// `Metrics::gauge_set` and `Metrics::set_help` are rendered after them,
/// sorted by name.
pub fn Metrics::render(self : Metrics) -> String {
  let entries = self.sorted_series()
  let buf = StringBuilder(size_hint=256 + entries.length() * 96)
  buf.write_string("# HELP ")
  buf.write_string(METRICS_REQUESTS_METRIC)
  buf.write_string(" Total number of HTTP requests handled.\n")
  buf.write_string("# TYPE ")
  buf.write_string(METRICS_REQUESTS_METRIC)
  buf.write_string(" counter\n")
  for series in entries {
    buf.write_string(METRICS_REQUESTS_METRIC)
    metrics_write_labels(buf, series)
    buf.write_char(' ')
    buf.write_object(series.count)
    buf.write_char('\n')
  }
  buf.write_string("# HELP ")
  buf.write_string(METRICS_DURATION_METRIC)
  buf.write_string(" Time spent handling HTTP requests, in milliseconds.\n")
  buf.write_string("# TYPE ")
  buf.write_string(METRICS_DURATION_METRIC)
  buf.write_string(" summary\n")
  for series in entries {
    buf.write_string(METRICS_DURATION_METRIC)
    buf.write_string("_count")
    metrics_write_labels(buf, series)
    buf.write_char(' ')
    buf.write_object(series.count)
    buf.write_char('\n')
    buf.write_string(METRICS_DURATION_METRIC)
    buf.write_string("_sum")
    metrics_write_labels(buf, series)
    buf.write_char(' ')
    buf.write_object(series.duration_sum)
    buf.write_char('\n')
  }
  if self.has_custom() {
    self.render_custom(buf)
  }
  buf.to_string()
}

///|
/// Write the registry to `ctx` as a `200` response in the Prometheus text
/// exposition format.
pub fn Metrics::write(self : Metrics, ctx : Context) -> Unit {
  ctx.text(200, self.render())
  ctx.set_content_type(
    "text/plain",
    parameters=[("version", "0.0.4"), ("charset", "utf-8")],
  )
}

///|
/// The key a series is stored under.
///
/// The parts are length-prefixed, so two different series can never share a
/// key even when a route pattern contains the separator characters.
fn metrics_series_key(method : String, route : String, status : Int32) -> String {
  method.length().to_string() +
  ":" +
  method +
  route.length().to_string() +
  ":" +
  route +
  status.to_string()
}

///|
/// Write the label set of one series.
fn metrics_write_labels(buf : StringBuilder, series : MetricsSeries) -> Unit {
  buf.write_string("{method=\"")
  metrics_write_escaped(buf, series.method)
  buf.write_string("\",route=\"")
  metrics_write_escaped(buf, series.route)
  buf.write_string("\",status=\"")
  buf.write_object(series.status)
  buf.write_string("\"}")
}

///|
/// Write a label value, escaping the characters the exposition format treats
/// specially.
fn metrics_write_escaped(buf : StringBuilder, value : String) -> Unit {
  let length = value.length()
  let mut start = 0
  let mut i = 0
  while i < length {
    let code = value.unsafe_get(i)
    let escaped = if code == ('\\' : UInt16) {
      Some("\\\\")
    } else if code == ('"' : UInt16) {
      Some("\\\"")
    } else if code == ('\n' : UInt16) {
      Some("\\n")
    } else {
      None
    }
    match escaped {
      Some(text) => {
        if start < i {
          buf.write_view(value.exact_view(start=start, end=i))
        }
        buf.write_string(text)
        start = i + 1
      }
      None => ()
    }
    i = i + 1
  }
  if start < length {
    buf.write_view(value.exact_view(start=start))
  }
}

///|
/// The route label of a request: the registered route pattern when a route
/// matched, the static marker for a static file mount, and the unmatched
/// marker otherwise.
fn metrics_route_label(ctx : Context) -> String {
  let pattern = ctx.route_pattern()
  if pattern != "" {
    return pattern
  }
  if ctx.state.get(STATIC_CHAIN_PASS_KEY) is Some(_) {
    return METRICS_STATIC_ROUTE
  }
  METRICS_UNMATCHED_ROUTE
}

///|
/// Record one request in the registry.
fn metrics_record_request(
  ctx : Context,
  metrics : Metrics,
  started : Int64,
) -> Unit {
  metrics.record(
    ctx.get_method(),
    metrics_route_label(ctx),
    ctx.response.status,
    @async.now() - started,
  )
}

///|
/// Middleware that records a request counter and the time spent handling each
/// request in a [`Metrics`] registry.
///
/// The series are labelled with the request method, the registered route
/// pattern and the response status, so a scrape groups the requests by route
/// instead of by concrete target. Requests that did not reach a route (a `404`,
/// a `405`, or a request that an earlier middleware rejected) are grouped under
/// [`METRICS_UNMATCHED_ROUTE`], and requests served by a static file mount
/// under [`METRICS_STATIC_ROUTE`].
///
/// Install the middleware before the handlers it should measure, and expose the
/// registry with a route of its own:
///
/// ```moonbit
/// let metrics = @feather.Metrics::new()
/// let app = @feather.App::new()
///   .use(@feather.middleware_metrics(metrics))
///   .get("/metrics", fn(ctx) { metrics.write(ctx) })
/// ```
pub fn middleware_metrics(metrics : Metrics) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      let started = @async.now()
      // The error is rendered by an outer recovery middleware, so the status
      // is not known yet; the framework error carries it. The bookkeeping
      // itself lives in `errdefer` so a cancelled request (which a `catch`
      // block will not see under the upcoming cancellation semantics) is still
      // recorded; a cancellation carries no framework status, so the request
      // falls back to `500`.
      let mut failure_status = 500
      errdefer {
        ctx.response.status = failure_status
        metrics_record_request(ctx, metrics, started)
      }
      next(ctx) catch {
        err => {
          failure_status = error_status(err)
          raise err
        }
      }
      // Static files and asynchronous endpoints are written after the
      // middleware chain returns, so their real status is not known yet.
      // Defer the record until request cleanup, after the server has filled it
      // in.
      if ctx.state.get(STATIC_CHAIN_PASS_KEY) is Some(_) ||
        ctx.state.get(ASYNC_ENDPOINT_KEY) is Some(_) ||
        ctx.state.get(ASYNC_CHAIN_PASS_KEY) is Some(_) {
        ctx.defer_cleanup(fn() {
          metrics_record_request(ctx, metrics, started)
        })
      } else {
        metrics_record_request(ctx, metrics, started)
      }
    }
  }
}
