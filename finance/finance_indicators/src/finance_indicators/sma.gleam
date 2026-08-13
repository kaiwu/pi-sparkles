import finance_core/decimal
import finance_indicators/calculation.{type CalculationError, type Output}
import finance_indicators/input.{type PriceSlot}
import finance_indicators/model.{type Request}
import finance_indicators/numeric
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

type WindowEntry {
  WindowEntry(
    slot: PriceSlot,
    usable: Result(decimal.Decimal, input.Unavailable),
  )
}

type Window {
  Window(
    front: List(WindowEntry),
    back: List(WindowEntry),
    size: Int,
    sum: decimal.Decimal,
    unavailable_count: Int,
  )
}

pub fn calculate(
  request request_value: Request,
  inputs slots: List(PriceSlot),
) -> Result(calculation.ResultData, CalculationError) {
  let spec = model.calculation(request_value)
  case spec {
    model.SmaV1(period, model.SlotWindowV1) -> {
      use _ <- result.try(validate_slots(request_value, slots))
      use outputs <- result.try(
        calculate_outputs(request_value, slots, period, empty_window(), []),
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
  window: Window,
  outputs_reversed: List(Output),
) -> Result(List(Output), CalculationError) {
  case remaining {
    [] -> Ok(list.reverse(outputs_reversed))
    [slot, ..rest] -> {
      let usable = input.usable(slot.value, model.parseable_policy(request))
      let window = push_window(window, WindowEntry(slot, usable), period)
      use output <- result.try(output_for(request, slot, usable, window, period))
      calculate_outputs(request, rest, period, window, [
        output,
        ..outputs_reversed
      ])
    }
  }
}

fn output_for(
  request: Request,
  slot: PriceSlot,
  current: Result(decimal.Decimal, input.Unavailable),
  window: Window,
  period: Int,
) -> Result(Output, CalculationError) {
  let input.PriceSlot(date, _) = slot
  case current {
    Error(reason) ->
      Ok(
        calculation.Unperformed(
          date,
          calculation.InputUnavailable([input.unavailable_name(reason)]),
          [model.input_field(model.request_context(request))],
        ),
      )
    Ok(_) ->
      case window.size < period {
        True ->
          Ok(
            calculation.Unperformed(
              date,
              calculation.InsufficientInputs(window.size, period),
              [],
            ),
          )
        False ->
          case first_unavailable(window) {
            Some(reason) ->
              Ok(
                calculation.Unperformed(
                  date,
                  calculation.InputUnavailable([input.unavailable_name(reason)]),
                  [model.input_field(model.request_context(request))],
                ),
              )
            None -> {
              let rounding = model.rounding(request)
              case
                numeric.ratio(
                  window.sum,
                  numeric.from_int(period),
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
                              decimal.to_string(window.sum),
                            ),
                            calculation.Intermediate(
                              "count",
                              period |> int.to_string,
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

fn empty_window() -> Window {
  Window([], [], 0, decimal.zero(), 0)
}

fn push_window(window: Window, entry: WindowEntry, maximum: Int) -> Window {
  let #(sum, unavailable_count) = case entry.usable {
    Ok(value) -> #(decimal.add(window.sum, value), window.unavailable_count)
    Error(_) -> #(window.sum, window.unavailable_count + 1)
  }
  let grown =
    Window(
      ..window,
      back: [entry, ..window.back],
      size: window.size + 1,
      sum: sum,
      unavailable_count: unavailable_count,
    )
  case grown.size > maximum {
    True -> drop_oldest(grown)
    False -> grown
  }
}

fn drop_oldest(window: Window) -> Window {
  case window.front {
    [entry, ..rest] -> remove_entry(Window(..window, front: rest), entry)
    [] ->
      case list.reverse(window.back) {
        [entry, ..rest] ->
          remove_entry(Window(..window, front: rest, back: []), entry)
        [] -> window
      }
  }
}

fn remove_entry(window: Window, entry: WindowEntry) -> Window {
  case entry.usable {
    Ok(value) ->
      Window(
        ..window,
        size: window.size - 1,
        sum: decimal.subtract(window.sum, value),
      )
    Error(_) ->
      Window(
        ..window,
        size: window.size - 1,
        unavailable_count: window.unavailable_count - 1,
      )
  }
}

fn first_unavailable(window: Window) -> Option(input.Unavailable) {
  case window.unavailable_count {
    0 -> None
    _ ->
      case unavailable_in(window.front) {
        Some(reason) -> Some(reason)
        None -> unavailable_in(list.reverse(window.back))
      }
  }
}

fn unavailable_in(entries: List(WindowEntry)) -> Option(input.Unavailable) {
  case entries {
    [] -> None
    [entry, ..rest] ->
      case entry.usable {
        Error(reason) -> Some(reason)
        Ok(_) -> unavailable_in(rest)
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
