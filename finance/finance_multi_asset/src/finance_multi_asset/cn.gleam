import finance_core/decimal
import finance_multi_asset/common
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Lt}
import gleam/result
import gleam/string

pub type IpoIdentity {
  IpoIdentity(
    issuer_name_cn: String,
    proposed_code: String,
    final_code: Option(String),
    board: String,
    mic: String,
    share_class: String,
    sponsor: String,
    accounting_firm: String,
    law_firm: String,
  )
}

pub type StateEvent {
  StateEvent(
    event_id: String,
    state: String,
    effective_date: String,
    publication_date: String,
    sequence: Int,
    receipt: String,
    corrects: Option(String),
  )
}

pub type IpoOffer {
  IpoOffer(
    currency: String,
    pre_ipo_shares: common.Fact,
    new_shares: common.Fact,
    total_offered: common.Fact,
    offer_price: common.Fact,
    listing_close: common.Fact,
  )
}

pub type IpoPacket {
  IpoPacket(
    source: common.Source,
    identity: IpoIdentity,
    states: List(StateEvent),
    offer: IpoOffer,
  )
}

pub fn ipo(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "cn_ipo_v1",
    "analyze",
    ipo_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate_ipo_identity(packet.identity))
  use _ <- result.try(validate_states(packet.states))
  use _ <- result.try(validate_offer(packet.offer))
  let post_shares = case
    common.fact_decimal("offer.preIpoShares", packet.offer.pre_ipo_shares),
    common.fact_decimal("offer.newShares", packet.offer.new_shares)
  {
    Ok(pre), Ok(new) -> Ok(decimal.add(pre, new))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let dilution = case
    common.fact_decimal("offer.preIpoShares", packet.offer.pre_ipo_shares),
    post_shares
  {
    Ok(pre), Ok(post) -> common.percentage(decimal.subtract(post, pre), post, 6)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let gross_proceeds = case
    common.fact_decimal("offer.totalOffered", packet.offer.total_offered),
    common.fact_decimal("offer.offerPrice", packet.offer.offer_price)
  {
    Ok(shares), Ok(price) -> Ok(decimal.multiply(shares, price))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let listing_return = case
    common.fact_decimal("offer.listingClose", packet.offer.listing_close),
    common.fact_decimal("offer.offerPrice", packet.offer.offer_price)
  {
    Ok(close), Ok(price) ->
      common.percentage(decimal.subtract(close, price), price, 6)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let last_state = last_state(packet.states)
  Ok(
    common.response(
      "cn_ipo_v1",
      "analyze",
      decoded.1,
      "Exact mainland IPO state chain and requested dilution calculations; no approval, eligibility, valuation, allocation, or subscription judgment",
      [
        #("source", common.source_json(packet.source)),
        #("track", json.string("cn")),
        #("identity", ipo_identity_json(packet.identity)),
        #("currentState", json.string(last_state.state)),
        #("stateHistory", json.array(packet.states, state_json)),
        #("offer", offer_json(packet.offer)),
        #(
          "calculations",
          json.object([
            #(
              "postIpoShares",
              common.calculation_json(
                "pre_ipo_shares + new_shares",
                post_shares,
                "shares",
                [
                  #(
                    "preIpoShares",
                    common.fact_json(packet.offer.pre_ipo_shares),
                  ),
                  #("newShares", common.fact_json(packet.offer.new_shares)),
                ],
              ),
            ),
            #(
              "dilutionPercent",
              common.calculation_json(
                "(post_ipo_shares - pre_ipo_shares) / post_ipo_shares * 100",
                dilution,
                "percent",
                [
                  #(
                    "preIpoShares",
                    common.fact_json(packet.offer.pre_ipo_shares),
                  ),
                  #("newShares", common.fact_json(packet.offer.new_shares)),
                ],
              ),
            ),
            #(
              "grossProceeds",
              common.calculation_json(
                "total_shares_offered * offer_price_final",
                gross_proceeds,
                packet.offer.currency,
                [
                  #(
                    "totalOffered",
                    common.fact_json(packet.offer.total_offered),
                  ),
                  #("offerPrice", common.fact_json(packet.offer.offer_price)),
                ],
              ),
            ),
            #(
              "listingDayReturnPercent",
              common.calculation_json(
                "(listing_day_close - offer_price_final) / offer_price_final * 100",
                listing_return,
                "percent",
                [
                  #(
                    "listingClose",
                    common.fact_json(packet.offer.listing_close),
                  ),
                  #("offerPrice", common.fact_json(packet.offer.offer_price)),
                ],
              ),
            ),
          ]),
        ),
        #(
          "availableOperations",
          json.array(
            [
              "inspect_state_history",
              "inspect_source_receipts",
              "supply_missing_offer_fact",
            ],
            json.string,
          ),
        ),
      ],
    ),
  )
}

fn ipo_decoder() -> decode.Decoder(IpoPacket) {
  use source <- decode.field("source", common.source_decoder())
  use identity <- decode.field("identity", ipo_identity_decoder())
  use states <- decode.field("stateHistory", decode.list(of: state_decoder()))
  use offer <- decode.field("offer", offer_decoder())
  decode.success(IpoPacket(source, identity, states, offer))
}

