import finance_core/decimal
import finance_math/statistics
import finance_multi_asset/common
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result

pub type Contract {
  Contract(
    contract_id: String,
    product_code: String,
    exchange: String,
    delivery_month: String,
    delivery_ordinal: Int,
    contract_size: String,
    size_unit: String,
    multiplier: String,
    quotation_unit: String,
    tick_size: String,
    tick_value: String,
    currency: String,
    settlement_type: String,
    last_trade_date: String,
    first_notice_date: String,
    specification_version: String,
    specification_receipt: String,
    settle: common.Fact,
    volume: common.Fact,
    open_interest: common.Fact,
    observation_receipt: String,
  )
}

pub type RollEvent {
  RollEvent(
    roll_date: String,
    from_contract_id: String,
    to_contract_id: String,
    from_settle: common.Fact,
    to_settle: common.Fact,
    weighting: String,
    receipt: String,
  )
}

pub type CommodityPacket {
  CommodityPacket(
    source: common.Source,
    as_of_date: String,
    session_type: String,
    calendar_receipt: String,
    contracts: List(Contract),
    near_contract_id: String,
    far_contract_id: String,
    inter_a_id: String,
    inter_b_id: String,
    roll_method: String,
    roll_parameters: String,
    roll_events: List(RollEvent),
  )
}

pub fn commodities(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "commodities_v1",
    "analyze",
    commodity_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate_commodity_packet(packet))
  let near = find_contract(packet.contracts, packet.near_contract_id)
  let far = find_contract(packet.contracts, packet.far_contract_id)
  let calendar_spread = case near, far {
    Some(near), Some(far) ->
      case
        near.product_code == far.product_code,
        near.exchange == far.exchange,
        common.fact_decimal("near.settle", near.settle),
        common.fact_decimal("far.settle", far.settle)
      {
        True, True, Ok(near_settle), Ok(far_settle) ->
          Ok(decimal.subtract(near_settle, far_settle))
        False, _, _, _ ->
          Error(common.CalculationUnperformed(
            "calendar spread requires the same product code",
          ))
        _, False, _, _ ->
          Error(common.CalculationUnperformed(
            "calendar spread requires the same exchange",
          ))
        _, _, Error(error), _ -> Error(error)
        _, _, _, Error(error) -> Error(error)
      }
    _, _ ->
      Error(common.CalculationUnperformed("calendar-spread leg not found"))
  }
  let inter_a = find_contract(packet.contracts, packet.inter_a_id)
  let inter_b = find_contract(packet.contracts, packet.inter_b_id)
  let inter_spread = case inter_a, inter_b {
    Some(left), Some(right) ->
      case
        left.currency == right.currency,
        common.fact_decimal("interA.settle", left.settle),
        decimal.parse(left.multiplier),
        common.fact_decimal("interB.settle", right.settle),
        decimal.parse(right.multiplier)
      {
        True,
          Ok(left_settle),
          Ok(left_multiplier),
          Ok(right_settle),
          Ok(right_multiplier)
        ->
          Ok(decimal.subtract(
            decimal.multiply(left_settle, left_multiplier),
            decimal.multiply(right_settle, right_multiplier),
          ))
        False, _, _, _, _ ->
          Error(common.CalculationUnperformed(
            "inter-commodity currencies differ and no FX receipt was supplied",
          ))
        _, Error(error), _, _, _ -> Error(error)
        _, _, Error(_), _, _ ->
          Error(common.InvalidField("interA.multiplier", "must be decimal"))
        _, _, _, Error(error), _ -> Error(error)
        _, _, _, _, Error(_) ->
          Error(common.InvalidField("interB.multiplier", "must be decimal"))
      }
    _, _ ->
      Error(common.CalculationUnperformed("inter-commodity leg not found"))
  }
  Ok(
    common.response(
      "commodities_v1",
      "analyze",
      decoded.1,
      "Exact X-CBT futures identities, as-of curve, caller-selected spreads and explicit roll artifact; no anonymous continuous contract, structure label, storage inference, forecast, or roll recommendation",
      [
        #("source", common.source_json(packet.source)),
        #("track", json.null()),
        #("asOfDate", json.string(packet.as_of_date)),
        #("sessionType", json.string(packet.session_type)),
        #("calendarReceipt", json.string(packet.calendar_receipt)),
        #("curve", json.array(packet.contracts, contract_json)),
        #(
          "calendarSpread",
          common.calculation_json(
            "near_settle - far_settle",
            calendar_spread,
            "native_quotation_unit",
            [
              #("nearContractId", json.string(packet.near_contract_id)),
              #("farContractId", json.string(packet.far_contract_id)),
            ],
          ),
        ),
        #(
          "interCommoditySpread",
          common.calculation_json(
            "settle_a * multiplier_a - settle_b * multiplier_b",
            inter_spread,
            "native_currency_per_contract",
            [
              #("contractA", json.string(packet.inter_a_id)),
              #("contractB", json.string(packet.inter_b_id)),
            ],
          ),
        ),
        #(
          "rollArtifact",
          json.object([
            #("method", json.string(packet.roll_method)),
            #("parameters", json.string(packet.roll_parameters)),
            #("events", json.array(packet.roll_events, roll_event_json)),
            #(
              "continuousSeriesKind",
              json.string("calculated_rolled_series_not_source_contract"),
            ),
          ]),
        ),
      ],
    ),
  )
}

