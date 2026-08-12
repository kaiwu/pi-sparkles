import finance_monitoring/source

pub fn descriptor() -> source.Descriptor {
  source.Descriptor("cn_stock_watch_v1", ["cn"], [
    "Announcement",
    "PerformanceForecast",
    "ExpressReport",
    "RestrictedShareUnlock",
    "Pledge",
    "Suspension",
    "RuleStateChange",
    "StockConnectEligibility",
  ])
}