fn ipo_identity_decoder() -> decode.Decoder(IpoIdentity) {
  use issuer <- decode.field("issuerNameCn", decode.string)
  use proposed <- decode.field("stockCodeProposed", decode.string)
  use final <- decode.optional_field(
    "stockCodeFinal",
    None,
    decode.optional(decode.string),
  )
  use board <- decode.field("board", decode.string)
  use mic <- decode.field("mic", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  use sponsor <- decode.field("sponsor", decode.string)
  use accounting <- decode.field("accountingFirm", decode.string)
  use law <- decode.field("lawFirm", decode.string)
  decode.success(IpoIdentity(
    issuer,
    proposed,
    final,
    board,
    mic,
    share_class,
    sponsor,
    accounting,
    law,
  ))
}

fn state_decoder() -> decode.Decoder(StateEvent) {
  use id <- decode.field("eventId", decode.string)
  use state <- decode.field("state", decode.string)
  use effective <- decode.field("effectiveDate", decode.string)
  use publication <- decode.field("publicationDate", decode.string)
  use sequence <- decode.field("sequence", decode.int)
  use receipt <- decode.field("receipt", decode.string)
  use corrects <- decode.optional_field(
    "corrects",
    None,
    decode.optional(decode.string),
  )
  decode.success(StateEvent(
    id,
    state,
    effective,
    publication,
    sequence,
    receipt,
    corrects,
  ))
}

fn offer_decoder() -> decode.Decoder(IpoOffer) {
  use currency <- decode.field("currency", decode.string)
  use pre <- decode.field("preIpoShares", common.fact_decoder())
  use new <- decode.field("newShares", common.fact_decoder())
  use total <- decode.field("totalOffered", common.fact_decoder())
  use price <- decode.field("offerPrice", common.fact_decoder())
  use close <- decode.field("listingClose", common.fact_decoder())
  decode.success(IpoOffer(currency, pre, new, total, price, close))
}

fn validate_ipo_identity(identity: IpoIdentity) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty(
    "identity.issuerNameCn",
    identity.issuer_name_cn,
  ))
  use _ <- result.try(common.non_empty(
    "identity.stockCodeProposed",
    identity.proposed_code,
  ))
  use _ <- result.try(
    common.one_of("identity.board", identity.board, [
      "main",
      "chinext",
      "star",
      "bse",
    ]),
  )
  use _ <- result.try(
    common.one_of("identity.mic", identity.mic, ["XSHG", "XSHE", "XBSE"]),
  )
  use _ <- result.try(
    common.one_of("identity.shareClass", identity.share_class, ["A-share"]),
  )
  use _ <- result.try(common.non_empty("identity.sponsor", identity.sponsor))
  use _ <- result.try(common.non_empty(
    "identity.accountingFirm",
    identity.accounting_firm,
  ))
  common.non_empty("identity.lawFirm", identity.law_firm)
}

fn validate_states(states: List(StateEvent)) -> Result(Nil, common.Error) {
  case states {
    [] -> Error(common.InvalidField("stateHistory", "must not be empty"))
    _ ->
      case list.length(states) > 200 {
        True ->
          Error(common.BudgetExceeded("stateHistory", list.length(states), 200))
        False -> validate_states_loop(states, 0, "")
      }
  }
}

fn validate_states_loop(
  states: List(StateEvent),
  prior_sequence: Int,
  prior_date: String,
) -> Result(Nil, common.Error) {
  case states {
    [] -> Ok(Nil)
    [event, ..rest] -> {
      use _ <- result.try(common.non_empty("state.eventId", event.event_id))
      use _ <- result.try(
        common.one_of("state.state", event.state, [
          "accepted",
          "inquiry",
          "inquiry_response",
          "reviewed",
          "approved",
          "rejected",
          "withdrawn",
          "terminated",
          "offering",
          "allotment",
          "listed",
          "post_listing",
        ]),
      )
      use _ <- result.try(common.date(
        "state.effectiveDate",
        event.effective_date,
      ))
      use _ <- result.try(common.date(
        "state.publicationDate",
        event.publication_date,
      ))
      use _ <- result.try(common.receipt("state.receipt", event.receipt))
      use _ <- result.try(case event.sequence == prior_sequence + 1 {
        True -> Ok(Nil)
        False ->
          Error(common.InvalidField(
            "state.sequence",
            "must be a contiguous append-only ordinal",
          ))
      })
      use _ <- result.try(
        case
          prior_date == ""
          || string.compare(event.effective_date, prior_date) != Lt
        {
          True -> Ok(Nil)
          False ->
            Error(common.InvalidField(
              "state.effectiveDate",
              "must be ordered without overwriting prior events",
            ))
        },
      )
      validate_states_loop(rest, event.sequence, event.effective_date)
    }
  }
}

fn validate_offer(offer: IpoOffer) -> Result(Nil, common.Error) {
  use _ <- result.try(common.one_of("offer.currency", offer.currency, ["CNY"]))
  use _ <- result.try(common.validate_fact(
    "offer.preIpoShares",
    offer.pre_ipo_shares,
  ))
  use _ <- result.try(common.validate_fact("offer.newShares", offer.new_shares))
  use _ <- result.try(common.validate_fact(
    "offer.totalOffered",
    offer.total_offered,
  ))
  use _ <- result.try(common.validate_fact(
    "offer.offerPrice",
    offer.offer_price,
  ))
  common.validate_fact("offer.listingClose", offer.listing_close)
}

fn last_state(states: List(StateEvent)) -> StateEvent {
  let assert [first, ..rest] = states
  list.fold(rest, first, fn(_, next) { next })
}

fn ipo_identity_json(identity: IpoIdentity) -> json.Json {
  json.object([
    #("issuerNameCn", json.string(identity.issuer_name_cn)),
    #("stockCodeProposed", json.string(identity.proposed_code)),
    #("stockCodeFinal", common.option_string_json(identity.final_code)),
    #("board", json.string(identity.board)),
    #("mic", json.string(identity.mic)),
    #("shareClass", json.string(identity.share_class)),
    #("sponsor", json.string(identity.sponsor)),
    #("accountingFirm", json.string(identity.accounting_firm)),
    #("lawFirm", json.string(identity.law_firm)),
  ])
}

fn state_json(event: StateEvent) -> json.Json {
  json.object([
    #("eventId", json.string(event.event_id)),
    #("state", json.string(event.state)),
    #("effectiveDate", json.string(event.effective_date)),
    #("publicationDate", json.string(event.publication_date)),
    #("sequence", json.int(event.sequence)),
    #("receipt", json.string(event.receipt)),
    #("corrects", common.option_string_json(event.corrects)),
  ])
}

fn offer_json(offer: IpoOffer) -> json.Json {
  json.object([
    #("currency", json.string(offer.currency)),
    #("preIpoShares", common.fact_json(offer.pre_ipo_shares)),
    #("newShares", common.fact_json(offer.new_shares)),
    #("totalOffered", common.fact_json(offer.total_offered)),
    #("offerPrice", common.fact_json(offer.offer_price)),
    #("listingClose", common.fact_json(offer.listing_close)),
  ])
}

