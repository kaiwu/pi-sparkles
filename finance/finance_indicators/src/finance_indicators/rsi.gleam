import finance_core/decimal.{type Decimal}
import finance_core/time.{type Date}
import finance_indicators/calculation.{type CalculationError, type Output}
import finance_indicators/input.{type PriceSlot}
import finance_indicators/model.{type GapPolicy, type Request}
import finance_indicators/numeric
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result

type State {
  Seeding(
    previous_close: Option(Decimal),
    closes_reversed: List(String),
    gains_reversed: List(Decimal),
    losses_reversed: List(Decimal),
  )
  Running(previous_close: Decimal, average_gain: Decimal, average_loss: Decimal)
  Stopped(reason: String)
}

pub fn calculate(
  request request_value: Request,
  inputs slots: List(PriceSlot),
) -> Result(calculation.ResultData, CalculationError) {
  case model.calculation(request_value) {
    model.WilderRsiV1(period, model.SlotWindowV1, gap_policy, convention) -> {
      use _ <- result.try(validate_slots(request_value, slots))
      use computed <- result.try(
        loop(
          request_value,
          slots,
          period,
          gap_policy,
          convention,
          Seeding(None, [], [], []),
          [],
          [],
        ),
      )
      let #(outputs, seed_inputs) = computed
      Ok(
        calculation.ResultData(
          "rsi_wilder_v1",
          "rsi_wilder_v1",
          calculation.Known("seed_wilder_first_n"),
          case seed_inputs {
            [] -> calculation.Unknown("no seed completed")
            values -> calculation.Known(values)
          },
          input.PriceInputs(slots),
          outputs,
          [
            "drill_full_series",
            "drill_intermediate_values",
            "drill_unperformed_dates",
            "drill_parameters",
            "request_zero_zero_convention",
          ],
        ),
      )
    }
    other ->
      Error(calculation.RequestCalculationMismatch(
        "rsi_wilder_v1",
        model.calculation_id(other),
      ))
  }
}

