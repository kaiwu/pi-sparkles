import finance_core/decimal.{type Decimal}
import finance_ohlcv/fact.{type Fact}
import gleam/order.{Eq, Gt, Lt}

/// A provider field before any domain constructor discards its raw lexeme.
pub opaque type DecimalField {
  DecimalField(raw: String, parsed: Fact(Decimal))
}

/// Mechanical comparisons exposed to the LLM as facts, never as a verdict.
pub opaque type MechanicalChecks {
  MechanicalChecks(
    open_non_negative: Fact(Bool),
    high_non_negative: Fact(Bool),
    low_non_negative: Fact(Bool),
    close_non_negative: Fact(Bool),
    volume_non_negative: Fact(Bool),
    high_ge_max: Fact(Bool),
    low_le_min: Fact(Bool),
  )
}

pub opaque type RowFacts {
  RowFacts(
    open: DecimalField,
    high: DecimalField,
    low: DecimalField,
    close: DecimalField,
    volume: DecimalField,
    checks: MechanicalChecks,
  )
}

/// Decode a provider row without throwing away parseable or unusual values.
pub fn inspect(
  open open_raw: String,
  high high_raw: String,
  low low_raw: String,
  close close_raw: String,
  volume volume_raw: String,
) -> RowFacts {
  let open = decimal_field(open_raw)
  let high = decimal_field(high_raw)
  let low = decimal_field(low_raw)
  let close = decimal_field(close_raw)
  let volume = decimal_field(volume_raw)
  RowFacts(
    open,
    high,
    low,
    close,
    volume,
    MechanicalChecks(
      non_negative(open),
      non_negative(high),
      non_negative(low),
      non_negative(close),
      non_negative(volume),
      high_check(high, open, low, close),
      low_check(low, open, high, close),
    ),
  )
}

pub fn raw(value: DecimalField) -> String {
  value.raw
}

pub fn parsed(value: DecimalField) -> Fact(Decimal) {
  value.parsed
}

pub fn open(value: RowFacts) -> DecimalField {
  value.open
}

pub fn high(value: RowFacts) -> DecimalField {
  value.high
}

pub fn low(value: RowFacts) -> DecimalField {
  value.low
}

pub fn close(value: RowFacts) -> DecimalField {
  value.close
}

pub fn volume(value: RowFacts) -> DecimalField {
  value.volume
}

pub fn checks(value: RowFacts) -> MechanicalChecks {
  value.checks
}

pub fn open_non_negative(value: MechanicalChecks) -> Fact(Bool) {
  value.open_non_negative
}

pub fn high_non_negative(value: MechanicalChecks) -> Fact(Bool) {
  value.high_non_negative
}

pub fn low_non_negative(value: MechanicalChecks) -> Fact(Bool) {
  value.low_non_negative
}

pub fn close_non_negative(value: MechanicalChecks) -> Fact(Bool) {
  value.close_non_negative
}

pub fn volume_non_negative(value: MechanicalChecks) -> Fact(Bool) {
  value.volume_non_negative
}

pub fn high_ge_max(value: MechanicalChecks) -> Fact(Bool) {
  value.high_ge_max
}

pub fn low_le_min(value: MechanicalChecks) -> Fact(Bool) {
  value.low_le_min
}

fn decimal_field(raw: String) -> DecimalField {
  DecimalField(raw, case decimal.parse(raw) {
    Ok(value) -> fact.Known(value)
    Error(_) -> fact.DecodeFailure(raw, "invalid_decimal")
  })
}

fn non_negative(value: DecimalField) -> Fact(Bool) {
  case value.parsed {
    fact.Known(value) ->
      fact.Known(case decimal.compare(value, decimal.zero()) {
        Lt -> False
        Eq | Gt -> True
      })
    fact.DecodeFailure(_, _) -> fact.NotObtained("decimal_not_decoded")
    fact.Unknown(reason) -> fact.Unknown(reason)
    fact.NotObtained(reason) -> fact.NotObtained(reason)
    fact.Conflicting(_) -> fact.NotObtained("decimal_conflicting")
  }
}

fn high_check(
  high: DecimalField,
  open: DecimalField,
  low: DecimalField,
  close: DecimalField,
) -> Fact(Bool) {
  case high.parsed, open.parsed, low.parsed, close.parsed {
    fact.Known(high), fact.Known(open), fact.Known(low), fact.Known(close) ->
      fact.Known(
        not_less(high, open) && not_less(high, low) && not_less(high, close),
      )
    _, _, _, _ -> fact.NotObtained("price_field_not_decoded")
  }
}

fn low_check(
  low: DecimalField,
  open: DecimalField,
  high: DecimalField,
  close: DecimalField,
) -> Fact(Bool) {
  case low.parsed, open.parsed, high.parsed, close.parsed {
    fact.Known(low), fact.Known(open), fact.Known(high), fact.Known(close) ->
      fact.Known(
        not_greater(low, open)
        && not_greater(low, high)
        && not_greater(low, close),
      )
    _, _, _, _ -> fact.NotObtained("price_field_not_decoded")
  }
}

fn not_less(left: Decimal, right: Decimal) -> Bool {
  case decimal.compare(left, right) {
    Lt -> False
    Eq | Gt -> True
  }
}

fn not_greater(left: Decimal, right: Decimal) -> Bool {
  case decimal.compare(left, right) {
    Gt -> False
    Eq | Lt -> True
  }
}