pub type FundIdentity {
  FundIdentity(
    fund_id: String,
    share_class_id: String,
    fund_name: String,
    fund_type: String,
    listing_kind: String,
    listing_id: Option(String),
    mic: Option(String),
    manager: String,
    benchmark: String,
    base_currency: String,
    share_class_currency: String,
    distribution_policy: String,
    inception_date: String,
    status: String,
    identity_receipt: String,
  )
}

pub type Holdings {
  Holdings(
    holdings_date: String,
    publication_date: String,
    top_n_complete: Bool,
    disclosed_count: Int,
    total_count: Option(Int),
    rights: String,
    receipt: String,
  )
}

pub type FundPacket {
  FundPacket(
    source: common.Source,
    identity: FundIdentity,
    nav_start: common.Fact,
    nav_end: common.Fact,
    distribution: common.Fact,
    market_price: common.Fact,
    nav_at_market: common.Fact,
    gross_return: common.Fact,
    net_return: common.Fact,
    holdings: Holdings,
    dealing_policy: String,
  )
}

pub fn listed_fund(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  fund(bytes, expected_sha256, "cn_funds_etf_v1", True)
}

pub fn mutual_fund(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  fund(bytes, expected_sha256, "cn_mutual_funds_v1", False)
}

fn fund(
  bytes: String,
  expected_sha256: String,
  contract_id: String,
  listed: Bool,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    contract_id,
    "analyze",
    fund_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate_fund_identity(packet.identity, listed))
  use _ <- result.try(validate_holdings(packet.holdings))
  use _ <- result.try(validate_fund_facts(packet))
  let nav_return = case
    common.fact_decimal("navStart", packet.nav_start),
    common.fact_decimal("navEnd", packet.nav_end),
    common.fact_decimal("distribution", packet.distribution)
  {
    Ok(start), Ok(end), Ok(distribution) ->
      common.percentage(
        decimal.add(decimal.subtract(end, start), distribution),
        start,
        6,
      )
    Error(error), _, _ -> Error(error)
    _, Error(error), _ -> Error(error)
    _, _, Error(error) -> Error(error)
  }
  let premium = case
    common.fact_decimal("marketPrice", packet.market_price),
    common.fact_decimal("navAtMarket", packet.nav_at_market)
  {
    Ok(price), Ok(nav) ->
      common.percentage(decimal.subtract(price, nav), nav, 6)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let fee_drag = case
    common.fact_decimal("grossReturn", packet.gross_return),
    common.fact_decimal("netReturn", packet.net_return)
  {
    Ok(gross), Ok(net) -> Ok(decimal.subtract(gross, net))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let second_calculation = case listed {
    True -> #(
      "premiumDiscountPercent",
      common.calculation_json(
        "(market_price - official_nav) / official_nav * 100",
        premium,
        "percent",
        [
          #("marketPrice", common.fact_json(packet.market_price)),
          #("officialNav", common.fact_json(packet.nav_at_market)),
        ],
      ),
    )
    False -> #(
      "feeDrag",
      common.calculation_json(
        "gross_return - net_return",
        fee_drag,
        "return_fraction",
        [
          #("grossReturn", common.fact_json(packet.gross_return)),
          #("netReturn", common.fact_json(packet.net_return)),
        ],
      ),
    )
  }
  Ok(
    common.response(
      contract_id,
      "analyze",
      decoded.1,
      case listed {
        True ->
          "Exact CN listed-fund share class with separate market-price and official-NAV calculations; no ETF/stock equivalence or suitability judgment"
        False ->
          "Exact CN mutual-fund share class with NAV-only dealing and fee facts; no continuous-price or suitability judgment"
      },
      [
        #("source", common.source_json(packet.source)),
        #("track", json.string("cn")),
        #("identity", fund_identity_json(packet.identity)),
        #("holdings", holdings_json(packet.holdings)),
        #("dealingPolicy", json.string(packet.dealing_policy)),
        #(
          "calculations",
          json.object([
            #(
              "navReturnPercent",
              common.calculation_json(
                "(nav_end - nav_start + distribution) / nav_start * 100",
                nav_return,
                "percent",
                [
                  #("navStart", common.fact_json(packet.nav_start)),
                  #("navEnd", common.fact_json(packet.nav_end)),
                  #("distribution", common.fact_json(packet.distribution)),
                ],
              ),
            ),
            second_calculation,
          ]),
        ),
        #(
          "limitations",
          json.array(
            [
              "holdings_are_a_dated_disclosure_not_current_portfolio",
              "top_n_is_not_complete_when_topNComplete_is_false",
              "no_peer_or_quality_or_liquidity_judgment",
            ],
            json.string,
          ),
        ),
      ],
    ),
  )
}

fn fund_decoder() -> decode.Decoder(FundPacket) {
  use source <- decode.field("source", common.source_decoder())
  use identity <- decode.field("identity", fund_identity_decoder())
  use nav_start <- decode.field("navStart", common.fact_decoder())
  use nav_end <- decode.field("navEnd", common.fact_decoder())
  use distribution <- decode.field("distribution", common.fact_decoder())
  use market <- decode.field("marketPrice", common.fact_decoder())
  use nav_market <- decode.field("navAtMarket", common.fact_decoder())
  use gross <- decode.field("grossReturn", common.fact_decoder())
  use net <- decode.field("netReturn", common.fact_decoder())
  use holdings <- decode.field("holdings", holdings_decoder())
  use dealing <- decode.field("dealingPolicy", decode.string)
  decode.success(FundPacket(
    source,
    identity,
    nav_start,
    nav_end,
    distribution,
    market,
    nav_market,
    gross,
    net,
    holdings,
    dealing,
  ))
}

