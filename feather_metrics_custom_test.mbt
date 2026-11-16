///|
test "Metrics custom counters accumulate and sanitize names" {
  let metrics = @feather.Metrics::new()
  metrics.counter_add("cache-hits")
  metrics.counter_add("cache-hits", value=4L)
  metrics.counter_add("cache-hits", value=-1L)
  assert_eq(metrics.counter("cache_hits"), 4L)
  assert_eq(metrics.counter("cache-hits"), 4L)
  // The same family is reached through every spelling that sanitizes equal.
  metrics.counter_add("cache.hits")
  assert_eq(metrics.counter("cache_hits"), 5L)
  // A name that starts with an invalid character is replaced by an
  // underscore, which keeps the exposition valid.
  metrics.counter_add("1abc", value=2L)
  assert_eq(metrics.counter("_abc"), 2L)
  // An empty name falls back to a bare-underscore family.
  metrics.counter_add("")
  assert_eq(metrics.counter(""), 1L)
}

///|
test "Metrics custom gauges hold the last value" {
  let metrics = @feather.Metrics::new()
  metrics.gauge_set("queue-depth", 3.5)
  assert_eq(metrics.gauge("queue_depth"), 3.5)
  metrics.gauge_set("queue_depth", 7.0)
  assert_eq(metrics.gauge("queue-depth"), 7.0)
  assert_eq(metrics.gauge("unknown"), 0.0)
  // A non-finite value is ignored because the exposition cannot represent it.
  metrics.gauge_set("queue_depth", 0.0 / 0.0)
  assert_eq(metrics.gauge("queue_depth"), 7.0)
}

///|
test "Metrics set_help applies to existing families only" {
  let metrics = @feather.Metrics::new()
  metrics.set_help("later", "created first?")
  metrics.gauge_set("later", 1.0)
  assert_eq(metrics.gauge("later"), 1.0)
  let rendered = metrics.render()
  assert_false(rendered.contains("created first?"))
  metrics.counter_add("hits")
  metrics.set_help("hits", "Cache hits since start.")
  let document = metrics.render()
  assert_true(document.contains("# HELP hits Cache hits since start.\n"))
  assert_true(document.contains("# TYPE hits counter\n"))
  assert_true(document.contains("hits 1\n"))
}

///|
/// The line number of the first rendered line containing `needle`, or `-1`.
fn metrics_line_of(document : String, needle : String) -> Int {
  let mut number = 0
  for line in document.split("\n") {
    if line.contains(needle) {
      return number
    }
    number = number + 1
  }
  -1
}

///|
test "Metrics render appends custom families after the built-ins" {
  let metrics = @feather.Metrics::new()
  metrics.record("GET", "/users/:id", 200, 5L)
  metrics.gauge_set("z-depth", 2.25)
  metrics.counter_add("a-hits", value=9L)
  metrics.set_help("a-hits", "Counter renamed.")
  let document = metrics.render()
  let requests = @feather.METRICS_REQUESTS_METRIC
  // The built-in families come first and stay unchanged.
  assert_eq(
    document.split("\n").collect()[0].to_owned(),
    "# HELP \{requests} Total number of HTTP requests handled.",
  )
  // Custom families are sorted by name and carry their own HELP/TYPE lines.
  let hits = metrics_line_of(document, "# TYPE a_hits counter")
  let hits_sample = metrics_line_of(document, "a_hits 9")
  let depth_type = metrics_line_of(document, "# TYPE z_depth gauge")
  let depth_sample = metrics_line_of(document, "z_depth 2.25")
  let summary = metrics_line_of(document, "\{@feather.METRICS_DURATION_METRIC}_sum{")
  let help_line = metrics_line_of(document, "# HELP a_hits Counter renamed.")
  assert_true(help_line > summary)
  assert_true(hits > summary)
  assert_true(depth_type > hits)
  assert_eq(hits_sample, hits + 1)
  assert_eq(depth_sample, depth_type + 1)
  let suffix = "# HELP a_hits Counter renamed.\n# TYPE a_hits counter\na_hits 9\n# TYPE z_depth gauge\nz_depth 2.25\n"
  assert_true(document.ends_with(suffix))
}
