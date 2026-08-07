import finance_cn_rules/official as cn_rules
import finance_core/decimal
import finance_core/identifier
import finance_core/source
import finance_core/time.{type Date, type Instant}
import finance_execution/calculation as execution_calculation
import finance_execution/instruction
import finance_execution/receipt as execution_receipt
import finance_execution/request as execution_request
import finance_execution/simulation
import finance_hk_rules/official as hk_rules
import finance_indicators/model as indicator_model
import finance_indicators/receipt as indicator_receipt
import finance_listing/effective
import finance_listing/listing
import finance_market_alpaca/assets as alpaca_assets
import finance_market_alpaca/query as alpaca_query
import finance_ohlcv/acquisition_receipt
import finance_provenance/hash
import finance_provenance/identity.{type EvidenceId, type Sha256}
import finance_risk/bound
import finance_risk/calculation as risk_calculation
import finance_risk/receipt as risk_receipt
import finance_risk/request as risk_request
import finance_strategy/context_receipt
import finance_track.{type Track}
import finance_us_rules/official as us_rules
import gleam/bool
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}

type Spec {
  Spec(
    track: Track,
    symbol: String,
    mic: String,
    instrument_id: String,
    currency: String,
    timezone: String,
    provider: String,
    source_reference: String,
  )
}

type ReceiptCopy {
  ReceiptCopy(
    schema: String,
    payload: String,
    canonical_content_hash: Sha256,
    integrity: String,
  )
}

