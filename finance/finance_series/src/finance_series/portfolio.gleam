import finance_core/observation
import finance_core/time.{type Instant}
import finance_series/series.{type Series}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Component {
  Component(id: String, weight: Float, returns: Series(Float))
}

pub type DynamicComponent {
  DynamicComponent(id: String, weights: Series(Float), returns: Series(Float))
}

pub type ComponentContribution {
  ComponentContribution(id: String, contributions: Series(Float))
}

pub type Attribution {
  Attribution(
    total_return: Series(Float),
    components: List(ComponentContribution),
  )
}

pub type MissingConstituentPolicy {
  RequireAll
  RenormalizeAvailable
}

pub type PortfolioError {
  EmptyPortfolio
  InvalidComponentId
  DuplicateComponent(id: String)
  InvalidTolerance
  WeightsDoNotSum(total: Float)
  WeightsDoNotSumAt(at: Instant, total: Float)
}

type AttributionRow {
  AttributionRow(
    at: Instant,
    total: series.Datum(Float),
    contributions: List(series.Datum(Float)),
  )
}

/// Aggregate fixed-weight component return series on their full union timeline.
///
/// `RequireAll` emits an explicit missing datum whenever any constituent is
/// absent or missing. `RenormalizeAvailable` is opt-in and divides by the net
/// available weight; a zero available weight remains missing.
pub fn weighted_returns(
  components: List(Component),
  missing missing_policy: MissingConstituentPolicy,
  weight_tolerance weight_tolerance: Float,
) -> Result(Series(Float), PortfolioError) {
  case validate(components, weight_tolerance, []) {
    Error(error) -> Error(error)
    Ok(Nil) -> {
      let points =
        components
        |> timestamps
        |> list.map(fn(at) {
          series.Point(
            at,
            aggregate_at(components, at, missing_policy, weight_tolerance),
          )
        })
      let assert Ok(result) = series.new(points)
      Ok(result)
    }
  }
}

/// Aggregate time-varying beginning-period weights and return each component's
/// arithmetic contribution alongside the total return.
pub fn dynamic_attribution(
  components: List(DynamicComponent),
  missing missing_policy: MissingConstituentPolicy,
  weight_tolerance weight_tolerance: Float,
) -> Result(Attribution, PortfolioError) {
  case validate_dynamic(components, weight_tolerance, []) {
    Error(error) -> Error(error)
    Ok(Nil) -> {
      let rows =
        components
        |> dynamic_timestamps
        |> calculate_rows(components, missing_policy, weight_tolerance, [])
      case rows {
        Error(error) -> Error(error)
        Ok(rows) -> {
          let total_points =
            list.map(rows, fn(row) { series.Point(row.at, row.total) })
          let assert Ok(total) = series.new(total_points)
          let contributions =
            components
            |> list.index_map(fn(component, index) {
              let points =
                list.map(rows, fn(row) {
                  series.Point(row.at, datum_at(row.contributions, index))
                })
              let assert Ok(values) = series.new(points)
              ComponentContribution(component.id, values)
            })
          Ok(Attribution(total, contributions))
        }
      }
    }
  }
}

fn validate(
  components: List(Component),
  tolerance: Float,
  ids: List(String),
) -> Result(Nil, PortfolioError) {
  case components, tolerance >. 0.0 {
    [], _ -> Error(EmptyPortfolio)
    _, False -> Error(InvalidTolerance)
    _, True -> {
      let total =
        components |> list.map(fn(component) { component.weight }) |> float.sum
      case float.absolute_value(total -. 1.0) <=. tolerance {
        False -> Error(WeightsDoNotSum(total))
        True -> validate_ids(components, ids)
      }
    }
  }
}

fn validate_ids(
  components: List(Component),
  ids: List(String),
) -> Result(Nil, PortfolioError) {
  case components {
    [] -> Ok(Nil)
    [component, ..rest] ->
      case
        component.id == "" || string.trim(component.id) != component.id,
        list.contains(ids, component.id)
      {
        True, _ -> Error(InvalidComponentId)
        _, True -> Error(DuplicateComponent(component.id))
        False, False -> validate_ids(rest, [component.id, ..ids])
      }
  }
}

fn validate_dynamic(
  components: List(DynamicComponent),
  tolerance: Float,
  ids: List(String),
) -> Result(Nil, PortfolioError) {
  case components, tolerance >. 0.0 {
    [], _ -> Error(EmptyPortfolio)
    _, False -> Error(InvalidTolerance)
    _, True -> validate_dynamic_ids(components, ids)
  }
}

fn validate_dynamic_ids(
  components: List(DynamicComponent),
  ids: List(String),
) -> Result(Nil, PortfolioError) {
  case components {
    [] -> Ok(Nil)
    [component, ..rest] ->
      case
        component.id == "" || string.trim(component.id) != component.id,
        list.contains(ids, component.id)
      {
        True, _ -> Error(InvalidComponentId)
        _, True -> Error(DuplicateComponent(component.id))
        False, False -> validate_dynamic_ids(rest, [component.id, ..ids])
      }
  }
}

fn timestamps(components: List(Component)) -> List(Instant) {
  components
  |> list.flat_map(fn(component) {
    component.returns
    |> series.to_list
    |> list.map(fn(point) { point.at })
  })
  |> list.sort(by: fn(left, right) {
    int.compare(time.unix_milliseconds(left), time.unix_milliseconds(right))
  })
  |> unique_timestamps([])
}