fn fund_identity_decoder() -> decode.Decoder(FundIdentity) {
  use fund_id <- decode.field("fundId", decode.string)
  use share_class <- decode.field("shareClassId", decode.string)
  use name <- decode.field("fundName", decode.string)
  use fund_type <- decode.field("fundType", decode.string)
  use listing_kind <- decode.field("listingKind", decode.string)
  use listing_id <- decode.optional_field(
    "listingId",
    None,
    decode.optional(decode.string),
  )
  use mic <- decode.optional_field("mic", None, decode.optional(decode.string))
  use manager <- decode.field("manager", decode.string)
  use benchmark <- decode.field("benchmark", decode.string)
  use base_currency <- decode.field("baseCurrency", decode.string)
  use share_currency <- decode.field("shareClassCurrency", decode.string)
  use distribution <- decode.field("distributionPolicy", decode.string)
  use inception <- decode.field("inceptionDate", decode.string)
  use status <- decode.field("status", decode.string)
  use receipt <- decode.field("identityReceipt", decode.string)
  decode.success(FundIdentity(
    fund_id,
    share_class,
    name,
    fund_type,
    listing_kind,
    listing_id,
    mic,
    manager,
    benchmark,
    base_currency,
    share_currency,
    distribution,
    inception,
    status,
    receipt,
  ))
}

fn holdings_decoder() -> decode.Decoder(Holdings) {
  use date <- decode.field("holdingsDate", decode.string)
  use published <- decode.field("publicationDate", decode.string)
  use complete <- decode.field("topNComplete", decode.bool)
  use disclosed <- decode.field("disclosedCount", decode.int)
  use total <- decode.optional_field(
    "totalCount",
    None,
    decode.optional(decode.int),
  )
  use rights <- decode.field("rights", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Holdings(
    date,
    published,
    complete,
    disclosed,
    total,
    rights,
    receipt,
  ))
}

fn validate_fund_identity(
  identity: FundIdentity,
  listed: Bool,
) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty("identity.fundId", identity.fund_id))
  use _ <- result.try(common.non_empty(
    "identity.shareClassId",
    identity.share_class_id,
  ))
  use _ <- result.try(common.non_empty("identity.fundName", identity.fund_name))
  use _ <- result.try(common.non_empty("identity.manager", identity.manager))
  use _ <- result.try(common.non_empty("identity.benchmark", identity.benchmark))
  use _ <- result.try(common.non_empty(
    "identity.baseCurrency",
    identity.base_currency,
  ))
  use _ <- result.try(common.non_empty(
    "identity.shareClassCurrency",
    identity.share_class_currency,
  ))
  use _ <- result.try(common.date(
    "identity.inceptionDate",
    identity.inception_date,
  ))
  use _ <- result.try(common.receipt(
    "identity.identityReceipt",
    identity.identity_receipt,
  ))
  case listed, identity.listing_kind, identity.listing_id, identity.mic {
    True, "listed", Some(listing_id), Some(mic) -> {
      use _ <- result.try(common.non_empty("identity.listingId", listing_id))
      use _ <- result.try(common.one_of("identity.mic", mic, ["XSHG", "XSHE"]))
      common.one_of("identity.fundType", identity.fund_type, [
        "ETF",
        "LOF",
        "ClosedEndFund",
      ])
    }
    False, "not_applicable", None, None ->
      common.one_of("identity.fundType", identity.fund_type, ["MutualFund"])
    True, _, _, _ ->
      Error(common.InvalidField(
        "identity.listingKind",
        "listed fund requires exact listingId and XSHG/XSHE MIC",
      ))
    False, _, _, _ ->
      Error(common.InvalidField(
        "identity.listingKind",
        "mutual fund must keep listingId and MIC not applicable",
      ))
  }
}

fn validate_holdings(holdings: Holdings) -> Result(Nil, common.Error) {
  use _ <- result.try(common.date(
    "holdings.holdingsDate",
    holdings.holdings_date,
  ))
  use _ <- result.try(common.date(
    "holdings.publicationDate",
    holdings.publication_date,
  ))
  use _ <- result.try(common.non_negative(
    "holdings.disclosedCount",
    holdings.disclosed_count,
  ))
  use _ <- result.try(common.non_empty("holdings.rights", holdings.rights))
  common.receipt("holdings.receipt", holdings.receipt)
}

fn validate_fund_facts(packet: FundPacket) -> Result(Nil, common.Error) {
  use _ <- result.try(common.validate_fact("navStart", packet.nav_start))
  use _ <- result.try(common.validate_fact("navEnd", packet.nav_end))
  use _ <- result.try(common.validate_fact("distribution", packet.distribution))
  use _ <- result.try(common.validate_fact("marketPrice", packet.market_price))
  use _ <- result.try(common.validate_fact("navAtMarket", packet.nav_at_market))
  use _ <- result.try(common.validate_fact("grossReturn", packet.gross_return))
  common.validate_fact("netReturn", packet.net_return)
}

fn fund_identity_json(identity: FundIdentity) -> json.Json {
  json.object([
    #("fundId", json.string(identity.fund_id)),
    #("shareClassId", json.string(identity.share_class_id)),
    #("fundName", json.string(identity.fund_name)),
    #("fundType", json.string(identity.fund_type)),
    #("listingKind", json.string(identity.listing_kind)),
    #("listingId", common.option_string_json(identity.listing_id)),
    #("mic", common.option_string_json(identity.mic)),
    #("manager", json.string(identity.manager)),
    #("benchmark", json.string(identity.benchmark)),
    #("baseCurrency", json.string(identity.base_currency)),
    #("shareClassCurrency", json.string(identity.share_class_currency)),
    #("distributionPolicy", json.string(identity.distribution_policy)),
    #("inceptionDate", json.string(identity.inception_date)),
    #("status", json.string(identity.status)),
    #("identityReceipt", json.string(identity.identity_receipt)),
  ])
}

fn holdings_json(holdings: Holdings) -> json.Json {
  json.object([
    #("holdingsDate", json.string(holdings.holdings_date)),
    #("publicationDate", json.string(holdings.publication_date)),
    #("topNComplete", json.bool(holdings.top_n_complete)),
    #("disclosedCount", json.int(holdings.disclosed_count)),
    #("totalCount", case holdings.total_count {
      Some(value) -> json.int(value)
      None -> json.null()
    }),
    #("rights", json.string(holdings.rights)),
    #("receipt", json.string(holdings.receipt)),
  ])
}

pub type ConvertibleIdentity {
  ConvertibleIdentity(
    instrument_id: String,
    issuer_id: String,
    underlying_listing_id: String,
    underlying_mic: String,
    currency: String,
    issue_date: String,
    maturity_date: String,
    terms_version: String,
    terms_receipt: String,
  )
}

