///|
async fn read_body(
  reader : &@io.Reader,
  limit : Int32,
  size_hint~ : Int32 = 0,
) -> String {
  @utf8.decode_lossy(read_body_bytes(reader, limit, size_hint~))
}

///|
async test "read_body utf8 split across chunks" {
  @async.with_task_group(group => {
    let (r, w) = @io.pipe()
    let full = "a".repeat(8191) + "世"
    let bytes = @utf8.encode(full)
    let chunk1 = bytes[0:8192]
    let chunk2 = bytes[8192:]
    group.spawn_bg(no_wait=true, () => {
      w.write(chunk1)
      w.write(chunk2)
      w.close()
    })
    let body = read_body(r, 100000)
    assert_eq(body, full)
  })
}
