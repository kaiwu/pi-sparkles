import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/time
import finance_math/exact
import finance_math/statistics
import finance_quant/common.{type Error, type Response}
import finance_replay/manifest
import finance_series/exact_path
import finance_series/path
import finance_series/series
import finance_track
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order}
import gleam/result
import gleam/string

const maximum_periods = 240

const maximum_listings_per_period = 10_000

type Definition {
  Definition(
    factor_id: String,
    source_field: String,
    source_unit: String,
    calculation: String,
    transformation: String,
    availability_rule: String,
    rebalance_schedule: String,
    weighting: String,
    bucket_count: Int,
    direction: String,
    return_horizon: String,
    currency: String,
    missing_policy: String,
    survivorship_policy: String,
    ic_method: String,
    scale: Int,
    rounding: String,
  )
}

type FactInput {
  FactInput(
    state: String,
    raw: Option(String),
    known_at_unix_ms: Int,
    reason: Option(String),
    alternatives: List(String),
    receipts: List(String),
  )
}

type MemberInput {
  MemberInput(
    listing_id: String,
    mic: String,
    observation_id: String,
    membership_state: String,
    membership_receipt: String,
    factor: FactInput,
    forward_return: FactInput,
    weight: Option(String),
    delisted: Bool,
    suspended: Bool,
  )
}

type PeriodInput {
  PeriodInput(
    period_id: String,
    at_unix_ms: Int,
    knowledge_cutoff_unix_ms: Int,
    members: List(MemberInput),
    rebalance_receipt: String,
  )
}

type Request {
  Request(
    binding: common.BindingInput,
    definition: Definition,
    periods: List(PeriodInput),
  )
}

type Eligible {
  Eligible(
    input: MemberInput,
    factor: Decimal,
    forward_return: Decimal,
    weight: Option(Decimal),
    rank: Int,
    bucket: Int,
  )
}

type Excluded {
  Excluded(input: MemberInput, reason: String)
}

type MemberResult {
  Included(Eligible)
  Omitted(Excluded)
}

type BucketResult {
  BucketResult(bucket: Int, members: List(Eligible), return_value: Decimal)
}

type PeriodResult {
  PeriodResult(
    input: PeriodInput,
    members: List(MemberResult),
    buckets: List(BucketResult),
    factor_return: Decimal,
    ic: String,
    turnover: Option(Decimal),
  )
}

