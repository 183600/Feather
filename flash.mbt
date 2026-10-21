///|
/// Session key prefix under which flash messages are kept.
const FLASH_PREFIX : String = "__flash:"

///|
/// Default flash category.
const FLASH_DEFAULT_CATEGORY : String = "default"

///|
/// Upper bound on messages retained per category. Extra messages are dropped
/// so a handler that never drains its flashes cannot grow the session value
/// without bound.
const FLASH_MAX_MESSAGES_PER_CATEGORY : Int = 32

///|
/// Upper bound on flash categories retained for one session.
const FLASH_MAX_CATEGORIES : Int = 16

///|
/// Approximate upper bound, in encoded characters, on the flash additions one
/// request may queue.
const FLASH_MAX_ENCODED_BYTES : Int = 8192

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
/// The request-local pending additions for this session, created on first use.
/// Messages queued by `Context::flash` land here and are encoded once, at
/// persist time.
fn Session::flash_pending_map(self : Session) -> Map[String, Array[String]] {
  match self.flash_pending {
    Some(pending) => pending
    None => {
      let pending : Map[String, Array[String]] = Map([])
      self.flash_pending = Some(pending)
      pending
    }
  }
}

///|
/// Approximate encoded size of one category's messages.
fn flash_message_bytes(messages : Array[String]) -> Int {
  let mut total = 0
  for message in messages {
    total = total + message.length() + 8
  }
  total
}

///|
/// Encoded size of the messages already stored under `key`, which are not part
/// of the current request's additions.
fn Session::flash_stored_bytes(self : Session, key : String) -> Int {
  match self.data.get(key) {
    Some(text) => flash_message_bytes(flash_decode(text))
    None => 0
  }
}

///|
/// Flash categories the session would retain if the current request's pending
/// additions were flushed: the keys already in the data plus the pending
/// categories that are new to it.
fn Session::flash_retained_categories(self : Session) -> Int {
  let mut categories = 0
  for key, _ in self.data {
    if key.has_prefix(FLASH_PREFIX) {
      categories = categories + 1
    }
  }
  match self.flash_pending {
    Some(pending) =>
      for category, _ in pending {
        if !self.data.contains(FLASH_PREFIX + category) {
          categories = categories + 1
        }
      }
    None => ()
  }
  categories
}

///|
/// Decode the messages stored in the session under `key`.
fn Context::flash_messages(self : Context, key : String) -> Array[String] {
  match self.session_materialized() {
    Some(session) =>
      match session.data.get(key) {
        Some(text) => flash_decode(text)
        None => []
      }
    None => []
  }
}

///|
/// Write pending additions into the session data, encoding each category once.
/// Values identical to what is already stored are left alone so a read-only
/// `flash_peek` does not mark the session as modified.
fn Session::flush_flash(self : Session) -> Unit {
  match self.flash_pending {
    Some(pending) => {
      self.flash_pending = None
      self.flash_pending_bytes = 0
      if pending.is_empty() {
        return
      }
      let mut categories = 0
      for key, _ in self.data {
        if key.has_prefix(FLASH_PREFIX) {
          categories = categories + 1
        }
      }
      for category, messages in pending {
        let key = FLASH_PREFIX + category
        if messages.is_empty() {
          if self.data.contains(key) {
            ignore(self.data.remove_and_get(key))
            self.modified = true
          }
        } else {
          if !self.data.contains(key) {
            if categories >= FLASH_MAX_CATEGORIES {
              continue
            }
            categories = categories + 1
          }
          let text = flash_encode(messages)
          if self.data.get(key) != Some(text) {
            self.data.set(key, text)
            self.modified = true
          }
        }
      }
    }
    None => ()
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
/// `middleware_session` is not installed. Messages beyond the per-category and
/// per-request caps are dropped.
pub fn Context::flash(
  self : Context,
  message : String,
  category~ : String = FLASH_DEFAULT_CATEGORY,
) -> Bool {
  match self.session_materialized() {
    Some(session) => {
      let pending = session.flash_pending_map()
      let is_new_category = !pending.contains(category)
      let messages = match pending.get(category) {
        Some(messages) => messages
        None => self.flash_messages(FLASH_PREFIX + category)
      }
      let adds_category = is_new_category &&
        !session.data.contains(FLASH_PREFIX + category)
      if !(adds_category &&
        session.flash_retained_categories() >= FLASH_MAX_CATEGORIES) &&
        messages.length() < FLASH_MAX_MESSAGES_PER_CATEGORY &&
        session.flash_pending_bytes + message.length() + 8 <=
        FLASH_MAX_ENCODED_BYTES {
        messages.push(message)
        pending.set(category, messages)
        session.flash_pending_bytes = session.flash_pending_bytes +
          message.length() +
          8
        session.modified = true
      }
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
  match self.session_materialized() {
    Some(session) => {
      let key = FLASH_PREFIX + category
      let mut taken : Array[String]? = None
      match session.flash_pending {
        Some(pending) =>
          match pending.remove_and_get(category) {
            Some(messages) => {
              let stored_bytes = session.flash_stored_bytes(key)
              ignore(session.data.remove_and_get(key))
              let added = flash_message_bytes(messages) - stored_bytes
              let remaining = session.flash_pending_bytes - added
              session.flash_pending_bytes = if remaining < 0 { 0 } else { remaining }
              session.modified = true
              taken = Some(messages)
            }
            None => ()
          }
        None => ()
      }
      match taken {
        Some(messages) => messages
        None =>
          match session.data.remove_and_get(key) {
            Some(text) => {
              session.modified = true
              flash_decode(text)
            }
            None => []
          }
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
  match self.session_materialized() {
    Some(session) => {
      let categories : Array[String] = []
      match session.flash_pending {
        Some(pending) =>
          for category, _ in pending {
            categories.push(category)
          }
        None => ()
      }
      for key, _ in session.data {
        if key.has_prefix(FLASH_PREFIX) {
          categories.push(key[FLASH_PREFIX.length():].to_owned())
        }
      }
      for category in categories {
        let mut taken : Array[String]? = None
        match session.flash_pending {
          Some(pending) =>
            match pending.remove_and_get(category) {
              Some(messages) => {
                let stored_bytes = session.flash_stored_bytes(
                  FLASH_PREFIX + category,
                )
                ignore(session.data.remove_and_get(FLASH_PREFIX + category))
                let added = flash_message_bytes(messages) - stored_bytes
                let remaining = session.flash_pending_bytes - added
                session.flash_pending_bytes = if remaining < 0 { 0 } else { remaining }
                taken = Some(messages)
              }
              None => ()
            }
          None => ()
        }
        let messages = match taken {
          Some(messages) => messages
          None =>
            match session.data.remove_and_get(FLASH_PREFIX + category) {
              Some(text) => flash_decode(text)
              None => continue
            }
        }
        session.modified = true
        if !messages.is_empty() {
          result.set(category, messages)
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
  match self.session_materialized() {
    Some(session) =>
      match session.flash_pending {
        Some(pending) =>
          match pending.get(category) {
            // Copy: callers must not be able to mutate the queued messages
            // (or bypass the flash byte accounting) through a peek.
            Some(messages) => messages.copy()
            None => self.flash_messages(FLASH_PREFIX + category)
          }
        None => self.flash_messages(FLASH_PREFIX + category)
      }
    None => []
  }
}