fn commodity_decoder() -> decode.Decoder(CommodityPacket) {
  use source <- decode.field("source", common.source_decoder())
  use as_of <- decode.field("asOfDate", decode.string)
  use session <- decode.field("sessionType", decode.string)
  use calendar <- decode.field("calendarReceipt", decode.string)
  use contracts <- decode.field(
    "contracts",
    decode.list(of: contract_decoder()),
  )
  use near <- decode.field("nearContractId", decode.string)
  use far <- decode.field("farContractId", decode.string)
  use inter_a <- decode.field("interCommodityContractA", decode.string)
  use inter_b <- decode.field("interCommodityContractB", decode.string)
  use method <- decode.field("rollMethod", decode.string)
  use parameters <- decode.field("rollParameters", decode.string)
  use events <- decode.field(
    "rollEvents",
    decode.list(of: roll_event_decoder()),
  )
  decode.success(CommodityPacket(
    source,
    as_of,
    session,
    calendar,
    contracts,
    near,
    far,
    inter_a,
    inter_b,
    method,
    parameters,
    events,
  ))
}

fn contract_decoder() -> decode.Decoder(Contract) {
  use id <- decode.field("contractId", decode.string)
  use product <- decode.field("productCode", decode.string)
  use exchange <- decode.field("exchange", decode.string)
  use month <- decode.field("deliveryMonth", decode.string)
  use ordinal <- decode.field("deliveryOrdinal", decode.int)
  use size <- decode.field("contractSize", decode.string)
  use size_unit <- decode.field("sizeUnit", decode.string)
  use multiplier <- decode.field("multiplier", decode.string)
  use quotation <- decode.field("quotationUnit", decode.string)
  use tick_size <- decode.field("tickSize", decode.string)
  use tick_value <- decode.field("tickValue", decode.string)
  use currency <- decode.field("currency", decode.string)
  use settlement <- decode.field("settlementType", decode.string)
  use last_trade <- decode.field("lastTradeDate", decode.string)
  use first_notice <- decode.field("firstNoticeDate", decode.string)
  use version <- decode.field("specificationVersion", decode.string)
  use spec_receipt <- decode.field("specificationReceipt", decode.string)
  use settle <- decode.field("settle", common.fact_decoder())
  use volume <- decode.field("volume", common.fact_decoder())
  use open_interest <- decode.field("openInterest", common.fact_decoder())
  use observation_receipt <- decode.field("observationReceipt", decode.string)
  decode.success(Contract(
    id,
    product,
    exchange,
    month,
    ordinal,
    size,
    size_unit,
    multiplier,
    quotation,
    tick_size,
    tick_value,
    currency,
    settlement,
    last_trade,
    first_notice,
    version,
    spec_receipt,
    settle,
    volume,
    open_interest,
    observation_receipt,
  ))
}