pub fn calculate(
  bytes: String,
  expected_sha256: String,
) -> Result(Response, Error) {
  use _ <- result.try(common.verify_packet(
    bytes,
    expected_sha256,
    "stock_factor_lab_v1",
    "calculate",
  ))
  use request <- result.try(common.parse(bytes, request_decoder()))
  use binding <- result.try(common.prepare_binding(request.binding))
  use mode <- result.try(validate_definition(request.definition, binding))
  use _ <- result.try(common.bounded_count(
    "periods",
    request.periods,
    maximum_periods,
  ))
  use _ <- result.try(common.require_unique(
    "periods[].periodId",
    list.map(request.periods, fn(value) { value.period_id }),
  ))
  use _ <- result.try(validate_period_order(request.periods))
  use periods <- result.try(
    calculate_periods(
      request.periods,
      request.definition,
      mode,
      binding,
      None,
      [],
    ),
  )
  use factor_series <- result.try(period_series(periods))
  use cumulative <- result.try(
    exact_path.cumulative_return(
      factor_series,
      missing: path.InvalidateAfterMissing,
    )
    |> result.map_error(fn(error) {
      common.CalculationFailure(
        "factor cumulative-return path failed: " <> string.inspect(error),
      )
    }),
  )
  let cumulative_value = case cumulative |> series.present_values |> list.last {
    Ok(value) -> Some(value.1)
    Error(_) -> None
  }
  use mean_return <- result.try(case periods {
    [] -> Ok(None)
    _ ->
      periods
      |> list.map(fn(value) { value.factor_return })
      |> exact.mean(request.definition.scale, mode)
      |> map_math
      |> result.map(Some)
  })
  let mean_ic = periods |> list.filter_map(fn(value) { float.parse(value.ic) })
  let ic_mean = case statistics.mean(mean_ic) {
    Ok(value) -> Some(float.to_string(value))
    Error(_) -> None
  }
  let turnover_values =
    list.filter_map(periods, fn(value) { value.turnover |> option_to_result })
  use turnover_mean <- result.try(case turnover_values {
    [] -> Ok(None)
    _ ->
      exact.mean(turnover_values, request.definition.scale, mode)
      |> map_math
      |> result.map(Some)
  })
  let fields = [
    #("schema", json.string("pi-sparkles/stock-factor-lab-result")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string("calculate")),
    #("binding", common.binding_json(binding)),
    #("definition", definition_json(request.definition)),
    #("periodCount", json.int(list.length(periods))),
    #("meanFactorReturn", json.nullable(mean_return, decimal_json)),
    #("cumulativeFactorReturn", json.nullable(cumulative_value, decimal_json)),
    #("icMean", json.nullable(ic_mean, json.string)),
    #("turnoverMean", json.nullable(turnover_mean, decimal_json)),
    #("periods", json.array(periods, period_json)),
    #(
      "orderedFormulas",
      json.array(
        [
          "eligible_t = member_t AND factor_known_by_cutoff_t AND forward_return_observed",
          "bucket_t = caller_bucket_count(sort(transformed_factor_value_t))",
          "bucket_return_t = caller_weighting(member_forward_returns_t)",
          "factor_return_t = caller_direction(top_bucket_return_t, bottom_bucket_return_t)",
          "IC_t = caller_selected_correlation(factor_value_t, forward_return_t)",
          "turnover_t = changed_bucket_members / prior_included_members",
        ],
        json.string,
      ),
    ),
    #("availableOperations", json.array(["calculate"], json.string)),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], json.string)),
    #(
      "limitations",
      json.array(
        [
          "the caller selects one factor definition, availability rule, buckets, direction, weighting, horizon, and survivorship policy",
          "late, missing, delisted, suspended, conflicting, and non-member rows remain explicit omissions",
          "no factor discovery, composite score, significance judgment, optimization, portfolio construction, recommendation, or deployability verdict is produced",
        ],
        json.string,
      ),
    ),
  ]
  Ok(common.response(
    "Factor study "
      <> request.definition.factor_id
      <> " | "
      <> int.to_string(list.length(periods))
      <> " point-in-time periods",
    common.content_bound(fields),
  ))
}

fn request_decoder() -> decode.Decoder(Request) {
  use binding <- decode.field("binding", common.binding_decoder())
  use definition <- decode.field("definition", definition_decoder())
  use periods <- decode.field("periods", decode.list(of: period_decoder()))
  decode.success(Request(binding, definition, periods))
}

fn definition_decoder() -> decode.Decoder(Definition) {
  use factor_id <- decode.field("factorId", decode.string)
  use source_field <- decode.field("sourceField", decode.string)
  use source_unit <- decode.field("sourceUnit", decode.string)
  use calculation <- decode.field("calculation", decode.string)
  use transformation <- decode.field("transformation", decode.string)
  use availability <- decode.field("availabilityRule", decode.string)
  use rebalance <- decode.field("rebalanceSchedule", decode.string)
  use weighting <- decode.field("weighting", decode.string)
  use buckets <- decode.field("bucketCount", decode.int)
  use direction <- decode.field("direction", decode.string)
  use horizon <- decode.field("returnHorizon", decode.string)
  use currency <- decode.field("currency", decode.string)
  use missing <- decode.field("missingPolicy", decode.string)
  use survivorship <- decode.field("survivorshipPolicy", decode.string)
  use ic <- decode.field("icMethod", decode.string)
  use scale <- decode.field("scale", decode.int)
  use rounding <- decode.field("rounding", decode.string)
  decode.success(Definition(
    factor_id,
    source_field,
    source_unit,
    calculation,
    transformation,
    availability,
    rebalance,
    weighting,
    buckets,
    direction,
    horizon,
    currency,
    missing,
    survivorship,
    ic,
    scale,
    rounding,
  ))
}

fn period_decoder() -> decode.Decoder(PeriodInput) {
  use period_id <- decode.field("periodId", decode.string)
  use at <- decode.field("atUnixMilliseconds", decode.int)
  use cutoff <- decode.field("knowledgeCutoffUnixMilliseconds", decode.int)
  use members <- decode.field("members", decode.list(of: member_decoder()))
  use receipt <- decode.field("rebalanceReceipt", decode.string)
  decode.success(PeriodInput(period_id, at, cutoff, members, receipt))
}

