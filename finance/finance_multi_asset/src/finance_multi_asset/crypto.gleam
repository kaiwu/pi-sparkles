import finance_core/decimal
import finance_multi_asset/common
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result

pub type Identity {
  Identity(
    asset_id: String,
    network: String,
    token_standard: String,
    contract_address: Option(String),
    token_symbol: String,
    venue: String,
    venue_instrument_id: String,
    base_asset_id: String,
    quote_asset_id: String,
    instrument_type: String,
    venue_type: String,
    stablecoin_quote: Bool,
    wrapped_asset_id: Option(String),
    identity_receipt: String,
  )
}

pub type Quote {
  Quote(
    venue: String,
    venue_instrument_id: String,
    bid: common.Fact,
    bid_size: common.Fact,
    ask: common.Fact,
    ask_size: common.Fact,
    venue_unix_ms: Int,
    receipt_unix_ms: Int,
    sequence: Int,
    receipt: String,
  )
}

pub type Trade {
  Trade(
    trade_id: String,
    price: common.Fact,
    size: common.Fact,
    venue_unix_ms: Int,
    sequence: Int,
    side: String,
    correction_lineage: List(String),
    receipt: String,
  )
}

pub type Candle {
  Candle(
    interval: String,
    boundary_convention: String,
    open_unix_ms: Int,
    close_unix_ms: Int,
    open: common.Fact,
    high: common.Fact,
    low: common.Fact,
    close: common.Fact,
    volume: common.Fact,
    receipt: String,
  )
}

pub type Level {
  Level(price: common.Fact, size: common.Fact)
}

pub type Book {
  Book(
    venue_unix_ms: Int,
    sequence: Int,
    bids: List(Level),
    asks: List(Level),
    receipt: String,
  )
}

pub type VenueStatus {
  VenueStatus(
    status: String,
    reason: String,
    source_role: String,
    jurisdiction: String,
    custody_model: String,
    unknown_facts: List(String),
    effective_date: String,
    receipt: String,
  )
}

pub type Funding {
  Funding(
    derivative_instrument_id: String,
    rate: common.Fact,
    interval: String,
    mark_price: common.Fact,
    index_price: common.Fact,
    open_interest: common.Fact,
    open_interest_unit: String,
    venue_unix_ms: Int,
    receipt: String,
  )
}

pub type Event {
  Event(
    event_id: String,
    event_type: String,
    effective_unix_ms: Int,
    legacy_asset_id: String,
    new_asset_id: String,
    source_description: String,
    receipt: String,
  )
}

pub type Packet {
  Packet(
    source: common.Source,
    identity: Identity,
    quote: Quote,
    comparison_quote: Quote,
    maximum_time_delta_ms: Int,
    trades: List(Trade),
    candle: Candle,
    order_book: Book,
    venue_status: VenueStatus,
    funding: Funding,
    events: List(Event),
    entitlement: String,
    licence: String,
  )
}

