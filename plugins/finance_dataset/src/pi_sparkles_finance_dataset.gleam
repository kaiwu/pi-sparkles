import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_finance_dataset/decode
import pi_sparkles_finance_dataset/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_inspect(api)
  register_drill(api)
  register_vintages(api)
  promise.resolve(Nil)
}

fn register_inspect(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "inspect_dataset",
    "Inspect one exact dataset manifest",
    "Verify and summarize one caller-supplied canonical finance_replay dataset manifest plus explicit OHLCV omission and receipt-root projections without fetching or judging data",
    "Supply the exact manifest bytes and matching handle; the LLM interprets coverage, fact-state counts, limitations, and omission facts",
    tool.parameters(inspect_schema(), decode.inspect_dataset()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      complete(domain.run_inspect(input))
    },
  )
}

fn register_drill(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "drill_observation",
    "Drill one exact listing and date",
    "Return an explicit page of every matching observation handle and caller-supplied OHLCV omission for one exact listing/date without fallback, repair, or vintage selection",
    "Supply the same exact dataset, one listing ID, canonical observation date, offset, and limit",
    tool.parameters(drill_schema(), decode.drill_observation()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      complete(domain.run_drill(input))
    },
  )
}

fn register_vintages(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "list_vintages",
    "List supplied observation vintages",
    "Return an explicit page of correction-vintage and bitemporal facts in canonical manifest order with optional exact listing/date filters and no preferred or latest-vintage choice",
    "Supply the same exact dataset, optional exact filters, offset, and limit; the LLM chooses and interprets any cutoff or vintage",
    tool.parameters(vintages_schema(), decode.list_vintages()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      complete(domain.run_vintages(input))
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

fn inspect_schema() -> schema.Schema {
  schema.object([schema.Required("dataset", dataset_schema())])
}

fn drill_schema() -> schema.Schema {
  schema.object([
    schema.Required("dataset", dataset_schema()),
    schema.Required("listingId", bounded_string(1, 2000)),
    schema.Required("observationDate", date_schema()),
    schema.Required("offset", bounded_integer(0.0, 10_000.0)),
    schema.Required("limit", bounded_integer(1.0, 200.0)),
  ])
}

fn vintages_schema() -> schema.Schema {
  schema.object([
    schema.Required("dataset", dataset_schema()),
    schema.Optional("listingId", schema.nullable(bounded_string(1, 2000))),
    schema.Optional("observationDate", schema.nullable(date_schema())),
    schema.Required("offset", bounded_integer(0.0, 10_000.0)),
    schema.Required("limit", bounded_integer(1.0, 200.0)),
  ])
}

fn dataset_schema() -> schema.Schema {
  schema.object([
    schema.Required("manifestJson", bounded_string(1, 10_000_000)),
    schema.Required("manifestHash", hash_schema()),
    schema.Required(
      "omissions",
      schema.array(omission_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "receiptRoots",
      schema.array(hash_schema()) |> schema.with_array_length(0, 10_000),
    ),
  ])
  |> schema.described(
    "Exact canonical finance_replay dataset envelope and matching digest, plus ordered caller-supplied finance_ohlcv gaps and receipt roots; this stateless shell performs no registry lookup",
  )
}

fn omission_schema() -> schema.Schema {
  schema.object([
    schema.Required("listingId", bounded_string(1, 2000)),
    schema.Required("observationDate", date_schema()),
    schema.Required(
      "state",
      schema.string_enum([
        "market_closure",
        "suspension",
        "provider_omission",
        "unavailable_history",
      ]),
    ),
    schema.Optional(
      "evidenceReference",
      schema.nullable(bounded_string(1, 4000)),
    ),
  ])
}

fn date_schema() -> schema.Schema {
  schema.string()
  |> schema.with_string_length(10, 10)
  |> schema.described("Canonical Gregorian YYYY-MM-DD")
}

fn hash_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(64, 64)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Float, maximum: Float) -> schema.Schema {
  schema.integer() |> schema.with_number_range(minimum, maximum)
}
