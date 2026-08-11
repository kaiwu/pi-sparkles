import finance_core/decimal
import finance_math/formula
import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import gleam/string

pub type Descriptor {
  Descriptor(
    contract_id: String,
    track: String,
    allowed_mics: List(String),
    operations: List(String),
  )
}

pub type Subject {
  Subject(
    issuer_id: String,
    listing_id: String,
    mic: String,
    share_class: String,
  )
}

pub type Operand {
  Operand(
    name: String,
    exact_lexeme: String,
    market_track: String,
    mic: String,
    unit: String,
    currency: Option(String),
    period_start: Option(String),
    period_end: String,
    accession: String,
    taxonomy: String,
    tag: String,
    context_key: String,
    source_receipt: String,
  )
}

pub type Request {
  Request(
    schema_version: Int,
    contract_id: String,
    track: String,
    request_id: String,
    subject: Subject,
    operation: String,
    output_unit: String,
    output_scale: Int,
    rounding: String,
    coherence_key: String,
    operands: List(Operand),
    assumptions: List(String),
  )
}

pub type Input {
  Input(path: String, expected_sha256: String)
}

pub type Response {
  Response(summary: String, details: json.Json)
}

pub type CalculationError {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract
  WrongTrack
  WrongMic
  InvalidRequest
  UnsupportedOperation
  DuplicateOperand
  MissingOperand(String)
  InvalidOperand(String)
  IncoherentContext(String)
  CalculationUnperformed(String)
}

pub fn input(path: String, expected_sha256: String) -> Input {
  Input(path, expected_sha256)
}

pub fn path(value: Input) -> String {
  value.path
}

pub fn expected_sha256(value: Input) -> String {
  value.expected_sha256
}