pub fn inspect(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "crypto_market_v1",
    "inspect",
    packet_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate(packet))
  let midpoint = quote_midpoint(packet.quote)
  let spread = quote_spread(packet.quote)
  let spread_percent = case spread, midpoint {
    Ok(spread), Ok(midpoint) -> common.percentage(spread, midpoint, 6)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let comparison_midpoint = quote_midpoint(packet.comparison_quote)
  let cross_delta = case midpoint, comparison_midpoint {
    Ok(left), Ok(right) -> Ok(decimal.subtract(left, right))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let time_delta =
    int.absolute_value(
      packet.quote.venue_unix_ms - packet.comparison_quote.venue_unix_ms,
    )
  let aligned = time_delta <= packet.maximum_time_delta_ms
  Ok(
    common.response(
      "crypto_market_v1",
      "inspect",
      decoded.1,
      "Exact venue-specific crypto identity, 24/7 observations, funding context and lineage with explicit cross-venue timing; no fourth equity track, stablecoin/fiat equivalence, venue safety, liquidity, arbitrage, or trade judgment",
      [
        #("source", common.source_json(packet.source)),
        #("track", json.null()),
        #("instrumentLeg", json.string("crypto_non_equity")),
        #("identity", identity_json(packet.identity)),
        #("quote", quote_json(packet.quote)),
        #(
          "quoteCalculations",
          json.object([
            #(
              "midpoint",
              common.calculation_json(
                "(venue_bid + venue_ask) / 2",
                midpoint,
                "quote_asset_per_base_asset",
                [],
              ),
            ),
            #(
              "spread",
              common.calculation_json(
                "venue_ask - venue_bid",
                spread,
                "quote_asset_per_base_asset",
                [],
              ),
            ),
            #(
              "spreadPercent",
              common.calculation_json(
                "(venue_ask - venue_bid) / midpoint * 100",
                spread_percent,
                "percent",
                [],
              ),
            ),
          ]),
        ),
        #("trades", json.array(packet.trades, trade_json)),
        #("candle", candle_json(packet.candle)),
        #("orderBook", book_json(packet.order_book)),
        #("venueStatus", venue_status_json(packet.venue_status)),
        #("fundingContext", funding_json(packet.funding)),
        #("events", json.array(packet.events, event_json)),
        #(
          "crossVenueComparison",
          json.object([
            #("otherQuote", quote_json(packet.comparison_quote)),
            #("timeDeltaMilliseconds", json.int(time_delta)),
            #(
              "maximumTimeDeltaMilliseconds",
              json.int(packet.maximum_time_delta_ms),
            ),
            #("alignedUnderCallerPolicy", json.bool(aligned)),
            #(
              "midpointDelta",
              common.calculation_json(
                "venue_a_midpoint - venue_b_midpoint",
                cross_delta,
                "quote_asset_per_base_asset",
                [],
              ),
            ),
            #(
              "executionClaim",
              json.string("not_executable_and_not_an_arbitrage_claim"),
            ),
          ]),
        ),
        #("entitlement", json.string(packet.entitlement)),
        #("licence", json.string(packet.licence)),
      ],
    ),
  )
}

fn packet_decoder() -> decode.Decoder(Packet) {
  use source <- decode.field("source", common.source_decoder())
  use identity <- decode.field("identity", identity_decoder())
  use quote <- decode.field("quote", quote_decoder())
  use comparison <- decode.field("comparisonQuote", quote_decoder())
  use maximum <- decode.field("maximumTimeDeltaMilliseconds", decode.int)
  use trades <- decode.field("trades", decode.list(of: trade_decoder()))
  use candle <- decode.field("candle", candle_decoder())
  use book <- decode.field("orderBook", book_decoder())
  use status <- decode.field("venueStatus", venue_status_decoder())
  use funding <- decode.field("fundingContext", funding_decoder())
  use events <- decode.field("events", decode.list(of: event_decoder()))
  use entitlement <- decode.field("entitlement", decode.string)
  use licence <- decode.field("licence", decode.string)
  decode.success(Packet(
    source,
    identity,
    quote,
    comparison,
    maximum,
    trades,
    candle,
    book,
    status,
    funding,
    events,
    entitlement,
    licence,
  ))
}

fn identity_decoder() -> decode.Decoder(Identity) {
  use asset <- decode.field("assetId", decode.string)
  use network <- decode.field("network", decode.string)
  use standard <- decode.field("tokenStandard", decode.string)
  use address <- decode.optional_field(
    "contractAddress",
    None,
    decode.optional(decode.string),
  )
  use symbol <- decode.field("tokenSymbol", decode.string)
  use venue <- decode.field("venue", decode.string)
  use venue_instrument <- decode.field("venueInstrumentId", decode.string)
  use base <- decode.field("baseAssetId", decode.string)
  use quote <- decode.field("quoteAssetId", decode.string)
  use instrument_type <- decode.field("instrumentType", decode.string)
  use venue_type <- decode.field("venueType", decode.string)
  use stablecoin <- decode.field("stablecoinQuote", decode.bool)
  use wrapped <- decode.optional_field(
    "wrappedAssetId",
    None,
    decode.optional(decode.string),
  )
  use receipt <- decode.field("identityReceipt", decode.string)
  decode.success(Identity(
    asset,
    network,
    standard,
    address,
    symbol,
    venue,
    venue_instrument,
    base,
    quote,
    instrument_type,
    venue_type,
    stablecoin,
    wrapped,
    receipt,
  ))
}