pub type Scenario {
  Scenario(
    id: String,
    kind: String,
    underlying_price: common.Fact,
    receipt: String,
  )
}

pub type ConvertiblePacket {
  ConvertiblePacket(
    source: common.Source,
    identity: ConvertibleIdentity,
    face_value: common.Fact,
    conversion_price: common.Fact,
    underlying_price: common.Fact,
    bond_price: common.Fact,
    bond_floor: common.Fact,
    call_price: common.Fact,
    put_price: common.Fact,
    maturity_redemption: common.Fact,
    scenarios: List(Scenario),
    adjustment_receipts: List(String),
  )
}

pub fn convertible(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "cn_convertible_bonds_v1",
    "analyze",
    convertible_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate_convertible(packet))
  let ratio = case
    common.fact_decimal("faceValue", packet.face_value),
    common.fact_decimal("conversionPrice", packet.conversion_price)
  {
    Ok(face), Ok(price) -> common.ratio(face, price, 8)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let conversion_value = case
    ratio,
    common.fact_decimal("underlyingPrice", packet.underlying_price)
  {
    Ok(ratio), Ok(price) -> Ok(decimal.multiply(ratio, price))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let conversion_premium = case
    common.fact_decimal("bondPrice", packet.bond_price),
    conversion_value
  {
    Ok(price), Ok(value) ->
      common.percentage(decimal.subtract(price, value), value, 6)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let investment_premium = case
    common.fact_decimal("bondPrice", packet.bond_price),
    common.fact_decimal("bondFloor", packet.bond_floor)
  {
    Ok(price), Ok(floor) ->
      common.percentage(decimal.subtract(price, floor), floor, 6)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  Ok(
    common.response(
      "cn_convertible_bonds_v1",
      "analyze",
      decoded.1,
      "Exact CN convertible terms, parity and caller-declared scenario payoffs; no call, reset, value, or exercise prediction",
      [
        #("source", common.source_json(packet.source)),
        #("track", json.string("cn")),
        #("identity", convertible_identity_json(packet.identity)),
        #(
          "adjustmentReceipts",
          json.array(packet.adjustment_receipts, json.string),
        ),
        #(
          "calculations",
          json.object([
            #(
              "conversionRatio",
              common.calculation_json(
                "face_value / current_conversion_price",
                ratio,
                "underlying_shares_per_bond",
                [
                  #("faceValue", common.fact_json(packet.face_value)),
                  #(
                    "conversionPrice",
                    common.fact_json(packet.conversion_price),
                  ),
                ],
              ),
            ),
            #(
              "conversionValue",
              common.calculation_json(
                "conversion_ratio * underlying_price",
                conversion_value,
                "CNY_per_bond",
                [
                  #("faceValue", common.fact_json(packet.face_value)),
                  #(
                    "conversionPrice",
                    common.fact_json(packet.conversion_price),
                  ),
                  #(
                    "underlyingPrice",
                    common.fact_json(packet.underlying_price),
                  ),
                ],
              ),
            ),
            #(
              "conversionPremiumPercent",
              common.calculation_json(
                "(bond_price - conversion_value) / conversion_value * 100",
                conversion_premium,
                "percent",
                [
                  #("bondPrice", common.fact_json(packet.bond_price)),
                  #(
                    "conversionValue",
                    common.fact_json(packet.underlying_price),
                  ),
                ],
              ),
            ),
            #(
              "investmentPremiumPercent",
              common.calculation_json(
                "(bond_price - caller_model_bond_floor) / caller_model_bond_floor * 100",
                investment_premium,
                "percent",
                [
                  #("bondPrice", common.fact_json(packet.bond_price)),
                  #("bondFloor", common.fact_json(packet.bond_floor)),
                ],
              ),
            ),
          ]),
        ),
        #(
          "scenarios",
          json.array(packet.scenarios, fn(value) {
            scenario_json(value, packet, ratio)
          }),
        ),
      ],
    ),
  )
}

fn convertible_decoder() -> decode.Decoder(ConvertiblePacket) {
  use source <- decode.field("source", common.source_decoder())
  use identity <- decode.field("identity", convertible_identity_decoder())
  use face <- decode.field("faceValue", common.fact_decoder())
  use conversion <- decode.field("conversionPrice", common.fact_decoder())
  use underlying <- decode.field("underlyingPrice", common.fact_decoder())
  use bond <- decode.field("bondPrice", common.fact_decoder())
  use floor <- decode.field("bondFloor", common.fact_decoder())
  use call <- decode.field("callPrice", common.fact_decoder())
  use put <- decode.field("putPrice", common.fact_decoder())
  use maturity <- decode.field("maturityRedemption", common.fact_decoder())
  use scenarios <- decode.field(
    "scenarios",
    decode.list(of: scenario_decoder()),
  )
  use adjustments <- decode.field(
    "adjustmentReceipts",
    decode.list(of: decode.string),
  )
  decode.success(ConvertiblePacket(
    source,
    identity,
    face,
    conversion,
    underlying,
    bond,
    floor,
    call,
    put,
    maturity,
    scenarios,
    adjustments,
  ))
}

fn convertible_identity_decoder() -> decode.Decoder(ConvertibleIdentity) {
  use instrument <- decode.field("instrumentId", decode.string)
  use issuer <- decode.field("issuerId", decode.string)
  use listing <- decode.field("underlyingListingId", decode.string)
  use mic <- decode.field("underlyingMic", decode.string)
  use currency <- decode.field("currency", decode.string)
  use issue <- decode.field("issueDate", decode.string)
  use maturity <- decode.field("maturityDate", decode.string)
  use version <- decode.field("termsVersion", decode.string)
  use receipt <- decode.field("termsReceipt", decode.string)
  decode.success(ConvertibleIdentity(
    instrument,
    issuer,
    listing,
    mic,
    currency,
    issue,
    maturity,
    version,
    receipt,
  ))
}

fn scenario_decoder() -> decode.Decoder(Scenario) {
  use id <- decode.field("scenarioId", decode.string)
  use kind <- decode.field("kind", decode.string)
  use price <- decode.field("underlyingPrice", common.fact_decoder())
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Scenario(id, kind, price, receipt))
}