fn member_decoder() -> decode.Decoder(MemberInput) {
  use listing_id <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use observation_id <- decode.field("observationId", decode.string)
  use membership <- decode.field("membershipState", decode.string)
  use membership_receipt <- decode.field("membershipReceipt", decode.string)
  use factor <- decode.field("factor", fact_decoder())
  use forward_return <- decode.field("forwardReturn", fact_decoder())
  use weight <- decode.optional_field(
    "weight",
    None,
    decode.optional(decode.string),
  )
  use delisted <- decode.field("delisted", decode.bool)
  use suspended <- decode.field("suspended", decode.bool)
  decode.success(MemberInput(
    listing_id,
    mic,
    observation_id,
    membership,
    membership_receipt,
    factor,
    forward_return,
    weight,
    delisted,
    suspended,
  ))
}

fn fact_decoder() -> decode.Decoder(FactInput) {
  use state <- decode.field("state", decode.string)
  use raw <- decode.optional_field("raw", None, decode.optional(decode.string))
  use known_at <- decode.field("knownAtUnixMilliseconds", decode.int)
  use reason <- decode.optional_field(
    "reason",
    None,
    decode.optional(decode.string),
  )
  use alternatives <- decode.field(
    "alternatives",
    decode.list(of: decode.string),
  )
  use receipts <- decode.field("receipts", decode.list(of: decode.string))
  decode.success(FactInput(state, raw, known_at, reason, alternatives, receipts))
}

fn validate_definition(
  value: Definition,
  binding: common.Binding,
) -> Result(RoundingMode, Error) {
  use _ <- result.try(common.non_empty("definition.factorId", value.factor_id))
  use _ <- result.try(common.non_empty(
    "definition.sourceField",
    value.source_field,
  ))
  use _ <- result.try(common.non_empty(
    "definition.sourceUnit",
    value.source_unit,
  ))
  use _ <- result.try(common.non_empty(
    "definition.calculation",
    value.calculation,
  ))
  use _ <- result.try(common.non_empty(
    "definition.availabilityRule",
    value.availability_rule,
  ))
  use _ <- result.try(common.non_empty(
    "definition.rebalanceSchedule",
    value.rebalance_schedule,
  ))
  use _ <- result.try(common.non_empty(
    "definition.returnHorizon",
    value.return_horizon,
  ))
  use _ <- result.try(
    case list.contains(["raw_v1", "rank_v1"], value.transformation) {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "definition.transformation",
          "expected raw_v1 or rank_v1",
        ))
    },
  )
  use _ <- result.try(
    case list.contains(["equal_weight", "caller_weight"], value.weighting) {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "definition.weighting",
          "expected equal_weight or caller_weight",
        ))
    },
  )
  use _ <- result.try(case value.bucket_count >= 2 && value.bucket_count <= 20 {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "definition.bucketCount",
        "must be 2 through 20",
      ))
  })
  use _ <- result.try(
    case list.contains(["high_minus_low", "low_minus_high"], value.direction) {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "definition.direction",
          "expected high_minus_low or low_minus_high",
        ))
    },
  )
  use _ <- result.try(
    case
      list.contains(
        ["exclude_period_member", "retain_unperformed"],
        value.missing_policy,
      )
    {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "definition.missingPolicy",
          "unsupported explicit policy",
        ))
    },
  )
  use _ <- result.try(
    case
      list.contains(
        [
          "require_survival_to_horizon",
          "include_delisted_with_observed_return",
          "include_delisted_with_unknown_return",
        ],
        value.survivorship_policy,
      )
    {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "definition.survivorshipPolicy",
          "unsupported explicit policy",
        ))
    },
  )
  use _ <- result.try(case value.ic_method == "pearson_v1" {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "definition.icMethod",
        "first slice supports pearson_v1",
      ))
  })
  use _ <- result.try(case value.scale >= 0 && value.scale <= 18 {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField("definition.scale", "must be 0 through 18"))
  })
  use _ <- result.try(case currency_for_track(binding.track, value.currency) {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "definition.currency",
        "does not match declared local track currency",
      ))
  })
  rounding_mode(value.rounding)
}

