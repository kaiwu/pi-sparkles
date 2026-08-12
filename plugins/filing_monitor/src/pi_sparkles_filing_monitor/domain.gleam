import finance_monitoring/source

pub fn descriptor() -> source.Descriptor {
  source.Descriptor("filing_monitor_v1", ["cn", "us"], [
    "FilingPublished",
    "FilingAmended",
    "FilingCorrected",
  ])
}