pub fn fixture_json() -> String {
  specs()
  |> list.map(fn(spec) { #(spec, market_receipt(spec)) })
  |> catalog_json
}

pub fn fixture_json_with_market_hashes(
  cn_market_hash: String,
  hk_market_hash: String,
  us_market_hash: String,
) -> String {
  let assert Ok(cn_hash) = identity.sha256(cn_market_hash)
  let assert Ok(hk_hash) = identity.sha256(hk_market_hash)
  let assert Ok(us_hash) = identity.sha256(us_market_hash)
  let assert [cn_spec, hk_spec, us_spec] = specs()
  catalog_json([
    #(cn_spec, bundled_market_receipt(cn_spec, cn_hash)),
    #(hk_spec, bundled_market_receipt(hk_spec, hk_hash)),
    #(us_spec, bundled_market_receipt(us_spec, us_hash)),
  ])
}

fn specs() -> List(Spec) {
  [
    Spec(
      finance_track.Cn,
      "600000",
      "XSHG",
      "fixture:cn:600000",
      "CNY",
      "Asia/Shanghai",
      "eastmoney",
      "https://push2his.eastmoney.com/api/qt/stock/kline/get",
    ),
    Spec(
      finance_track.Hk,
      "00700",
      "XHKG",
      "fixture:hk:00700",
      "HKD",
      "Asia/Hong_Kong",
      "eastmoney",
      "https://push2his.eastmoney.com/api/qt/stock/kline/get",
    ),
    Spec(
      finance_track.Us,
      "AAPL",
      "XNAS",
      "fixture:us:AAPL",
      "USD",
      "America/New_York",
      "alpaca",
      "https://data.alpaca.markets/v2/stocks/bars",
    ),
  ]
}

fn catalog_json(tracks: List(#(Spec, ReceiptCopy))) -> String {
  json.object([
    #("schema", json.string("pi-sparkles/swing-acceptance-receipts")),
    #("schemaVersion", json.int(1)),
    #(
      "tracks",
      json.object(
        list.map(tracks, fn(item) {
          let #(spec, market) = item
          #(finance_track.name(spec.track), track_json(spec, market))
        }),
      ),
    ),
  ])
  |> json.to_string
}

fn track_json(spec: Spec, market: ReceiptCopy) -> Json {
  let rule = rule_receipt(spec)
  let indicator = indicator_request_receipt(spec, market)
  let risk = risk_request_receipt(spec, market, indicator, rule)
  let execution = execution_request_receipt(spec, market, risk, rule)
  let sector_regime = sector_regime_receipt(spec, market)
  let catalyst = catalyst_receipt(spec)
  let universe_candidate = universe_candidate_receipt(spec)
  let task_time =
    task_time_receipt(
      spec,
      market,
      indicator,
      risk,
      rule,
      execution,
      sector_regime,
      catalyst,
      universe_candidate,
    )
  json.object([
    #("track", json.string(finance_track.name(spec.track))),
    #("symbol", json.string(spec.symbol)),
    #("mic", json.string(spec.mic)),
    #("instrumentId", json.string(spec.instrument_id)),
    #("currency", json.string(spec.currency)),
    #("timezone", json.string(spec.timezone)),
    #("market", receipt_json(market)),
    #("indicator", receipt_json(indicator)),
    #("risk", receipt_json(risk)),
    #("rule", receipt_json(rule)),
    #("execution", receipt_json(execution)),
    #("sectorRegime", receipt_json(sector_regime)),
    #("catalyst", receipt_json(catalyst)),
    #("taskTime", receipt_json(task_time)),
    #("universeCandidate", receipt_json(universe_candidate)),
  ])
}

fn sector_regime_receipt(spec: Spec, market: ReceiptCopy) -> ReceiptCopy {
  let sector_source_receipt =
    sha(finance_track.name(spec.track) <> ":sector-classification-source")
  let regime_source_receipt =
    sha(finance_track.name(spec.track) <> ":regime-classification-source")
  let assert Ok(sector) =
    context_receipt.classification(
      "acceptance-fixture-sector-v1",
      sector_label(spec.track),
      instant(1_786_092_000_000),
      instant(1_786_092_200_000),
      timezone(spec.timezone),
      fixture_source(
        "fixture://" <> finance_track.name(spec.track) <> "/sector",
      ),
      sector_source_receipt,
    )
  let assert Ok(regime) =
    context_receipt.classification(
      "acceptance-fixture-regime-v1",
      "source-declared-sideways",
      instant(1_786_092_000_000),
      instant(1_786_092_200_000),
      timezone(spec.timezone),
      fixture_source(
        "fixture://" <> finance_track.name(spec.track) <> "/regime",
      ),
      regime_source_receipt,
    )
  let assert Ok(value) =
    context_receipt.sector_regime_receipt(
      listing_key(spec),
      context_receipt.Known(sector),
      context_receipt.Known(regime),
      instant(1_786_092_300_000),
      [
        evidence_root(sector_source_receipt),
        evidence_root(regime_source_receipt),
        evidence_root(content_hash(market)),
      ],
      [
        "classification labels are synthetic source declarations",
        "no regime interpretation or workflow action is supplied",
      ],
    )
  context_copy(value)
}

fn catalyst_receipt(spec: Spec) -> ReceiptCopy {
  let source_receipt =
    sha(finance_track.name(spec.track) <> ":catalyst-source-row")
  let assert Ok(event) =
    context_receipt.catalyst_event(
      "fixture-" <> finance_track.name(spec.track) <> "-event-1",
      "earnings_calendar",
      "Synthetic scheduled issuer event",
      "source_declared_scheduled",
      context_receipt.Known(instant(1_788_184_800_000)),
      context_receipt.Unknown("publication timestamp absent from fixture row"),
      timezone(spec.timezone),
      fixture_source(
        "fixture://" <> finance_track.name(spec.track) <> "/catalyst",
      ),
      source_receipt,
      [],
    )
  let assert Ok(snapshot) =
    context_receipt.catalyst_snapshot(
      "exact listing; 2026-08-07 through 2026-08-31; earnings calendar",
      [event],
    )
  let assert Ok(value) =
    context_receipt.catalyst_receipt(
      listing_key(spec),
      context_receipt.Known(snapshot),
      instant(1_786_092_300_000),
      [evidence_root(source_receipt)],
      [
        "synthetic bounded query result only",
        "no event impact sentiment importance or action is supplied",
      ],
    )
  context_copy(value)
}

fn universe_candidate_receipt(spec: Spec) -> ReceiptCopy {
  case spec.track {
    finance_track.Us -> alpaca_universe_candidate_receipt(spec)
    finance_track.Cn | finance_track.Hk ->
      synthetic_universe_candidate_receipt(spec)
  }
}

fn synthetic_universe_candidate_receipt(spec: Spec) -> ReceiptCopy {
  let track = finance_track.name(spec.track)
  let source_receipt = sha(track <> ":universe-source-row")
  let universe_receipt = sha(track <> ":point-in-time-universe-snapshot")
  let assert Ok(observation) =
    context_receipt.universe_candidate_observation(
      "fixture-" <> track <> "-point-in-time-universe",
      "2026-08-07.1",
      "track="
        <> track
        <> "; as_of=2026-08-07; source-declared eligible/liquid predicate",
      "fixture-" <> track <> "-row-" <> spec.symbol,
      "source_declared_included",
      ["source row returned by the bounded point-in-time query"],
      [],
      instant(1_786_092_000_000),
      instant(1_786_092_300_000),
      instant(1_786_092_400_000),
      timezone(spec.timezone),
      fixture_source("fixture://" <> track <> "/universe"),
      source_receipt,
      universe_receipt,
      [evidence_root(source_receipt), evidence_root(universe_receipt)],
    )
  let assert Ok(value) =
    context_receipt.universe_candidate_receipt(
      listing_key(spec),
      context_receipt.Known(observation),
      instant(1_786_092_500_000),
      [
        "synthetic source-declared membership from one bounded query",
        "no complete-population proof rank qualification selection or action is supplied",
      ],
    )
  context_copy(value)
}

fn alpaca_universe_candidate_receipt(spec: Spec) -> ReceiptCopy {
  let assert Ok(plan) =
    alpaca_query.asset_universe(
      alpaca_query.Paper,
      alpaca_query.Active,
      alpaca_query.Nasdaq,
      1000,
    )
  let body = alpaca_asset_fixture()
  let assert Ok(snapshot) = alpaca_assets.decode_snapshot(body, for: plan)
  let assert [asset] = alpaca_assets.rows(snapshot)
  let assert True = alpaca_assets.symbol(asset) == spec.symbol
  let reference = alpaca_query.asset_universe_source_reference(plan)
  let source_receipt = sha(body)
  let universe_receipt = sha(reference <> "\n" <> body)
  let source_fields = [
    provider_field("asset_id", alpaca_assets.id(asset)),
    provider_field("class", alpaca_assets.asset_class(asset)),
    provider_field("exchange", alpaca_assets.exchange(asset)),
    provider_field("symbol", alpaca_assets.symbol(asset)),
    provider_field("name", alpaca_assets.name(asset)),
    provider_field("status", alpaca_assets.status(asset)),
    provider_field("tradable", bool.to_string(alpaca_assets.tradable(asset))),
    provider_field(
      "marginable",
      bool.to_string(alpaca_assets.marginable(asset)),
    ),
    provider_field("shortable", bool.to_string(alpaca_assets.shortable(asset))),
    provider_field(
      "easy_to_borrow",
      bool.to_string(alpaca_assets.easy_to_borrow(asset)),
    ),
    provider_field(
      "fractionable",
      bool.to_string(alpaca_assets.fractionable(asset)),
    ),
    provider_field(
      "attributes",
      alpaca_assets.attributes(asset)
        |> json.array(json.string)
        |> json.to_string,
    ),
  ]
  let assert Ok(observation) =
    context_receipt.universe_candidate_observation(
      "alpaca-us-equity-active-NASDAQ",
      "alpaca-assets-v2",
      reference,
      alpaca_assets.id(asset),
      "provider_returned_row",
      [],
      source_fields,
      instant(1_786_092_400_000),
      instant(1_786_092_400_000),
      instant(1_786_092_400_000),
      timezone(spec.timezone),
      alpaca_source(reference),
      source_receipt,
      universe_receipt,
      [evidence_root(source_receipt), evidence_root(universe_receipt)],
    )
  let assert Ok(value) =
    context_receipt.universe_candidate_receipt(
      listing_key(spec),
      context_receipt.Known(observation),
      instant(1_786_092_500_000),
      [
        "decoded from exact scripted Alpaca asset response bytes",
        "content hashes are not provider signatures and the endpoint has no historical as-of parameter",
        "provider asset fields do not prove authoritative listing identity eligibility rank selection or action",
      ],
    )
  context_copy(value)
}

fn provider_field(name: String, value: String) -> context_receipt.SourceField {
  let assert Ok(value) = context_receipt.source_field(name, value)
  value
}

fn alpaca_asset_fixture() -> String {
  "[{\"id\":\"b0b6dd9d-8b9b-48a9-ba46-b9d54906e415\",\"class\":\"us_equity\",\"exchange\":\"NASDAQ\",\"symbol\":\"AAPL\",\"name\":\"Apple Inc. Common Stock\",\"status\":\"active\",\"tradable\":true,\"marginable\":true,\"shortable\":true,\"easy_to_borrow\":true,\"fractionable\":true,\"attributes\":[\"has_options\"]}]"
}

fn task_time_receipt(
  spec: Spec,
  market: ReceiptCopy,
  indicator: ReceiptCopy,
  risk: ReceiptCopy,
  rule: ReceiptCopy,
  execution: ReceiptCopy,
  sector_regime: ReceiptCopy,
  catalyst: ReceiptCopy,
  universe_candidate: ReceiptCopy,
) -> ReceiptCopy {
  let roots =
    [
      market,
      indicator,
      risk,
      rule,
      execution,
      sector_regime,
      catalyst,
      universe_candidate,
    ]
    |> list.map(fn(value) { evidence_root(content_hash(value)) })
  let assert Ok(after_close) =
    task_time_observation(
      spec,
      "after-close",
      "after_close",
      1_786_093_200_000,
      context_receipt.Known(instant(1_786_092_000_000)),
      context_receipt.Known(instant(1_786_092_300_000)),
      roots,
    )
  let assert Ok(preflight) =
    task_time_observation(
      spec,
      "preflight",
      "preflight",
      1_786_174_200_000,
      context_receipt.Known(instant(1_786_092_000_000)),
      context_receipt.Known(instant(1_786_092_300_000)),
      roots,
    )
  let assert Ok(monitor) =
    task_time_observation(
      spec,
      "monitor",
      "monitor",
      1_786_203_000_000,
      context_receipt.NotObtained("newer observation not supplied"),
      context_receipt.Known(instant(1_786_092_300_000)),
      roots,
    )
  let assert Ok(review) =
    task_time_observation(
      spec,
      "review",
      "review",
      1_786_203_003_000,
      context_receipt.Known(instant(1_786_092_000_000)),
      context_receipt.Known(instant(1_786_092_300_000)),
      roots,
    )
  let assert Ok(value) =
    context_receipt.task_time_receipt(
      listing_key(spec),
      [after_close, preflight, monitor, review],
      [
        "exact clocks only",
        "no freshness lateness deadline or next-operation label is supplied",
      ],
    )
  context_copy(value)
}

fn task_time_observation(
  spec: Spec,
  suffix: String,
  stage: String,
  requested_at: Int,
  context_as_of: context_receipt.Information(Instant),
  source_cutoff: context_receipt.Information(Instant),
  roots: List(EvidenceId),
) -> Result(context_receipt.TaskTimeObservation, context_receipt.ContextError) {
  context_receipt.task_time_observation(
    "fixture-" <> finance_track.name(spec.track) <> "-" <> suffix,
    stage,
    instant(requested_at),
    context_as_of,
    source_cutoff,
    instant(requested_at + 1),
    timezone(spec.timezone),
    roots,
  )
}

fn context_copy(value: context_receipt.Receipt) -> ReceiptCopy {
  ReceiptCopy(
    context_receipt.schema(value),
    context_receipt.encode(value),
    context_receipt.canonical_content_hash(value),
    "envelope_payload_sha256",
  )
}

fn sector_label(track: Track) -> String {
  case track {
    finance_track.Cn -> "Banks"
    finance_track.Hk -> "Interactive Media & Services"
    finance_track.Us -> "Technology Hardware, Storage & Peripherals"
  }
}

fn listing_key(spec: Spec) -> listing.Key {
  let assert Ok(instrument_id) = identifier.instrument_id(spec.instrument_id)
  let assert Ok(symbol) = identifier.symbol(spec.symbol)
  let assert Ok(mic) = identifier.mic(spec.mic)
  listing.new(spec.track, instrument_id, symbol, mic)
}

fn fixture_source(reference: String) -> source.SourceRef {
  let assert Ok(value) =
    source.new("acceptance_fixture", reference, source.Synthetic)
  value
}

fn alpaca_source(reference: String) -> source.SourceRef {
  let assert Ok(value) = source.new("alpaca", reference, source.LicensedVendor)
  value
}

fn timezone(value: String) -> time.Timezone {
  let assert Ok(value) = time.timezone(value)
  value
}

fn bundled_market_receipt(spec: Spec, content_hash: Sha256) -> ReceiptCopy {
  let schema = case spec.track {
    finance_track.Cn -> "pi-sparkles/cn-ohlcv-gap-receipt"
    finance_track.Hk -> "pi-sparkles/hk-ohlcv-gap-receipt"
    finance_track.Us -> "pi-sparkles/us-ohlcv-gap-receipt"
  }
  ReceiptCopy(
    schema,
    "bundled result inserted by the acceptance shell",
    content_hash,
    "bundled_tool_gap_projection_sha256",
  )
}

fn market_receipt(spec: Spec) -> ReceiptCopy {
  let assert Ok(instrument) =
    acquisition_receipt.identity_field("instrument_id", spec.instrument_id)
  let assert Ok(symbol) =
    acquisition_receipt.identity_field("symbol", spec.symbol)
  let assert Ok(mic) = acquisition_receipt.identity_field("mic", spec.mic)
  let assert Ok(page) =
    acquisition_receipt.page(
      1,
      Some("acceptance-page-1"),
      512,
      sha(finance_track.name(spec.track) <> ":copied-provider-page"),
    )
  let assert Ok(value) =
    acquisition_receipt.new(
      schema: "pi-sparkles/ohlcv-acquisition-receipt",
      schema_version: 1,
      track: spec.track,
      provider: spec.provider,
      identity: [instrument, symbol, mic],
      source_reference: spec.source_reference,
      retrieved_at: instant(1_786_092_300_000),
      pagination: acquisition_receipt.Complete,
      pages: [page],
      range_start: date(2026, 8, 3),
      range_end: date(2026, 8, 7),
      bar_dates: [
        date(2026, 8, 3),
        date(2026, 8, 4),
        date(2026, 8, 5),
        date(2026, 8, 6),
        date(2026, 8, 7),
      ],
    )
  let payload = acquisition_receipt.canonical_text(value)
  ReceiptCopy(
    "finance_ohlcv/acquisition_receipt",
    payload,
    sha(payload),
    "canonical_text_sha256",
  )
}

fn indicator_request_receipt(spec: Spec, market: ReceiptCopy) -> ReceiptCopy {
  let assert Ok(source_leg) =
    indicator_model.source_leg(
      spec.provider,
      spec.source_reference,
      content_hash(market),
      instant(1_786_092_300_000),
    )
  let assert Ok(zone) = time.timezone(spec.timezone)
  let assert Ok(context) =
    indicator_model.context(
      spec.track,
      spec.instrument_id,
      spec.mic,
      zone,
      date(2026, 8, 3),
      date(2026, 8, 7),
      source_leg,
      Some(instant(1_786_092_300_000)),
      "close",
      indicator_model.KnownUnit(spec.currency),
      indicator_model.Raw,
      [],
      [],
      [evidence_root(content_hash(market))],
    )
  let assert Ok(request) =
    indicator_model.request(
      sha(finance_track.name(spec.track) <> ":llm-indicator-instruction"),
      context,
      indicator_model.WilderRsiV1(
        5,
        indicator_model.SlotWindowV1,
        indicator_model.StopAtGapV1,
        indicator_model.ZeroZeroUnperformedV1,
      ),
      indicator_model.ExcludeParseableWithChecks,
      indicator_model.RoundingSpec(
        4,
        decimal.HalfUp,
        indicator_model.PerStep,
        8,
      ),
      [indicator_model.LatestValue],
    )
  let assert Ok(value) = indicator_receipt.request_receipt(request)
  ReceiptCopy(
    "finance_indicators/request_receipt",
    indicator_receipt.encode(value),
    indicator_receipt.canonical_content_hash(value),
    "envelope_payload_sha256",
  )
}

fn risk_request_receipt(
  spec: Spec,
  market: ReceiptCopy,
  indicator: ReceiptCopy,
  rule: ReceiptCopy,
) -> ReceiptCopy {
  let instruction_ref =
    sha(finance_track.name(spec.track) <> ":llm-risk-instruction")
  let assert Ok(context) =
    risk_request.context(
      "acceptance-account",
      "acceptance-portfolio",
      spec.track,
      spec.instrument_id,
      instant(1_786_093_200_000),
      spec.currency,
      [
        evidence_root(content_hash(market)),
        evidence_root(content_hash(indicator)),
        evidence_root(content_hash(rule)),
      ],
    )
  let assert Ok(operation) =
    risk_request.operation(
      "planned_loss",
      "long_planned_loss_per_unit_v1",
      [],
      instruction_ref,
      ["entry_price", "stop_price"],
    )
  let assert Ok(rounding) = risk_calculation.rounding(4, 8, decimal.HalfUp)
  let assert Ok(request) =
    risk_request.request(
      instruction_ref,
      context,
      [operation],
      [],
      ["llm_declared_risk_budget"],
      ["llm_declared_gap_scenario"],
      [],
      bound.FloorToIncrement,
      rounding,
      risk_request.NativeCurrency,
      risk_request.AllBranches,
      ["ordered_inputs_as_supplied"],
      ["receipt_handle"],
      risk_request.ExecutionBudgets(16, 8),
      ["supply_fact", "calculate_requested_operation", "inspect_formula"],
    )
  let assert Ok(value) = risk_receipt.request_receipt(request)
  ReceiptCopy(
    "finance_risk/request_receipt",
    risk_receipt.encode(value),
    risk_receipt.canonical_content_hash(value),
    "envelope_payload_sha256",
  )
}

fn execution_request_receipt(
  spec: Spec,
  market: ReceiptCopy,
  risk: ReceiptCopy,
  rule: ReceiptCopy,
) -> ReceiptCopy {
  let instruction_ref =
    sha(finance_track.name(spec.track) <> ":llm-desired-instruction")
  let capability_ref = sha(finance_track.name(spec.track) <> ":capability-fact")
  let account_ref = sha(finance_track.name(spec.track) <> ":account-fact")
  let assert Ok(desired) =
    instruction.desired(
      "acceptance-" <> finance_track.name(spec.track) <> "-instruction",
      instruction_ref,
      spec.track,
      spec.instrument_id,
      spec.mic,
      "acceptance-account",
      spec.currency,
      instruction.Buy,
      Some(instruction.Open),
      exact("100"),
      instruction.Shares,
      instruction.Limit(exact("10.91")),
      instruction.Day,
      Some(instruction.Regular),
      None,
      None,
      spec.timezone,
      [content_hash(rule)],
      [capability_ref],
      [account_ref],
      instruction.KnownAlternatives([
        "daily_bar_stop_first",
        "daily_bar_target_first",
      ]),
    )
  let assert Ok(operation) =
    execution_request.operation(
      "daily_bar_paths",
      simulation.bar_possible_paths_v1,
      [],
      instruction_ref,
      [],
    )
  let assert Ok(rounding) = execution_calculation.rounding(4, decimal.HalfUp)
  let assert Ok(request) =
    execution_request.request(
      desired,
      [operation],
      [],
      execution_request.ReferenceSet(
        [capability_ref],
        [content_hash(rule)],
        [],
        [content_hash(market)],
        [],
        [],
        [content_hash(risk)],
        [],
        [],
      ),
      "next_regular_session",
      "2026-08-08T09:30:00+track_timezone",
      [#("model", simulation.bar_possible_paths_v1)],
      [],
      [],
      [],
      [],
      rounding,
      "native",
      execution_request.AllBranches,
      ["all_compatible_branches", "unknown_ordering"],
      execution_request.Budgets(16, 1, 8, 1, 16, 100_000, 8),
      ["supply_daily_bar", "calculate_all_branches", "inspect_branch"],
    )
  let assert Ok(bar) =
    simulation.daily_bar(
      exact("10.80"),
      exact("12.30"),
      exact("9.80"),
      exact("11.00"),
    )
  let branches =
    simulation.stop_target_possible_paths(bar, exact("10.00"), exact("12.00"))
  let assert Ok(value) =
    execution_receipt.semantic_result_receipt(request, [
      execution_receipt.BranchResult("daily_bar_paths", branches),
    ])
  ReceiptCopy(
    "finance_execution/semantic_result_receipt",
    execution_receipt.encode(value),
    execution_receipt.canonical_content_hash(value),
    "envelope_payload_sha256",
  )
}

fn rule_receipt(spec: Spec) -> ReceiptCopy {
  let payload = case spec.track {
    finance_track.Cn -> cn_rule_json() |> json.to_string
    finance_track.Hk -> hk_rule_json() |> json.to_string
    finance_track.Us -> us_rule_json(spec) |> json.to_string
  }
  ReceiptCopy(
    "track_owned/effective_rule_projection",
    payload,
    sha(payload),
    "canonical_projection_sha256_not_provider_signature",
  )
}

fn cn_rule_json() -> Json {
  let assert Ok(value) =
    cn_rules.established_equity(
      cn_rules.Sse,
      cn_rules.MainBoard,
      date(2026, 8, 7),
    )
  let interval = cn_rules.effective(value)
  json.object([
    #("schema", json.string("pi-sparkles/cn-effective-rule-projection")),
    #("schema_version", json.int(1)),
    #("track", json.string("cn")),
    #("venue", json.string(cn_rules.venue_name(cn_rules.venue(value)))),
    #("board", json.string(cn_rules.board_name(cn_rules.board(value)))),
    #("effective", interval_json(interval)),
    #("tick_size", json.string(decimal.to_string(cn_rules.tick_size(value)))),
    #("minimum_buy_quantity", json.int(cn_rules.minimum_buy_quantity(value))),
    #("buy_quantity_increment", case cn_rules.buy_quantity_increment(value) {
      Some(value) -> json.int(value)
      None -> json.null()
    }),
    #(
      "daily_price_limit_ratio",
      json.string(decimal.to_string(cn_rules.daily_price_limit(value))),
    ),
    #("source", source_json(cn_rules.source(value))),
    #("clauses", json.array(cn_rules.clauses(value), json.string)),
    #("limitations", json.array(cn_rules.limitations(value), json.string)),
  ])
}