pub fn calculate(
  descriptor: Descriptor,
  input: Input,
  bytes: String,
) -> Result(Response, CalculationError) {
  use _ <- result.try(verify_hash(bytes, input.expected_sha256))
  use request <- result.try(case json.parse(bytes, request_decoder()) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(InvalidJson)
  })
  use _ <- result.try(validate_request(descriptor, request))
  use rounding <- result.try(rounding_mode(request.rounding))
  use calculation <- result.try(build_formula(
    request.operation,
    request.operands,
    request.output_scale,
    rounding,
  ))
  let #(expression, expression_tree) = calculation
  use inputs <- result.try(
    list.try_map(request.operands, fn(operand) {
      case decimal.parse(operand.exact_lexeme) {
        Ok(value) -> Ok(formula.Input(operand.name, formula.Available(value)))
        Error(_) -> Error(InvalidOperand(operand.name <> ":invalid_decimal"))
      }
    }),
  )
  use value <- result.try(
    formula.evaluate(expression, with: inputs)
    |> result.map_error(fn(error) {
      CalculationUnperformed(string.inspect(error))
    }),
  )
  let semantic =
    json.object([
      #("schemaVersion", json.int(1)),
      #("contractId", json.string(request.contract_id)),
      #("track", json.string(request.track)),
      #("requestId", json.string(request.request_id)),
      #("subject", subject_json(request.subject)),
      #("operation", json.string(request.operation)),
      #("state", json.string("calculated")),
      #("resultExact", json.string(decimal.to_string(value))),
      #("outputUnit", json.string(request.output_unit)),
      #("outputScale", json.int(request.output_scale)),
      #("rounding", json.string(request.rounding)),
      #("coherenceKey", json.string(request.coherence_key)),
      #("expression", expression_tree),
      #("orderedInputs", json.array(request.operands, operand_json)),
      #("assumptions", json.array(request.assumptions, json.string)),
      #("sourcePacketSha256", json.string(input.expected_sha256)),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ])
  let assert Ok(receipt) = semantic |> json.to_string |> hash.text
  Ok(Response(
    request.operation
      <> " = "
      <> decimal.to_string(value)
      <> " "
      <> request.output_unit
      <> "; exact mechanical calculation, no investment verdict",
    json.object([
      #("canonicalCalculation", semantic),
      #("canonicalContentHash", receipt |> identity.sha256_value |> json.string),
    ]),
  ))
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> json.Json {
  value.details
}

pub fn error_message(error: CalculationError) -> String {
  case error {
    InvalidJson -> "Calculation import is not valid versioned JSON"
    ContentHashMismatch ->
      "Calculation import bytes do not match expectedSha256"
    WrongSchema -> "Calculation schemaVersion must be 1"
    WrongContract -> "Calculation contractId does not match this plugin"
    WrongTrack -> "Calculation track does not match this plugin"
    WrongMic -> "Calculation MIC is outside this plugin's exact scope"
    InvalidRequest ->
      "Calculation request identity, bounds, or assumptions are invalid"
    UnsupportedOperation ->
      "Calculation operation is not supported by this plugin"
    DuplicateOperand -> "Calculation request contains duplicate operand names"
    MissingOperand(name) -> "Calculation request is missing operand: " <> name
    InvalidOperand(reason) -> "Calculation operand is invalid: " <> reason
    IncoherentContext(reason) -> "Calculation context is incoherent: " <> reason
    CalculationUnperformed(reason) -> "Calculation was unperformed: " <> reason
  }
}

fn validate_request(
  descriptor: Descriptor,
  request: Request,
) -> Result(Nil, CalculationError) {
  case request.schema_version == 1 {
    False -> Error(WrongSchema)
    True ->
      case request.contract_id == descriptor.contract_id {
        False -> Error(WrongContract)
        True ->
          case request.track == descriptor.track {
            False -> Error(WrongTrack)
            True -> validate_request_scope(descriptor, request)
          }
      }
  }
}

fn validate_request_scope(
  descriptor: Descriptor,
  request: Request,
) -> Result(Nil, CalculationError) {
  case
    nonempty(request.request_id)
    && nonempty(request.subject.issuer_id)
    && nonempty(request.subject.listing_id)
    && nonempty(request.subject.share_class)
    && nonempty(request.output_unit)
    && nonempty(request.coherence_key)
    && request.output_scale >= 0
    && request.output_scale <= 18
    && list.length(request.operands) >= 1
    && list.length(request.operands) <= 100
    && list.length(request.assumptions) <= 100
  {
    False -> Error(InvalidRequest)
    True ->
      case list.contains(descriptor.allowed_mics, request.subject.mic) {
        False -> Error(WrongMic)
        True ->
          case list.contains(descriptor.operations, request.operation) {
            False -> Error(UnsupportedOperation)
            True -> validate_operands(request)
          }
      }
  }
}

fn validate_operands(request: Request) -> Result(Nil, CalculationError) {
  let names = list.map(request.operands, fn(operand) { operand.name })
  case unique(names) {
    False -> Error(DuplicateOperand)
    True -> {
      use _ <- result.try(
        list.try_each(request.operands, fn(operand) {
          validate_operand(operand, request.coherence_key)
        }),
      )
      use required <- result.try(required_names(
        request.operation,
        request.operands,
      ))
      use _ <- result.try(
        list.try_each(required, fn(name) {
          case list.contains(names, name) {
            True -> Ok(Nil)
            False -> Error(MissingOperand(name))
          }
        }),
      )
      use _ <- result.try(validate_operand_tracks(
        request.operation,
        request.track,
        request.operands,
      ))
      validate_units(request.operation, request.operands)
    }
  }
}

fn validate_operand(
  operand: Operand,
  coherence_key: String,
) -> Result(Nil, CalculationError) {
  case
    nonempty(operand.name)
    && nonempty(operand.exact_lexeme)
    && list.contains(["cn", "hk", "us", "global"], operand.market_track)
    && nonempty(operand.mic)
    && nonempty(operand.unit)
    && nonempty(operand.period_end)
    && nonempty(operand.accession)
    && nonempty(operand.taxonomy)
    && nonempty(operand.tag)
    && valid_sha256(operand.source_receipt)
  {
    False -> Error(InvalidOperand(operand.name))
    True ->
      case operand.context_key == coherence_key {
        True -> Ok(Nil)
        False -> Error(IncoherentContext(operand.name <> ":context_key"))
      }
  }
}

fn validate_operand_tracks(
  operation: String,
  request_track: String,
  operands: List(Operand),
) -> Result(Nil, CalculationError) {
  case operation {
    "premium_discount_fx" -> {
      use primary <- result.try(find_operand(operands, "primary_price"))
      use comparison <- result.try(find_operand(operands, "comparison_price"))
      use fx <- result.try(find_operand(operands, "fx_rate"))
      case
        primary.market_track == request_track
        && comparison.market_track != primary.market_track
        && list.contains(["cn", "hk", "us"], comparison.market_track)
        && fx.market_track == "global"
      {
        True -> Ok(Nil)
        False -> Error(IncoherentContext("cross_listing_tracks_or_fx_leg"))
      }
    }
    _ ->
      case
        list.all(operands, fn(value) { value.market_track == request_track })
      {
        True -> Ok(Nil)
        False -> Error(IncoherentContext("operand_market_track"))
      }
  }
}

fn required_names(
  operation: String,
  operands: List(Operand),
) -> Result(List(String), CalculationError) {
  case operation {
    "ratio" -> Ok(["numerator", "denominator"])
    "difference" -> Ok(["current", "reference"])
    "percent_change" -> Ok(["current", "prior"])
    "mean" ->
      case operands {
        [] -> Error(InvalidRequest)
        _ -> Ok([])
      }
    "net_margin" -> Ok(["parent_profit", "revenue"])
    "enterprise_to_equity_per_share" ->
      Ok(["enterprise_value", "net_debt", "diluted_shares"])
    "premium_discount_fx" ->
      Ok(["primary_price", "comparison_price", "fx_rate"])
    _ -> Error(UnsupportedOperation)
  }
}

fn validate_units(
  operation: String,
  operands: List(Operand),
) -> Result(Nil, CalculationError) {
  case operation {
    "difference" | "percent_change" | "mean" | "net_margin" ->
      require_same_unit_currency(operands)
    "enterprise_to_equity_per_share" -> {
      use enterprise <- result.try(find_operand(operands, "enterprise_value"))
      use debt <- result.try(find_operand(operands, "net_debt"))
      use shares <- result.try(find_operand(operands, "diluted_shares"))
      case
        enterprise.unit == debt.unit
        && enterprise.currency == debt.currency
        && shares.unit == "shares"
      {
        True -> Ok(Nil)
        False -> Error(IncoherentContext("enterprise/debt/share units"))
      }
    }
    "premium_discount_fx" -> Ok(Nil)
    "ratio" -> Ok(Nil)
    _ -> Error(UnsupportedOperation)
  }
}

fn require_same_unit_currency(
  operands: List(Operand),
) -> Result(Nil, CalculationError) {
  case operands {
    [] -> Error(InvalidRequest)
    [first, ..rest] ->
      case
        list.all(rest, fn(value) {
          value.unit == first.unit && value.currency == first.currency
        })
      {
        True -> Ok(Nil)
        False -> Error(IncoherentContext("unit_or_currency"))
      }
  }
}

fn build_formula(
  operation: String,
  operands: List(Operand),
  scale: Int,
  rounding: decimal.RoundingMode,
) -> Result(#(formula.Formula, json.Json), CalculationError) {
  let reference = fn(name) { formula.Reference(name) }
  case operation {
    "ratio" ->
      Ok(#(
        formula.Divide(
          reference("numerator"),
          reference("denominator"),
          scale,
          rounding,
        ),
        binary_tree("divide", "numerator", "denominator"),
      ))
    "difference" ->
      Ok(#(
        formula.Subtract(reference("current"), reference("reference")),
        binary_tree("subtract", "current", "reference"),
      ))
    "percent_change" ->
      Ok(#(
        formula.Divide(
          formula.Subtract(reference("current"), reference("prior")),
          reference("prior"),
          scale,
          rounding,
        ),
        json.object([
          #("operation", json.string("divide")),
          #("numerator", binary_tree("subtract", "current", "prior")),
          #("denominator", reference_json("prior")),
        ]),
      ))
    "mean" -> {
      let names = list.map(operands, fn(operand) { operand.name })
      Ok(#(
        formula.Mean(list.map(names, reference), scale, rounding),
        json.object([
          #("operation", json.string("mean")),
          #("inputs", json.array(names, reference_json)),
        ]),
      ))
    }
    "net_margin" ->
      Ok(#(
        formula.Divide(
          reference("parent_profit"),
          reference("revenue"),
          scale,
          rounding,
        ),
        binary_tree("divide", "parent_profit", "revenue"),
      ))
    "enterprise_to_equity_per_share" ->
      Ok(#(
        formula.Divide(
          formula.Subtract(reference("enterprise_value"), reference("net_debt")),
          reference("diluted_shares"),
          scale,
          rounding,
        ),
        json.object([
          #("operation", json.string("divide")),
          #(
            "numerator",
            binary_tree("subtract", "enterprise_value", "net_debt"),
          ),
          #("denominator", reference_json("diluted_shares")),
        ]),
      ))
    "premium_discount_fx" ->
      Ok(#(
        formula.Divide(
          formula.Subtract(
            formula.Multiply(reference("primary_price"), reference("fx_rate")),
            reference("comparison_price"),
          ),
          reference("comparison_price"),
          scale,
          rounding,
        ),
        json.object([
          #("operation", json.string("divide")),
          #(
            "numerator",
            json.object([
              #("operation", json.string("subtract")),
              #("left", binary_tree("multiply", "primary_price", "fx_rate")),
              #("right", reference_json("comparison_price")),
            ]),
          ),
          #("denominator", reference_json("comparison_price")),
        ]),
      ))
    _ -> Error(UnsupportedOperation)
  }
}

