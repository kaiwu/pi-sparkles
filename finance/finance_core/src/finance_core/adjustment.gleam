import gleam/string

pub opaque type ProviderBasis {
  ProviderBasis(provider: String, basis: String)
}

pub type Adjustment {
  Raw
  SplitAdjusted
  DividendAdjusted
  TotalReturnAdjusted
  ProviderAdjusted(ProviderBasis)
}

pub type AdjustmentError {
  InvalidProvider
  InvalidBasis
}

pub fn provider_adjusted(
  provider provider: String,
  basis basis: String,
) -> Result(Adjustment, AdjustmentError) {
  case valid(provider), valid(basis) {
    False, _ -> Error(InvalidProvider)
    _, False -> Error(InvalidBasis)
    True, True -> Ok(ProviderAdjusted(ProviderBasis(provider, basis)))
  }
}

pub fn provider(value: ProviderBasis) -> String {
  let ProviderBasis(provider, _) = value
  provider
}

pub fn basis(value: ProviderBasis) -> String {
  let ProviderBasis(_, basis) = value
  basis
}

fn valid(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
