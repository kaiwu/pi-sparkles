import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_finance_sources/decode
import pi_sparkles_finance_sources/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_list(api)
  register_inspect(api)
  register_export(api)
  promise.resolve(Nil)
}

fn register_list(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "list_sources",
    "List supplied source receipts",
    "Return one explicit page of compact provenance facts from a caller-supplied immutable catalogue; no source is selected, ranked, trusted, or interpreted",
    "Supply the exact catalogue, offset, and limit; the LLM decides which receipt, if any, to inspect next",
    tool.parameters(list_schema(), decode.list_sources()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) { complete(domain.run_list(input)) },
  )
}

fn register_inspect(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "inspect_source",
    "Inspect one supplied source receipt",
    "Return the complete safe projection and linked assumptions for one exact receipt hash in a caller-supplied immutable catalogue; no fallback or source judgment is made",
    "Supply the same exact catalogue and the exact receipt hash selected by the LLM",
    tool.parameters(inspect_schema(), decode.inspect_source()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      complete(domain.run_inspect(input))
    },
  )
}

fn register_export(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "export_manifest",
    "Export a canonical source manifest",
    "Return exact finance_provenance schema-v1 canonical manifest JSON and SHA-256 from a caller-supplied immutable catalogue within an explicit byte budget",
    "Supply the exact catalogue and byte budget; excess fails without truncation and the LLM decides how to use the unsigned manifest",
    tool.parameters(export_schema(), decode.export_manifest()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      complete(domain.run_export(input))
    },
  )
}

fn complete(
  value: Result(domain.Response, domain.DomainError),
) -> Promise(tool.ToolResult) {
  case value {
    Ok(value) ->
      tool.text_result(domain.summary(value), domain.details(value))
      |> promise.resolve
    Error(error) -> tool.reject(domain.error_message(error))
  }
}

fn list_schema() -> schema.Schema {
  schema.object([
    schema.Required("catalogue", catalogue_schema()),
    schema.Required(
      "offset",
      schema.integer() |> schema.with_number_range(0.0, 500.0),
    ),
    schema.Required(
      "limit",
      schema.integer() |> schema.with_number_range(1.0, 200.0),
    ),
  ])
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Required("catalogue", catalogue_schema()),
    schema.Required("receiptHash", hash_schema()),
  ])
}

fn export_schema() -> schema.Schema {
  schema.object([
    schema.Required("catalogue", catalogue_schema()),
    schema.Required(
      "maximumManifestBytes",
      schema.integer() |> schema.with_number_range(1.0, 5_000_000.0),
    ),
  ])
}

fn catalogue_schema() -> schema.Schema {
  schema.object([
    schema.Required("instructionRef", hash_schema()),
    schema.Required(
      "additionalSensitiveQueryKeys",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 100),
    ),
    schema.Required(
      "assumptions",
      schema.array(assumption_schema()) |> schema.with_array_length(0, 500),
    ),
    schema.Required(
      "evidence",
      schema.array(evidence_schema()) |> schema.with_array_length(1, 500),
    ),
    schema.Required(
      "roots",
      schema.array(hash_schema()) |> schema.with_array_length(0, 500),
    ),
  ])
  |> schema.described(
    "Exact bounded provenance catalogue replayed for this stateless operation; evidence must be parent-before-child",
  )
}

fn assumption_schema() -> schema.Schema {
  schema.object([
    schema.Required("id", bounded_string(1, 500)),
    schema.Required("name", bounded_string(1, 500)),
    schema.Required(
      "origin",
      schema.string_enum(["user", "provider", "method", "policy"]),
    ),
    schema.Required("explanation", bounded_string(1, 4000)),
    schema.Required("value", assumption_value_schema()),
  ])
}

fn assumption_value_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum(["text", "decimal", "money", "boolean"]),
    ),
    schema.Optional("text", schema.nullable(bounded_string(1, 4000))),
    schema.Optional("decimal", schema.nullable(bounded_string(1, 500))),
    schema.Optional("amount", schema.nullable(bounded_string(1, 500))),
    schema.Optional("currency", schema.nullable(bounded_string(3, 3))),
    schema.Optional("boolean", schema.nullable(schema.boolean())),
  ])
  |> schema.described(
    "Supply exactly the field(s) named by kind: text, decimal, amount+currency, or boolean",
  )
}

fn evidence_schema() -> schema.Schema {
  schema.object([
    schema.Required("receiptHash", hash_schema()),
    schema.Required("sourceFingerprint", hash_schema()),
    schema.Required("source", source_schema()),
    schema.Required("licence", licence_schema()),
    schema.Required("asOfUnixMilliseconds", schema.integer()),
    schema.Required("retrievedAtUnixMilliseconds", schema.integer()),
    schema.Required("mediaType", bounded_string(1, 500)),
    schema.Required(
      "byteLength",
      schema.integer() |> schema.with_number_range(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("contentHash", hash_schema()),
    schema.Required(
      "parents",
      schema.array(hash_schema()) |> schema.with_array_length(0, 500),
    ),
    schema.Required(
      "assumptions",
      schema.array(bounded_string(1, 500)) |> schema.with_array_length(0, 500),
    ),
    schema.Required("availability", availability_schema()),
  ])
}

fn source_schema() -> schema.Schema {
  schema.object([
    schema.Required("provider", bounded_string(1, 500)),
    schema.Required("reference", bounded_string(1, 8000)),
    schema.Required(
      "kind",
      schema.string_enum([
        "official",
        "exchange",
        "regulator",
        "licensed_vendor",
        "user_supplied",
        "synthetic",
        "other",
      ]),
    ),
    schema.Optional("otherKind", schema.nullable(bounded_string(1, 500))),
  ])
}

fn licence_schema() -> schema.Schema {
  schema.object([
    schema.Required("label", bounded_string(1, 500)),
    schema.Required(
      "redistribution",
      schema.string_enum([
        "public_domain",
        "attribution_required",
        "internal_use_only",
        "no_redistribution",
        "unknown",
      ]),
    ),
    schema.Optional("notes", schema.nullable(bounded_string(1, 4000))),
  ])
}

fn availability_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum([
        "available",
        "unavailable",
        "expired",
        "superseded",
        "verification_failed",
      ]),
    ),
    schema.Optional("reason", schema.nullable(bounded_string(1, 4000))),
    schema.Optional("supersededBy", schema.nullable(hash_schema())),
  ])
  |> schema.described(
    "Unavailable and verification_failed require reason; superseded requires supersededBy; other states forbid both",
  )
}

fn hash_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(64, 64)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}
