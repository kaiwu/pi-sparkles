import finance_core/currency.{type Currency}
import finance_core/identifier.{type InstrumentId, type Mic, type Symbol}
import gleam/option.{type Option}

pub type InstrumentKind {
  CommonStock
  PreferredStock
  DepositaryReceipt
  ExchangeTradedFund
  Fund
  Bond
  Future
  OptionContract
  Index
  Other(kind: String)
}

pub type ListingStatus {
  Active
  Suspended
  Delisted
  UnknownStatus
}

pub type Listing {
  Listing(symbol: Symbol, mic: Mic, currency: Currency, status: ListingStatus)
}

pub type Instrument {
  Instrument(
    id: InstrumentId,
    name: String,
    kind: InstrumentKind,
    primary_listing: Option(Listing),
    listings: List(Listing),
  )
}
