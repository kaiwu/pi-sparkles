import gleam/list
import gleam/string

pub fn is_dangerous(command: String) -> Bool {
  ["rm -rf", "rm -fr", "sudo ", "chmod 777", "chown 777"]
  |> list.any(fn(term) { string.contains(command, term) })
}
