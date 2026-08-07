import finance_core/currency.{type Currency}
import finance_core/decimal.{type Decimal}
import finance_core/source.{type SourceRef}
import finance_ohlcv/fact.{type Fact}
import gleam/order.{Eq, Gt, Lt}

pub type QuantityUnit {
  Shares
  Lots(lot_size: Fact(Int))
  MonetaryTurnover(currency: Currency)
  ProviderScaled(description: String)
  UnknownQuantity
}

/// A reported quantity keeps its raw value, decoded value, unit state, and unit
/// evidence separate. No unit is guessed from the track.
pub opaque type QuantityFacts {
  QuantityFacts(
    raw: String,
    parsed: Fact(Decimal),
    non_negative: Fact(Bool),
    unit: Fact(QuantityUnit),
    unit_evidence: List(SourceRef),
  )
}

pub fn inspect(
  raw raw_value: String,
  unit unit_value: Fact(QuantityUnit),
  unit_evidence evidence: List(SourceRef),
) -> QuantityFacts {
  let parsed = case decimal.parse(raw_value) {
    Ok(value) -> fact.Known(value)
    Error(_) -> fact.DecodeFailure(raw_value, "invalid_decimal")
  }
  let non_negative = case parsed {
    fact.Known(value) ->
      fact.Known(case decimal.compare(value, decimal.zero()) {
        Lt -> False
        Eq | Gt -> True
      })
    fact.DecodeFailure(_, _) -> fact.NotObtained("quantity_not_decoded")
    fact.Unknown(reason) -> fact.Unknown(reason)
    fact.NotObtained(reason) -> fact.NotObtained(reason)
    fact.Conflicting(_) -> fact.NotObtained("quantity_conflicting")
  }
  QuantityFacts(raw_value, parsed, non_negative, unit_value, evidence)
}

pub fn raw(value: QuantityFacts) -> String {
  value.raw
}

pub fn parsed(value: QuantityFacts) -> Fact(Decimal) {
  value.parsed
}

pub fn non_negative(value: QuantityFacts) -> Fact(Bool) {
  value.non_negative
}

pub fn unit(value: QuantityFacts) -> Fact(QuantityUnit) {
  value.unit
}

pub fn unit_evidence(value: QuantityFacts) -> List(SourceRef) {
  value.unit_evidence
}