fn validate_convertible(
  packet: ConvertiblePacket,
) -> Result(Nil, common.Error) {
  let identity = packet.identity
  use _ <- result.try(common.non_empty(
    "identity.instrumentId",
    identity.instrument_id,
  ))
  use _ <- result.try(common.non_empty("identity.issuerId", identity.issuer_id))
  use _ <- result.try(common.non_empty(
    "identity.underlyingListingId",
    identity.underlying_listing_id,
  ))
  use _ <- result.try(
    common.one_of("identity.underlyingMic", identity.underlying_mic, [
      "XSHG",
      "XSHE",
    ]),
  )
  use _ <- result.try(
    common.one_of("identity.currency", identity.currency, ["CNY"]),
  )
  use _ <- result.try(common.date("identity.issueDate", identity.issue_date))
  use _ <- result.try(common.date(
    "identity.maturityDate",
    identity.maturity_date,
  ))
  use _ <- result.try(common.non_empty(
    "identity.termsVersion",
    identity.terms_version,
  ))
  use _ <- result.try(common.receipt(
    "identity.termsReceipt",
    identity.terms_receipt,
  ))
  use _ <- result.try(common.validate_fact("faceValue", packet.face_value))
  use _ <- result.try(common.validate_fact(
    "conversionPrice",
    packet.conversion_price,
  ))
  use _ <- result.try(common.validate_fact(
    "underlyingPrice",
    packet.underlying_price,
  ))
  use _ <- result.try(common.validate_fact("bondPrice", packet.bond_price))
  use _ <- result.try(common.validate_fact("bondFloor", packet.bond_floor))
  use _ <- result.try(common.validate_fact("callPrice", packet.call_price))
  use _ <- result.try(common.validate_fact("putPrice", packet.put_price))
  use _ <- result.try(common.validate_fact(
    "maturityRedemption",
    packet.maturity_redemption,
  ))
  use _ <- result.try(common.validate_receipts(
    "adjustmentReceipts",
    packet.adjustment_receipts,
  ))
  packet.scenarios
  |> list.try_map(fn(scenario) {
    use _ <- result.try(common.non_empty("scenario.scenarioId", scenario.id))
    use _ <- result.try(
      common.one_of("scenario.kind", scenario.kind, [
        "call",
        "convert",
        "hold",
        "put",
      ]),
    )
    use _ <- result.try(common.validate_fact(
      "scenario.underlyingPrice",
      scenario.underlying_price,
    ))
    common.receipt("scenario.receipt", scenario.receipt)
  })
  |> result.map(fn(_) { Nil })
}

fn scenario_json(
  scenario: Scenario,
  packet: ConvertiblePacket,
  ratio: Result(decimal.Decimal, common.Error),
) -> json.Json {
  let payoff = case scenario.kind {
    "call" -> common.fact_decimal("callPrice", packet.call_price)
    "put" -> common.fact_decimal("putPrice", packet.put_price)
    "hold" ->
      common.fact_decimal("maturityRedemption", packet.maturity_redemption)
    "convert" ->
      case
        ratio,
        common.fact_decimal(
          "scenario.underlyingPrice",
          scenario.underlying_price,
        )
      {
        Ok(ratio), Ok(price) -> Ok(decimal.multiply(ratio, price))
        Error(error), _ -> Error(error)
        _, Error(error) -> Error(error)
      }
    _ -> Error(common.CalculationUnperformed("unsupported scenario"))
  }
  json.object([
    #("scenarioId", json.string(scenario.id)),
    #("kind", json.string(scenario.kind)),
    #("receipt", json.string(scenario.receipt)),
    #(
      "payoff",
      common.calculation_json(
        "caller_declared_scenario_payoff",
        payoff,
        "CNY_per_bond",
        [
          #("underlyingPrice", common.fact_json(scenario.underlying_price)),
          #("callPrice", common.fact_json(packet.call_price)),
          #("putPrice", common.fact_json(packet.put_price)),
          #("maturityRedemption", common.fact_json(packet.maturity_redemption)),
        ],
      ),
    ),
  ])
}

fn convertible_identity_json(identity: ConvertibleIdentity) -> json.Json {
  json.object([
    #("instrumentId", json.string(identity.instrument_id)),
    #("issuerId", json.string(identity.issuer_id)),
    #("underlyingListingId", json.string(identity.underlying_listing_id)),
    #("underlyingMic", json.string(identity.underlying_mic)),
    #("track", json.string("cn")),
    #("currency", json.string(identity.currency)),
    #("issueDate", json.string(identity.issue_date)),
    #("maturityDate", json.string(identity.maturity_date)),
    #("termsVersion", json.string(identity.terms_version)),
    #("termsReceipt", json.string(identity.terms_receipt)),
  ])
}

pub type MacroObservation {
  MacroObservation(
    period: String,
    raw_value: String,
    publication_unix_ms: Int,
    vintage_unix_ms: Int,
    revision: String,
    receipt: String,
  )
}

pub type MacroPacket {
  MacroPacket(
    source: common.Source,
    publisher: String,
    series_id: String,
    title_cn: String,
    geography: String,
    unit: String,
    scale: String,
    frequency: String,
    seasonal_adjustment: String,
    current_period: String,
    previous_period: String,
    knowledge_cutoff_unix_ms: Int,
    observations: List(MacroObservation),
  )
}

