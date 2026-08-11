import finance_research_diff as diff
import gleam/option

pub fn descriptor() -> diff.Descriptor {
  diff.Descriptor(
    "cn_stock_filing_diff_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    ["年报", "半年报", "季报", "一季报", "三季报", "业绩预告", "业绩快报", "更正公告"],
    option.Some("zh-CN"),
  )
}