fn quote_decoder() -> decode.Decoder(Quote) {
  use venue <- decode.field("venue", decode.string)
  use instrument <- decode.field("venueInstrumentId", decode.string)
  use bid <- decode.field("bid", common.fact_decoder())
  use bid_size <- decode.field("bidSize", common.fact_decoder())
  use ask <- decode.field("ask", common.fact_decoder())
  use ask_size <- decode.field("askSize", common.fact_decoder())
  use venue_time <- decode.field("venueUnixMilliseconds", decode.int)
  use receipt_time <- decode.field("receiptUnixMilliseconds", decode.int)
  use sequence <- decode.field("sequence", decode.int)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Quote(
    venue,
    instrument,
    bid,
    bid_size,
    ask,
    ask_size,
    venue_time,
    receipt_time,
    sequence,
    receipt,
  ))
}

fn trade_decoder() -> decode.Decoder(Trade) {
  use id <- decode.field("tradeId", decode.string)
  use price <- decode.field("price", common.fact_decoder())
  use size <- decode.field("size", common.fact_decoder())
  use time <- decode.field("venueUnixMilliseconds", decode.int)
  use sequence <- decode.field("sequence", decode.int)
  use side <- decode.field("side", decode.string)
  use corrections <- decode.field(
    "correctionLineage",
    decode.list(of: decode.string),
  )
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Trade(
    id,
    price,
    size,
    time,
    sequence,
    side,
    corrections,
    receipt,
  ))
}

fn candle_decoder() -> decode.Decoder(Candle) {
  use interval <- decode.field("interval", decode.string)
  use boundary <- decode.field("boundaryConvention", decode.string)
  use open_time <- decode.field("openUnixMilliseconds", decode.int)
  use close_time <- decode.field("closeUnixMilliseconds", decode.int)
  use open <- decode.field("open", common.fact_decoder())
  use high <- decode.field("high", common.fact_decoder())
  use low <- decode.field("low", common.fact_decoder())
  use close <- decode.field("close", common.fact_decoder())
  use volume <- decode.field("volume", common.fact_decoder())
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Candle(
    interval,
    boundary,
    open_time,
    close_time,
    open,
    high,
    low,
    close,
    volume,
    receipt,
  ))
}

fn level_decoder() -> decode.Decoder(Level) {
  use price <- decode.field("price", common.fact_decoder())
  use size <- decode.field("size", common.fact_decoder())
  decode.success(Level(price, size))
}

fn book_decoder() -> decode.Decoder(Book) {
  use time <- decode.field("venueUnixMilliseconds", decode.int)
  use sequence <- decode.field("sequence", decode.int)
  use bids <- decode.field("bids", decode.list(of: level_decoder()))
  use asks <- decode.field("asks", decode.list(of: level_decoder()))
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Book(time, sequence, bids, asks, receipt))
}

fn venue_status_decoder() -> decode.Decoder(VenueStatus) {
  use status <- decode.field("status", decode.string)
  use reason <- decode.field("reason", decode.string)
  use role <- decode.field("sourceRole", decode.string)
  use jurisdiction <- decode.field("jurisdiction", decode.string)
  use custody <- decode.field("custodyModel", decode.string)
  use unknowns <- decode.field("unknownFacts", decode.list(of: decode.string))
  use date <- decode.field("effectiveDate", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(VenueStatus(
    status,
    reason,
    role,
    jurisdiction,
    custody,
    unknowns,
    date,
    receipt,
  ))
}

fn funding_decoder() -> decode.Decoder(Funding) {
  use instrument <- decode.field("derivativeInstrumentId", decode.string)
  use rate <- decode.field("rate", common.fact_decoder())
  use interval <- decode.field("interval", decode.string)
  use mark <- decode.field("markPrice", common.fact_decoder())
  use index <- decode.field("indexPrice", common.fact_decoder())
  use oi <- decode.field("openInterest", common.fact_decoder())
  use oi_unit <- decode.field("openInterestUnit", decode.string)
  use time <- decode.field("venueUnixMilliseconds", decode.int)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Funding(
    instrument,
    rate,
    interval,
    mark,
    index,
    oi,
    oi_unit,
    time,
    receipt,
  ))
}

