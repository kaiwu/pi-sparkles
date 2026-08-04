import finance_core/currency.{type Currency}
import finance_core/decimal.{type Decimal}
import gleam/order.{type Order}

pub type Money {
  Money(amount: Decimal, currency: Currency)
}

pub type MoneyError {
  CurrencyMismatch(expected: String, actual: String)
}

pub fn new(amount: Decimal, currency: Currency) -> Money {
  Money(amount, currency)
}

pub fn same_currency(left: Money, right: Money) -> Result(Nil, MoneyError) {
  let Money(currency: left_currency, ..) = left
  let Money(currency: right_currency, ..) = right
  let left_code = currency.code(left_currency)
  let right_code = currency.code(right_currency)
  case left_code == right_code {
    True -> Ok(Nil)
    False -> Error(CurrencyMismatch(left_code, right_code))
  }
}

pub fn add(left: Money, right: Money) -> Result(Money, MoneyError) {
  use _ <- result_try(same_currency(left, right))
  Ok(Money(decimal.add(left.amount, right.amount), left.currency))
}

pub fn subtract(left: Money, right: Money) -> Result(Money, MoneyError) {
  use _ <- result_try(same_currency(left, right))
  Ok(Money(decimal.subtract(left.amount, right.amount), left.currency))
}

pub fn compare(left: Money, right: Money) -> Result(Order, MoneyError) {
  use _ <- result_try(same_currency(left, right))
  Ok(decimal.compare(left.amount, right.amount))
}

pub fn to_string(value: Money) -> String {
  currency.code(value.currency) <> " " <> decimal.to_string(value.amount)
}

fn result_try(
  result: Result(value, error),
  next: fn(value) -> Result(next_value, error),
) -> Result(next_value, error) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