fn calculate_periods(
  values: List(PeriodInput),
  definition: Definition,
  mode: RoundingMode,
  binding: common.Binding,
  previous: Option(PeriodResult),
  accumulated: List(PeriodResult),
) -> Result(List(PeriodResult), Error) {
  case values {
    [] -> Ok(list.reverse(accumulated))
    [value, ..rest] -> {
      use calculated <- result.try(calculate_period(
        value,
        definition,
        mode,
        binding,
        previous,
      ))
      calculate_periods(rest, definition, mode, binding, Some(calculated), [
        calculated,
        ..accumulated
      ])
    }
  }
}

fn calculate_period(
  input: PeriodInput,
  definition: Definition,
  mode: RoundingMode,
  binding: common.Binding,
  previous: Option(PeriodResult),
) -> Result(PeriodResult, Error) {
  use _ <- result.try(common.non_empty("periods[].periodId", input.period_id))
  use _ <- result.try(common.receipt(
    "periods[].rebalanceReceipt",
    input.rebalance_receipt,
  ))
  use _ <- result.try(
    case input.knowledge_cutoff_unix_ms <= binding.knowledge_cutoff_unix_ms {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "periods[].knowledgeCutoffUnixMilliseconds",
          "exceeds run binding cutoff",
        ))
    },
  )
  use _ <- result.try(common.bounded_count(
    "periods[].members",
    input.members,
    maximum_listings_per_period,
  ))
  use _ <- result.try(common.require_unique(
    "periods[].members[].listingId",
    list.map(input.members, fn(value) { value.listing_id <> ":" <> value.mic }),
  ))
  use prepared <- result.try(
    list.try_map(input.members, fn(value) {
      prepare_member(value, input, definition, binding)
    }),
  )
  let eligible =
    prepared
    |> list.filter_map(fn(value) {
      case value {
        Included(value) -> Ok(value)
        Omitted(_) -> Error(Nil)
      }
    })
    |> list.sort(compare_eligible)
  use _ <- result.try(case list.length(eligible) >= definition.bucket_count {
    True -> Ok(Nil)
    False ->
      Error(common.CalculationFailure(
        "period "
        <> input.period_id
        <> " has fewer eligible listings than buckets",
      ))
  })
  let ranked =
    eligible
    |> list.index_map(fn(value, index) {
      Eligible(
        ..value,
        rank: index + 1,
        bucket: index * definition.bucket_count / list.length(eligible) + 1,
      )
    })
  let members = merge_ranked(prepared, ranked)
  use buckets <- result.try(
    int.range(
      from: 1,
      to: definition.bucket_count + 1,
      with: [],
      run: fn(values, value) { list.append(values, [value]) },
    )
    |> list.try_map(fn(bucket) {
      calculate_bucket(bucket, ranked, definition, mode)
    }),
  )
  let assert Ok(low) = list.first(buckets)
  let assert Ok(high) = list.last(buckets)
  let factor_return = case definition.direction {
    "high_minus_low" -> decimal.subtract(high.return_value, low.return_value)
    _ -> decimal.subtract(low.return_value, high.return_value)
  }
  use ic <- result.try(calculate_ic(ranked))
  use turnover <- result.try(turnover(previous, ranked, definition.scale, mode))
  Ok(PeriodResult(input, members, buckets, factor_return, ic, turnover))
}

