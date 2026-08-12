import finance_core/decimal
import finance_multi_asset/common
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/order.{Eq}
import gleam/result
import gleam/string

pub type Observation {
  Observation(
    period_date: String,
    vintage_at_unix_ms: Int,
    correction_state: String,
    value: common.Fact,
    receipt: String,
  )
}

pub type Panel {
  Panel(
    panel_id: String,
    title: String,
    series_id: String,
    geography: String,
    native_frequency: String,
    unit: String,
    transform: String,
    entitlement: String,
    licence: String,
    source_receipt: String,
    observations: List(Observation),
  )
}

pub type Packet {
  Packet(
    knowledge_cutoff_unix_ms: Int,
    alignment_policy: String,
    panels: List(Panel),
    handoff_receipts: List(String),
  )
}

pub fn dashboard(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "macro_dashboard_v1",
    "compose",
    decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(validate(packet))
  let selected =
    packet.panels
    |> list.map(fn(panel) {
      #(
        panel,
        select_vintages(panel.observations, packet.knowledge_cutoff_unix_ms),
      )
    })
  let matched_dates = intersection_dates(selected)
  Ok(
    common.response(
      "macro_dashboard_v1",
      "compose",
      decoded.1,
      "Caller-composed macro dashboard with native geography, frequency, units, knowledge-cutoff vintages, explicit intersection alignment and least-permissive rights inventory",
      [
        #("track", json.null()),
        #("directAcquisition", json.bool(False)),
        #(
          "knowledgeCutoffUnixMilliseconds",
          json.int(packet.knowledge_cutoff_unix_ms),
        ),
        #("alignmentPolicy", json.string(packet.alignment_policy)),
        #("matchedDates", json.array(matched_dates, json.string)),
        #(
          "panels",
          json.array(selected, fn(item) { panel_json(item.0, item.1) }),
        ),
        #(
          "rights",
          json.object([
            #("aggregation", json.string("least_permissive")),
            #(
              "inventory",
              json.array(packet.panels, fn(panel) {
                json.object([
                  #("panelId", json.string(panel.panel_id)),
                  #("entitlement", json.string(panel.entitlement)),
                  #("licence", json.string(panel.licence)),
                ])
              }),
            ),
          ]),
        ),
        #("handoffReceipts", json.array(packet.handoff_receipts, json.string)),
        #(
          "interpretation",
          json.string("not_provided_decision_owner_is_llm_or_user"),
        ),
      ],
    ),
  )
}

fn decoder() -> decode.Decoder(Packet) {
  use cutoff <- decode.field("knowledgeCutoffUnixMilliseconds", decode.int)
  use alignment <- decode.field("alignmentPolicy", decode.string)
  use panels <- decode.field("panels", decode.list(of: panel_decoder()))
  use receipts <- decode.field(
    "handoffReceipts",
    decode.list(of: decode.string),
  )
  decode.success(Packet(cutoff, alignment, panels, receipts))
}

fn panel_decoder() -> decode.Decoder(Panel) {
  use id <- decode.field("panelId", decode.string)
  use title <- decode.field("title", decode.string)
  use series <- decode.field("seriesId", decode.string)
  use geography <- decode.field("geography", decode.string)
  use frequency <- decode.field("nativeFrequency", decode.string)
  use unit <- decode.field("unit", decode.string)
  use transform <- decode.field("transform", decode.string)
  use entitlement <- decode.field("entitlement", decode.string)
  use licence <- decode.field("licence", decode.string)
  use receipt <- decode.field("sourceReceipt", decode.string)
  use observations <- decode.field(
    "observations",
    decode.list(of: observation_decoder()),
  )
  decode.success(Panel(
    id,
    title,
    series,
    geography,
    frequency,
    unit,
    transform,
    entitlement,
    licence,
    receipt,
    observations,
  ))
}

fn observation_decoder() -> decode.Decoder(Observation) {
  use date <- decode.field("periodDate", decode.string)
  use vintage <- decode.field("vintageAtUnixMilliseconds", decode.int)
  use correction <- decode.field("correctionState", decode.string)
  use value <- decode.field("value", common.fact_decoder())
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Observation(date, vintage, correction, value, receipt))
}