fn find_operand(
  operands: List(Operand),
  name: String,
) -> Result(Operand, CalculationError) {
  case list.find(operands, fn(value) { value.name == name }) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(MissingOperand(name))
  }
}

fn rounding_mode(
  value: String,
) -> Result(decimal.RoundingMode, CalculationError) {
  case value {
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    "half_up" -> Ok(decimal.HalfUp)
    "half_even" -> Ok(decimal.HalfEven)
    _ -> Error(InvalidRequest)
  }
}

fn verify_hash(
  bytes: String,
  expected: String,
) -> Result(Nil, CalculationError) {
  case hash.text(bytes) {
    Error(_) -> Error(ContentHashMismatch)
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
  }
}

fn valid_sha256(value: String) -> Bool {
  case identity.sha256(value) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn unique(values: List(String)) -> Bool {
  case values {
    [] -> True
    [value, ..rest] -> !list.contains(rest, value) && unique(rest)
  }
}

fn nonempty(value: String) -> Bool {
  value != "" && value == string.trim(value) && string.length(value) <= 20_000
}

fn request_decoder() -> decode.Decoder(Request) {
  use schema_version <- decode.field("schemaVersion", decode.int)
  use contract_id <- decode.field("contractId", decode.string)
  use track <- decode.field("track", decode.string)
  use request_id <- decode.field("requestId", decode.string)
  use subject <- decode.field("subject", subject_decoder())
  use operation <- decode.field("operation", decode.string)
  use output_unit <- decode.field("outputUnit", decode.string)
  use output_scale <- decode.field("outputScale", decode.int)
  use rounding <- decode.field("rounding", decode.string)
  use coherence_key <- decode.field("coherenceKey", decode.string)
  use operands <- decode.field("operands", decode.list(operand_decoder()))
  use assumptions <- decode.field("assumptions", decode.list(decode.string))
  decode.success(Request(
    schema_version,
    contract_id,
    track,
    request_id,
    subject,
    operation,
    output_unit,
    output_scale,
    rounding,
    coherence_key,
    operands,
    assumptions,
  ))
}

fn subject_decoder() -> decode.Decoder(Subject) {
  use issuer_id <- decode.field("issuerId", decode.string)
  use listing_id <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  decode.success(Subject(issuer_id, listing_id, mic, share_class))
}

fn operand_decoder() -> decode.Decoder(Operand) {
  use name <- decode.field("name", decode.string)
  use exact_lexeme <- decode.field("exactLexeme", decode.string)
  use market_track <- decode.field("marketTrack", decode.string)
  use mic <- decode.field("mic", decode.string)
  use unit <- decode.field("unit", decode.string)
  use currency <- optional_string("currency")
  use period_start <- optional_string("periodStart")
  use period_end <- decode.field("periodEnd", decode.string)
  use accession <- decode.field("accession", decode.string)
  use taxonomy <- decode.field("taxonomy", decode.string)
  use tag <- decode.field("tag", decode.string)
  use context_key <- decode.field("contextKey", decode.string)
  use source_receipt <- decode.field("sourceReceipt", decode.string)
  decode.success(Operand(
    name,
    exact_lexeme,
    market_track,
    mic,
    unit,
    currency,
    period_start,
    period_end,
    accession,
    taxonomy,
    tag,
    context_key,
    source_receipt,
  ))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn subject_json(subject: Subject) -> json.Json {
  json.object([
    #("issuerId", json.string(subject.issuer_id)),
    #("listingId", json.string(subject.listing_id)),
    #("mic", json.string(subject.mic)),
    #("shareClass", json.string(subject.share_class)),
  ])
}

fn operand_json(operand: Operand) -> json.Json {
  json.object([
    #("name", json.string(operand.name)),
    #("exactLexeme", json.string(operand.exact_lexeme)),
    #("marketTrack", json.string(operand.market_track)),
    #("mic", json.string(operand.mic)),
    #("unit", json.string(operand.unit)),
    #("currency", json.nullable(operand.currency, json.string)),
    #("periodStart", json.nullable(operand.period_start, json.string)),
    #("periodEnd", json.string(operand.period_end)),
    #("accession", json.string(operand.accession)),
    #("taxonomy", json.string(operand.taxonomy)),
    #("tag", json.string(operand.tag)),
    #("contextKey", json.string(operand.context_key)),
    #("sourceReceipt", json.string(operand.source_receipt)),
  ])
}

fn reference_json(name: String) -> json.Json {
  json.object([
    #("operation", json.string("reference")),
    #("name", json.string(name)),
  ])
}

fn binary_tree(operation: String, left: String, right: String) -> json.Json {
  json.object([
    #("operation", json.string(operation)),
    #("left", reference_json(left)),
    #("right", reference_json(right)),
  ])
}