fn hk_rule_json() -> Json {
  let assert Ok(value) =
    hk_rules.applicable_hkd_equity(
      date(2026, 8, 7),
      exact("9.995"),
      500,
      "copied HKEX issuer-profile board-lot fixture for 00700",
    )
  json.object([
    #("schema", json.string("pi-sparkles/hk-effective-rule-projection")),
    #("schema_version", json.int(1)),
    #("track", json.string("hk")),
    #("effective", interval_json(hk_rules.effective(value))),
    #(
      "nominal_price",
      json.string(decimal.to_string(hk_rules.nominal_price(value))),
    ),
    #(
      "price_band",
      json.string(hk_rules.price_band_name(hk_rules.selected_price_band(value))),
    ),
    #("tick_size", json.string(decimal.to_string(hk_rules.tick_size(value)))),
    #("board_lot", json.int(hk_rules.board_lot(value))),
    #("board_lot_source", json.string(hk_rules.board_lot_source(value))),
    #(
      "sources",
      json.array(
        [hk_rules.spread_source(value), hk_rules.board_lot_rule_source(value)],
        source_json,
      ),
    ),
    #("clauses", json.array(hk_rules.clauses(value), json.string)),
    #("limitations", json.array(hk_rules.limitations(value), json.string)),
  ])
}