fn roll_event_decoder() -> decode.Decoder(RollEvent) {
  use date <- decode.field("rollDate", decode.string)
  use from <- decode.field("fromContractId", decode.string)
  use to <- decode.field("toContractId", decode.string)
  use from_settle <- decode.field("fromSettle", common.fact_decoder())
  use to_settle <- decode.field("toSettle", common.fact_decoder())
  use weighting <- decode.field("weighting", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(RollEvent(
    date,
    from,
    to,
    from_settle,
    to_settle,
    weighting,
    receipt,
  ))
}

fn validate_commodity_packet(
  packet: CommodityPacket,
) -> Result(Nil, common.Error) {
  use _ <- result.try(common.date("asOfDate", packet.as_of_date))
  use _ <- result.try(common.non_empty("sessionType", packet.session_type))
  use _ <- result.try(common.receipt("calendarReceipt", packet.calendar_receipt))
  use _ <- result.try(case packet.contracts {
    [_, _, ..] -> Ok(Nil)
    _ ->
      Error(common.InvalidField("contracts", "requires at least two contracts"))
  })
  use _ <- result.try(case list.length(packet.contracts) <= 100 {
    True -> Ok(Nil)
    False ->
      Error(common.BudgetExceeded(
        "contracts",
        list.length(packet.contracts),
        100,
      ))
  })
  use _ <- result.try(validate_contracts(packet.contracts, -1, []))
  use _ <- result.try(common.non_empty(
    "nearContractId",
    packet.near_contract_id,
  ))
  use _ <- result.try(common.non_empty("farContractId", packet.far_contract_id))
  use _ <- result.try(common.non_empty(
    "interCommodityContractA",
    packet.inter_a_id,
  ))
  use _ <- result.try(common.non_empty(
    "interCommodityContractB",
    packet.inter_b_id,
  ))
  use _ <- result.try(
    common.one_of("rollMethod", packet.roll_method, [
      "roll_calendar_v1",
      "roll_volume_v1",
      "roll_open_interest_v1",
      "roll_fixed_date_v1",
      "roll_percentage_v1",
    ]),
  )
  use _ <- result.try(common.non_empty("rollParameters", packet.roll_parameters))
  packet.roll_events
  |> list.try_map(fn(event) {
    use _ <- result.try(common.date("rollEvent.rollDate", event.roll_date))
    use _ <- result.try(common.non_empty(
      "rollEvent.fromContractId",
      event.from_contract_id,
    ))
    use _ <- result.try(common.non_empty(
      "rollEvent.toContractId",
      event.to_contract_id,
    ))
    use _ <- result.try(common.validate_fact(
      "rollEvent.fromSettle",
      event.from_settle,
    ))
    use _ <- result.try(common.validate_fact(
      "rollEvent.toSettle",
      event.to_settle,
    ))
    use _ <- result.try(common.non_empty("rollEvent.weighting", event.weighting))
    common.receipt("rollEvent.receipt", event.receipt)
  })
  |> result.map(fn(_) { Nil })
}

fn validate_contracts(
  contracts: List(Contract),
  prior_ordinal: Int,
  ids: List(String),
) -> Result(Nil, common.Error) {
  case contracts {
    [] -> Ok(Nil)
    [contract, ..rest] -> {
      use _ <- result.try(common.non_empty(
        "contract.contractId",
        contract.contract_id,
      ))
      use _ <- result.try(case list.contains(ids, contract.contract_id) {
        True ->
          Error(common.InvalidField("contract.contractId", "must be unique"))
        False -> Ok(Nil)
      })
      use _ <- result.try(common.non_empty(
        "contract.productCode",
        contract.product_code,
      ))
      use _ <- result.try(
        common.one_of("contract.exchange", contract.exchange, ["XCBT"]),
      )
      use _ <- result.try(common.non_empty(
        "contract.deliveryMonth",
        contract.delivery_month,
      ))
      use _ <- result.try(case contract.delivery_ordinal > prior_ordinal {
        True -> Ok(Nil)
        False ->
          Error(common.InvalidField(
            "contract.deliveryOrdinal",
            "curve must be strictly ordered by delivery",
          ))
      })
      use _ <- result.try(decimal_field(
        "contract.contractSize",
        contract.contract_size,
      ))
      use _ <- result.try(common.non_empty(
        "contract.sizeUnit",
        contract.size_unit,
      ))
      use _ <- result.try(decimal_field(
        "contract.multiplier",
        contract.multiplier,
      ))
      use _ <- result.try(common.non_empty(
        "contract.quotationUnit",
        contract.quotation_unit,
      ))
      use _ <- result.try(decimal_field("contract.tickSize", contract.tick_size))
      use _ <- result.try(decimal_field(
        "contract.tickValue",
        contract.tick_value,
      ))
      use _ <- result.try(common.non_empty(
        "contract.currency",
        contract.currency,
      ))
      use _ <- result.try(
        common.one_of("contract.settlementType", contract.settlement_type, [
          "physical",
          "cash",
        ]),
      )
      use _ <- result.try(common.date(
        "contract.lastTradeDate",
        contract.last_trade_date,
      ))
      use _ <- result.try(common.date(
        "contract.firstNoticeDate",
        contract.first_notice_date,
      ))
      use _ <- result.try(common.non_empty(
        "contract.specificationVersion",
        contract.specification_version,
      ))
      use _ <- result.try(common.receipt(
        "contract.specificationReceipt",
        contract.specification_receipt,
      ))
      use _ <- result.try(common.validate_fact(
        "contract.settle",
        contract.settle,
      ))
      use _ <- result.try(common.validate_fact(
        "contract.volume",
        contract.volume,
      ))
      use _ <- result.try(common.validate_fact(
        "contract.openInterest",
        contract.open_interest,
      ))
      use _ <- result.try(common.receipt(
        "contract.observationReceipt",
        contract.observation_receipt,
      ))
      validate_contracts(rest, contract.delivery_ordinal, [
        contract.contract_id,
        ..ids
      ])
    }
  }
}

fn decimal_field(field: String, value: String) -> Result(Nil, common.Error) {
  case decimal.parse(value) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(common.InvalidField(field, "must be an exact decimal"))
  }
}

