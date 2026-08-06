import finance_cn_calendar/dataset as cn_calendar
import finance_cn_identity/identity as cn_identity
import finance_core/source.{type SourceRef}
import finance_core/time.{type Date}
import finance_listing/effective.{type Interval}
import finance_ohlcv/gap_assessment
import gleam/result
import gleam/string

pub opaque type ListingReceipt {
  ListingReceipt(
    listing: cn_identity.Listing,
    interval: Interval,
    evidence_reference: String,
  )
}

pub opaque type Assessment {
  Assessment(
    venue: cn_identity.Venue,
    listing: ListingReceipt,
    classification: gap_assessment.Assessment,
  )
}

pub type ReceiptError {
  InvalidEvidenceReference
}

pub type AssessmentError {
  ListingVenueMismatch
  CalendarDatasetError(cn_calendar.CalendarDatasetError)
  InvalidAssessment(gap_assessment.AssessmentError)
}

pub fn listing_receipt(
  listing listing_value: cn_identity.Listing,
  interval interval_value: Interval,
  evidence_reference evidence: String,
) -> Result(ListingReceipt, ReceiptError) {
  case valid_reference(evidence) {
    True -> Ok(ListingReceipt(listing_value, interval_value, evidence))
    False -> Error(InvalidEvidenceReference)
  }
}

pub fn assess(
  venue venue_value: cn_identity.Venue,
  listing listing_value: ListingReceipt,
  start_date start: Date,
  end_date end: Date,
  returned_bar_dates bar_dates: List(Date),
  statuses status_values: List(gap_assessment.StatusReceipt),
  provider provider_value: gap_assessment.ProviderReceipt,
) -> Result(Assessment, AssessmentError) {
  use _ <- result.try(
    case cn_identity.venue(listing_value.listing) == venue_value {
      True -> Ok(Nil)
      False -> Error(ListingVenueMismatch)
    },
  )
  use calendar <- result.try(
    cn_calendar.official_2026(venue_value)
    |> result.map_error(CalendarDatasetError),
  )
  use classification <- result.try(
    gap_assessment.assess(
      calendar: calendar,
      listing_interval: listing_value.interval,
      listing_evidence_reference: listing_value.evidence_reference,
      start_date: start,
      end_date: end,
      returned_bar_dates: bar_dates,
      statuses: status_values,
      provider: provider_value,
    )
    |> result.map_error(InvalidAssessment),
  )
  Ok(Assessment(venue_value, listing_value, classification))
}

pub fn venue(value: Assessment) -> cn_identity.Venue {
  value.venue
}

pub fn listing_receipt_value(value: Assessment) -> ListingReceipt {
  value.listing
}

pub fn classification(value: Assessment) -> gap_assessment.Assessment {
  value.classification
}

pub fn listing(value: ListingReceipt) -> cn_identity.Listing {
  value.listing
}

pub fn listing_interval(value: ListingReceipt) -> Interval {
  value.interval
}

pub fn listing_evidence_reference(value: ListingReceipt) -> String {
  value.evidence_reference
}

pub fn start_date(value: Assessment) -> Date {
  value.classification |> gap_assessment.start_date
}

pub fn end_date(value: Assessment) -> Date {
  value.classification |> gap_assessment.end_date
}

pub fn calendar_source(value: Assessment) -> SourceRef {
  value.classification |> gap_assessment.calendar_source
}

pub fn calendar_version(value: Assessment) -> String {
  value.classification |> gap_assessment.calendar_version
}

pub fn assessed_date_count(value: Assessment) -> Int {
  value.classification |> gap_assessment.assessed_date_count
}

fn valid_reference(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 2000
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}