fn validate(packet: Packet) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_negative(
    "knowledgeCutoffUnixMilliseconds",
    packet.knowledge_cutoff_unix_ms,
  ))
  use _ <- result.try(case packet.alignment_policy {
    "intersection_of_selected_period_dates" -> Ok(Nil)
    _ ->
      Error(common.InvalidField(
        "alignmentPolicy",
        "must be intersection_of_selected_period_dates",
      ))
  })
  use _ <- result.try(case list.length(packet.panels) {
    count if count >= 2 && count <= 12 -> Ok(Nil)
    count -> Error(common.BudgetExceeded("panels", count, 12))
  })
  use _ <- result.try(case packet.handoff_receipts {
    [] -> Error(common.InvalidField("handoffReceipts", "must not be empty"))
    receipts -> common.validate_receipts("handoffReceipts", receipts)
  })
  packet.panels
  |> list.index_map(fn(panel, index) {
    validate_panel(panel, "panels[" <> int.to_string(index) <> "]")
  })
  |> list.try_map(fn(value) { value })
  |> result.map(fn(_) { Nil })
}

fn validate_panel(panel: Panel, field: String) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty(field <> ".panelId", panel.panel_id))
  use _ <- result.try(common.non_empty(field <> ".title", panel.title))
  use _ <- result.try(common.non_empty(field <> ".seriesId", panel.series_id))
  use _ <- result.try(common.non_empty(field <> ".geography", panel.geography))
  use _ <- result.try(
    common.one_of(field <> ".nativeFrequency", panel.native_frequency, [
      "daily",
      "weekly",
      "monthly",
      "quarterly",
      "annual",
    ]),
  )
  use _ <- result.try(common.non_empty(field <> ".unit", panel.unit))
  use _ <- result.try(
    common.one_of(field <> ".transform", panel.transform, [
      "level",
      "period_percent_change",
      "rebase_100",
    ]),
  )
  use _ <- result.try(common.non_empty(
    field <> ".entitlement",
    panel.entitlement,
  ))
  use _ <- result.try(common.non_empty(field <> ".licence", panel.licence))
  use _ <- result.try(common.receipt(
    field <> ".sourceReceipt",
    panel.source_receipt,
  ))
  use _ <- result.try(case list.length(panel.observations) {
    count if count >= 2 && count <= 240 -> Ok(Nil)
    count -> Error(common.BudgetExceeded(field <> ".observations", count, 240))
  })
  panel.observations
  |> list.index_map(fn(observation, index) {
    validate_observation(
      observation,
      panel.unit,
      field <> ".observations[" <> int.to_string(index) <> "]",
    )
  })
  |> list.try_map(fn(value) { value })
  |> result.map(fn(_) { Nil })
}

fn validate_observation(
  observation: Observation,
  unit: String,
  field: String,
) -> Result(Nil, common.Error) {
  use _ <- result.try(common.date(
    field <> ".periodDate",
    observation.period_date,
  ))
  use _ <- result.try(common.non_negative(
    field <> ".vintageAtUnixMilliseconds",
    observation.vintage_at_unix_ms,
  ))
  use _ <- result.try(common.non_empty(
    field <> ".correctionState",
    observation.correction_state,
  ))
  use _ <- result.try(common.validate_fact(field <> ".value", observation.value))
  use _ <- result.try(case observation.value.unit == unit {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        field <> ".value.unit",
        "must match panel native unit",
      ))
  })
  common.receipt(field <> ".receipt", observation.receipt)
}

fn select_vintages(
  observations: List(Observation),
  cutoff: Int,
) -> List(Observation) {
  observations
  |> list.filter(fn(observation) { observation.vintage_at_unix_ms <= cutoff })
  |> list.sort(fn(left, right) {
    case string.compare(left.period_date, right.period_date) {
      Eq -> int.compare(right.vintage_at_unix_ms, left.vintage_at_unix_ms)
      order -> order
    }
  })
  |> list.fold([], fn(selected: List(Observation), observation) {
    case
      list.any(selected, fn(item) {
        item.period_date == observation.period_date
      })
    {
      True -> selected
      False -> [observation, ..selected]
    }
  })
  |> list.sort(fn(left, right) {
    string.compare(left.period_date, right.period_date)
  })
}

