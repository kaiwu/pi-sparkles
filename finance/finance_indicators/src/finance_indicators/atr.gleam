import finance_core/decimal.{type Decimal}
import finance_core/time.{type Date}
import finance_indicators/calculation.{type CalculationError, type Output}
import finance_indicators/input.{type BarSlot, type NumericFact}
import finance_indicators/model.{type GapPolicy, type Request}
import finance_indicators/numeric
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

type State {
  Seeding(previous_close: Option(Decimal), true_ranges_reversed: List(Decimal))
  Running(previous_close: Decimal, average_true_range: Decimal)
  Stopped(reason: String)
}

type BarValues {
  BarValues(high: Decimal, low: Decimal, close: Decimal)
}

type TrueRange {
  TrueRange(
    value: Decimal,
    high_low: Decimal,
    high_previous_close: Option(Decimal),
    low_previous_close: Option(Decimal),
  )
}

pub fn calculate(
  request request_value: Request,
  inputs slots: List(BarSlot),
) -> Result(calculation.ResultData, CalculationError) {
  case model.calculation(request_value) {
    model.WilderAtrV1(period, model.SlotWindowV1, gap_policy) -> {
      use _ <- result.try(validate_slots(request_value, slots))
      use computed <- result.try(
        loop(
          request_value,
          slots,
          period,
          gap_policy,
          Seeding(None, []),
          [],
          [],
        ),
      )
      let #(outputs, seed_inputs) = computed
      Ok(
        calculation.ResultData(
          "atr_wilder_v1",
          "atr_wilder_v1",
          calculation.Known("seed_wilder_tr_mean_v1"),
          case seed_inputs {
            [] -> calculation.Unknown("no seed completed")
            values -> calculation.Known(values)
          },
          input.BarInputs(slots),
          outputs,
          [
            "drill_full_series",
            "drill_true_range_components",
            "drill_unperformed_dates",
            "drill_parameters",
          ],
        ),
      )
    }
    other ->
      Error(calculation.RequestCalculationMismatch(
        "atr_wilder_v1",
        model.calculation_id(other),
      ))
  }
}