fn find_contract(contracts: List(Contract), id: String) -> Option(Contract) {
  list.find(contracts, fn(contract) { contract.contract_id == id })
  |> result.map(Some)
  |> result.unwrap(None)
}

fn contract_json(contract: Contract) -> json.Json {
  json.object([
    #("contractId", json.string(contract.contract_id)),
    #("productCode", json.string(contract.product_code)),
    #("exchange", json.string(contract.exchange)),
    #("deliveryMonth", json.string(contract.delivery_month)),
    #("contractSize", json.string(contract.contract_size)),
    #("sizeUnit", json.string(contract.size_unit)),
    #("multiplier", json.string(contract.multiplier)),
    #("quotationUnit", json.string(contract.quotation_unit)),
    #("tickSize", json.string(contract.tick_size)),
    #("tickValue", json.string(contract.tick_value)),
    #("currency", json.string(contract.currency)),
    #("settlementType", json.string(contract.settlement_type)),
    #("lastTradeDate", json.string(contract.last_trade_date)),
    #("firstNoticeDate", json.string(contract.first_notice_date)),
    #("specificationVersion", json.string(contract.specification_version)),
    #("specificationReceipt", json.string(contract.specification_receipt)),
    #("settle", common.fact_json(contract.settle)),
    #("volume", common.fact_json(contract.volume)),
    #("openInterest", common.fact_json(contract.open_interest)),
    #("observationReceipt", json.string(contract.observation_receipt)),
  ])
}

fn roll_event_json(event: RollEvent) -> json.Json {
  let gap = case
    common.fact_decimal("roll.fromSettle", event.from_settle),
    common.fact_decimal("roll.toSettle", event.to_settle)
  {
    Ok(from), Ok(to) -> Ok(decimal.subtract(from, to))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  json.object([
    #("rollDate", json.string(event.roll_date)),
    #("fromContractId", json.string(event.from_contract_id)),
    #("toContractId", json.string(event.to_contract_id)),
    #("weighting", json.string(event.weighting)),
    #("receipt", json.string(event.receipt)),
    #(
      "priceGapAtRoll",
      common.calculation_json(
        "from_settle - to_settle",
        gap,
        "native_quotation_unit",
        [
          #("fromSettle", common.fact_json(event.from_settle)),
          #("toSettle", common.fact_json(event.to_settle)),
        ],
      ),
    ),
  ])
}