fn prepare_member(
  input: MemberInput,
  period: PeriodInput,
  definition: Definition,
  binding: common.Binding,
) -> Result(MemberResult, Error) {
  use _ <- result.try(common.non_empty(
    "periods[].members[].listingId",
    input.listing_id,
  ))
  use _ <- result.try(validate_mic(binding.track, input.mic))
  use _ <- result.try(common.non_empty(
    "periods[].members[].observationId",
    input.observation_id,
  ))
  use _ <- result.try(common.receipt(
    "periods[].members[].membershipReceipt",
    input.membership_receipt,
  ))
  use _ <- result.try(validate_fact(input.factor, "factor"))
  use _ <- result.try(validate_fact(input.forward_return, "forwardReturn"))
  use _ <- result.try(case manifest_contains(binding, input) {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "periods[].members[].observationId",
        "not bound to exact universe and dataset manifests",
      ))
  })
  case omission_reason(input, period, definition) {
    Some(reason) -> Ok(Omitted(Excluded(input, reason)))
    None -> {
      let assert Some(factor_raw) = input.factor.raw
      let assert Some(return_raw) = input.forward_return.raw
      let assert Ok(factor) = decimal.parse(factor_raw)
      let assert Ok(forward_return) = decimal.parse(return_raw)
      use weight <- result.try(case input.weight {
        None if definition.weighting == "equal_weight" -> Ok(None)
        Some(raw) if definition.weighting == "caller_weight" ->
          decimal.parse(raw)
          |> result.map(Some)
          |> result.map_error(fn(_) {
            common.InvalidField(
              "periods[].members[].weight",
              "expected exact decimal",
            )
          })
        _ ->
          Error(common.InvalidField(
            "periods[].members[].weight",
            "must be absent for equal_weight and present for caller_weight",
          ))
      })
      Ok(Included(Eligible(input, factor, forward_return, weight, 0, 0)))
    }
  }
}

fn validate_fact(value: FactInput, field: String) -> Result(Nil, Error) {
  use _ <- result.try(
    list.try_each(value.receipts, fn(receipt) {
      common.receipt("periods[].members[]." <> field <> ".receipts[]", receipt)
    }),
  )
  case value.state, value.raw, value.reason, value.alternatives {
    "known", Some(raw), None, [] ->
      decimal.parse(raw)
      |> result.map(fn(_) { Nil })
      |> result.map_error(fn(_) {
        common.InvalidField(field, "expected exact decimal")
      })
    "unknown", None, Some(_), [] | "not_obtained", None, Some(_), [] -> Ok(Nil)
    "conflicting", None, Some(_), alternatives if alternatives != [] -> Ok(Nil)
    _, _, _, _ ->
      Error(common.InvalidField(field, "fact fields do not match state"))
  }
}

fn omission_reason(
  input: MemberInput,
  period: PeriodInput,
  definition: Definition,
) -> Option(String) {
  case input.membership_state, input.factor.state, input.forward_return.state {
    "member", "known", "known" ->
      case input.factor.known_at_unix_ms > period.knowledge_cutoff_unix_ms {
        True -> Some("factor_known_after_cutoff")
        False ->
          case
            input.delisted
            && definition.survivorship_policy == "require_survival_to_horizon"
          {
            True -> Some("delisted_before_horizon_under_survival_policy")
            False ->
              case input.suspended {
                True -> Some("suspended_for_forward_horizon")
                False -> None
              }
          }
      }
    "not_member", _, _ -> Some("not_member_at_period")
    "unresolved", _, _ -> Some("membership_unresolved")
    _, state, _ if state != "known" -> Some("factor_" <> state)
    _, _, state -> Some("forward_return_" <> state)
  }
}

fn manifest_contains(binding: common.Binding, input: MemberInput) -> Bool {
  let universe_match =
    binding.universe
    |> manifest.universe_memberships
    |> list.any(fn(value) {
      value.listing_id == input.listing_id && value.mic == input.mic
    })
  let dataset_match =
    binding.dataset
    |> manifest.dataset_observations
    |> list.any(fn(value) {
      value.observation_id == input.observation_id
      && value.listing_id == input.listing_id
      && value.mic == input.mic
    })
  universe_match && dataset_match
}

fn calculate_bucket(
  bucket: Int,
  eligible: List(Eligible),
  definition: Definition,
  mode: RoundingMode,
) -> Result(BucketResult, Error) {
  let members = list.filter(eligible, fn(value) { value.bucket == bucket })
  use return_value <- result.try(case definition.weighting {
    "equal_weight" ->
      members
      |> list.map(fn(value) { value.forward_return })
      |> exact.mean(definition.scale, mode)
      |> map_math
    _ -> weighted_return(members, definition.scale, mode)
  })
  Ok(BucketResult(bucket, members, return_value))
}

fn weighted_return(
  values: List(Eligible),
  scale: Int,
  mode: RoundingMode,
) -> Result(Decimal, Error) {
  let weighted =
    list.map(values, fn(value) {
      let assert Some(weight) = value.weight
      decimal.multiply(value.forward_return, weight)
    })
  let weights =
    list.map(values, fn(value) {
      let assert Some(weight) = value.weight
      weight
    })
  exact.ratio(exact.sum(weighted), exact.sum(weights), scale, mode) |> map_math
}