fn event_decoder() -> decode.Decoder(Event) {
  use id <- decode.field("eventId", decode.string)
  use kind <- decode.field("eventType", decode.string)
  use effective <- decode.field("effectiveUnixMilliseconds", decode.int)
  use legacy <- decode.field("legacyAssetId", decode.string)
  use new <- decode.field("newAssetId", decode.string)
  use description <- decode.field("sourceDescription", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Event(id, kind, effective, legacy, new, description, receipt))
}

fn validate(packet: Packet) -> Result(Nil, common.Error) {
  let identity = packet.identity
  use _ <- result.try(common.non_empty("identity.assetId", identity.asset_id))
  use _ <- result.try(common.non_empty("identity.network", identity.network))
  use _ <- result.try(common.non_empty(
    "identity.tokenStandard",
    identity.token_standard,
  ))
  use _ <- result.try(common.non_empty(
    "identity.tokenSymbol",
    identity.token_symbol,
  ))
  use _ <- result.try(common.non_empty("identity.venue", identity.venue))
  use _ <- result.try(common.non_empty(
    "identity.venueInstrumentId",
    identity.venue_instrument_id,
  ))
  use _ <- result.try(common.non_empty(
    "identity.baseAssetId",
    identity.base_asset_id,
  ))
  use _ <- result.try(common.non_empty(
    "identity.quoteAssetId",
    identity.quote_asset_id,
  ))
  use _ <- result.try(
    common.one_of("identity.instrumentType", identity.instrument_type, ["spot"]),
  )
  use _ <- result.try(
    common.one_of("identity.venueType", identity.venue_type, [
      "CEX",
      "DEX",
      "RFQ",
    ]),
  )
  use _ <- result.try(common.receipt(
    "identity.identityReceipt",
    identity.identity_receipt,
  ))
  use _ <- result.try(validate_quote("quote", packet.quote))
  use _ <- result.try(validate_quote("comparisonQuote", packet.comparison_quote))
  use _ <- result.try(common.non_negative(
    "maximumTimeDeltaMilliseconds",
    packet.maximum_time_delta_ms,
  ))
  use _ <- result.try(case list.length(packet.trades) <= 1000 {
    True -> Ok(Nil)
    False ->
      Error(common.BudgetExceeded("trades", list.length(packet.trades), 1000))
  })
  use _ <- result.try(
    packet.trades
    |> list.try_map(validate_trade)
    |> result.map(fn(_) { Nil }),
  )
  use _ <- result.try(validate_candle(packet.candle))
  use _ <- result.try(validate_book(packet.order_book))
  use _ <- result.try(validate_venue_status(packet.venue_status))
  use _ <- result.try(validate_funding(packet.funding))
  use _ <- result.try(
    packet.events
    |> list.try_map(validate_event)
    |> result.map(fn(_) { Nil }),
  )
  use _ <- result.try(common.non_empty("entitlement", packet.entitlement))
  common.non_empty("licence", packet.licence)
}

