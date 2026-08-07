import finance_core/decimal.{type Decimal}
import finance_risk/calculation.{type Expression, type RoundingSpec}
import finance_risk/fact.{type Fact}
import finance_risk/numeric
import gleam/int
import gleam/list

pub type ProjectionPolicy {
  FloorToIncrement
}

pub opaque type TradeUnit {
  TradeUnit(minimum: Int, increment: Int)
}

pub type TradeUnitError {
  InvalidMinimum
  InvalidIncrement
}

pub type Projection {
  Projected(
    quantity: Int,
    minimum: Int,
    increment: Int,
    policy: ProjectionPolicy,
  )
  ProjectionUnperformed(reason: String)
}

pub opaque type Bound {
  Bound(
    bound_id: String,
    formula_variant: String,
    raw: Expression,
    whole_share: Projection,
    grid: Projection,
  )
}

pub type IntersectionValue {
  IntersectionCalculated(quantity: Int, tightest_bound_ids: List(String))
  IntersectionUnperformed(reason: String)
}

pub opaque type Intersection {
  Intersection(
    operation_id: String,
    selected_bound_ids: List(String),
    value: IntersectionValue,
  )
}

pub fn trade_unit(
  minimum minimum_value: Int,
  increment increment_value: Int,
) -> Result(TradeUnit, TradeUnitError) {
  case minimum_value <= 0, increment_value <= 0 {
    True, _ -> Error(InvalidMinimum)
    _, True -> Error(InvalidIncrement)
    False, False -> Ok(TradeUnit(minimum_value, increment_value))
  }
}

pub fn quantity_bound(
  bound_id bound_id_value: String,
  formula_variant formula_value: String,
  numerator_name numerator_name_value: String,
  numerator numerator_value: Fact(Decimal),
  denominator denominator_value: Expression,
  trade_unit trade_unit_value: Fact(TradeUnit),
  rounding rounding_value: RoundingSpec,
) -> Bound {
  let raw =
    calculation.ratio_by_expression(
      bound_id_value,
      formula_value,
      numerator_name_value,
      numerator_value,
      denominator_value,
      rounding_value,
    )
  let whole_share = project_whole_share(raw)
  let grid = project_grid(raw, trade_unit_value)
  Bound(bound_id_value, formula_value, raw, whole_share, grid)
}

pub fn requested_intersection(
  operation_id operation_id_value: String,
  bounds bound_values: List(Bound),
) -> Intersection {
  let ids = list.map(bound_values, bound_id)
  case bound_values {
    [] ->
      Intersection(
        operation_id_value,
        ids,
        IntersectionUnperformed("empty_bound_list"),
      )
    _ -> {
      let projected =
        list.map(bound_values, fn(value) { #(value.bound_id, value.grid) })
      case first_projection_failure(projected) {
        Ok(Nil) -> {
          let quantities =
            list.map(projected, fn(value) {
              let assert #(_, Projected(quantity, _, _, _)) = value
              quantity
            })
          let assert Ok(minimum) = list.first(quantities)
          let minimum = list.fold(quantities, minimum, int.min)
          let tightest =
            projected
            |> list.filter(fn(value) {
              case value {
                #(_, Projected(quantity, _, _, _)) -> quantity == minimum
                #(_, ProjectionUnperformed(_)) -> False
              }
            })
            |> list.map(fn(value) { value.0 })
          Intersection(
            operation_id_value,
            ids,
            IntersectionCalculated(minimum, tightest),
          )
        }
        Error(reason) ->
          Intersection(operation_id_value, ids, IntersectionUnperformed(reason))
      }
    }
  }
}

pub fn bound_id(value: Bound) -> String {
  value.bound_id
}

pub fn formula_variant(value: Bound) -> String {
  value.formula_variant
}

pub fn raw(value: Bound) -> Expression {
  value.raw
}

pub fn whole_share_projection(value: Bound) -> Projection {
  value.whole_share
}

pub fn grid_projection(value: Bound) -> Projection {
  value.grid
}

pub fn minimum_quantity(value: TradeUnit) -> Int {
  value.minimum
}

pub fn quantity_increment(value: TradeUnit) -> Int {
  value.increment
}

pub fn intersection_operation_id(value: Intersection) -> String {
  value.operation_id
}

pub fn selected_bound_ids(value: Intersection) -> List(String) {
  value.selected_bound_ids
}

pub fn intersection_value(value: Intersection) -> IntersectionValue {
  value.value
}

fn project_whole_share(value: Expression) -> Projection {
  case calculation.calculated_value(value) {
    Ok(raw_value) ->
      Projected(
        numeric.nonnegative_floor_int(raw_value),
        1,
        1,
        FloorToIncrement,
      )
    Error(reason) -> ProjectionUnperformed("raw_bound_unperformed:" <> reason)
  }
}

fn project_grid(value: Expression, grid: Fact(TradeUnit)) -> Projection {
  case calculation.calculated_value(value), fact.known_value(grid) {
    Ok(raw_value), Ok(sourced_grid) -> {
      let rule = fact.sourced_value(sourced_grid)
      let whole = numeric.nonnegative_floor_int(raw_value)
      let projected = case whole <= 0 {
        True -> 0
        False -> {
          let assert Ok(multiple) = int.floor_divide(whole, by: rule.increment)
          let candidate = multiple * rule.increment
          case candidate < rule.minimum {
            True -> 0
            False -> candidate
          }
        }
      }
      Projected(projected, rule.minimum, rule.increment, FloorToIncrement)
    }
    Error(reason), _ ->
      ProjectionUnperformed("raw_bound_unperformed:" <> reason)
    _, Error(reason) ->
      ProjectionUnperformed("missing_trade_unit_fact:" <> reason)
  }
}

fn first_projection_failure(
  values: List(#(String, Projection)),
) -> Result(Nil, String) {
  case values {
    [] -> Ok(Nil)
    [#(id, ProjectionUnperformed(reason)), ..] ->
      Error("bound_projection_unperformed:" <> id <> ":" <> reason)
    [#(_, Projected(_, _, _, _)), ..rest] -> first_projection_failure(rest)
  }
}