pub type Category {
  Category(
    name: String,
    long_positions: common.Fact,
    short_positions: common.Fact,
    spreading_positions: common.Fact,
    prior_net: common.Fact,
  )
}

pub type HistoricalPoint {
  HistoricalPoint(report_date: String, net: common.Fact)
}

pub type CotPacket {
  CotPacket(
    source: common.Source,
    report_id: String,
    report_type: String,
    market_code: String,
    market_name: String,
    futures_only: Bool,
    report_date: String,
    release_date: String,
    report_lag_days: Int,
    taxonomy_version: String,
    revision: String,
    categories: List(Category),
    selected_category: String,
    historical_window: List(HistoricalPoint),
    crosswalk_state: String,
    known_contracts: List(String),
    report_receipt: String,
  )
}

pub fn cot(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "cftc_cot_v1",
    "analyze",
    cot_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate_cot(packet))
  let selected = find_category(packet.categories, packet.selected_category)
  let net = case selected {
    Some(category) -> category_net(category)
    None -> Error(common.CalculationUnperformed("selected category not found"))
  }
  let change = case selected, net {
    Some(category), Ok(current) ->
      case common.fact_decimal("category.priorNet", category.prior_net) {
        Ok(prior) -> Ok(decimal.subtract(current, prior))
        Error(error) -> Error(error)
      }
    _, Error(error) -> Error(error)
    _, _ -> Error(common.CalculationUnperformed("selected category not found"))
  }
  let net_percent = case selected {
    Some(category) ->
      case
        common.fact_decimal("category.long", category.long_positions),
        common.fact_decimal("category.short", category.short_positions),
        net
      {
        Ok(long), Ok(short), Ok(net) ->
          common.percentage(net, decimal.add(long, short), 6)
        Error(error), _, _ -> Error(error)
        _, Error(error), _ -> Error(error)
        _, _, Error(error) -> Error(error)
      }
    None -> Error(common.CalculationUnperformed("selected category not found"))
  }
  let history = history_values(packet.historical_window)
  let percentile = case history, net {
    Ok(values), Ok(current) -> percentile(values, current)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let z_score = case history, net {
    Ok(values), Ok(current) -> z_score(values, current)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  Ok(
    common.response(
      "cftc_cot_v1",
      "analyze",
      decoded.1,
      "Exact lagged CFTC report/category facts and caller-selected positioning calculations; no exact contract equivalence, intent inference, extreme label, signal, or recommendation",
      [
        #("source", common.source_json(packet.source)),
        #("track", json.null()),
        #(
          "report",
          json.object([
            #("reportId", json.string(packet.report_id)),
            #("reportType", json.string(packet.report_type)),
            #("marketCode", json.string(packet.market_code)),
            #("marketName", json.string(packet.market_name)),
            #("futuresOnly", json.bool(packet.futures_only)),
            #("reportDate", json.string(packet.report_date)),
            #("releaseDate", json.string(packet.release_date)),
            #("reportLagDays", json.int(packet.report_lag_days)),
            #("taxonomyVersion", json.string(packet.taxonomy_version)),
            #("revision", json.string(packet.revision)),
            #("receipt", json.string(packet.report_receipt)),
          ]),
        ),
        #("categories", json.array(packet.categories, category_json)),
        #("selectedCategory", json.string(packet.selected_category)),
        #(
          "calculations",
          json.object([
            #(
              "netPosition",
              common.calculation_json(
                "long_positions - short_positions",
                net,
                "contracts",
                [],
              ),
            ),
            #(
              "netChange",
              common.calculation_json(
                "current_net - prior_net",
                change,
                "contracts",
                [],
              ),
            ),
            #(
              "netPercent",
              common.calculation_json(
                "net / (long + short) * 100",
                net_percent,
                "percent",
                [],
              ),
            ),
            #(
              "percentile",
              float_result_json(
                "rank_le_current / valid_window_count * 100",
                percentile,
                "percentile_points",
              ),
            ),
            #(
              "zScore",
              float_result_json(
                "(current - population_mean) / population_standard_deviation",
                z_score,
                "standard_deviations",
              ),
            ),
          ]),
        ),
        #(
          "historicalWindow",
          json.array(packet.historical_window, historical_json),
        ),
        #(
          "crosswalk",
          json.object([
            #("state", json.string(packet.crosswalk_state)),
            #("knownContracts", json.array(packet.known_contracts, json.string)),
            #(
              "limitation",
              json.string(
                "CFTC market reports aggregate markets and do not prove contract-month positions",
              ),
            ),
          ]),
        ),
      ],
    ),
  )
}