fn us_rule_json(spec: Spec) -> Json {
  let assert Ok(value) =
    us_rules.regular_displayed_nms_quote(
      us_rules.Nasdaq,
      spec.instrument_id,
      spec.symbol,
      spec.currency,
      "nms_stock",
      "normal",
      "regular_displayed_quote",
      date(2026, 8, 7),
      exact("182.375"),
    )
  json.object([
    #("schema", json.string("pi-sparkles/us-effective-rule-projection")),
    #("schema_version", json.int(1)),
    #("track", json.string("us")),
    #("venue", json.string(us_rules.venue_name(us_rules.venue(value)))),
    #("effective", interval_json(us_rules.effective(value))),
    #(
      "nominal_price",
      json.string(decimal.to_string(us_rules.nominal_price(value))),
    ),
    #(
      "price_band",
      json.string(us_rules.price_band_name(us_rules.selected_price_band(value))),
    ),
    #(
      "minimum_price_increment",
      json.string(decimal.to_string(us_rules.minimum_price_increment(value))),
    ),
    #("sources", json.array(us_rules.sources(value), source_json)),
    #("clauses", json.array(us_rules.clauses(value), json.string)),
    #("limitations", json.array(us_rules.limitations(value), json.string)),
  ])
}

fn receipt_json(value: ReceiptCopy) -> Json {
  let ReceiptCopy(schema, payload, content_hash, integrity) = value
  json.object([
    #("schema", json.string(schema)),
    #("payload", json.string(payload)),
    #(
      "canonicalContentHash",
      content_hash |> identity.sha256_value |> json.string,
    ),
    #("integrity", json.string(integrity)),
  ])
}