fn loop(
  request: Request,
  remaining: List(BarSlot),
  period: Int,
  gap_policy: GapPolicy,
  state: State,
  outputs_reversed: List(Output),
  seed_inputs_reversed: List(String),
) -> Result(#(List(Output), List(String)), CalculationError) {
  case remaining {
    [] ->
      Ok(#(list.reverse(outputs_reversed), list.reverse(seed_inputs_reversed)))
    [input.BarSlot(date, high, low, close), ..rest] ->
      case state {
        Stopped(reason) ->
          loop(
            request,
            rest,
            period,
            gap_policy,
            state,
            [
              calculation.Unperformed(
                date,
                calculation.StoppedAfterGap(reason),
                ["high", "low", "close"],
              ),
              ..outputs_reversed
            ],
            seed_inputs_reversed,
          )
        _ ->
          case bar_values(request, high, low, close) {
            Error(details) -> {
              let reason =
                list.first(details) |> result.unwrap("input_unavailable")
              let next_state = case gap_policy {
                model.StopAtGapV1 -> Stopped(reason)
                model.RestartSeedAfterGapV1 -> Seeding(None, [])
              }
              loop(
                request,
                rest,
                period,
                gap_policy,
                next_state,
                [
                  calculation.Unperformed(
                    date,
                    calculation.InputUnavailable(details),
                    ["high", "low", "close"],
                  ),
                  ..outputs_reversed
                ],
                seed_inputs_reversed,
              )
            }
            Ok(values) ->
              advance(
                request,
                rest,
                date,
                values,
                period,
                gap_policy,
                state,
                outputs_reversed,
                seed_inputs_reversed,
              )
          }
      }
  }
}

fn advance(
  request: Request,
  rest: List(BarSlot),
  date: Date,
  values: BarValues,
  period: Int,
  gap_policy: GapPolicy,
  state: State,
  outputs_reversed: List(Output),
  seed_inputs_reversed: List(String),
) -> Result(#(List(Output), List(String)), CalculationError) {
  let previous_close = case state {
    Seeding(previous, _) -> previous
    Running(previous, _) -> Some(previous)
    Stopped(_) -> None
  }
  let tr = true_range(values, previous_close)
  case state {
    Stopped(_) -> panic as "stopped state is handled before advance"
    Seeding(_, ranges) -> {
      let ranges = [tr.value, ..ranges]
      let count = list.length(ranges)
      case count < period {
        True ->
          loop(
            request,
            rest,
            period,
            gap_policy,
            Seeding(Some(values.close), ranges),
            [
              calculation.Unperformed(
                date,
                calculation.InsufficientInputs(count, period),
                [],
              ),
              ..outputs_reversed
            ],
            seed_inputs_reversed,
          )
        False -> {
          use average <- result.try(
            arithmetic(numeric.mean(
              list.reverse(ranges),
              model.intermediate_scale(model.rounding(request)),
              model.rounding_mode(model.rounding(request)),
            )),
          )
          use output <- result.try(atr_output(request, date, average, tr))
          let seeds =
            ranges
            |> list.reverse
            |> list.map(decimal.to_string)
          loop(
            request,
            rest,
            period,
            gap_policy,
            Running(values.close, average),
            [output, ..outputs_reversed],
            list.append(seeds, seed_inputs_reversed),
          )
        }
      }
    }
    Running(_, average) -> {
      let numerator =
        average
        |> decimal.multiply(numeric.from_int(period - 1))
        |> decimal.add(tr.value)
      use next <- result.try(
        arithmetic(numeric.ratio(
          numerator,
          numeric.from_int(period),
          model.intermediate_scale(model.rounding(request)),
          model.rounding_mode(model.rounding(request)),
        )),
      )
      use output <- result.try(atr_output(request, date, next, tr))
      loop(
        request,
        rest,
        period,
        gap_policy,
        Running(values.close, next),
        [output, ..outputs_reversed],
        seed_inputs_reversed,
      )
    }
  }
}

fn bar_values(
  request: Request,
  high: NumericFact,
  low: NumericFact,
  close: NumericFact,
) -> Result(BarValues, List(String)) {
  let policy = model.parseable_policy(request)
  case
    input.usable(high, policy),
    input.usable(low, policy),
    input.usable(close, policy)
  {
    Ok(high), Ok(low), Ok(close) -> Ok(BarValues(high, low, close))
    high, low, close ->
      Error(
        list.flatten([
          unavailable("high", high),
          unavailable("low", low),
          unavailable("close", close),
        ]),
      )
  }
}

fn unavailable(
  name: String,
  value: Result(Decimal, input.Unavailable),
) -> List(String) {
  case value {
    Ok(_) -> []
    Error(reason) -> [name <> ":" <> input.unavailable_name(reason)]
  }
}

fn true_range(values: BarValues, previous: Option(Decimal)) -> TrueRange {
  let high_low = decimal.subtract(values.high, values.low)
  case previous {
    None -> TrueRange(high_low, high_low, None, None)
    Some(previous) -> {
      let high_previous =
        decimal.subtract(values.high, previous) |> numeric.absolute
      let low_previous =
        decimal.subtract(values.low, previous) |> numeric.absolute
      TrueRange(
        numeric.maximum(high_low, [high_previous, low_previous]),
        high_low,
        Some(high_previous),
        Some(low_previous),
      )
    }
  }
}

fn atr_output(
  request: Request,
  date: Date,
  average: Decimal,
  tr: TrueRange,
) -> Result(Output, CalculationError) {
  let rounding = model.rounding(request)
  use output_value <- result.try(
    arithmetic(numeric.formatted(
      average,
      model.output_scale(rounding),
      model.rounding_mode(rounding),
    )),
  )
  Ok(
    calculation.Calculated(
      date,
      output_value,
      model.unit_name(model.input_unit(model.request_context(request))),
      [
        calculation.Intermediate("true_range", decimal.to_string(tr.value)),
        calculation.Intermediate("high_low", decimal.to_string(tr.high_low)),
        calculation.Intermediate(
          "high_previous_close",
          optional_decimal(tr.high_previous_close),
        ),
        calculation.Intermediate(
          "low_previous_close",
          optional_decimal(tr.low_previous_close),
        ),
      ],
    ),
  )
}

fn optional_decimal(value: Option(Decimal)) -> String {
  case value {
    None -> "not_applicable:no_previous_close"
    Some(value) -> decimal.to_string(value)
  }
}

fn arithmetic(value: Result(value, String)) -> Result(value, CalculationError) {
  case value {
    Ok(value) -> Ok(value)
    Error(reason) -> Error(calculation.ArithmeticFailure(reason))
  }
}

fn validate_slots(
  request: Request,
  slots: List(BarSlot),
) -> Result(Nil, CalculationError) {
  case input.validate_bar_slots(slots) {
    Error(_) -> Error(calculation.InvalidInputOrder)
    Ok(_) ->
      case
        list.all(slots, fn(slot) {
          model.date_key(slot.date)
          >= model.date_key(model.date_start(model.request_context(request)))
          && model.date_key(slot.date)
          <= model.date_key(model.date_end(model.request_context(request)))
        })
      {
        True -> Ok(Nil)
        False -> Error(calculation.InputOutsideRequestedRange)
      }
  }
}