fn cot_decoder() -> decode.Decoder(CotPacket) {
  use source <- decode.field("source", common.source_decoder())
  use id <- decode.field("reportId", decode.string)
  use kind <- decode.field("reportType", decode.string)
  use code <- decode.field("marketCode", decode.string)
  use name <- decode.field("marketName", decode.string)
  use futures_only <- decode.field("futuresOnly", decode.bool)
  use report_date <- decode.field("reportDate", decode.string)
  use release_date <- decode.field("releaseDate", decode.string)
  use lag <- decode.field("reportLagDays", decode.int)
  use taxonomy <- decode.field("taxonomyVersion", decode.string)
  use revision <- decode.field("revision", decode.string)
  use categories <- decode.field(
    "categories",
    decode.list(of: category_decoder()),
  )
  use selected <- decode.field("selectedCategory", decode.string)
  use history <- decode.field(
    "historicalWindow",
    decode.list(of: historical_decoder()),
  )
  use crosswalk <- decode.field("crosswalkState", decode.string)
  use contracts <- decode.field(
    "knownContracts",
    decode.list(of: decode.string),
  )
  use receipt <- decode.field("reportReceipt", decode.string)
  decode.success(CotPacket(
    source,
    id,
    kind,
    code,
    name,
    futures_only,
    report_date,
    release_date,
    lag,
    taxonomy,
    revision,
    categories,
    selected,
    history,
    crosswalk,
    contracts,
    receipt,
  ))
}

fn category_decoder() -> decode.Decoder(Category) {
  use name <- decode.field("name", decode.string)
  use long <- decode.field("long", common.fact_decoder())
  use short <- decode.field("short", common.fact_decoder())
  use spreading <- decode.field("spreading", common.fact_decoder())
  use prior <- decode.field("priorNet", common.fact_decoder())
  decode.success(Category(name, long, short, spreading, prior))
}

fn historical_decoder() -> decode.Decoder(HistoricalPoint) {
  use date <- decode.field("reportDate", decode.string)
  use net <- decode.field("net", common.fact_decoder())
  decode.success(HistoricalPoint(date, net))
}

fn validate_cot(packet: CotPacket) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty("reportId", packet.report_id))
  use _ <- result.try(
    common.one_of("reportType", packet.report_type, [
      "cftc_legacy",
      "cftc_disaggregated",
    ]),
  )
  use _ <- result.try(common.non_empty("marketCode", packet.market_code))
  use _ <- result.try(common.non_empty("marketName", packet.market_name))
  use _ <- result.try(common.date("reportDate", packet.report_date))
  use _ <- result.try(common.date("releaseDate", packet.release_date))
  use _ <- result.try(common.non_negative(
    "reportLagDays",
    packet.report_lag_days,
  ))
  use _ <- result.try(common.non_empty(
    "taxonomyVersion",
    packet.taxonomy_version,
  ))
  use _ <- result.try(common.non_empty("revision", packet.revision))
  use _ <- result.try(common.receipt("reportReceipt", packet.report_receipt))
  use _ <- result.try(case packet.categories {
    [] -> Error(common.InvalidField("categories", "must not be empty"))
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    packet.categories
    |> list.try_map(fn(category) {
      use _ <- result.try(common.non_empty("category.name", category.name))
      use _ <- result.try(common.validate_fact(
        "category.long",
        category.long_positions,
      ))
      use _ <- result.try(common.validate_fact(
        "category.short",
        category.short_positions,
      ))
      use _ <- result.try(common.validate_fact(
        "category.spreading",
        category.spreading_positions,
      ))
      common.validate_fact("category.priorNet", category.prior_net)
    })
    |> result.map(fn(_) { Nil }),
  )
  use _ <- result.try(case packet.historical_window {
    [_, _, ..] -> Ok(Nil)
    _ ->
      Error(common.InvalidField(
        "historicalWindow",
        "requires at least two reports",
      ))
  })
  use _ <- result.try(
    packet.historical_window
    |> list.try_map(fn(point) {
      use _ <- result.try(common.date(
        "historical.reportDate",
        point.report_date,
      ))
      common.validate_fact("historical.net", point.net)
    })
    |> result.map(fn(_) { Nil }),
  )
  use _ <- result.try(
    common.one_of("crosswalkState", packet.crosswalk_state, [
      "exact",
      "probable",
      "multiple",
      "unknown",
    ]),
  )
  common.non_empty("selectedCategory", packet.selected_category)
}