fn validate_quote(prefix: String, quote: Quote) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty(prefix <> ".venue", quote.venue))
  use _ <- result.try(common.non_empty(
    prefix <> ".venueInstrumentId",
    quote.venue_instrument_id,
  ))
  use _ <- result.try(common.validate_fact(prefix <> ".bid", quote.bid))
  use _ <- result.try(common.validate_fact(prefix <> ".bidSize", quote.bid_size))
  use _ <- result.try(common.validate_fact(prefix <> ".ask", quote.ask))
  use _ <- result.try(common.validate_fact(prefix <> ".askSize", quote.ask_size))
  use _ <- result.try(common.non_negative(
    prefix <> ".venueUnixMilliseconds",
    quote.venue_unix_ms,
  ))
  use _ <- result.try(common.non_negative(
    prefix <> ".receiptUnixMilliseconds",
    quote.receipt_unix_ms,
  ))
  use _ <- result.try(common.non_negative(prefix <> ".sequence", quote.sequence))
  common.receipt(prefix <> ".receipt", quote.receipt)
}

fn validate_trade(trade: Trade) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty("trade.tradeId", trade.trade_id))
  use _ <- result.try(common.validate_fact("trade.price", trade.price))
  use _ <- result.try(common.validate_fact("trade.size", trade.size))
  use _ <- result.try(common.non_negative(
    "trade.venueUnixMilliseconds",
    trade.venue_unix_ms,
  ))
  use _ <- result.try(common.non_negative("trade.sequence", trade.sequence))
  use _ <- result.try(
    common.one_of("trade.side", trade.side, ["buy", "sell", "unknown"]),
  )
  use _ <- result.try(common.validate_receipts(
    "trade.correctionLineage",
    trade.correction_lineage,
  ))
  common.receipt("trade.receipt", trade.receipt)
}

fn validate_candle(candle: Candle) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty("candle.interval", candle.interval))
  use _ <- result.try(common.non_empty(
    "candle.boundaryConvention",
    candle.boundary_convention,
  ))
  use _ <- result.try(case candle.close_unix_ms > candle.open_unix_ms {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField("candle", "close time must follow open time"))
  })
  use _ <- result.try(common.validate_fact("candle.open", candle.open))
  use _ <- result.try(common.validate_fact("candle.high", candle.high))
  use _ <- result.try(common.validate_fact("candle.low", candle.low))
  use _ <- result.try(common.validate_fact("candle.close", candle.close))
  use _ <- result.try(common.validate_fact("candle.volume", candle.volume))
  common.receipt("candle.receipt", candle.receipt)
}

fn validate_book(book: Book) -> Result(Nil, common.Error) {
  use _ <- result.try(case book.bids, book.asks {
    [], _ -> Error(common.InvalidField("orderBook.bids", "must not be empty"))
    _, [] -> Error(common.InvalidField("orderBook.asks", "must not be empty"))
    _, _ -> Ok(Nil)
  })
  use _ <- result.try(
    case list.length(book.bids) <= 100 && list.length(book.asks) <= 100 {
      True -> Ok(Nil)
      False ->
        Error(common.BudgetExceeded(
          "orderBook.levels",
          list.length(book.bids) + list.length(book.asks),
          200,
        ))
    },
  )
  use _ <- result.try(
    book.bids
    |> list.append(book.asks)
    |> list.try_map(fn(level) {
      use _ <- result.try(common.validate_fact("book.price", level.price))
      common.validate_fact("book.size", level.size)
    })
    |> result.map(fn(_) { Nil }),
  )
  common.receipt("orderBook.receipt", book.receipt)
}

fn validate_venue_status(status: VenueStatus) -> Result(Nil, common.Error) {
  use _ <- result.try(
    common.one_of("venueStatus.status", status.status, [
      "operational",
      "maintenance",
      "halted",
      "degraded",
    ]),
  )
  use _ <- result.try(common.non_empty("venueStatus.reason", status.reason))
  use _ <- result.try(
    common.one_of("venueStatus.sourceRole", status.source_role, [
      "venue_self_reported",
      "third_party_reported",
      "regulatory_published",
    ]),
  )
  use _ <- result.try(common.non_empty(
    "venueStatus.jurisdiction",
    status.jurisdiction,
  ))
  use _ <- result.try(common.non_empty(
    "venueStatus.custodyModel",
    status.custody_model,
  ))
  use _ <- result.try(common.date(
    "venueStatus.effectiveDate",
    status.effective_date,
  ))
  common.receipt("venueStatus.receipt", status.receipt)
}