fn calculate_ic(values: List(Eligible)) -> Result(String, Error) {
  let factors = list.map(values, fn(value) { decimal_float(value.factor) })
  let returns =
    list.map(values, fn(value) { decimal_float(value.forward_return) })
  statistics.correlation(factors, returns, statistics.Sample)
  |> map_math
  |> result.map(float.to_string)
}

fn turnover(
  previous: Option(PeriodResult),
  current: List(Eligible),
  scale: Int,
  mode: RoundingMode,
) -> Result(Option(Decimal), Error) {
  case previous {
    None -> Ok(None)
    Some(previous) -> {
      let prior =
        previous.members
        |> list.filter_map(fn(value) {
          case value {
            Included(value) -> Ok(value)
            Omitted(_) -> Error(Nil)
          }
        })
      let changed =
        prior
        |> list.filter(fn(value) {
          case find_eligible(current, value.input.listing_id, value.input.mic) {
            Some(current) -> current.bucket != value.bucket
            None -> True
          }
        })
        |> list.length
      let assert Ok(numerator) = changed |> int.to_string |> decimal.parse
      let assert Ok(denominator) =
        prior |> list.length |> int.to_string |> decimal.parse
      exact.ratio(numerator, denominator, scale, mode)
      |> map_math
      |> result.map(Some)
    }
  }
}

fn find_eligible(
  values: List(Eligible),
  listing_id: String,
  mic: String,
) -> Option(Eligible) {
  case values {
    [] -> None
    [value, ..rest] ->
      case value.input.listing_id == listing_id && value.input.mic == mic {
        True -> Some(value)
        False -> find_eligible(rest, listing_id, mic)
      }
  }
}

fn merge_ranked(
  original: List(MemberResult),
  ranked: List(Eligible),
) -> List(MemberResult) {
  list.map(original, fn(value) {
    case value {
      Omitted(_) -> value
      Included(eligible) ->
        case
          find_eligible(ranked, eligible.input.listing_id, eligible.input.mic)
        {
          Some(value) -> Included(value)
          None -> value
        }
    }
  })
}

fn compare_eligible(left: Eligible, right: Eligible) -> Order {
  decimal.compare(left.factor, right.factor)
}

fn validate_period_order(values: List(PeriodInput)) -> Result(Nil, Error) {
  case values {
    [] | [_] -> Ok(Nil)
    [left, right, ..rest] ->
      case left.at_unix_ms < right.at_unix_ms {
        True -> validate_period_order([right, ..rest])
        False ->
          Error(common.InvalidField(
            "periods",
            "atUnixMilliseconds must be strictly increasing",
          ))
      }
  }
}

fn period_series(
  values: List(PeriodResult),
) -> Result(series.Series(Decimal), Error) {
  use points <- result.try(
    list.try_map(values, fn(value) {
      use at <- result.try(
        time.instant(value.input.at_unix_ms)
        |> result.map_error(fn(_) {
          common.InvalidField(
            "periods[].atUnixMilliseconds",
            "outside supported instant range",
          )
        }),
      )
      Ok(#(at, value.factor_return))
    }),
  )
  series.from_present(points)
  |> result.map_error(fn(error) {
    common.CalculationFailure(
      "invalid factor-return series: " <> string.inspect(error),
    )
  })
}

fn validate_mic(track: finance_track.Track, mic: String) -> Result(Nil, Error) {
  let valid = case track {
    finance_track.Cn -> ["XSHG", "XSHE", "XBSE"]
    finance_track.Hk -> ["XHKG"]
    finance_track.Us -> ["XNYS", "XNAS"]
  }
  case list.contains(valid, mic) {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "periods[].members[].mic",
        "does not belong to declared track",
      ))
  }
}

fn currency_for_track(track: finance_track.Track, currency: String) -> Bool {
  case track, currency {
    finance_track.Cn, "CNY"
    | finance_track.Hk, "HKD"
    | finance_track.Us, "USD"
    -> True
    _, _ -> False
  }
}

fn rounding_mode(value: String) -> Result(RoundingMode, Error) {
  case value {
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    "half_up" -> Ok(decimal.HalfUp)
    "half_even" -> Ok(decimal.HalfEven)
    _ ->
      Error(common.InvalidField(
        "definition.rounding",
        "unsupported rounding mode",
      ))
  }
}