fn find_category(categories: List(Category), name: String) -> Option(Category) {
  list.find(categories, fn(category) { category.name == name })
  |> result.map(Some)
  |> result.unwrap(None)
}

fn category_net(category: Category) -> Result(decimal.Decimal, common.Error) {
  case
    common.fact_decimal("category.long", category.long_positions),
    common.fact_decimal("category.short", category.short_positions)
  {
    Ok(long), Ok(short) -> Ok(decimal.subtract(long, short))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
}

fn history_values(
  points: List(HistoricalPoint),
) -> Result(List(decimal.Decimal), common.Error) {
  points
  |> list.try_map(fn(point) { common.fact_decimal("historical.net", point.net) })
}

fn percentile(
  values: List(decimal.Decimal),
  current: decimal.Decimal,
) -> Result(Float, common.Error) {
  let rank =
    values
    |> list.filter(fn(value) {
      case decimal.compare(value, current) {
        Lt | Eq -> True
        Gt -> False
      }
    })
    |> list.length
  Ok(int.to_float(rank) /. int.to_float(list.length(values)) *. 100.0)
}

fn z_score(
  values: List(decimal.Decimal),
  current: decimal.Decimal,
) -> Result(Float, common.Error) {
  use floats <- result.try(
    values
    |> list.try_map(fn(value) {
      common.decimal_float(value)
      |> result.map_error(fn(_) {
        common.CalculationUnperformed("historical value outside float range")
      })
    }),
  )
  use current <- result.try(
    common.decimal_float(current)
    |> result.map_error(fn(_) {
      common.CalculationUnperformed("current value outside float range")
    }),
  )
  use mean <- result.try(
    statistics.mean(floats)
    |> result.map_error(fn(_) {
      common.CalculationUnperformed("historical mean unavailable")
    }),
  )
  use deviation <- result.try(
    statistics.standard_deviation(floats, statistics.Population)
    |> result.map_error(fn(_) {
      common.CalculationUnperformed("historical standard deviation unavailable")
    }),
  )
  case deviation == 0.0 {
    True -> Error(common.CalculationUnperformed("historical variance is zero"))
    False -> Ok({ current -. mean } /. deviation)
  }
}

fn category_json(category: Category) -> json.Json {
  json.object([
    #("name", json.string(category.name)),
    #("long", common.fact_json(category.long_positions)),
    #("short", common.fact_json(category.short_positions)),
    #("spreading", common.fact_json(category.spreading_positions)),
    #("priorNet", common.fact_json(category.prior_net)),
  ])
}

fn historical_json(point: HistoricalPoint) -> json.Json {
  json.object([
    #("reportDate", json.string(point.report_date)),
    #("net", common.fact_json(point.net)),
  ])
}

fn float_result_json(
  formula: String,
  value: Result(Float, common.Error),
  unit: String,
) -> json.Json {
  case value {
    Ok(number) ->
      json.object([
        #("state", json.string("calculated")),
        #("formula", json.string(formula)),
        #("value", json.string(float.to_string(number))),
        #("unit", json.string(unit)),
        #("windowPolicy", json.string("caller_supplied_valid_reports_only")),
      ])
    Error(error) ->
      json.object([
        #("state", json.string("unperformed")),
        #("formula", json.string(formula)),
        #("reason", json.string(common.error_message(error))),
        #("unit", json.string(unit)),
      ])
  }
}