fn dynamic_timestamps(components: List(DynamicComponent)) -> List(Instant) {
  components
  |> list.flat_map(fn(component) {
    list.append(
      component.weights |> series.to_list |> list.map(fn(point) { point.at }),
      component.returns |> series.to_list |> list.map(fn(point) { point.at }),
    )
  })
  |> list.sort(by: fn(left, right) {
    int.compare(time.unix_milliseconds(left), time.unix_milliseconds(right))
  })
  |> unique_timestamps([])
}

fn unique_timestamps(
  timestamps: List(Instant),
  unique_reversed: List(Instant),
) -> List(Instant) {
  case timestamps, unique_reversed {
    [], _ -> list.reverse(unique_reversed)
    [timestamp, ..rest], [previous, ..] ->
      case
        time.unix_milliseconds(timestamp) == time.unix_milliseconds(previous)
      {
        True -> unique_timestamps(rest, unique_reversed)
        False -> unique_timestamps(rest, [timestamp, ..unique_reversed])
      }
    [timestamp, ..rest], _ ->
      unique_timestamps(rest, [timestamp, ..unique_reversed])
  }
}

fn aggregate_at(
  components: List(Component),
  at: Instant,
  policy: MissingConstituentPolicy,
  tolerance: Float,
) -> series.Datum(Float) {
  let #(weighted_sum, available_weight, available_count) =
    list.fold(components, #(0.0, 0.0, 0), fn(state, component) {
      case value_at(component.returns, at) {
        None -> state
        Some(value) -> #(
          state.0 +. component.weight *. value,
          state.1 +. component.weight,
          state.2 + 1,
        )
      }
    })
  case policy {
    RequireAll ->
      case available_count == list.length(components) {
        True -> series.Present(weighted_sum)
        False -> series.Missing(observation.Unavailable)
      }
    RenormalizeAvailable ->
      case float.absolute_value(available_weight) <=. tolerance {
        True -> series.Missing(observation.Unavailable)
        False -> series.Present(weighted_sum /. available_weight)
      }
  }
}

fn calculate_rows(
  timestamps: List(Instant),
  components: List(DynamicComponent),
  policy: MissingConstituentPolicy,
  tolerance: Float,
  rows_reversed: List(AttributionRow),
) -> Result(List(AttributionRow), PortfolioError) {
  case timestamps {
    [] -> Ok(list.reverse(rows_reversed))
    [at, ..rest] ->
      case dynamic_at(components, at, policy, tolerance) {
        Error(error) -> Error(error)
        Ok(#(total, contributions)) ->
          calculate_rows(rest, components, policy, tolerance, [
            AttributionRow(at, total, contributions),
            ..rows_reversed
          ])
      }
  }
}

fn dynamic_at(
  components: List(DynamicComponent),
  at: Instant,
  policy: MissingConstituentPolicy,
  tolerance: Float,
) -> Result(#(series.Datum(Float), List(series.Datum(Float))), PortfolioError) {
  let available =
    list.map(components, fn(component) {
      case value_at(component.weights, at), value_at(component.returns, at) {
        Some(weight), Some(return_value) -> Some(#(weight, return_value))
        _, _ -> None
      }
    })
  let available_count =
    list.filter_map(available, fn(value) {
      case value {
        Some(value) -> Ok(value)
        None -> Error(Nil)
      }
    })
  case policy, list.length(available_count) == list.length(components) {
    RequireAll, False ->
      Ok(#(
        series.Missing(observation.Unavailable),
        list.map(components, fn(_) { series.Missing(observation.Unavailable) }),
      ))
    _, _ -> {
      let total_weight =
        available_count |> list.map(fn(value) { value.0 }) |> float.sum
      case
        policy,
        float.absolute_value(total_weight) <=. tolerance,
        float.absolute_value(total_weight -. 1.0) <=. tolerance
      {
        RequireAll, _, False -> Error(WeightsDoNotSumAt(at, total_weight))
        RenormalizeAvailable, True, _ ->
          Ok(#(
            series.Missing(observation.Unavailable),
            list.map(components, fn(_) {
              series.Missing(observation.Unavailable)
            }),
          ))
        _, _, _ -> {
          let denominator = case policy {
            RequireAll -> 1.0
            RenormalizeAvailable -> total_weight
          }
          let contributions =
            list.map(available, fn(value) {
              case value {
                None -> series.Missing(observation.Unavailable)
                Some(#(weight, return_value)) ->
                  series.Present(weight /. denominator *. return_value)
              }
            })
          let total =
            contributions
            |> list.filter_map(fn(datum) {
              case datum {
                series.Present(value) -> Ok(value)
                series.Missing(_) -> Error(Nil)
              }
            })
            |> float.sum
          Ok(#(series.Present(total), contributions))
        }
      }
    }
  }
}

fn value_at(returns: Series(Float), at: Instant) -> Option(Float) {
  case
    returns
    |> series.to_list
    |> list.find(fn(point) {
      time.unix_milliseconds(point.at) == time.unix_milliseconds(at)
    })
  {
    Error(_) -> None
    Ok(series.Point(_, series.Missing(_))) -> None
    Ok(series.Point(_, series.Present(value))) -> Some(value)
  }
}

fn datum_at(
  values: List(series.Datum(Float)),
  index: Int,
) -> series.Datum(Float) {
  let assert [value, ..] = list.drop(values, index)
  value
}
