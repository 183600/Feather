pub typealias Handler = async (Ctx) -> Unit

struct TrieNode {
  static_children : Map[String, TrieNode]
  param_child : (String, TrieNode)?
  wildcard_child : (String, TrieNode)?
  handler : Handler?
}

fn TrieNode::new() -> TrieNode {
  {
    static_children: Map::new(),
    param_child: None,
    wildcard_child: None,
    handler: None
  }
}

pub struct Router {
  routes : Map[String, TrieNode]
}

pub fn Router::new() -> Router {
  { routes: Map::new() }
}

fn parse_path(path : String) -> Array[String] {
  let parts = path.split("/")
  let result : Array[String] = []
  for part in parts {
    if part != "" {
      result.push(part)
    }
  }
  result
}

pub fn Router::add_route(
  self : Router,
  method : String,
  path : String,
  handler : Handler
) -> Unit {
  let method_routes = match self.routes.get(method) {
    Some(node) => node
    None => {
      let new_node = TrieNode::new()
      self.routes[method] = new_node
      new_node
    }
  }
  
  let parts = parse_path(path)
  let mut current = method_routes
  
  for i = 0; i < parts.length(); i = i + 1 {
    let part = parts[i]
    
    if part[0] == ':' {
      let param_name = part.substring(start=1)
      match current.param_child {
        Some((_, next)) => {
          current = next
        }
        None => {
          let new_node = TrieNode::new()
          current.param_child = Some((param_name, new_node))
          current = new_node
        }
      }
    } else if part[0] == '*' {
      let wildcard_name = part.substring(start=1)
      match current.wildcard_child {
        Some((_, next)) => {
          current = next
        }
        None => {
          let new_node = TrieNode::new()
          current.wildcard_child = Some((wildcard_name, new_node))
          current = new_node
        }
      }
      break
    } else {
      match current.static_children.get(part) {
        Some(next) => {
          current = next
        }
        None => {
          let new_node = TrieNode::new()
          current.static_children[part] = new_node
          current = new_node
        }
      }
    }
  }
  
  current.handler = Some(handler)
}

pub fn Router::match(
  self : Router,
  method : String,
  path : String
) -> (Handler?, Map[String, String]) {
  let params = Map::new()
  
  let method_routes = match self.routes.get(method) {
    Some(node) => node
    None => return (None, params)
  }
  
  let parts = parse_path(path)
  let mut current = method_routes
  
  for i = 0; i < parts.length(); i = i + 1 {
    let part = parts[i]
    
    match current.static_children.get(part) {
      Some(next) => {
        current = next
        continue
      }
      None => {
      }
    }
    
    match current.param_child {
      Some((param_name, next)) => {
        params[param_name] = part
        current = next
        continue
      }
      None => {
      }
    }
    
    match current.wildcard_child {
      Some((wildcard_name, next)) => {
        let remaining_path = parts.slice(i).join("/")
        params[wildcard_name] = remaining_path
        current = next
        break
      }
      None => {
        return (None, params)
      }
    }
  }
  
  (current.handler, params)
}
