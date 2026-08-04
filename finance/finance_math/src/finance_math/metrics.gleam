import finance_core/decimal.{type RoundingMode}
import finance_math/formula.{type Formula}

/// Generic numerator/base formula used by margins, yields, turnover, leverage,
/// coverage, valuation multiples, and return-on-capital metrics.
pub fn ratio(
  numerator: Formula,
  base: Formula,
  scale: Int,
  rounding: RoundingMode,
) -> Formula {
  formula.Divide(numerator, base, scale, rounding)
}

pub fn percentage(
  numerator: Formula,
  base: Formula,
  scale: Int,
  rounding: RoundingMode,
) -> Formula {
  let assert Ok(hundred) = decimal.parse("100")
  formula.Divide(
    formula.Multiply(numerator, formula.Literal(hundred)),
    base,
    scale,
    rounding,
  )
}

pub fn growth(
  current: Formula,
  previous: Formula,
  scale: Int,
  rounding: RoundingMode,
) -> Formula {
  ratio(formula.Subtract(current, previous), previous, scale, rounding)
}

pub fn average_balance(
  beginning: Formula,
  ending: Formula,
  scale: Int,
  rounding: RoundingMode,
) -> Formula {
  formula.Mean([beginning, ending], scale, rounding)
}

pub fn return_on_average_balance(
  result: Formula,
  beginning_balance: Formula,
  ending_balance: Formula,
  scale: Int,
  rounding: RoundingMode,
) -> Formula {
  ratio(
    result,
    average_balance(beginning_balance, ending_balance, scale, rounding),
    scale,
    rounding,
  )
}

pub fn per_share(
  amount: Formula,
  weighted_average_shares: Formula,
  scale: Int,
  rounding: RoundingMode,
) -> Formula {
  ratio(amount, weighted_average_shares, scale, rounding)
}

pub fn free_cash_flow(
  operating_cash_flow: Formula,
  capital_expenditure: Formula,
) -> Formula {
  formula.Subtract(operating_cash_flow, capital_expenditure)
}

pub fn enterprise_value(
  market_capitalization: Formula,
  debt: Formula,
  preferred_equity: Formula,
  non_controlling_interest: Formula,
  cash: Formula,
) -> Formula {
  formula.Subtract(
    formula.Sum([
      market_capitalization,
      debt,
      preferred_equity,
      non_controlling_interest,
    ]),
    cash,
  )
}

/// Three-factor DuPont decomposition.
pub fn dupont_return_on_equity(
  net_margin: Formula,
  asset_turnover: Formula,
  equity_multiplier: Formula,
) -> Formula {
  formula.Multiply(
    formula.Multiply(net_margin, asset_turnover),
    equity_multiplier,
  )
}