pub fn macro_series(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "cn_macro_v1",
    "analyze",
    macro_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate_macro(packet))
  let current =
    latest_vintage(
      packet.observations,
      packet.current_period,
      packet.knowledge_cutoff_unix_ms,
    )
  let previous =
    latest_vintage(
      packet.observations,
      packet.previous_period,
      packet.knowledge_cutoff_unix_ms,
    )
  let change = case current, previous {
    Some(current), Some(previous) ->
      case decimal.parse(current.raw_value), decimal.parse(previous.raw_value) {
        Ok(current), Ok(previous) ->
          common.percentage(decimal.subtract(current, previous), previous, 6)
        _, _ ->
          Error(common.CalculationUnperformed(
            "selected vintage has a non-numeric source lexeme",
          ))
      }
    None, _ ->
      Error(common.CalculationUnperformed(
        "current period not released by cutoff",
      ))
    _, None ->
      Error(common.CalculationUnperformed(
        "previous period not released by cutoff",
      ))
  }
  Ok(
    common.response(
      "cn_macro_v1",
      "analyze",
      decoded.1,
      "Exact official CN macro vintages selected at a caller knowledge cutoff; no latest-wins substitution, regime label, forecast, or advice",
      [
        #("source", common.source_json(packet.source)),
        #("track", json.null()),
        #(
          "series",
          json.object([
            #("publisher", json.string(packet.publisher)),
            #("seriesId", json.string(packet.series_id)),
            #("titleCn", json.string(packet.title_cn)),
            #("geography", json.string(packet.geography)),
            #("unit", json.string(packet.unit)),
            #("scale", json.string(packet.scale)),
            #("frequency", json.string(packet.frequency)),
            #("seasonalAdjustment", json.string(packet.seasonal_adjustment)),
          ]),
        ),
        #(
          "knowledgeCutoffUnixMilliseconds",
          json.int(packet.knowledge_cutoff_unix_ms),
        ),
        #("selectedCurrent", option_macro_json(current)),
        #("selectedPrevious", option_macro_json(previous)),
        #(
          "periodChangePercent",
          common.calculation_json(
            "(current_vintage - previous_vintage) / previous_vintage * 100",
            change,
            "percent",
            [
              #("currentPeriod", json.string(packet.current_period)),
              #("previousPeriod", json.string(packet.previous_period)),
            ],
          ),
        ),
        #(
          "allVintages",
          json.array(packet.observations, macro_observation_json),
        ),
      ],
    ),
  )
}

fn macro_decoder() -> decode.Decoder(MacroPacket) {
  use source <- decode.field("source", common.source_decoder())
  use publisher <- decode.field("publisher", decode.string)
  use series_id <- decode.field("seriesId", decode.string)
  use title <- decode.field("titleCn", decode.string)
  use geography <- decode.field("geography", decode.string)
  use unit <- decode.field("unit", decode.string)
  use scale <- decode.field("scale", decode.string)
  use frequency <- decode.field("frequency", decode.string)
  use seasonal <- decode.field("seasonalAdjustment", decode.string)
  use current <- decode.field("currentPeriod", decode.string)
  use previous <- decode.field("previousPeriod", decode.string)
  use cutoff <- decode.field("knowledgeCutoffUnixMilliseconds", decode.int)
  use observations <- decode.field(
    "observations",
    decode.list(of: macro_observation_decoder()),
  )
  decode.success(MacroPacket(
    source,
    publisher,
    series_id,
    title,
    geography,
    unit,
    scale,
    frequency,
    seasonal,
    current,
    previous,
    cutoff,
    observations,
  ))
}

fn macro_observation_decoder() -> decode.Decoder(MacroObservation) {
  use period <- decode.field("period", decode.string)
  use raw <- decode.field("rawValue", decode.string)
  use publication <- decode.field("publicationUnixMilliseconds", decode.int)
  use vintage <- decode.field("vintageUnixMilliseconds", decode.int)
  use revision <- decode.field("revision", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(MacroObservation(
    period,
    raw,
    publication,
    vintage,
    revision,
    receipt,
  ))
}

fn validate_macro(packet: MacroPacket) -> Result(Nil, common.Error) {
  use _ <- result.try(
    common.one_of("publisher", packet.publisher, [
      "NBS",
      "PBOC",
      "SAFE",
      "StateCouncil",
    ]),
  )
  use _ <- result.try(common.non_empty("seriesId", packet.series_id))
  use _ <- result.try(common.non_empty("titleCn", packet.title_cn))
  use _ <- result.try(common.one_of("geography", packet.geography, ["CN"]))
  use _ <- result.try(common.non_empty("unit", packet.unit))
  use _ <- result.try(common.non_empty("scale", packet.scale))
  use _ <- result.try(
    common.one_of("frequency", packet.frequency, [
      "annual",
      "quarterly",
      "monthly",
      "weekly",
      "daily",
    ]),
  )
  use _ <- result.try(common.non_empty(
    "seasonalAdjustment",
    packet.seasonal_adjustment,
  ))
  use _ <- result.try(common.non_empty("currentPeriod", packet.current_period))
  use _ <- result.try(common.non_empty("previousPeriod", packet.previous_period))
  use _ <- result.try(common.non_negative(
    "knowledgeCutoffUnixMilliseconds",
    packet.knowledge_cutoff_unix_ms,
  ))
  case packet.observations {
    [] -> Error(common.InvalidField("observations", "must not be empty"))
    observations ->
      case list.length(observations) > 500 {
        True ->
          Error(common.BudgetExceeded(
            "observations",
            list.length(observations),
            500,
          ))
        False ->
          observations
          |> list.try_map(fn(observation) {
            use _ <- result.try(common.non_empty(
              "observation.period",
              observation.period,
            ))
            use _ <- result.try(common.non_empty(
              "observation.rawValue",
              observation.raw_value,
            ))
            use _ <- result.try(common.non_negative(
              "observation.publicationUnixMilliseconds",
              observation.publication_unix_ms,
            ))
            use _ <- result.try(common.non_negative(
              "observation.vintageUnixMilliseconds",
              observation.vintage_unix_ms,
            ))
            common.receipt("observation.receipt", observation.receipt)
          })
          |> result.map(fn(_) { Nil })
      }
  }
}

fn latest_vintage(
  observations: List(MacroObservation),
  period: String,
  cutoff: Int,
) -> Option(MacroObservation) {
  observations
  |> list.filter(fn(value) {
    value.period == period && value.vintage_unix_ms <= cutoff
  })
  |> list.fold(
    None,
    fn(selected: Option(MacroObservation), candidate: MacroObservation) {
      case selected {
        None -> Some(candidate)
        Some(current) if candidate.vintage_unix_ms > current.vintage_unix_ms ->
          Some(candidate)
        Some(current) -> Some(current)
      }
    },
  )
}

fn option_macro_json(value: Option(MacroObservation)) -> json.Json {
  case value {
    Some(observation) -> macro_observation_json(observation)
    None ->
      json.object([
        #("state", json.string("unavailable")),
        #("reason", json.string("not_released_by_knowledge_cutoff")),
      ])
  }
}

fn macro_observation_json(value: MacroObservation) -> json.Json {
  json.object([
    #("period", json.string(value.period)),
    #("rawValue", json.string(value.raw_value)),
    #("publicationUnixMilliseconds", json.int(value.publication_unix_ms)),
    #("vintageUnixMilliseconds", json.int(value.vintage_unix_ms)),
    #("revision", json.string(value.revision)),
    #("receipt", json.string(value.receipt)),
  ])
}

pub type PolicyDocument {
  PolicyDocument(
    document_id: String,
    publisher: String,
    authority_role: String,
    title_cn: String,
    language: String,
    document_type: String,
    document_number: String,
    publication_date: String,
    effective_date: Option(String),
    jurisdiction_scope: String,
    market_scope: String,
    status: String,
    correction_lineage: List(String),
    source_url: String,
    receipt: String,
  )
}

pub type PolicyPacket {
  PolicyPacket(source: common.Source, documents: List(PolicyDocument))
}

pub fn policy_documents(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "cn_policy_monitor_v1",
    "inspect",
    policy_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate_policy_documents(packet.documents))
  Ok(
    common.response(
      "cn_policy_monitor_v1",
      "inspect",
      decoded.1,
      "Exact original-language CN policy document metadata; no interpretation, affected-company inference, impact score, notification, or advice",
      [
        #("source", common.source_json(packet.source)),
        #("track", json.null()),
        #("documentCount", json.int(list.length(packet.documents))),
        #("documents", json.array(packet.documents, policy_document_json)),
        #(
          "coverageLimitation",
          json.string(
            "source coverage is controlling; silence is not proof of no policy publication",
          ),
        ),
      ],
    ),
  )
}

