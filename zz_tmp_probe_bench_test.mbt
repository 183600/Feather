///|
test "probe-map-alloc" (b : @bench.T) {
  b.bench(() => {
    let m : Map[String, String] = Map([], capacity=0)
    b.keep(m.length())
  })
}
