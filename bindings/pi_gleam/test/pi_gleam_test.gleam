import gleam/dynamic/decode
import gleeunit
import gleeunit/should
import pi/raw

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn raw_object_test() {
  let value = raw.object([#("name", raw.dynamic("Ada"))])
  let decoder = {
    use name <- decode.field("name", decode.string)
    decode.success(name)
  }

  value
  |> decode.run(decoder)
  |> should.equal(Ok("Ada"))
}
