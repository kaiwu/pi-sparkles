import finance_market_alpaca/query.{type AssetUniverseQuery}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

/// One Alpaca asset row copied without interpreting its status or capability
/// flags as eligibility, suitability, or a workflow decision.
pub opaque type Asset {
  Asset(
    id: String,
    asset_class: String,
    exchange: String,
    symbol: String,
    name: String,
    status: String,
    tradable: Bool,
    marginable: Bool,
    shortable: Bool,
    easy_to_borrow: Bool,
    fractionable: Bool,
    attributes: List(String),
  )
}

/// Provider order and duplicates are retained exactly.
pub opaque type Snapshot {
  Snapshot(assets: List(Asset))
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  TooManyAssets(maximum: Int, received: Int)
}

pub fn decode_snapshot(
  body: String,
  for plan: AssetUniverseQuery,
) -> Result(Snapshot, DecodeError) {
  use values <- result.try(
    json.parse(body, decode.list(asset_decoder()))
    |> result.map_error(InvalidJson),
  )
  let received = list.length(values)
  case received <= query.maximum_assets(plan) {
    True -> Ok(Snapshot(values))
    False -> Error(TooManyAssets(query.maximum_assets(plan), received))
  }
}

pub fn rows(value: Snapshot) -> List(Asset) {
  value.assets
}

pub fn id(value: Asset) -> String {
  value.id
}

pub fn asset_class(value: Asset) -> String {
  value.asset_class
}

pub fn exchange(value: Asset) -> String {
  value.exchange
}

pub fn symbol(value: Asset) -> String {
  value.symbol
}

pub fn name(value: Asset) -> String {
  value.name
}

pub fn status(value: Asset) -> String {
  value.status
}

pub fn tradable(value: Asset) -> Bool {
  value.tradable
}

pub fn marginable(value: Asset) -> Bool {
  value.marginable
}

pub fn shortable(value: Asset) -> Bool {
  value.shortable
}

pub fn easy_to_borrow(value: Asset) -> Bool {
  value.easy_to_borrow
}

pub fn fractionable(value: Asset) -> Bool {
  value.fractionable
}

pub fn attributes(value: Asset) -> List(String) {
  value.attributes
}

fn asset_decoder() -> decode.Decoder(Asset) {
  use id <- decode.field("id", decode.string)
  use asset_class <- decode.field("class", decode.string)
  use exchange <- decode.field("exchange", decode.string)
  use symbol <- decode.field("symbol", decode.string)
  use name <- decode.field("name", decode.string)
  use status <- decode.field("status", decode.string)
  use tradable <- decode.field("tradable", decode.bool)
  use marginable <- decode.field("marginable", decode.bool)
  use shortable <- decode.field("shortable", decode.bool)
  use easy_to_borrow <- decode.field("easy_to_borrow", decode.bool)
  use fractionable <- decode.field("fractionable", decode.bool)
  use attributes <- decode.optional_field(
    "attributes",
    [],
    decode.list(of: decode.string),
  )
  decode.success(Asset(
    id,
    asset_class,
    exchange,
    symbol,
    name,
    status,
    tradable,
    marginable,
    shortable,
    easy_to_borrow,
    fractionable,
    attributes,
  ))
}