fn policy_decoder() -> decode.Decoder(PolicyPacket) {
  use source <- decode.field("source", common.source_decoder())
  use documents <- decode.field(
    "documents",
    decode.list(of: policy_document_decoder()),
  )
  decode.success(PolicyPacket(source, documents))
}

fn policy_document_decoder() -> decode.Decoder(PolicyDocument) {
  use id <- decode.field("documentId", decode.string)
  use publisher <- decode.field("publisher", decode.string)
  use role <- decode.field("authorityRole", decode.string)
  use title <- decode.field("titleCn", decode.string)
  use language <- decode.field("language", decode.string)
  use kind <- decode.field("documentType", decode.string)
  use number <- decode.field("documentNumber", decode.string)
  use publication <- decode.field("publicationDate", decode.string)
  use effective <- decode.optional_field(
    "effectiveDate",
    None,
    decode.optional(decode.string),
  )
  use jurisdiction <- decode.field("jurisdictionScope", decode.string)
  use market <- decode.field("marketScope", decode.string)
  use status <- decode.field("status", decode.string)
  use corrections <- decode.field(
    "correctionLineage",
    decode.list(of: decode.string),
  )
  use url <- decode.field("sourceUrl", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(PolicyDocument(
    id,
    publisher,
    role,
    title,
    language,
    kind,
    number,
    publication,
    effective,
    jurisdiction,
    market,
    status,
    corrections,
    url,
    receipt,
  ))
}

fn validate_policy_documents(
  documents: List(PolicyDocument),
) -> Result(Nil, common.Error) {
  case documents {
    [] -> Error(common.InvalidField("documents", "must not be empty"))
    _ ->
      case list.length(documents) > 200 {
        True ->
          Error(common.BudgetExceeded("documents", list.length(documents), 200))
        False ->
          documents
          |> list.try_map(fn(document) {
            use _ <- result.try(common.non_empty(
              "document.documentId",
              document.document_id,
            ))
            use _ <- result.try(
              common.one_of("document.publisher", document.publisher, [
                "CSRC",
                "SSE",
                "SZSE",
                "BSE",
                "PBOC",
                "NBS",
                "StateCouncil",
              ]),
            )
            use _ <- result.try(common.non_empty(
              "document.authorityRole",
              document.authority_role,
            ))
            use _ <- result.try(common.non_empty(
              "document.titleCn",
              document.title_cn,
            ))
            use _ <- result.try(
              common.one_of("document.language", document.language, ["zh-CN"]),
            )
            use _ <- result.try(
              common.one_of("document.documentType", document.document_type, [
                "rule",
                "notice",
                "guideline",
                "consultation",
                "enforcement",
              ]),
            )
            use _ <- result.try(common.date(
              "document.publicationDate",
              document.publication_date,
            ))
            use _ <- result.try(case document.effective_date {
              Some(value) -> common.date("document.effectiveDate", value)
              None -> Ok(Nil)
            })
            use _ <- result.try(common.non_empty(
              "document.jurisdictionScope",
              document.jurisdiction_scope,
            ))
            use _ <- result.try(common.non_empty(
              "document.marketScope",
              document.market_scope,
            ))
            use _ <- result.try(
              common.one_of("document.status", document.status, [
                "draft",
                "final",
                "amended",
                "repealed",
              ]),
            )
            use _ <- result.try(common.non_empty(
              "document.sourceUrl",
              document.source_url,
            ))
            use _ <- result.try(common.receipt(
              "document.receipt",
              document.receipt,
            ))
            common.validate_receipts(
              "document.correctionLineage",
              document.correction_lineage,
            )
          })
          |> result.map(fn(_) { Nil })
      }
  }
}

fn policy_document_json(document: PolicyDocument) -> json.Json {
  json.object([
    #("documentId", json.string(document.document_id)),
    #("publisher", json.string(document.publisher)),
    #("authorityRole", json.string(document.authority_role)),
    #("titleCn", json.string(document.title_cn)),
    #("language", json.string(document.language)),
    #("documentType", json.string(document.document_type)),
    #("documentNumber", json.string(document.document_number)),
    #("publicationDate", json.string(document.publication_date)),
    #("effectiveDate", common.option_string_json(document.effective_date)),
    #("jurisdictionScope", json.string(document.jurisdiction_scope)),
    #("marketScope", json.string(document.market_scope)),
    #("status", json.string(document.status)),
    #("correctionLineage", json.array(document.correction_lineage, json.string)),
    #("sourceUrl", json.string(document.source_url)),
    #("receipt", json.string(document.receipt)),
  ])
}
