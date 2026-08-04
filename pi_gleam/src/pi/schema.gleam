import gleam/javascript/array
import gleam/json.{type Json}
import gleam/list

/// A JSON Schema value accepted by Pi's TypeBox-based tool validation.
pub type Schema

pub type Property {
  Required(name: String, schema: Schema)
  Optional(name: String, schema: Schema)
}

@external(javascript, "./schema_ffi.mjs", "anything")
pub fn anything() -> Schema

@external(javascript, "./schema_ffi.mjs", "string")
pub fn string() -> Schema

@external(javascript, "./schema_ffi.mjs", "integer")
pub fn integer() -> Schema

@external(javascript, "./schema_ffi.mjs", "number")
pub fn number() -> Schema

@external(javascript, "./schema_ffi.mjs", "boolean")
pub fn boolean() -> Schema

@external(javascript, "./schema_ffi.mjs", "null_schema")
pub fn null() -> Schema

@external(javascript, "./schema_ffi.mjs", "literal_string")
pub fn literal_string(value: String) -> Schema

@external(javascript, "./schema_ffi.mjs", "string_enum")
fn string_enum_array(values: array.Array(String)) -> Schema

/// Build the flat string-enum schema expected by Pi and Google providers.
pub fn string_enum(values: List(String)) -> Schema {
  values |> array.from_list |> string_enum_array
}

@external(javascript, "./schema_ffi.mjs", "array")
pub fn array(items: Schema) -> Schema

@external(javascript, "./schema_ffi.mjs", "tuple")
fn tuple_array(items: array.Array(Schema)) -> Schema

pub fn tuple(items: List(Schema)) -> Schema {
  items |> array.from_list |> tuple_array
}

@external(javascript, "./schema_ffi.mjs", "object")
fn object_array(
  properties: array.Array(#(String, Schema, Bool)),
  additional_properties: Bool,
) -> Schema

pub fn object(properties: List(Property)) -> Schema {
  object_with_extra_properties(properties, False)
}

pub fn object_with_extra_properties(
  properties: List(Property),
  additional_properties: Bool,
) -> Schema {
  properties
  |> list.map(fn(property) {
    case property {
      Required(name, schema) -> #(name, schema, True)
      Optional(name, schema) -> #(name, schema, False)
    }
  })
  |> array.from_list
  |> object_array(additional_properties)
}

@external(javascript, "./schema_ffi.mjs", "record")
pub fn record(values: Schema) -> Schema

@external(javascript, "./schema_ffi.mjs", "one_of")
fn one_of_array(items: array.Array(Schema)) -> Schema

pub fn one_of(items: List(Schema)) -> Schema {
  items |> array.from_list |> one_of_array
}

@external(javascript, "./schema_ffi.mjs", "nullable")
pub fn nullable(schema: Schema) -> Schema

@external(javascript, "./schema_ffi.mjs", "described")
pub fn described(schema: Schema, description: String) -> Schema

@external(javascript, "./schema_ffi.mjs", "with_default")
pub fn with_default(schema: Schema, default: Json) -> Schema

@external(javascript, "./schema_ffi.mjs", "with_title")
pub fn with_title(schema: Schema, title: String) -> Schema

@external(javascript, "./schema_ffi.mjs", "with_string_length")
pub fn with_string_length(schema: Schema, minimum: Int, maximum: Int) -> Schema

@external(javascript, "./schema_ffi.mjs", "with_number_range")
pub fn with_number_range(
  schema: Schema,
  minimum: Float,
  maximum: Float,
) -> Schema

@external(javascript, "./schema_ffi.mjs", "with_array_length")
pub fn with_array_length(schema: Schema, minimum: Int, maximum: Int) -> Schema

@external(javascript, "./schema_ffi.mjs", "raw")
pub fn raw(value: Json) -> Schema