fn interval_json(value: effective.Interval) -> Json {
  json.object([
    #("start", json.string(date_text(effective.start(value)))),
    #("end", case effective.end(value) {
      Some(value) -> json.string(date_text(value))
      None -> json.null()
    }),
  ])
}

fn source_json(value: source.SourceRef) -> Json {
  json.object([
    #("provider", json.string(source.provider(value))),
    #("reference", json.string(source.reference(value))),
    #("kind", json.string(source_kind_name(source.kind(value)))),
  ])
}

fn source_kind_name(value: source.SourceKind) -> String {
  case value {
    source.Official -> "official"
    source.Exchange -> "exchange"
    source.Regulator -> "regulator"
    source.LicensedVendor -> "licensed_vendor"
    source.UserSupplied -> "user_supplied"
    source.Synthetic -> "synthetic"
    source.Other(value) -> value
  }
}

fn content_hash(value: ReceiptCopy) -> Sha256 {
  let ReceiptCopy(_, _, value, _) = value
  value
}

fn evidence_root(value: Sha256) -> EvidenceId {
  identity.evidence_id(value)
}

fn sha(value: String) -> Sha256 {
  let assert Ok(value) = hash.text(value)
  value
}

fn exact(value: String) -> decimal.Decimal {
  let assert Ok(value) = decimal.parse(value)
  value
}

fn instant(value: Int) -> Instant {
  let assert Ok(value) = time.instant(value)
  value
}

fn date(year: Int, month: Int, day: Int) -> Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