fn loop(
  request: Request,
  remaining: List(PriceSlot),
  period: Int,
  gap_policy: GapPolicy,
  convention: model.RsiZeroZeroConvention,
  state: State,
  outputs_reversed: List(Output),
  seed_inputs_reversed: List(String),
) -> Result(#(List(Output), List(String)), CalculationError) {
  case remaining {
    [] ->
      Ok(#(list.reverse(outputs_reversed), list.reverse(seed_inputs_reversed)))
    [input.PriceSlot(date, fact), ..rest] ->
      case state {
        Stopped(reason) ->
          loop(
            request,
            rest,
            period,
            gap_policy,
            convention,
            state,
            [
              calculation.Unperformed(
                date,
                calculation.StoppedAfterGap(reason),
                [model.input_field(model.request_context(request))],
              ),
              ..outputs_reversed
            ],
            seed_inputs_reversed,
          )
        _ ->
          case input.usable(fact, model.parseable_policy(request)) {
            Error(reason) -> {
              let reason_name = input.unavailable_name(reason)
              let next_state = case gap_policy {
                model.StopAtGapV1 -> Stopped(reason_name)
                model.RestartSeedAfterGapV1 -> Seeding(None, [], [], [])
              }
              loop(
                request,
                rest,
                period,
                gap_policy,
                convention,
                next_state,
                [
                  calculation.Unperformed(
                    date,
                    calculation.InputUnavailable([reason_name]),
                    [model.input_field(model.request_context(request))],
                  ),
                  ..outputs_reversed
                ],
                seed_inputs_reversed,
              )
            }
            Ok(close) ->
              advance(
                request,
                rest,
                date,
                close,
                period,
                gap_policy,
                convention,
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
  rest: List(PriceSlot),
  date: Date,
  close: Decimal,
  period: Int,
  gap_policy: GapPolicy,
  convention: model.RsiZeroZeroConvention,
  state: State,
  outputs_reversed: List(Output),
  seed_inputs_reversed: List(String),
) -> Result(#(List(Output), List(String)), CalculationError) {
  case state {
    Stopped(_) -> panic as "stopped state is handled before advance"
    Seeding(None, _, _, _) ->
      loop(
        request,
        rest,
        period,
        gap_policy,
        convention,
        Seeding(Some(close), [decimal.to_string(close)], [], []),
        [
          calculation.Unperformed(
            date,
            calculation.InsufficientInputs(0, period),
            [],
          ),
          ..outputs_reversed
        ],
        seed_inputs_reversed,
      )
    Seeding(Some(previous), closes, gains, losses) -> {
      let delta = decimal.subtract(close, previous)
      let #(gain, loss) = gain_and_loss(delta)
      let gains = [gain, ..gains]
      let losses = [loss, ..losses]
      let closes = [decimal.to_string(close), ..closes]
      let count = list.length(gains)
      case count < period {
        True ->
          loop(
            request,
            rest,
            period,
            gap_policy,
            convention,
            Seeding(Some(close), closes, gains, losses),
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
          use average_gain <- result.try(
            arithmetic(numeric.mean(
              list.reverse(gains),
              model.intermediate_scale(model.rounding(request)),
              model.rounding_mode(model.rounding(request)),
            )),
          )
          use average_loss <- result.try(
            arithmetic(numeric.mean(
              list.reverse(losses),
              model.intermediate_scale(model.rounding(request)),
              model.rounding_mode(model.rounding(request)),
            )),
          )
          use output <- result.try(rsi_output(
            request,
            date,
            average_gain,
            average_loss,
            convention,
          ))
          loop(
            request,
            rest,
            period,
            gap_policy,
            convention,
            Running(close, average_gain, average_loss),
            [output, ..outputs_reversed],
            list.append(list.reverse(closes), seed_inputs_reversed),
          )
        }
      }
    }
    Running(previous, average_gain, average_loss) -> {
      let delta = decimal.subtract(close, previous)
      let #(gain, loss) = gain_and_loss(delta)
      let n_minus_one = numeric.from_int(period - 1)
      let numerator_gain =
        average_gain |> decimal.multiply(n_minus_one) |> decimal.add(gain)
      let numerator_loss =
        average_loss |> decimal.multiply(n_minus_one) |> decimal.add(loss)
      use next_gain <- result.try(
        arithmetic(numeric.ratio(
          numerator_gain,
          numeric.from_int(period),
          model.intermediate_scale(model.rounding(request)),
          model.rounding_mode(model.rounding(request)),
        )),
      )
      use next_loss <- result.try(
        arithmetic(numeric.ratio(
          numerator_loss,
          numeric.from_int(period),
          model.intermediate_scale(model.rounding(request)),
          model.rounding_mode(model.rounding(request)),
        )),
      )
      use output <- result.try(rsi_output(
        request,
        date,
        next_gain,
        next_loss,
        convention,
      ))
      loop(
        request,
        rest,
        period,
        gap_policy,
        convention,
        Running(close, next_gain, next_loss),
        [output, ..outputs_reversed],
        seed_inputs_reversed,
      )
    }
  }
}

fn rsi_output(
  request: Request,
  date: Date,
  average_gain: Decimal,
  average_loss: Decimal,
  convention: model.RsiZeroZeroConvention,
) -> Result(Output, CalculationError) {
  let rounding = model.rounding(request)
  let zero_gain = numeric.is_zero(average_gain)
  let zero_loss = numeric.is_zero(average_loss)
  case zero_gain, zero_loss, convention {
    True, True, model.ZeroZeroUnperformedV1 ->
      Ok(
        calculation.Unperformed(date, calculation.ZeroGainAndLoss, [
          "average_gain",
          "average_loss",
        ]),
      )
    True, True, model.ZeroZeroValueV1(value) ->
      calculated_rsi(
        request,
        date,
        value,
        average_gain,
        average_loss,
        "zero_zero_convention",
      )
    _, True, _ ->
      calculated_rsi(
        request,
        date,
        numeric.from_int(100),
        average_gain,
        average_loss,
        "rsi_no_loss_convention_v1",
      )
    True, False, _ ->
      calculated_rsi(
        request,
        date,
        decimal.zero(),
        average_gain,
        average_loss,
        "rsi_no_gain_convention_v1",
      )
    False, False, _ -> {
      use relative_strength <- result.try(
        arithmetic(numeric.ratio(
          average_gain,
          average_loss,
          model.intermediate_scale(rounding),
          model.rounding_mode(rounding),
        )),
      )
      use complement <- result.try(
        arithmetic(numeric.ratio(
          numeric.from_int(100),
          decimal.add(numeric.from_int(1), relative_strength),
          model.intermediate_scale(rounding),
          model.rounding_mode(rounding),
        )),
      )
      calculated_rsi(
        request,
        date,
        decimal.subtract(numeric.from_int(100), complement),
        average_gain,
        average_loss,
        "formula",
      )
    }
  }
}

fn calculated_rsi(
  request: Request,
  date: Date,
  value: Decimal,
  average_gain: Decimal,
  average_loss: Decimal,
  applied: String,
) -> Result(Output, CalculationError) {
  let rounding = model.rounding(request)
  use output_value <- result.try(
    arithmetic(numeric.formatted(
      value,
      model.output_scale(rounding),
      model.rounding_mode(rounding),
    )),
  )
  Ok(
    calculation.Calculated(date, output_value, "dimensionless_0_100", [
      calculation.Intermediate(
        "average_gain",
        numeric.formatted_exact(
          average_gain,
          model.intermediate_scale(rounding),
        ),
      ),
      calculation.Intermediate(
        "average_loss",
        numeric.formatted_exact(
          average_loss,
          model.intermediate_scale(rounding),
        ),
      ),
      calculation.Intermediate("applied", applied),
    ]),
  )
}

fn gain_and_loss(delta: Decimal) -> #(Decimal, Decimal) {
  case decimal.compare(delta, decimal.zero()) {
    Lt -> #(decimal.zero(), decimal.negate(delta))
    Eq | Gt -> #(delta, decimal.zero())
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
  slots: List(PriceSlot),
) -> Result(Nil, CalculationError) {
  case input.validate_price_slots(slots) {
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
