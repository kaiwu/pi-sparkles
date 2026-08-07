import finance_core/decimal
import finance_indicators/calculation.{type CalculationError, type Output}
import finance_indicators/input.{type PriceSlot}
import finance_indicators/model.{type Request}
import finance_indicators/numeric
import finance_math/exact
import gleam/int
import gleam/list
import gleam/result

pub fn calculate(
  request request_value: Request,
  inputs slots: List(PriceSlot),
) -> Result(calculation.ResultData, CalculationError) {
  let spec = model.calculation(request_value)
  case spec {
    model.SmaV1(period, model.SlotWindowV1) -> {
      use _ <- result.try(validate_slots(request_value, slots))
      use outputs <- result.try(
        calculate_outputs(request_value, slots, period, [], []),
      )
      Ok(
        calculation.ResultData(
          "sma_v1",
          "sma_v1",
          calculation.NotApplicable("non-recursive formula"),
          calculation.NotApplicable("non-recursive formula"),
          input.PriceInputs(slots),
          outputs,
          [
            "drill_full_series",
            "drill_intermediate_values",
            "drill_unperformed_dates",
            "drill_parameters",
          ],
        ),
      )
    }
    other ->
      Error(calculation.RequestCalculationMismatch(
        "sma_v1",
        model.calculation_id(other),
      ))
  }
}

fn calculate_outputs(
  request: Request,
  remaining: List(PriceSlot),
  period: Int,
  seen: List(PriceSlot),
  outputs_reversed: List(Output),
) -> Result(List(Output), CalculationError) {
  case remaining {
    [] -> Ok(list.reverse(outputs_reversed))
    [slot, ..rest] -> {
      let seen = list.append(seen, [slot])
      let window =
        seen
        |> list.drop(int.max(list.length(seen) - period, 0))
      use output <- result.try(output_for(request, slot, window, period))
      calculate_outputs(request, rest, period, seen, [
        output,
        ..outputs_reversed
      ])
    }
  }
}

fn output_for(
  request: Request,
  slot: PriceSlot,
  window: List(PriceSlot),
  period: Int,
) -> Result(Output, CalculationError) {
  let input.PriceSlot(date, current) = slot
  case input.usable(current, model.parseable_policy(request)) {
    Error(reason) ->
      Ok(
        calculation.Unperformed(
          date,
          calculation.InputUnavailable([input.unavailable_name(reason)]),
          [model.input_field(model.request_context(request))],
        ),
      )
    Ok(_) ->
      case list.length(window) < period {
        True ->
          Ok(
            calculation.Unperformed(
              date,
              calculation.InsufficientInputs(list.length(window), period),
              [],
            ),
          )
        False ->
          case
            list.try_map(window, fn(value) {
              input.usable(value.value, model.parseable_policy(request))
            })
          {
            Error(reason) ->
              Ok(
                calculation.Unperformed(
                  date,
                  calculation.InputUnavailable([input.unavailable_name(reason)]),
                  [model.input_field(model.request_context(request))],
                ),
              )
            Ok(values) -> {
              let rounding = model.rounding(request)
              case
                numeric.mean(
                  values,
                  model.intermediate_scale(rounding),
                  model.rounding_mode(rounding),
                )
              {
                Error(reason) -> Error(calculation.ArithmeticFailure(reason))
                Ok(mean) ->
                  case
                    numeric.formatted(
                      mean,
                      model.output_scale(rounding),
                      model.rounding_mode(rounding),
                    )
                  {
                    Error(reason) ->
                      Error(calculation.ArithmeticFailure(reason))
                    Ok(value) ->
                      Ok(
                        calculation.Calculated(
                          date,
                          value,
                          model.unit_name(
                            model.input_unit(model.request_context(request)),
                          ),
                          [
                            calculation.Intermediate(
                              "sum",
                              values |> exact.sum |> decimal.to_string,
                            ),
                            calculation.Intermediate(
                              "count",
                              list.length(values) |> int.to_string,
                            ),
                          ],
                        ),
                      )
                  }
              }
            }
          }
      }
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
