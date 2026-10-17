///|
/// Session key prefix under which flash messages are kept.
const FLASH_PREFIX : String = "__flash:"

///|
/// Default flash category.
const FLASH_DEFAULT_CATEGORY : String = "default"

///|
/// Encode a list of flash messages as a JSON array, the representation stored
/// in the session.
fn flash_encode(messages : Array[String]) -> String {
  let items : Array[Json] = Array(capacity=messages.length())
  for message in messages {
    items.push(Json::string(message))
  }
  Json::array(items).stringify()
}

///|
/// Decode the JSON array written by `flash_encode`, ignoring malformed values
/// so a hand-edited session cannot take the request down.
fn flash_decode(text : String) -> Array[String] {
  let messages : Array[String] = []
  let parsed : Json = @json.parse(text) catch {
    _ => Json::null()
  }
  if parsed is Json::Array(items) {
    for item in items {
      if item is Json::String(value) {
        messages.push(value)
      }
    }
  }
  messages
}

///|
fn Context::flash_messages(self : Context, key : String) -> Array[String] {
  match self.session {
    Some(session) =>
      match session.data.get(key) {
        Some(text) => flash_decode(text)
        None => []
      }
    None => []
  }
}

///|
/// Queue a flash message for the next request handled with the same session.
///
/// Flash messages are the usual way to report the outcome of a redirect (for
/// example "Saved" or "Invalid password"): the handler for the current request
/// queues a message, and the handler that renders the next page takes it with
/// `Context::flash_take`. Messages are grouped by `category` so a layout can
/// render "errors" apart from "notices".
///
/// Returns `false` when the request has no session, for example when
/// `middleware_session` is not installed.
pub fn Context::flash(
  self : Context,
  message : String,
  category~ : String = FLASH_DEFAULT_CATEGORY,
) -> Bool {
  match self.session {
    Some(session) => {
      let key = FLASH_PREFIX + category
      let messages = self.flash_messages(key)
      messages.push(message)
      session.data.set(key, flash_encode(messages))
      session.modified = true
      true
    }
    None => false
  }
}

///|
/// Return the flash messages queued for `category` under this session and
/// remove them, so each message is shown exactly once. Returns `[]` when there
/// is no session or nothing was queued.
pub fn Context::flash_take(
  self : Context,
  category~ : String = FLASH_DEFAULT_CATEGORY,
) -> Array[String] {
  match self.session {
    Some(session) => {
      let key = FLASH_PREFIX + category
      match session.data.remove_and_get(key) {
        Some(text) => {
          session.modified = true
          flash_decode(text)
        }
        None => []
      }
    }
    None => []
  }
}

///|
/// Return every queued flash message, grouped by category, and remove them
/// from the session. Categories with no messages are left out; the returned
/// map is empty when there is no session or nothing was queued.
pub fn Context::flash_take_all(self : Context) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = Map([], capacity=4)
  match self.session {
    Some(session) => {
      let keys : Array[String] = []
      for key, _ in session.data {
        if key.has_prefix(FLASH_PREFIX) {
          keys.push(key)
        }
      }
      for key in keys {
        match session.data.remove_and_get(key) {
          Some(text) => {
            session.modified = true
            result.set(key[FLASH_PREFIX.length():].to_owned(), flash_decode(text))
          }
          None => ()
        }
      }
    }
    None => ()
  }
  result
}

///|
/// Look at the flash messages queued for `category` without consuming them.
/// Returns `[]` when there is no session or nothing was queued.
pub fn Context::flash_peek(
  self : Context,
  category~ : String = FLASH_DEFAULT_CATEGORY,
) -> Array[String] {
  self.flash_messages(FLASH_PREFIX + category)
}