fn validate_funding(funding: Funding) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty(
    "funding.derivativeInstrumentId",
    funding.derivative_instrument_id,
  ))
  use _ <- result.try(common.validate_fact("funding.rate", funding.rate))
  use _ <- result.try(common.non_empty("funding.interval", funding.interval))
  use _ <- result.try(common.validate_fact(
    "funding.markPrice",
    funding.mark_price,
  ))
  use _ <- result.try(common.validate_fact(
    "funding.indexPrice",
    funding.index_price,
  ))
  use _ <- result.try(common.validate_fact(
    "funding.openInterest",
    funding.open_interest,
  ))
  use _ <- result.try(common.non_empty(
    "funding.openInterestUnit",
    funding.open_interest_unit,
  ))
  use _ <- result.try(common.non_negative(
    "funding.venueUnixMilliseconds",
    funding.venue_unix_ms,
  ))
  common.receipt("funding.receipt", funding.receipt)
}

fn validate_event(event: Event) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty("event.eventId", event.event_id))
  use _ <- result.try(
    common.one_of("event.eventType", event.event_type, [
      "fork",
      "airdrop",
      "redenomination",
      "token_migration",
      "delisting",
    ]),
  )
  use _ <- result.try(common.non_negative(
    "event.effectiveUnixMilliseconds",
    event.effective_unix_ms,
  ))
  use _ <- result.try(common.non_empty(
    "event.legacyAssetId",
    event.legacy_asset_id,
  ))
  use _ <- result.try(common.non_empty("event.newAssetId", event.new_asset_id))
  use _ <- result.try(common.non_empty(
    "event.sourceDescription",
    event.source_description,
  ))
  common.receipt("event.receipt", event.receipt)
}

