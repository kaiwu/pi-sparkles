import finance_monitoring/source

pub fn descriptor() -> source.Descriptor {
  source.Descriptor("finance_catalysts_v1", ["cn", "hk", "us"], [
    "FilingPublished",
    "EarningsAnnounced",
    "CorporateAction",
    "NewsArticle",
    "CallerEvent",
  ])
}