fn intersection_dates(
  selected: List(#(Panel, List(Observation))),
) -> List(String) {
  case selected {
    [] -> []
    [first, ..rest] ->
      first.1
      |> list.map(fn(observation) { observation.period_date })
      |> list.filter(fn(date) {
        list.all(rest, fn(item) {
          list.any(item.1, fn(observation) { observation.period_date == date })
        })
      })
  }
}

fn panel_json(panel: Panel, selected: List(Observation)) -> json.Json {
  json.object([
    #("panelId", json.string(panel.panel_id)),
    #("title", json.string(panel.title)),
    #("seriesId", json.string(panel.series_id)),
    #("geography", json.string(panel.geography)),
    #("nativeFrequency", json.string(panel.native_frequency)),
    #("nativeUnit", json.string(panel.unit)),
    #("transform", json.string(panel.transform)),
    #("sourceReceipt", json.string(panel.source_receipt)),
    #("selectedObservations", transformed_json(panel, selected)),
    #("allVintageCount", json.int(list.length(panel.observations))),
  ])
}

fn transformed_json(panel: Panel, selected: List(Observation)) -> json.Json {
  case panel.transform, selected {
    "level", _ -> json.array(selected, observation_json)
    "rebase_100", [first, ..] -> {
      let base = common.fact_decimal("rebase.base", first.value)
      json.array(selected, fn(observation) {
        let calculated = case
          base,
          common.fact_decimal("rebase.value", observation.value)
        {
          Ok(base), Ok(value) -> common.percentage(value, base, 8)
          Error(error), _ -> Error(error)
          _, Error(error) -> Error(error)
        }
        transformed_observation_json(
          observation,
          "value / first_value * 100",
          calculated,
          "index_100",
        )
      })
    }
    "period_percent_change", [first, ..rest] -> {
      let rows = percent_change_rows(first, rest, [])
      json.array(rows, fn(row) { row })
    }
    _, _ -> json.array([], fn(value) { value })
  }
}

fn percent_change_rows(
  previous: Observation,
  remaining: List(Observation),
  accumulated: List(json.Json),
) -> List(json.Json) {
  case remaining {
    [] -> list.reverse(accumulated)
    [current, ..rest] -> {
      let calculated = case
        common.fact_decimal("change.current", current.value),
        common.fact_decimal("change.previous", previous.value)
      {
        Ok(current_value), Ok(previous_value) ->
          common.percentage(
            decimal.subtract(current_value, previous_value),
            previous_value,
            8,
          )
        Error(error), _ -> Error(error)
        _, Error(error) -> Error(error)
      }
      percent_change_rows(current, rest, [
        transformed_observation_json(
          current,
          "(current - previous) / previous * 100",
          calculated,
          "percent",
        ),
        ..accumulated
      ])
    }
  }
}

fn observation_json(observation: Observation) -> json.Json {
  json.object([
    #("periodDate", json.string(observation.period_date)),
    #("vintageAtUnixMilliseconds", json.int(observation.vintage_at_unix_ms)),
    #("correctionState", json.string(observation.correction_state)),
    #("value", common.fact_json(observation.value)),
    #("receipt", json.string(observation.receipt)),
  ])
}

fn transformed_observation_json(
  observation: Observation,
  formula: String,
  value: Result(decimal.Decimal, common.Error),
  unit: String,
) -> json.Json {
  json.object([
    #("periodDate", json.string(observation.period_date)),
    #("vintageAtUnixMilliseconds", json.int(observation.vintage_at_unix_ms)),
    #(
      "calculation",
      common.calculation_json(formula, value, unit, [
        #("sourceValue", common.fact_json(observation.value)),
      ]),
    ),
    #("receipt", json.string(observation.receipt)),
  ])
}