fn quote_midpoint(quote: Quote) -> Result(decimal.Decimal, common.Error) {
  case
    common.fact_decimal("quote.bid", quote.bid),
    common.fact_decimal("quote.ask", quote.ask)
  {
    Ok(bid), Ok(ask) -> {
      let assert Ok(two) = decimal.parse("2")
      common.ratio(decimal.add(bid, ask), two, 8)
    }
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
}

fn quote_spread(quote: Quote) -> Result(decimal.Decimal, common.Error) {
  case
    common.fact_decimal("quote.bid", quote.bid),
    common.fact_decimal("quote.ask", quote.ask)
  {
    Ok(bid), Ok(ask) -> Ok(decimal.subtract(ask, bid))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
}

fn identity_json(identity: Identity) -> json.Json {
  json.object([
    #("assetId", json.string(identity.asset_id)),
    #("network", json.string(identity.network)),
    #("tokenStandard", json.string(identity.token_standard)),
    #("contractAddress", common.option_string_json(identity.contract_address)),
    #("tokenSymbol", json.string(identity.token_symbol)),
    #("venue", json.string(identity.venue)),
    #("venueInstrumentId", json.string(identity.venue_instrument_id)),
    #("baseAssetId", json.string(identity.base_asset_id)),
    #("quoteAssetId", json.string(identity.quote_asset_id)),
    #("instrumentType", json.string(identity.instrument_type)),
    #("venueType", json.string(identity.venue_type)),
    #("stablecoinQuote", json.bool(identity.stablecoin_quote)),
    #("stablecoinIsFiat", json.bool(False)),
    #("wrappedAssetId", common.option_string_json(identity.wrapped_asset_id)),
    #("identityReceipt", json.string(identity.identity_receipt)),
  ])
}

fn quote_json(quote: Quote) -> json.Json {
  json.object([
    #("venue", json.string(quote.venue)),
    #("venueInstrumentId", json.string(quote.venue_instrument_id)),
    #("bid", common.fact_json(quote.bid)),
    #("bidSize", common.fact_json(quote.bid_size)),
    #("ask", common.fact_json(quote.ask)),
    #("askSize", common.fact_json(quote.ask_size)),
    #("venueUnixMilliseconds", json.int(quote.venue_unix_ms)),
    #("receiptUnixMilliseconds", json.int(quote.receipt_unix_ms)),
    #("sequence", json.int(quote.sequence)),
    #("receipt", json.string(quote.receipt)),
  ])
}

fn trade_json(trade: Trade) -> json.Json {
  json.object([
    #("tradeId", json.string(trade.trade_id)),
    #("price", common.fact_json(trade.price)),
    #("size", common.fact_json(trade.size)),
    #("venueUnixMilliseconds", json.int(trade.venue_unix_ms)),
    #("sequence", json.int(trade.sequence)),
    #("side", json.string(trade.side)),
    #("correctionLineage", json.array(trade.correction_lineage, json.string)),
    #("receipt", json.string(trade.receipt)),
  ])
}

fn candle_json(candle: Candle) -> json.Json {
  json.object([
    #("interval", json.string(candle.interval)),
    #("boundaryConvention", json.string(candle.boundary_convention)),
    #("sessionSemantics", json.string("none_24_7_interval_only")),
    #("openUnixMilliseconds", json.int(candle.open_unix_ms)),
    #("closeUnixMilliseconds", json.int(candle.close_unix_ms)),
    #("open", common.fact_json(candle.open)),
    #("high", common.fact_json(candle.high)),
    #("low", common.fact_json(candle.low)),
    #("close", common.fact_json(candle.close)),
    #("volume", common.fact_json(candle.volume)),
    #("receipt", json.string(candle.receipt)),
  ])
}

fn book_json(book: Book) -> json.Json {
  json.object([
    #("venueUnixMilliseconds", json.int(book.venue_unix_ms)),
    #("sequence", json.int(book.sequence)),
    #("bids", json.array(book.bids, level_json)),
    #("asks", json.array(book.asks, level_json)),
    #(
      "depthLevels",
      json.int(int.min(list.length(book.bids), list.length(book.asks))),
    ),
    #("receipt", json.string(book.receipt)),
  ])
}

fn level_json(level: Level) -> json.Json {
  json.object([
    #("price", common.fact_json(level.price)),
    #("size", common.fact_json(level.size)),
  ])
}

fn venue_status_json(status: VenueStatus) -> json.Json {
  json.object([
    #("status", json.string(status.status)),
    #("reason", json.string(status.reason)),
    #("sourceRole", json.string(status.source_role)),
    #("jurisdiction", json.string(status.jurisdiction)),
    #("custodyModel", json.string(status.custody_model)),
    #("unknownFacts", json.array(status.unknown_facts, json.string)),
    #("effectiveDate", json.string(status.effective_date)),
    #("receipt", json.string(status.receipt)),
    #("safetyVerdict", json.null()),
  ])
}

fn funding_json(funding: Funding) -> json.Json {
  json.object([
    #("derivativeInstrumentId", json.string(funding.derivative_instrument_id)),
    #("rate", common.fact_json(funding.rate)),
    #("interval", json.string(funding.interval)),
    #("markPrice", common.fact_json(funding.mark_price)),
    #("indexPrice", common.fact_json(funding.index_price)),
    #("openInterest", common.fact_json(funding.open_interest)),
    #("openInterestUnit", json.string(funding.open_interest_unit)),
    #("venueUnixMilliseconds", json.int(funding.venue_unix_ms)),
    #("receipt", json.string(funding.receipt)),
    #("tradeSignal", json.null()),
  ])
}

fn event_json(event: Event) -> json.Json {
  json.object([
    #("eventId", json.string(event.event_id)),
    #("eventType", json.string(event.event_type)),
    #("effectiveUnixMilliseconds", json.int(event.effective_unix_ms)),
    #("legacyAssetId", json.string(event.legacy_asset_id)),
    #("newAssetId", json.string(event.new_asset_id)),
    #("sourceDescription", json.string(event.source_description)),
    #("receipt", json.string(event.receipt)),
    #("canonicalChainSelection", json.null()),
  ])
}