fn decimal_float(value: Decimal) -> Float {
  let text = decimal.to_string(value)
  let normalized = case string.contains(text, ".") {
    True -> text
    False -> text <> ".0"
  }
  let assert Ok(value) = float.parse(normalized)
  value
}

fn map_math(value: Result(value, error)) -> Result(value, Error) {
  value
  |> result.map_error(fn(error) {
    common.CalculationFailure(string.inspect(error))
  })
}

fn option_to_result(value: Option(value)) -> Result(value, Nil) {
  case value {
    Some(value) -> Ok(value)
    None -> Error(Nil)
  }
}

fn definition_json(value: Definition) -> json.Json {
  json.object([
    #("factorId", json.string(value.factor_id)),
    #("sourceField", json.string(value.source_field)),
    #("sourceUnit", json.string(value.source_unit)),
    #("calculation", json.string(value.calculation)),
    #("transformation", json.string(value.transformation)),
    #("availabilityRule", json.string(value.availability_rule)),
    #("rebalanceSchedule", json.string(value.rebalance_schedule)),
    #("weighting", json.string(value.weighting)),
    #("bucketCount", json.int(value.bucket_count)),
    #("direction", json.string(value.direction)),
    #("returnHorizon", json.string(value.return_horizon)),
    #("currency", json.string(value.currency)),
    #("missingPolicy", json.string(value.missing_policy)),
    #("survivorshipPolicy", json.string(value.survivorship_policy)),
    #("icMethod", json.string(value.ic_method)),
    #("scale", json.int(value.scale)),
    #("rounding", json.string(value.rounding)),
  ])
}

fn period_json(value: PeriodResult) -> json.Json {
  json.object([
    #("periodId", json.string(value.input.period_id)),
    #("atUnixMilliseconds", json.int(value.input.at_unix_ms)),
    #(
      "knowledgeCutoffUnixMilliseconds",
      json.int(value.input.knowledge_cutoff_unix_ms),
    ),
    #("rebalanceReceipt", json.string(value.input.rebalance_receipt)),
    #("factorReturn", decimal_json(value.factor_return)),
    #("ic", json.string(value.ic)),
    #("turnover", json.nullable(value.turnover, decimal_json)),
    #("members", json.array(value.members, member_result_json)),
    #("buckets", json.array(value.buckets, bucket_json)),
  ])
}

fn member_result_json(value: MemberResult) -> json.Json {
  case value {
    Omitted(value) ->
      member_common_json(value.input, [
        #("state", json.string("omitted")),
        #("reason", json.string(value.reason)),
      ])
    Included(value) ->
      member_common_json(value.input, [
        #("state", json.string("included")),
        #("factorRaw", decimal_json(value.factor)),
        #("forwardReturn", decimal_json(value.forward_return)),
        #("rank", json.int(value.rank)),
        #("bucket", json.int(value.bucket)),
      ])
  }
}

fn member_common_json(
  value: MemberInput,
  extra: List(#(String, json.Json)),
) -> json.Json {
  json.object(list.append(
    [
      #("listingId", json.string(value.listing_id)),
      #("mic", json.string(value.mic)),
      #("observationId", json.string(value.observation_id)),
      #("membershipState", json.string(value.membership_state)),
      #("membershipReceipt", json.string(value.membership_receipt)),
      #("delisted", json.bool(value.delisted)),
      #("suspended", json.bool(value.suspended)),
      #("factorReceipts", json.array(value.factor.receipts, json.string)),
      #(
        "forwardReturnReceipts",
        json.array(value.forward_return.receipts, json.string),
      ),
    ],
    extra,
  ))
}

fn bucket_json(value: BucketResult) -> json.Json {
  json.object([
    #("bucket", json.int(value.bucket)),
    #("memberCount", json.int(list.length(value.members))),
    #("return", decimal_json(value.return_value)),
    #(
      "listingIds",
      json.array(
        list.map(value.members, fn(value) { value.input.listing_id }),
        json.string,
      ),
    ),
  ])
}

fn decimal_json(value: Decimal) -> json.Json {
  json.string(decimal.to_string(value))
}
