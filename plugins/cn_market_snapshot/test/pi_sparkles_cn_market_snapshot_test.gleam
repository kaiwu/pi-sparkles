import finance_core/time
import finance_eastmoney/history as provider_history
import finance_eastmoney/overview as provider_overview
import finance_eastmoney/query
import finance_provenance/hash
import finance_track
import gleam/list
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_cn_market_snapshot/overview
import pi_sparkles_cn_market_snapshot/sector_series

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn acquired_overview_retains_breadth_and_explicit_evidence_boundaries_test() {
  let body = fixture()
  let assert Ok(plan) = query.cn_overview(finance_track.Cn)
  let assert Ok(provider_value) = provider_overview.decode(body, for: plan)
  let assert Ok(digest) = hash.text(body)
  let assert Ok(value) =
    overview.assemble(provider_value, 1_786_694_800_000, 2048, digest)

  overview.summary(value)
  |> should.equal(
    "CN track | Eastmoney SSE/SZSE provider overview | 5 benchmarks | breadth 2350 advanced, 2753 declined, 180 unchanged | completeness and latency unknown",
  )
  overview.content(value)
  |> string.contains("No intraday ordering, fund flow, sector rotation")
  |> should.be_true
  overview.content(value)
  |> string.contains("399006 创业板指 last=3626.30")
  |> should.be_true
  overview.content(value)
  |> string.contains("000688 科创50 last=1234.56")
  |> should.be_true
}

pub fn sector_series_use_exact_eleven_index_profile_and_emit_calculation_handoff_test() {
  let assert Ok(series) = build_sector_series(query.cn_sector_indices(), [])
  let assert Ok(manifest) = hash.text("exact-sector-manifest")
  let assert Ok(value) =
    sector_series.assemble(
      series,
      civil(2026, 8, 7),
      civil(2026, 8, 14),
      1_786_694_800_000,
      manifest,
    )

  sector_series.summary(value)
  |> string.contains("11 receipt-bound CSI 800 sector series")
  |> should.be_true
  sector_series.content(value)
  |> string.contains("COMPARISON_INPUT")
  |> should.be_true
  sector_series.content(value)
  |> string.contains("\"seriesId\":\"399965\"")
  |> should.be_true
  sector_series.content(value)
  |> string.contains("\"role\":\"five_sessions_ago\"")
  |> should.be_true
  sector_series.content(value)
  |> string.contains("latestSessionReturnPercent")
  |> should.be_false
  sector_series.content(value)
  |> string.contains("000934")
  |> should.be_false
}

fn build_sector_series(
  indices: List(query.CnSectorIndex),
  acquired: List(sector_series.AcquiredSeries),
) -> Result(List(sector_series.AcquiredSeries), Nil) {
  case indices {
    [] -> Ok(list.reverse(acquired))
    [index, ..rest] -> {
      let body = sector_fixture(query.cn_sector_code(index))
      use plan <- result.try(
        result_nil(query.cn_sector_history(
          index,
          civil(2026, 8, 7),
          civil(2026, 8, 14),
          64,
        )),
      )
      use value <- result.try(
        result_nil(provider_history.decode(body, for: plan)),
      )
      use digest <- result.try(result_nil(hash.text(body)))
      build_sector_series(rest, [
        sector_series.AcquiredSeries(
          index,
          value,
          query.history_source_reference(plan),
          string.length(body),
          digest,
        ),
        ..acquired
      ])
    }
  }
}

fn result_nil(value: Result(a, error)) -> Result(a, Nil) {
  case value {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}

fn civil(year: Int, month: Int, day: Int) {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn sector_fixture(code: String) -> String {
  "{\"rc\":0,\"data\":{\"code\":\""
  <> code
  <> "\",\"name\":\"provider-"
  <> code
  <> "\",\"klines\":[\"2026-08-07,100,100,101,99,1,1,1,0,0,0\",\"2026-08-10,101,101,102,100,1,1,1,1,1,0\",\"2026-08-11,102,102,103,101,1,1,1,1,1,0\",\"2026-08-12,103,103,104,102,1,1,1,1,1,0\",\"2026-08-13,104,104,105,103,1,1,1,1,1,0\",\"2026-08-14,110,110,111,109,1,1,1,1,1,0\"]}}"
}

fn fixture() -> String {
  "{\"rc\":0,\"data\":{\"total\":5,\"diff\":[{\"f2\":392718,\"f3\":1,\"f4\":22,\"f5\":499525613,\"f6\":990371924237.7,\"f12\":\"000001\",\"f13\":1,\"f14\":\"上证指数\",\"f15\":393264,\"f16\":390370,\"f17\":393002,\"f18\":392696,\"f104\":1012,\"f105\":1254,\"f106\":85},{\"f2\":1435431,\"f3\":45,\"f4\":6487,\"f5\":642557319,\"f6\":1152471301164.9692,\"f12\":\"399001\",\"f13\":0,\"f14\":\"深证成指\",\"f15\":1438418,\"f16\":1420399,\"f17\":1433541,\"f18\":1428944,\"f104\":1338,\"f105\":1499,\"f106\":95},{\"f2\":362630,\"f3\":112,\"f4\":4026,\"f5\":199294854,\"f6\":556471146251.9,\"f12\":\"399006\",\"f13\":0,\"f14\":\"创业板指\",\"f15\":363303,\"f16\":357861,\"f17\":361019,\"f18\":358604,\"f104\":753,\"f105\":612,\"f106\":36},{\"f2\":466588,\"f3\":4,\"f4\":193,\"f5\":178430696,\"f6\":549769606284.4,\"f12\":\"000300\",\"f13\":1,\"f14\":\"沪深300\",\"f15\":467671,\"f16\":463713,\"f17\":467298,\"f18\":466395,\"f104\":108,\"f105\":186,\"f106\":6},{\"f2\":123456,\"f3\":-607,\"f4\":-7970,\"f5\":100000000,\"f6\":250000000000,\"f12\":\"000688\",\"f13\":1,\"f14\":\"科创50\",\"f15\":131426,\"f16\":122000,\"f17\":130000,\"f18\":131426,\"f104\":12,\"f105\":38,\"f106\":0}]}}"
}
