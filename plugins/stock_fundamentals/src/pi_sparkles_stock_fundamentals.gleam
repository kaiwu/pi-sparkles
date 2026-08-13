import finance_core/decimal
import finance_core/identifier
import finance_http/response as http_response
import finance_http/transport
import finance_math/formula
import finance_math/metric as math_metric
import finance_sec
import finance_sec/derivation
import finance_sec/fundamentals
import finance_sec/periods
import finance_sec/request
import finance_sec/runtime
import finance_sec/xbrl
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pi
import pi/context
import pi/raw
import pi/schema
import pi/tool
import pi/ui
import pi_sparkles_stock_fundamentals/effect/environment
import pi_sparkles_stock_fundamentals/guide
import pi_sparkles_stock_fundamentals/metrics as stock_metrics

pub type DefinitionsInput {
  DefinitionsInput
}

pub type FundamentalInput {
  FundamentalInput(cik: finance_sec.Cik, query: fundamentals.Query)
}

pub type PeriodInput {
  PeriodInput(
    cik: finance_sec.Cik,
    query: fundamentals.Query,
    policy: fundamentals.FilingPolicy,
  )
}

pub type Q4Input {
  Q4Input(
    cik: finance_sec.Cik,
    annual_query: fundamentals.Query,
    nine_month_query: fundamentals.Query,
    annual_policy: fundamentals.FilingPolicy,
    nine_month_policy: fundamentals.FilingPolicy,
  )
}

pub type TrendInput {
  TrendInput(
    cik: finance_sec.Cik,
    queries: List(#(String, fundamentals.Query)),
    policy: fundamentals.FilingPolicy,
    period_class: periods.Class,
  )
}

type GrowthInput {
  GrowthInput(
    cik: finance_sec.Cik,
    queries: List(#(String, fundamentals.Query)),
    policy: fundamentals.FilingPolicy,
    period_class: periods.Class,
    gap: stock_metrics.GrowthGap,
    scale: Int,
  )
}

type TtmInput {
  TtmInput(
    cik: finance_sec.Cik,
    queries: List(#(String, fundamentals.Query)),
    policy: fundamentals.FilingPolicy,
  )
}

type TtmBridgeInput {
  TtmBridgeInput(
    cik: finance_sec.Cik,
    annual_query: fundamentals.Query,
    current_ytd_query: fundamentals.Query,
    prior_ytd_query: fundamentals.Query,
    annual_policy: fundamentals.FilingPolicy,
    current_ytd_policy: fundamentals.FilingPolicy,
    prior_ytd_policy: fundamentals.FilingPolicy,
  )
}

type ComposedTtmInput {
  ComposedTtmInput(
    cik: finance_sec.Cik,
    direct_queries: List(ComposedQuarterQuery),
    annual_query: fundamentals.Query,
    nine_month_query: fundamentals.Query,
    annual_policy: fundamentals.FilingPolicy,
    nine_month_policy: fundamentals.FilingPolicy,
  )
}

type ComposedQuarterQuery {
  ComposedQuarterQuery(
    end: String,
    query: fundamentals.Query,
    policy: fundamentals.FilingPolicy,
  )
}

type ResolvedComposedQuarter {
  ResolvedComposedQuarter(
    end: String,
    policy: fundamentals.FilingPolicy,
    resolution: identifier.Resolution(fundamentals.Candidate),
  )
}

type CalculatedMetricInput {
  CalculatedMetricInput(
    cik: finance_sec.Cik,
    kind: stock_metrics.Kind,
    queries: List(MetricQuery),
    base_policy: fundamentals.FilingPolicy,
    period_class: periods.Class,
    scale: Int,
  )
}

type Provider {
  Ready(access: finance_sec.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

type ResolvedPeriod {
  ResolvedPeriod(
    end: String,
    resolution: identifier.Resolution(fundamentals.Candidate),
  )
}

type MetricQuery {
  MetricQuery(
    name: String,
    query: fundamentals.Query,
    policy: fundamentals.FilingPolicy,
  )
}

type ResolvedMetricSource {
  ResolvedMetricSource(
    name: String,
    policy: fundamentals.FilingPolicy,
    resolution: identifier.Resolution(fundamentals.Candidate),
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()

  pi.register_command(
    api,
    "fundamentals",
    "Show the stock fundamentals workflow and supported metrics",
    fn(_args, ctx) {
      ui.notify(context.ui(ctx), us_text(guide.text()), ui.Info)
      promise.resolve(Nil)
    },
  )

  tool.register(
    api,
    "stock_fundamental_definitions",
    "Stock fundamental definitions",
    "List the exact initial SEC tag, period, unit, and interpretation policies used by stock_fundamental",
    "Inspect supported normalized metrics before requesting company data",
    tool.parameters(schema.object([]), definitions_decoder()),
    tool.Parallel,
    fn(_id, _input, _signal, _updates, _ctx) {
      let definitions = supported_definitions()
      tool.text_result(
        render_definitions(definitions),
        json.object(
          list.append(us_track_fields(), [
            #("definitions", json.array(definitions, definition_json)),
          ]),
        ),
      )
      |> promise.resolve
    },
  )

  tool.register(
    api,
    "stock_fundamental_q4",
    "Stock fundamental Q4",
    "Derive a fourth quarter as annual minus nine-month YTD only when metric, tag, unit, fiscal start, and period shapes are compatible",
    "Build one source-retaining Q4 value without treating weighted averages or instant facts as additive",
    tool.parameters(q4_schema(), q4_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      execute_q4(provider, input, id, signal)
    },
  )

  tool.register(
    api,
    "stock_fundamental_trend",
    "Stock fundamental trend",
    "Resolve two to twenty comparable statement periods and build a trend only when every point is unique and shares metric, tag, unit, and period class",
    "Create an ordered source-retaining direct-fact series without interpolation or hidden restatement policy",
    tool.parameters(trend_schema(), trend_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      execute_trend(provider, input, id, signal)
    },
  )

  tool.register(
    api,
    "stock_fundamental_growth",
    "Stock fundamental growth",
    "Calculate an exact growth series from comparable direct facts only when every adjacent end date matches an explicit quarter-over-quarter or year-over-year gap",
    "Build source-retaining percentage growth without silently comparing skipped or irregular periods",
    tool.parameters(growth_schema(), growth_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      execute_growth(provider, input, id, signal)
    },
  )

  tool.register(
    api,
    "stock_fundamental_ttm",
    "Stock fundamental trailing twelve months",
    "Sum exactly four contiguous comparable direct-quarter facts for an additive monetary metric",
    "Build a source-retaining TTM value without filling missing quarters or averaging non-additive facts",
    tool.parameters(ttm_schema(), ttm_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      execute_ttm(provider, input, id, signal)
    },
  )

  tool.register(
    api,
    "stock_fundamental_ttm_bridge",
    "Stock fundamental TTM bridge",
    "Calculate annual plus current YTD minus prior comparable YTD only when all three unique direct facts pass strict fiscal and calendar proofs",
    "Build a source-retaining TTM value when four direct quarters are unavailable",
    tool.parameters(ttm_bridge_schema(), ttm_bridge_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      execute_ttm_bridge(provider, input, id, signal)
    },
  )

  tool.register(
    api,
    "stock_fundamental_ttm_composed",
    "Stock fundamental composed TTM",
    "Sum three unique direct quarters and one revalidated derived Q4 while expanding the derived value to its annual and nine-month source leaves",
    "Build a mixed direct/derived source graph without presenting derived Q4 as directly reported",
    tool.parameters(composed_ttm_schema(), composed_ttm_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      execute_composed_ttm(provider, input, id, signal)
    },
  )

  tool.register(
    api,
    "stock_fundamental_metric",
    "Calculated stock fundamental",
    "Calculate free cash flow, net margin, or diluted EPS from unique same-filing SEC facts through an exact finance_math formula",
    "Build one typed, source-retaining multi-input metric with explicit period, filing, unit, precision, and rounding policy",
    tool.parameters(calculated_metric_schema(), calculated_metric_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      execute_calculated_metric(provider, input, id, signal)
    },
  )

  tool.register(
    api,
    "stock_fundamental",
    "Stock fundamental",
    "Resolve one explicitly defined SEC fundamental for an exact reporting period; return no-match, unique, or ambiguous without hidden precedence",
    "Retrieve a directly reported revenue, income, balance-sheet, cash-flow, capex, or diluted-share fact",
    tool.parameters(fundamental_schema(), fundamental_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use outcome <- promise.await(fetch_company_facts(
            provider_runtime,
            access,
            input.cik,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(company) ->
              case fundamentals.resolve(company, input.query) {
                Error(error) ->
                  tool.reject(
                    "SEC fundamental normalization failed safely: "
                    <> string.inspect(error),
                  )
                Ok(resolution) ->
                  tool.text_result(
                    render_resolution(company.entity_name, resolution),
                    resolution_json(
                      company,
                      input.query,
                      resolution,
                      "preserve_all",
                    ),
                  )
                  |> promise.resolve
              }
          }
        }
      }
    },
  )

  tool.register(
    api,
    "stock_fundamental_period",
    "Stock fundamental period",
    "Resolve an instant, quarter, half-year YTD, nine-month YTD, or annual direct fact ending on an exact date under an explicit filing policy",
    "Select statement-period shapes without guessing start dates or amendment precedence",
    tool.parameters(period_schema(), period_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use outcome <- promise.await(fetch_company_facts(
            provider_runtime,
            access,
            input.cik,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(company) ->
              case
                fundamentals.resolve_with_policy(
                  company,
                  input.query,
                  input.policy,
                )
              {
                Error(error) ->
                  tool.reject(
                    "SEC statement-period normalization failed safely: "
                    <> string.inspect(error),
                  )
                Ok(resolution) ->
                  tool.text_result(
                    render_resolution(company.entity_name, resolution),
                    resolution_json(
                      company,
                      input.query,
                      resolution,
                      fundamentals.filing_policy_name(input.policy),
                    ),
                  )
                  |> promise.resolve
              }
          }
        }
      }
    },
  )

  promise.resolve(Nil)
}

fn execute_q4(
  provider: Provider,
  input: Q4Input,
  id: String,
  signal: pi.AbortSignal,
) -> Promise(tool.ToolResult) {
  case provider {
    InvalidConfiguration(reason) -> tool.reject(reason)
    Ready(access, provider_runtime) -> {
      use outcome <- promise.await(fetch_company_facts(
        provider_runtime,
        access,
        input.cik,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      ))
      case outcome {
        Error(message) -> tool.reject(message)
        Ok(company) ->
          case
            fundamentals.resolve_with_policy(
              company,
              input.annual_query,
              input.annual_policy,
            ),
            fundamentals.resolve_with_policy(
              company,
              input.nine_month_query,
              input.nine_month_policy,
            )
          {
            Error(error), _ | _, Error(error) ->
              tool.reject(
                "SEC Q4 source resolution failed safely: "
                <> string.inspect(error),
              )
            Ok(annual), Ok(nine_month) ->
              case annual, nine_month {
                identifier.Unique(annual), identifier.Unique(nine_month) ->
                  case derivation.q4(annual, nine_month) {
                    Error(error) ->
                      tool.reject(
                        "SEC Q4 derivation was incompatible: "
                        <> string.inspect(error),
                      )
                    Ok(derived) ->
                      tool.text_result(
                        render_q4(company.entity_name, derived),
                        q4_json(company, input, derived),
                      )
                      |> promise.resolve
                  }
                _, _ ->
                  tool.text_result(
                    us_text(
                      company.entity_name
                      <> ": Q4 derivation blocked until both annual and nine-month sources are unique",
                    ),
                    unresolved_q4_json(company, input, annual, nine_month),
                  )
                  |> promise.resolve
              }
          }
      }
    }
  }
}

fn execute_trend(
  provider: Provider,
  input: TrendInput,
  id: String,
  signal: pi.AbortSignal,
) -> Promise(tool.ToolResult) {
  case provider {
    InvalidConfiguration(reason) -> tool.reject(reason)
    Ready(access, provider_runtime) -> {
      use outcome <- promise.await(fetch_company_facts(
        provider_runtime,
        access,
        input.cik,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      ))
      case outcome {
        Error(message) -> tool.reject(message)
        Ok(company) ->
          case resolve_periods(company, input.queries, input.policy, []) {
            Error(error) ->
              tool.reject(
                "SEC trend source resolution failed safely: "
                <> string.inspect(error),
              )
            Ok(resolutions) ->
              case unique_points(resolutions, []) {
                Error(_) ->
                  tool.text_result(
                    us_text(
                      company.entity_name
                      <> ": trend blocked because every requested period must resolve uniquely",
                    ),
                    unresolved_trend_json(company, input, resolutions),
                  )
                  |> promise.resolve
                Ok(points) ->
                  case derivation.trend(points, input.period_class) {
                    Error(error) ->
                      tool.reject(
                        "SEC trend comparability check failed: "
                        <> string.inspect(error),
                      )
                    Ok(trend) ->
                      tool.text_result(
                        render_trend(company.entity_name, trend),
                        trend_json(company, input, trend),
                      )
                      |> promise.resolve
                  }
              }
          }
      }
    }
  }
}

fn execute_growth(
  provider: Provider,
  input: GrowthInput,
  id: String,
  signal: pi.AbortSignal,
) -> Promise(tool.ToolResult) {
  case provider {
    InvalidConfiguration(reason) -> tool.reject(reason)
    Ready(access, provider_runtime) -> {
      use outcome <- promise.await(fetch_company_facts(
        provider_runtime,
        access,
        input.cik,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      ))
      case outcome {
        Error(message) -> tool.reject(message)
        Ok(company) ->
          case resolve_periods(company, input.queries, input.policy, []) {
            Error(error) ->
              tool.reject(
                "SEC growth source resolution failed safely: "
                <> string.inspect(error),
              )
            Ok(resolutions) ->
              case unique_points(resolutions, []) {
                Error(_) ->
                  tool.text_result(
                    us_text(
                      company.entity_name
                      <> ": growth blocked because every requested period must resolve uniquely",
                    ),
                    unresolved_growth_json(company, input, resolutions),
                  )
                  |> promise.resolve
                Ok(points) ->
                  case derivation.trend(points, input.period_class) {
                    Error(error) ->
                      tool.reject(
                        "SEC growth comparability check failed: "
                        <> string.inspect(error),
                      )
                    Ok(trend) ->
                      case
                        stock_metrics.growth_series(
                          trend,
                          input.gap,
                          input.scale,
                        )
                      {
                        Error(error) ->
                          tool.reject(
                            "SEC growth calculation was incompatible: "
                            <> string.inspect(error),
                          )
                        Ok(growth) ->
                          tool.text_result(
                            render_growth(company.entity_name, growth),
                            growth_json(company, input, growth),
                          )
                          |> promise.resolve
                      }
                  }
              }
          }
      }
    }
  }
}

fn execute_ttm(
  provider: Provider,
  input: TtmInput,
  id: String,
  signal: pi.AbortSignal,
) -> Promise(tool.ToolResult) {
  case provider {
    InvalidConfiguration(reason) -> tool.reject(reason)
    Ready(access, provider_runtime) -> {
      use outcome <- promise.await(fetch_company_facts(
        provider_runtime,
        access,
        input.cik,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      ))
      case outcome {
        Error(message) -> tool.reject(message)
        Ok(company) ->
          case resolve_periods(company, input.queries, input.policy, []) {
            Error(error) ->
              tool.reject(
                "SEC TTM source resolution failed safely: "
                <> string.inspect(error),
              )
            Ok(resolutions) ->
              case unique_points(resolutions, []) {
                Error(_) ->
                  tool.text_result(
                    us_text(
                      company.entity_name
                      <> ": TTM blocked because all four quarters must resolve uniquely",
                    ),
                    unresolved_ttm_json(company, input, resolutions),
                  )
                  |> promise.resolve
                Ok(points) ->
                  case derivation.trend(points, periods.Quarter) {
                    Error(error) ->
                      tool.reject(
                        "SEC TTM comparability check failed: "
                        <> string.inspect(error),
                      )
                    Ok(trend) ->
                      case stock_metrics.trailing_twelve_months(trend) {
                        Error(error) ->
                          tool.reject(
                            "SEC TTM calculation was incompatible: "
                            <> string.inspect(error),
                          )
                        Ok(trailing) ->
                          tool.text_result(
                            render_ttm(company.entity_name, trailing),
                            ttm_json(company, input, trailing),
                          )
                          |> promise.resolve
                      }
                  }
              }
          }
      }
    }
  }
}

fn execute_ttm_bridge(
  provider: Provider,
  input: TtmBridgeInput,
  id: String,
  signal: pi.AbortSignal,
) -> Promise(tool.ToolResult) {
  case provider {
    InvalidConfiguration(reason) -> tool.reject(reason)
    Ready(access, provider_runtime) -> {
      use outcome <- promise.await(fetch_company_facts(
        provider_runtime,
        access,
        input.cik,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      ))
      case outcome {
        Error(message) -> tool.reject(message)
        Ok(company) ->
          case
            fundamentals.resolve_with_policy(
              company,
              input.annual_query,
              input.annual_policy,
            ),
            fundamentals.resolve_with_policy(
              company,
              input.current_ytd_query,
              input.current_ytd_policy,
            ),
            fundamentals.resolve_with_policy(
              company,
              input.prior_ytd_query,
              input.prior_ytd_policy,
            )
          {
            Error(error), _, _ | _, Error(error), _ | _, _, Error(error) ->
              tool.reject(
                "SEC TTM bridge source resolution failed safely: "
                <> string.inspect(error),
              )
            Ok(annual), Ok(current_ytd), Ok(prior_ytd) ->
              case annual, current_ytd, prior_ytd {
                identifier.Unique(annual),
                  identifier.Unique(current_ytd),
                  identifier.Unique(prior_ytd)
                ->
                  case
                    stock_metrics.trailing_twelve_months_bridge(
                      annual,
                      current_ytd,
                      prior_ytd,
                    )
                  {
                    Error(error) ->
                      tool.reject(
                        "SEC TTM bridge calculation was incompatible: "
                        <> string.inspect(error),
                      )
                    Ok(trailing) ->
                      tool.text_result(
                        render_ttm(company.entity_name, trailing),
                        ttm_bridge_json(company, input, trailing),
                      )
                      |> promise.resolve
                  }
                _, _, _ ->
                  tool.text_result(
                    us_text(
                      company.entity_name
                      <> ": TTM bridge blocked until annual, current YTD, and prior YTD sources are unique",
                    ),
                    unresolved_ttm_bridge_json(
                      company,
                      input,
                      annual,
                      current_ytd,
                      prior_ytd,
                    ),
                  )
                  |> promise.resolve
              }
          }
      }
    }
  }
}

fn execute_composed_ttm(
  provider: Provider,
  input: ComposedTtmInput,
  id: String,
  signal: pi.AbortSignal,
) -> Promise(tool.ToolResult) {
  case provider {
    InvalidConfiguration(reason) -> tool.reject(reason)
    Ready(access, provider_runtime) -> {
      use outcome <- promise.await(fetch_company_facts(
        provider_runtime,
        access,
        input.cik,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      ))
      case outcome {
        Error(message) -> tool.reject(message)
        Ok(company) ->
          case resolve_composed_quarters(company, input.direct_queries, []) {
            Error(error) ->
              tool.reject(
                "SEC composed TTM direct-quarter resolution failed safely: "
                <> string.inspect(error),
              )
            Ok(direct_resolutions) ->
              case
                fundamentals.resolve_with_policy(
                  company,
                  input.annual_query,
                  input.annual_policy,
                ),
                fundamentals.resolve_with_policy(
                  company,
                  input.nine_month_query,
                  input.nine_month_policy,
                )
              {
                Error(error), _ | _, Error(error) ->
                  tool.reject(
                    "SEC composed TTM Q4-source resolution failed safely: "
                    <> string.inspect(error),
                  )
                Ok(annual), Ok(nine_month) ->
                  case
                    unique_composed_candidates(direct_resolutions, []),
                    annual,
                    nine_month
                  {
                    Ok(direct_candidates),
                      identifier.Unique(annual),
                      identifier.Unique(nine_month)
                    ->
                      case derivation.q4(annual, nine_month) {
                        Error(error) ->
                          tool.reject(
                            "SEC composed TTM Q4 derivation was incompatible: "
                            <> string.inspect(error),
                          )
                        Ok(q4) -> {
                          let observations = [
                            stock_metrics.DerivedQuarter(q4),
                            ..list.map(direct_candidates, fn(candidate) {
                              stock_metrics.DirectQuarter(candidate)
                            })
                          ]
                          case
                            stock_metrics.composed_trailing_twelve_months(
                              observations,
                            )
                          {
                            Error(error) ->
                              tool.reject(
                                "SEC composed TTM calculation was incompatible: "
                                <> string.inspect(error),
                              )
                            Ok(trailing) ->
                              tool.text_result(
                                render_composed_ttm(
                                  company.entity_name,
                                  trailing,
                                ),
                                composed_ttm_json(company, input, trailing),
                              )
                              |> promise.resolve
                          }
                        }
                      }
                    _, _, _ ->
                      tool.text_result(
                        us_text(
                          company.entity_name
                          <> ": composed TTM blocked until all direct and Q4 source facts are unique",
                        ),
                        unresolved_composed_ttm_json(
                          company,
                          input,
                          direct_resolutions,
                          annual,
                          nine_month,
                        ),
                      )
                      |> promise.resolve
                  }
              }
          }
      }
    }
  }
}

fn resolve_composed_quarters(
  company: xbrl.CompanyFacts,
  queries: List(ComposedQuarterQuery),
  out: List(ResolvedComposedQuarter),
) -> Result(List(ResolvedComposedQuarter), fundamentals.ResolveError) {
  case queries {
    [] -> Ok(list.reverse(out))
    [ComposedQuarterQuery(end, query, policy), ..rest] -> {
      use resolution <- result.try(fundamentals.resolve_with_policy(
        company,
        query,
        policy,
      ))
      resolve_composed_quarters(company, rest, [
        ResolvedComposedQuarter(end, policy, resolution),
        ..out
      ])
    }
  }
}

fn unique_composed_candidates(
  values: List(ResolvedComposedQuarter),
  out: List(fundamentals.Candidate),
) -> Result(List(fundamentals.Candidate), Nil) {
  case values {
    [] -> Ok(list.reverse(out))
    [ResolvedComposedQuarter(_, _, identifier.Unique(candidate)), ..rest] ->
      unique_composed_candidates(rest, [candidate, ..out])
    _ -> Error(Nil)
  }
}

fn execute_calculated_metric(
  provider: Provider,
  input: CalculatedMetricInput,
  id: String,
  signal: pi.AbortSignal,
) -> Promise(tool.ToolResult) {
  case provider {
    InvalidConfiguration(reason) -> tool.reject(reason)
    Ready(access, provider_runtime) -> {
      use outcome <- promise.await(fetch_company_facts(
        provider_runtime,
        access,
        input.cik,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      ))
      case outcome {
        Error(message) -> tool.reject(message)
        Ok(company) ->
          case resolve_metric_sources(company, input.queries, []) {
            Error(error) ->
              tool.reject(
                "SEC calculated-metric source resolution failed safely: "
                <> string.inspect(error),
              )
            Ok(resolutions) ->
              case unique_metric_candidates(resolutions, []) {
                Error(_) ->
                  tool.text_result(
                    us_text(
                      company.entity_name
                      <> ": calculation blocked because every required source must resolve uniquely",
                    ),
                    unresolved_metric_json(company, input, resolutions),
                  )
                  |> promise.resolve
                Ok(candidates) ->
                  case
                    stock_metrics.calculate(
                      input.kind,
                      candidates,
                      input.period_class,
                      input.scale,
                    )
                  {
                    Error(error) ->
                      tool.reject(
                        "SEC calculated metric was incompatible: "
                        <> string.inspect(error),
                      )
                    Ok(derived) ->
                      tool.text_result(
                        render_calculated_metric(company.entity_name, derived),
                        calculated_metric_json(company, input, derived),
                      )
                      |> promise.resolve
                  }
              }
          }
      }
    }
  }
}

fn resolve_metric_sources(
  company: xbrl.CompanyFacts,
  queries: List(MetricQuery),
  out: List(ResolvedMetricSource),
) -> Result(List(ResolvedMetricSource), fundamentals.ResolveError) {
  case queries {
    [] -> Ok(list.reverse(out))
    [MetricQuery(name, query, policy), ..rest] -> {
      use resolution <- result.try(fundamentals.resolve_with_policy(
        company,
        query,
        policy,
      ))
      resolve_metric_sources(company, rest, [
        ResolvedMetricSource(name, policy, resolution),
        ..out
      ])
    }
  }
}

fn unique_metric_candidates(
  values: List(ResolvedMetricSource),
  out: List(fundamentals.Candidate),
) -> Result(List(fundamentals.Candidate), Nil) {
  case values {
    [] -> Ok(list.reverse(out))
    [ResolvedMetricSource(_, _, identifier.Unique(candidate)), ..rest] ->
      unique_metric_candidates(rest, [candidate, ..out])
    _ -> Error(Nil)
  }
}

fn resolve_periods(
  company: xbrl.CompanyFacts,
  queries: List(#(String, fundamentals.Query)),
  policy: fundamentals.FilingPolicy,
  out: List(ResolvedPeriod),
) -> Result(List(ResolvedPeriod), fundamentals.ResolveError) {
  case queries {
    [] -> Ok(list.reverse(out))
    [#(end, query), ..rest] -> {
      use resolution <- result.try(fundamentals.resolve_with_policy(
        company,
        query,
        policy,
      ))
      resolve_periods(company, rest, policy, [
        ResolvedPeriod(end, resolution),
        ..out
      ])
    }
  }
}

fn unique_points(
  resolutions: List(ResolvedPeriod),
  out: List(fundamentals.Candidate),
) -> Result(List(fundamentals.Candidate), Nil) {
  case resolutions {
    [] -> Ok(list.reverse(out))
    [ResolvedPeriod(_, identifier.Unique(candidate)), ..rest] ->
      unique_points(rest, [candidate, ..out])
    _ -> Error(Nil)
  }
}

fn provider() -> Provider {
  case finance_sec.access(environment.product(), environment.contact()) {
    Error(_) ->
      InvalidConfiguration(
        "SEC access requires AGENT_CONTACT (for example ops@example.com)",
      )
    Ok(access) ->
      case runtime.new(access) {
        Error(_) ->
          InvalidConfiguration(
            "SEC fundamentals runtime could not initialize safely",
          )
        Ok(provider_runtime) -> Ready(access, provider_runtime)
      }
  }
}

fn fetch_company_facts(
  provider_runtime: runtime.Runtime,
  access: finance_sec.Access,
  cik: finance_sec.Cik,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(xbrl.CompanyFacts, String)) {
  case request.company_facts(access, cik) {
    Error(_) -> promise.resolve(Error("SEC company-facts request was invalid"))
    Ok(request_value) -> {
      use outcome <- promise.await(runtime.send(
        provider_runtime,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      case outcome {
        Error(error) ->
          promise.resolve(Error(
            "SEC company-facts request failed safely: " <> string.inspect(error),
          ))
        Ok(response) -> {
          let status = http_response.status(response)
          case status >= 200 && status < 300 {
            False ->
              promise.resolve(Error(
                "SEC company-facts request returned HTTP "
                <> int.to_string(status),
              ))
            True ->
              case xbrl.decode_company_facts(http_response.body(response)) {
                Error(_) ->
                  promise.resolve(Error(
                    "SEC returned invalid company-facts data",
                  ))
                Ok(company) -> promise.resolve(Ok(company))
              }
          }
        }
      }
    }
  }
}

fn fundamental_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "cik",
      schema.string()
        |> schema.with_string_length(1, 10)
        |> schema.described("SEC CIK, with or without leading zeroes"),
    ),
    schema.Required(
      "metric",
      schema.string_enum(metric_names())
        |> schema.described("One audited initial metric definition"),
    ),
    schema.Required(
      "unit",
      schema.string()
        |> schema.with_string_length(1, 100)
        |> schema.described("Exact SEC unit key, for example USD or shares"),
    ),
    schema.Optional(
      "start",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described(
          "Exact YYYY-MM-DD start; required for duration metrics and forbidden for instant metrics",
        ),
    ),
    schema.Required(
      "end",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Exact YYYY-MM-DD period end or instant date"),
    ),
    schema.Optional(
      "form",
      schema.string()
        |> schema.with_string_length(1, 20)
        |> schema.described("Optional exact form, such as 10-K or 10-K/A"),
    ),
  ])
}

fn period_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "cik",
      schema.string()
        |> schema.with_string_length(1, 10)
        |> schema.described("SEC CIK, with or without leading zeroes"),
    ),
    schema.Required("metric", schema.string_enum(metric_names())),
    schema.Required(
      "unit",
      schema.string()
        |> schema.with_string_length(1, 100)
        |> schema.described("Exact SEC unit key"),
    ),
    schema.Required(
      "period",
      schema.string_enum([
        "instant",
        "quarter",
        "half_year_ytd",
        "nine_month_ytd",
        "annual",
      ])
        |> schema.described("Calendar-shape class ending on the supplied date"),
    ),
    schema.Required(
      "end",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Exact YYYY-MM-DD period end"),
    ),
    schema.Optional(
      "form",
      schema.string()
        |> schema.with_string_length(1, 20)
        |> schema.described("Optional exact SEC form"),
    ),
    schema.Optional(
      "filingPolicy",
      schema.string_enum([
        "preserve_all",
        "original_only",
        "amendments_only",
        "latest_filed",
        "exact_accession",
      ])
        |> schema.described(
          "Explicit precedence policy; defaults to preserve_all",
        ),
    ),
    schema.Optional(
      "accession",
      schema.string()
        |> schema.with_string_length(1, 100)
        |> schema.described("Required when filingPolicy is exact_accession"),
    ),
  ])
}

fn q4_schema() -> schema.Schema {
  schema.object([
    schema.Required("cik", schema.string() |> schema.with_string_length(1, 10)),
    schema.Required(
      "metric",
      schema.string_enum([
        "revenue",
        "net_income",
        "operating_cash_flow",
        "capital_expenditures_reported",
      ])
        |> schema.described(
          "Additive duration metric eligible for Q4 subtraction",
        ),
    ),
    schema.Required(
      "unit",
      schema.string() |> schema.with_string_length(1, 100),
    ),
    schema.Required(
      "annualEnd",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Exact annual period end"),
    ),
    schema.Required(
      "nineMonthEnd",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Exact nine-month YTD period end"),
    ),
    schema.Optional(
      "annualForm",
      schema.string() |> schema.with_string_length(1, 20),
    ),
    schema.Optional(
      "nineMonthForm",
      schema.string() |> schema.with_string_length(1, 20),
    ),
    schema.Optional(
      "filingPolicy",
      filing_policy_schema()
        |> schema.described(
          "Base policy for each source; defaults to preserve_all",
        ),
    ),
    schema.Optional(
      "annualAccession",
      schema.string()
        |> schema.with_string_length(1, 100)
        |> schema.described("Optional exact annual source accession"),
    ),
    schema.Optional(
      "nineMonthAccession",
      schema.string()
        |> schema.with_string_length(1, 100)
        |> schema.described("Optional exact nine-month source accession"),
    ),
  ])
}

fn trend_schema() -> schema.Schema {
  schema.object([
    schema.Required("cik", schema.string() |> schema.with_string_length(1, 10)),
    schema.Required("metric", schema.string_enum(metric_names())),
    schema.Required(
      "unit",
      schema.string() |> schema.with_string_length(1, 100),
    ),
    schema.Required(
      "period",
      schema.string_enum([
        "instant",
        "quarter",
        "half_year_ytd",
        "nine_month_ytd",
        "annual",
      ]),
    ),
    schema.Required(
      "ends",
      schema.array(
        schema.string()
        |> schema.with_string_length(10, 10),
      )
        |> schema.with_array_length(2, 20)
        |> schema.described("Two to twenty exact period-end dates"),
    ),
    schema.Optional("form", schema.string() |> schema.with_string_length(1, 20)),
    schema.Optional(
      "filingPolicy",
      filing_policy_schema()
        |> schema.described("One explicit policy applied to every period"),
    ),
  ])
}

fn growth_schema() -> schema.Schema {
  schema.object([
    schema.Required("cik", schema.string() |> schema.with_string_length(1, 10)),
    schema.Required("metric", schema.string_enum(metric_names())),
    schema.Required(
      "unit",
      schema.string() |> schema.with_string_length(1, 100),
    ),
    schema.Required(
      "period",
      schema.string_enum([
        "instant",
        "quarter",
        "half_year_ytd",
        "nine_month_ytd",
        "annual",
      ]),
    ),
    schema.Required(
      "comparison",
      schema.string_enum(["quarter_over_quarter", "year_over_year"])
        |> schema.described(
          "Required calendar gap between adjacent period-end dates",
        ),
    ),
    schema.Required(
      "ends",
      schema.array(schema.string() |> schema.with_string_length(10, 10))
        |> schema.with_array_length(2, 20),
    ),
    schema.Optional("form", schema.string() |> schema.with_string_length(1, 20)),
    schema.Optional("filingPolicy", filing_policy_schema()),
    schema.Optional(
      "scale",
      schema.integer()
        |> schema.with_number_range(0.0, 18.0)
        |> schema.described(
          "Percentage-point decimal places; defaults to 4 with half-even rounding",
        ),
    ),
  ])
}

fn ttm_schema() -> schema.Schema {
  schema.object([
    schema.Required("cik", schema.string() |> schema.with_string_length(1, 10)),
    schema.Required(
      "metric",
      schema.string_enum([
        "revenue",
        "net_income",
        "operating_cash_flow",
        "capital_expenditures_reported",
      ]),
    ),
    schema.Required(
      "unit",
      schema.string()
        |> schema.with_string_length(3, 3)
        |> schema.described("Exact three-letter SEC monetary unit such as USD"),
    ),
    schema.Required(
      "ends",
      schema.array(schema.string() |> schema.with_string_length(10, 10))
        |> schema.with_array_length(4, 4)
        |> schema.described("Exactly four direct-quarter end dates"),
    ),
    schema.Optional("form", schema.string() |> schema.with_string_length(1, 20)),
    schema.Optional("filingPolicy", filing_policy_schema()),
  ])
}

fn ttm_bridge_schema() -> schema.Schema {
  schema.object([
    schema.Required("cik", schema.string() |> schema.with_string_length(1, 10)),
    schema.Required(
      "metric",
      schema.string_enum([
        "revenue",
        "net_income",
        "operating_cash_flow",
        "capital_expenditures_reported",
      ]),
    ),
    schema.Required(
      "unit",
      schema.string()
        |> schema.with_string_length(3, 3)
        |> schema.described("Exact three-letter SEC monetary unit such as USD"),
    ),
    schema.Required(
      "ytdPeriod",
      schema.string_enum(["quarter", "half_year_ytd", "nine_month_ytd"]),
    ),
    schema.Required(
      "annualEnd",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Required(
      "currentYtdEnd",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Required(
      "priorYtdEnd",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Optional(
      "annualForm",
      schema.string() |> schema.with_string_length(1, 20),
    ),
    schema.Optional(
      "currentYtdForm",
      schema.string() |> schema.with_string_length(1, 20),
    ),
    schema.Optional(
      "priorYtdForm",
      schema.string() |> schema.with_string_length(1, 20),
    ),
    schema.Optional("filingPolicy", filing_policy_schema()),
    schema.Optional(
      "annualAccession",
      schema.string() |> schema.with_string_length(1, 100),
    ),
    schema.Optional(
      "currentYtdAccession",
      schema.string() |> schema.with_string_length(1, 100),
    ),
    schema.Optional(
      "priorYtdAccession",
      schema.string() |> schema.with_string_length(1, 100),
    ),
  ])
}

fn composed_ttm_schema() -> schema.Schema {
  schema.object([
    schema.Required("cik", schema.string() |> schema.with_string_length(1, 10)),
    schema.Required(
      "metric",
      schema.string_enum([
        "revenue",
        "net_income",
        "operating_cash_flow",
        "capital_expenditures_reported",
      ]),
    ),
    schema.Required(
      "unit",
      schema.string()
        |> schema.with_string_length(3, 3)
        |> schema.described("Exact three-letter SEC monetary unit such as USD"),
    ),
    schema.Required(
      "directEnds",
      schema.array(schema.string() |> schema.with_string_length(10, 10))
        |> schema.with_array_length(3, 3)
        |> schema.described("Exactly three directly reported quarter ends"),
    ),
    schema.Optional(
      "directAccessions",
      schema.array(schema.string() |> schema.with_string_length(1, 100))
        |> schema.with_array_length(3, 3)
        |> schema.described(
          "Optional exact accessions aligned positionally with directEnds",
        ),
    ),
    schema.Required(
      "annualEnd",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Required(
      "nineMonthEnd",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Optional(
      "directForm",
      schema.string() |> schema.with_string_length(1, 20),
    ),
    schema.Optional(
      "annualForm",
      schema.string() |> schema.with_string_length(1, 20),
    ),
    schema.Optional(
      "nineMonthForm",
      schema.string() |> schema.with_string_length(1, 20),
    ),
    schema.Optional("filingPolicy", filing_policy_schema()),
    schema.Optional(
      "annualAccession",
      schema.string() |> schema.with_string_length(1, 100),
    ),
    schema.Optional(
      "nineMonthAccession",
      schema.string() |> schema.with_string_length(1, 100),
    ),
  ])
}

fn calculated_metric_schema() -> schema.Schema {
  schema.object([
    schema.Required("cik", schema.string() |> schema.with_string_length(1, 10)),
    schema.Required(
      "metric",
      schema.string_enum(["free_cash_flow", "net_margin", "diluted_eps"]),
    ),
    schema.Required(
      "currencyUnit",
      schema.string()
        |> schema.with_string_length(3, 3)
        |> schema.described("Exact three-letter SEC monetary unit such as USD"),
    ),
    schema.Optional(
      "sharesUnit",
      schema.string()
        |> schema.with_string_length(1, 30)
        |> schema.described("Exact SEC shares unit; defaults to shares"),
    ),
    schema.Required(
      "period",
      schema.string_enum([
        "quarter",
        "half_year_ytd",
        "nine_month_ytd",
        "annual",
      ]),
    ),
    schema.Required(
      "end",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Exact YYYY-MM-DD period end shared by all inputs"),
    ),
    schema.Optional("form", schema.string() |> schema.with_string_length(1, 20)),
    schema.Optional(
      "filingPolicy",
      filing_policy_schema()
        |> schema.described("One explicit policy applied to every input"),
    ),
    schema.Optional(
      "sourceAccessions",
      schema.object([
        schema.Optional(
          "operating_cash_flow",
          schema.string() |> schema.with_string_length(1, 100),
        ),
        schema.Optional(
          "capital_expenditures_reported",
          schema.string() |> schema.with_string_length(1, 100),
        ),
        schema.Optional(
          "net_income",
          schema.string() |> schema.with_string_length(1, 100),
        ),
        schema.Optional(
          "revenue",
          schema.string() |> schema.with_string_length(1, 100),
        ),
        schema.Optional(
          "diluted_weighted_average_shares",
          schema.string() |> schema.with_string_length(1, 100),
        ),
      ])
        |> schema.described(
          "Optional exact accession per named formula input; unspecified inputs use filingPolicy",
        ),
    ),
    schema.Optional(
      "scale",
      schema.integer()
        |> schema.with_number_range(0.0, 18.0)
        |> schema.described(
          "Decimal places for division metrics; defaults to 4 and uses half-even rounding",
        ),
    ),
  ])
}

fn filing_policy_schema() -> schema.Schema {
  schema.string_enum([
    "preserve_all",
    "original_only",
    "amendments_only",
    "latest_filed",
  ])
}

fn definitions_decoder() -> decode.Decoder(DefinitionsInput) {
  decode.success(DefinitionsInput)
}

fn fundamental_decoder() -> decode.Decoder(FundamentalInput) {
  use cik_value <- decode.field("cik", decode.string)
  use metric_name <- decode.field("metric", decode.string)
  use unit <- decode.field("unit", decode.string)
  use start <- optional_string_field("start")
  use end <- decode.field("end", decode.string)
  use form <- optional_string_field("form")
  let assert Ok(placeholder_cik) = finance_sec.cik("0")
  let assert Ok(placeholder_query) =
    fundamentals.query(fundamentals.Assets, "USD", None, "2024-12-31", None)
  case fundamentals.metric(metric_name), finance_sec.cik(cik_value) {
    Ok(metric), Ok(cik) ->
      case fundamentals.query(metric, unit, start, end, form) {
        Ok(query) -> decode.success(FundamentalInput(cik, query))
        Error(_) ->
          decode.failure(
            FundamentalInput(placeholder_cik, placeholder_query),
            "valid metric period, unit, and form",
          )
      }
    _, _ ->
      decode.failure(
        FundamentalInput(placeholder_cik, placeholder_query),
        "valid SEC fundamental request",
      )
  }
}

fn period_decoder() -> decode.Decoder(PeriodInput) {
  use cik_value <- decode.field("cik", decode.string)
  use metric_name <- decode.field("metric", decode.string)
  use unit <- decode.field("unit", decode.string)
  use period_name <- decode.field("period", decode.string)
  use end <- decode.field("end", decode.string)
  use form <- optional_string_field("form")
  use policy_name <- decode.optional_field(
    "filingPolicy",
    "preserve_all",
    decode.string,
  )
  use accession <- optional_string_field("accession")
  let assert Ok(placeholder_cik) = finance_sec.cik("0")
  let assert Ok(placeholder_target) =
    periods.target(periods.Instant, "2024-12-31")
  let assert Ok(placeholder_query) =
    fundamentals.period_query(
      fundamentals.Assets,
      "USD",
      placeholder_target,
      None,
    )
  let assert Ok(placeholder_policy) =
    fundamentals.filing_policy("preserve_all", None)
  case
    finance_sec.cik(cik_value),
    fundamentals.metric(metric_name),
    period_class(period_name)
  {
    Ok(cik), Ok(metric), Ok(class) ->
      case
        periods.target(class, end),
        fundamentals.filing_policy(policy_name, accession)
      {
        Ok(target), Ok(policy) ->
          case fundamentals.period_query(metric, unit, target, form) {
            Ok(query) -> decode.success(PeriodInput(cik, query, policy))
            Error(_) ->
              period_decode_failure(
                placeholder_cik,
                placeholder_query,
                placeholder_policy,
              )
          }
        _, _ ->
          period_decode_failure(
            placeholder_cik,
            placeholder_query,
            placeholder_policy,
          )
      }
    _, _, _ ->
      period_decode_failure(
        placeholder_cik,
        placeholder_query,
        placeholder_policy,
      )
  }
}

fn q4_decoder() -> decode.Decoder(Q4Input) {
  use cik_value <- decode.field("cik", decode.string)
  use metric_name <- decode.field("metric", decode.string)
  use unit <- decode.field("unit", decode.string)
  use annual_end <- decode.field("annualEnd", decode.string)
  use nine_month_end <- decode.field("nineMonthEnd", decode.string)
  use annual_form <- optional_string_field("annualForm")
  use nine_month_form <- optional_string_field("nineMonthForm")
  use policy_name <- decode.optional_field(
    "filingPolicy",
    "preserve_all",
    decode.string,
  )
  use annual_accession <- optional_string_field("annualAccession")
  use nine_month_accession <- optional_string_field("nineMonthAccession")
  let placeholder = placeholder_q4_input()
  case
    finance_sec.cik(cik_value),
    q4_metric(metric_name),
    fundamentals.filing_policy(policy_name, None),
    periods.target(periods.Annual, annual_end),
    periods.target(periods.NineMonthToDate, nine_month_end)
  {
    Ok(cik), Ok(metric), Ok(base_policy), Ok(annual_target), Ok(ytd_target) ->
      case
        fundamentals.period_query(metric, unit, annual_target, annual_form),
        fundamentals.period_query(metric, unit, ytd_target, nine_month_form),
        source_policy(base_policy, annual_accession),
        source_policy(base_policy, nine_month_accession)
      {
        Ok(annual_query), Ok(ytd_query), Ok(annual_policy), Ok(ytd_policy) ->
          decode.success(Q4Input(
            cik,
            annual_query,
            ytd_query,
            annual_policy,
            ytd_policy,
          ))
        _, _, _, _ -> decode.failure(placeholder, "valid strict Q4 derivation")
      }
    _, _, _, _, _ -> decode.failure(placeholder, "valid strict Q4 derivation")
  }
}

fn trend_decoder() -> decode.Decoder(TrendInput) {
  use cik_value <- decode.field("cik", decode.string)
  use metric_name <- decode.field("metric", decode.string)
  use unit <- decode.field("unit", decode.string)
  use period_name <- decode.field("period", decode.string)
  use ends <- decode.field("ends", decode.list(of: decode.string))
  use form <- optional_string_field("form")
  use policy_name <- decode.optional_field(
    "filingPolicy",
    "preserve_all",
    decode.string,
  )
  let placeholder = placeholder_trend_input()
  case
    finance_sec.cik(cik_value),
    fundamentals.metric(metric_name),
    period_class(period_name),
    fundamentals.filing_policy(policy_name, None),
    list.length(ends) >= 2 && list.length(ends) <= 20
  {
    Ok(cik), Ok(metric), Ok(class), Ok(policy), True ->
      case build_trend_queries(metric, unit, class, ends, form, []) {
        Error(_) ->
          decode.failure(placeholder, "valid comparable trend periods")
        Ok(queries) -> decode.success(TrendInput(cik, queries, policy, class))
      }
    _, _, _, _, _ ->
      decode.failure(placeholder, "valid comparable trend periods")
  }
}

fn growth_decoder() -> decode.Decoder(GrowthInput) {
  use cik_value <- decode.field("cik", decode.string)
  use metric_name <- decode.field("metric", decode.string)
  use unit <- decode.field("unit", decode.string)
  use period_name <- decode.field("period", decode.string)
  use comparison <- decode.field("comparison", decode.string)
  use ends <- decode.field("ends", decode.list(of: decode.string))
  use form <- optional_string_field("form")
  use policy_name <- decode.optional_field(
    "filingPolicy",
    "preserve_all",
    decode.string,
  )
  use scale <- decode.optional_field("scale", 4, decode.int)
  let placeholder = placeholder_growth_input()
  case
    finance_sec.cik(cik_value),
    fundamentals.metric(metric_name),
    period_class(period_name),
    stock_metrics.growth_gap(comparison),
    fundamentals.filing_policy(policy_name, None),
    list.length(ends) >= 2 && list.length(ends) <= 20,
    scale >= 0 && scale <= 18
  {
    Ok(cik), Ok(metric), Ok(class), Ok(gap), Ok(policy), True, True ->
      case build_trend_queries(metric, unit, class, ends, form, []) {
        Error(_) -> decode.failure(placeholder, "valid exact growth series")
        Ok(queries) ->
          decode.success(GrowthInput(cik, queries, policy, class, gap, scale))
      }
    _, _, _, _, _, _, _ ->
      decode.failure(placeholder, "valid exact growth series")
  }
}

fn ttm_decoder() -> decode.Decoder(TtmInput) {
  use cik_value <- decode.field("cik", decode.string)
  use metric_name <- decode.field("metric", decode.string)
  use unit <- decode.field("unit", decode.string)
  use ends <- decode.field("ends", decode.list(of: decode.string))
  use form <- optional_string_field("form")
  use policy_name <- decode.optional_field(
    "filingPolicy",
    "preserve_all",
    decode.string,
  )
  let placeholder = placeholder_ttm_input()
  case
    finance_sec.cik(cik_value),
    q4_metric(metric_name),
    fundamentals.filing_policy(policy_name, None),
    list.length(ends) == 4
  {
    Ok(cik), Ok(metric), Ok(policy), True ->
      case build_trend_queries(metric, unit, periods.Quarter, ends, form, []) {
        Error(_) -> decode.failure(placeholder, "valid direct-quarter TTM")
        Ok(queries) -> decode.success(TtmInput(cik, queries, policy))
      }
    _, _, _, _ -> decode.failure(placeholder, "valid direct-quarter TTM")
  }
}

fn ttm_bridge_decoder() -> decode.Decoder(TtmBridgeInput) {
  use cik_value <- decode.field("cik", decode.string)
  use metric_name <- decode.field("metric", decode.string)
  use unit <- decode.field("unit", decode.string)
  use ytd_period_name <- decode.field("ytdPeriod", decode.string)
  use annual_end <- decode.field("annualEnd", decode.string)
  use current_ytd_end <- decode.field("currentYtdEnd", decode.string)
  use prior_ytd_end <- decode.field("priorYtdEnd", decode.string)
  use annual_form <- optional_string_field("annualForm")
  use current_ytd_form <- optional_string_field("currentYtdForm")
  use prior_ytd_form <- optional_string_field("priorYtdForm")
  use policy_name <- decode.optional_field(
    "filingPolicy",
    "preserve_all",
    decode.string,
  )
  use annual_accession <- optional_string_field("annualAccession")
  use current_ytd_accession <- optional_string_field("currentYtdAccession")
  use prior_ytd_accession <- optional_string_field("priorYtdAccession")
  let placeholder = placeholder_ttm_bridge_input()
  case
    finance_sec.cik(cik_value),
    q4_metric(metric_name),
    ytd_period_class(ytd_period_name),
    fundamentals.filing_policy(policy_name, None),
    periods.target(periods.Annual, annual_end)
  {
    Ok(cik), Ok(metric), Ok(ytd_class), Ok(base_policy), Ok(annual_target) ->
      case
        periods.target(ytd_class, current_ytd_end),
        periods.target(ytd_class, prior_ytd_end)
      {
        Ok(current_target), Ok(prior_target) ->
          case
            fundamentals.period_query(metric, unit, annual_target, annual_form),
            fundamentals.period_query(
              metric,
              unit,
              current_target,
              current_ytd_form,
            ),
            fundamentals.period_query(
              metric,
              unit,
              prior_target,
              prior_ytd_form,
            ),
            source_policy(base_policy, annual_accession),
            source_policy(base_policy, current_ytd_accession),
            source_policy(base_policy, prior_ytd_accession)
          {
            Ok(annual_query),
              Ok(current_query),
              Ok(prior_query),
              Ok(annual_policy),
              Ok(current_policy),
              Ok(prior_policy)
            ->
              decode.success(TtmBridgeInput(
                cik,
                annual_query,
                current_query,
                prior_query,
                annual_policy,
                current_policy,
                prior_policy,
              ))
            _, _, _, _, _, _ ->
              decode.failure(placeholder, "valid annual-plus-YTD TTM bridge")
          }
        _, _ -> decode.failure(placeholder, "valid annual-plus-YTD TTM bridge")
      }
    _, _, _, _, _ ->
      decode.failure(placeholder, "valid annual-plus-YTD TTM bridge")
  }
}

fn composed_ttm_decoder() -> decode.Decoder(ComposedTtmInput) {
  use cik_value <- decode.field("cik", decode.string)
  use metric_name <- decode.field("metric", decode.string)
  use unit <- decode.field("unit", decode.string)
  use direct_ends <- decode.field("directEnds", decode.list(of: decode.string))
  use direct_accessions <- decode.optional_field(
    "directAccessions",
    [],
    decode.list(of: decode.string),
  )
  use annual_end <- decode.field("annualEnd", decode.string)
  use nine_month_end <- decode.field("nineMonthEnd", decode.string)
  use direct_form <- optional_string_field("directForm")
  use annual_form <- optional_string_field("annualForm")
  use nine_month_form <- optional_string_field("nineMonthForm")
  use policy_name <- decode.optional_field(
    "filingPolicy",
    "preserve_all",
    decode.string,
  )
  use annual_accession <- optional_string_field("annualAccession")
  use nine_month_accession <- optional_string_field("nineMonthAccession")
  let placeholder = placeholder_composed_ttm_input()
  case
    finance_sec.cik(cik_value),
    q4_metric(metric_name),
    fundamentals.filing_policy(policy_name, None),
    periods.target(periods.Annual, annual_end),
    periods.target(periods.NineMonthToDate, nine_month_end),
    list.length(direct_ends) == 3,
    direct_accessions == [] || list.length(direct_accessions) == 3
  {
    Ok(cik),
      Ok(metric),
      Ok(base_policy),
      Ok(annual_target),
      Ok(ytd_target),
      True,
      True
    ->
      case
        build_composed_direct_queries(
          direct_ends,
          direct_accessions,
          metric,
          unit,
          direct_form,
          base_policy,
          [],
        ),
        fundamentals.period_query(metric, unit, annual_target, annual_form),
        fundamentals.period_query(metric, unit, ytd_target, nine_month_form),
        source_policy(base_policy, annual_accession),
        source_policy(base_policy, nine_month_accession)
      {
        Ok(direct_queries),
          Ok(annual_query),
          Ok(ytd_query),
          Ok(annual_policy),
          Ok(ytd_policy)
        ->
          decode.success(ComposedTtmInput(
            cik,
            direct_queries,
            annual_query,
            ytd_query,
            annual_policy,
            ytd_policy,
          ))
        _, _, _, _, _ ->
          decode.failure(placeholder, "valid composed direct/derived TTM")
      }
    _, _, _, _, _, _, _ ->
      decode.failure(placeholder, "valid composed direct/derived TTM")
  }
}

fn calculated_metric_decoder() -> decode.Decoder(CalculatedMetricInput) {
  use cik_value <- decode.field("cik", decode.string)
  use metric_name <- decode.field("metric", decode.string)
  use currency_unit <- decode.field("currencyUnit", decode.string)
  use shares_unit <- decode.optional_field(
    "sharesUnit",
    "shares",
    decode.string,
  )
  use period_name <- decode.field("period", decode.string)
  use end <- decode.field("end", decode.string)
  use form <- optional_string_field("form")
  use policy_name <- decode.optional_field(
    "filingPolicy",
    "preserve_all",
    decode.string,
  )
  use source_accessions <- decode.optional_field(
    "sourceAccessions",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )
  use scale <- decode.optional_field("scale", 4, decode.int)
  let placeholder = placeholder_calculated_metric_input()
  case
    finance_sec.cik(cik_value),
    stock_metrics.kind(metric_name),
    duration_period_class(period_name),
    fundamentals.filing_policy(policy_name, None),
    valid_source_accessions(stock_metrics.kind(metric_name), source_accessions),
    scale >= 0 && scale <= 18
  {
    Ok(cik), Ok(kind), Ok(class), Ok(policy), True, True ->
      case periods.target(class, end) {
        Error(_) -> decode.failure(placeholder, "valid calculated SEC metric")
        Ok(target) ->
          case
            build_metric_queries(
              stock_metrics.required_inputs(kind),
              currency_unit,
              shares_unit,
              target,
              form,
              policy,
              source_accessions,
              [],
            )
          {
            Error(_) ->
              decode.failure(placeholder, "valid calculated SEC metric")
            Ok(queries) ->
              decode.success(CalculatedMetricInput(
                cik,
                kind,
                queries,
                policy,
                class,
                scale,
              ))
          }
      }
    _, _, _, _, _, _ ->
      decode.failure(placeholder, "valid calculated SEC metric")
  }
}

fn placeholder_q4_input() -> Q4Input {
  let assert Ok(cik) = finance_sec.cik("0")
  let assert Ok(annual_target) = periods.target(periods.Annual, "2024-12-31")
  let assert Ok(ytd_target) =
    periods.target(periods.NineMonthToDate, "2024-09-30")
  let assert Ok(annual_query) =
    fundamentals.period_query(fundamentals.Revenue, "USD", annual_target, None)
  let assert Ok(ytd_query) =
    fundamentals.period_query(fundamentals.Revenue, "USD", ytd_target, None)
  let assert Ok(policy) = fundamentals.filing_policy("preserve_all", None)
  Q4Input(cik, annual_query, ytd_query, policy, policy)
}

fn placeholder_trend_input() -> TrendInput {
  let assert Ok(cik) = finance_sec.cik("0")
  let assert Ok(target) = periods.target(periods.Annual, "2024-12-31")
  let assert Ok(query) =
    fundamentals.period_query(fundamentals.Revenue, "USD", target, None)
  let assert Ok(policy) = fundamentals.filing_policy("preserve_all", None)
  TrendInput(
    cik,
    [#("2024-12-31", query), #("2024-12-31", query)],
    policy,
    periods.Annual,
  )
}

fn placeholder_growth_input() -> GrowthInput {
  let assert Ok(cik) = finance_sec.cik("0")
  let assert Ok(first_target) = periods.target(periods.Annual, "2023-12-31")
  let assert Ok(second_target) = periods.target(periods.Annual, "2024-12-31")
  let assert Ok(first) =
    fundamentals.period_query(fundamentals.Revenue, "USD", first_target, None)
  let assert Ok(second) =
    fundamentals.period_query(fundamentals.Revenue, "USD", second_target, None)
  let assert Ok(policy) = fundamentals.filing_policy("preserve_all", None)
  GrowthInput(
    cik,
    [#("2023-12-31", first), #("2024-12-31", second)],
    policy,
    periods.Annual,
    stock_metrics.YearOverYear,
    4,
  )
}

fn placeholder_ttm_input() -> TtmInput {
  let assert Ok(cik) = finance_sec.cik("0")
  let ends = ["2024-03-31", "2024-06-30", "2024-09-30", "2024-12-31"]
  let assert Ok(queries) =
    build_trend_queries(
      fundamentals.Revenue,
      "USD",
      periods.Quarter,
      ends,
      None,
      [],
    )
  let assert Ok(policy) = fundamentals.filing_policy("preserve_all", None)
  TtmInput(cik, queries, policy)
}

fn placeholder_ttm_bridge_input() -> TtmBridgeInput {
  let assert Ok(cik) = finance_sec.cik("0")
  let assert Ok(annual_target) = periods.target(periods.Annual, "2024-12-31")
  let assert Ok(current_target) =
    periods.target(periods.NineMonthToDate, "2025-09-30")
  let assert Ok(prior_target) =
    periods.target(periods.NineMonthToDate, "2024-09-30")
  let assert Ok(annual) =
    fundamentals.period_query(fundamentals.Revenue, "USD", annual_target, None)
  let assert Ok(current) =
    fundamentals.period_query(fundamentals.Revenue, "USD", current_target, None)
  let assert Ok(prior) =
    fundamentals.period_query(fundamentals.Revenue, "USD", prior_target, None)
  let assert Ok(policy) = fundamentals.filing_policy("preserve_all", None)
  TtmBridgeInput(cik, annual, current, prior, policy, policy, policy)
}

fn placeholder_composed_ttm_input() -> ComposedTtmInput {
  let assert Ok(cik) = finance_sec.cik("0")
  let assert Ok(policy) = fundamentals.filing_policy("preserve_all", None)
  let assert Ok(direct_queries) =
    build_composed_direct_queries(
      ["2025-03-31", "2025-06-30", "2025-09-30"],
      [],
      fundamentals.Revenue,
      "USD",
      None,
      policy,
      [],
    )
  let assert Ok(annual_target) = periods.target(periods.Annual, "2024-12-31")
  let assert Ok(ytd_target) =
    periods.target(periods.NineMonthToDate, "2024-09-30")
  let assert Ok(annual) =
    fundamentals.period_query(fundamentals.Revenue, "USD", annual_target, None)
  let assert Ok(ytd) =
    fundamentals.period_query(fundamentals.Revenue, "USD", ytd_target, None)
  ComposedTtmInput(cik, direct_queries, annual, ytd, policy, policy)
}

fn placeholder_calculated_metric_input() -> CalculatedMetricInput {
  let assert Ok(cik) = finance_sec.cik("0")
  let assert Ok(target) = periods.target(periods.Annual, "2024-12-31")
  let assert Ok(operating) =
    fundamentals.period_query(
      fundamentals.OperatingCashFlow,
      "USD",
      target,
      None,
    )
  let assert Ok(capex) =
    fundamentals.period_query(
      fundamentals.CapitalExpendituresReported,
      "USD",
      target,
      None,
    )
  let assert Ok(policy) = fundamentals.filing_policy("preserve_all", None)
  CalculatedMetricInput(
    cik,
    stock_metrics.FreeCashFlow,
    [
      MetricQuery("operating_cash_flow", operating, policy),
      MetricQuery("capital_expenditures_reported", capex, policy),
    ],
    policy,
    periods.Annual,
    4,
  )
}

fn source_policy(
  base: fundamentals.FilingPolicy,
  accession: Option(String),
) -> Result(fundamentals.FilingPolicy, fundamentals.FilingPolicyError) {
  case accession {
    None -> Ok(base)
    Some(accession) ->
      fundamentals.filing_policy("exact_accession", Some(accession))
  }
}

fn q4_metric(name: String) -> Result(fundamentals.Metric, Nil) {
  case fundamentals.metric(name) {
    Ok(fundamentals.Revenue as metric)
    | Ok(fundamentals.NetIncome as metric)
    | Ok(fundamentals.OperatingCashFlow as metric)
    | Ok(fundamentals.CapitalExpendituresReported as metric) -> Ok(metric)
    _ -> Error(Nil)
  }
}

fn build_trend_queries(
  metric: fundamentals.Metric,
  unit: String,
  class: periods.Class,
  ends: List(String),
  form: Option(String),
  out: List(#(String, fundamentals.Query)),
) -> Result(List(#(String, fundamentals.Query)), Nil) {
  case ends {
    [] -> Ok(list.reverse(out))
    [end, ..rest] ->
      case periods.target(class, end) {
        Error(_) -> Error(Nil)
        Ok(target) ->
          case fundamentals.period_query(metric, unit, target, form) {
            Error(_) -> Error(Nil)
            Ok(query) ->
              build_trend_queries(metric, unit, class, rest, form, [
                #(end, query),
                ..out
              ])
          }
      }
  }
}

fn build_metric_queries(
  inputs: List(#(String, fundamentals.Metric)),
  currency_unit: String,
  shares_unit: String,
  target: periods.Target,
  form: Option(String),
  base_policy: fundamentals.FilingPolicy,
  source_accessions: Dict(String, String),
  out: List(MetricQuery),
) -> Result(List(MetricQuery), Nil) {
  case inputs {
    [] -> Ok(list.reverse(out))
    [#(name, metric), ..rest] -> {
      let unit = case metric {
        fundamentals.DilutedWeightedAverageShares -> shares_unit
        _ -> currency_unit
      }
      let accession = case dict.get(source_accessions, name) {
        Error(_) -> None
        Ok(value) -> Some(value)
      }
      case
        fundamentals.period_query(metric, unit, target, form),
        source_policy(base_policy, accession)
      {
        Error(_), _ | _, Error(_) -> Error(Nil)
        Ok(query), Ok(policy) ->
          build_metric_queries(
            rest,
            currency_unit,
            shares_unit,
            target,
            form,
            base_policy,
            source_accessions,
            [MetricQuery(name, query, policy), ..out],
          )
      }
    }
  }
}

fn valid_source_accessions(
  kind: Result(stock_metrics.Kind, Nil),
  accessions: Dict(String, String),
) -> Bool {
  case kind {
    Error(_) -> False
    Ok(kind) -> {
      let names =
        stock_metrics.required_inputs(kind)
        |> list.map(fn(input) { input.0 })
      accessions
      |> dict.to_list
      |> list.all(fn(entry) { list.contains(names, entry.0) })
    }
  }
}

fn build_composed_direct_queries(
  ends: List(String),
  accessions: List(String),
  metric: fundamentals.Metric,
  unit: String,
  form: Option(String),
  base_policy: fundamentals.FilingPolicy,
  out: List(ComposedQuarterQuery),
) -> Result(List(ComposedQuarterQuery), Nil) {
  case ends, accessions {
    [], [] -> Ok(list.reverse(out))
    [end, ..rest], [] ->
      case periods.target(periods.Quarter, end) {
        Error(_) -> Error(Nil)
        Ok(target) ->
          case fundamentals.period_query(metric, unit, target, form) {
            Error(_) -> Error(Nil)
            Ok(query) ->
              build_composed_direct_queries(
                rest,
                [],
                metric,
                unit,
                form,
                base_policy,
                [ComposedQuarterQuery(end, query, base_policy), ..out],
              )
          }
      }
    [end, ..rest], [accession, ..remaining_accessions] ->
      case
        periods.target(periods.Quarter, end),
        fundamentals.filing_policy("exact_accession", Some(accession))
      {
        Ok(target), Ok(policy) ->
          case fundamentals.period_query(metric, unit, target, form) {
            Error(_) -> Error(Nil)
            Ok(query) ->
              build_composed_direct_queries(
                rest,
                remaining_accessions,
                metric,
                unit,
                form,
                base_policy,
                [ComposedQuarterQuery(end, query, policy), ..out],
              )
          }
        _, _ -> Error(Nil)
      }
    _, _ -> Error(Nil)
  }
}

fn period_decode_failure(
  cik: finance_sec.Cik,
  query: fundamentals.Query,
  policy: fundamentals.FilingPolicy,
) -> decode.Decoder(PeriodInput) {
  decode.failure(
    PeriodInput(cik, query, policy),
    "valid SEC statement-period fundamental request",
  )
}

fn period_class(name: String) -> Result(periods.Class, Nil) {
  case name {
    "instant" -> Ok(periods.Instant)
    "quarter" -> Ok(periods.Quarter)
    "half_year_ytd" -> Ok(periods.HalfYearToDate)
    "nine_month_ytd" -> Ok(periods.NineMonthToDate)
    "annual" -> Ok(periods.Annual)
    _ -> Error(Nil)
  }
}

fn duration_period_class(name: String) -> Result(periods.Class, Nil) {
  case period_class(name) {
    Ok(periods.Instant) | Error(_) -> Error(Nil)
    Ok(class) -> Ok(class)
  }
}

fn ytd_period_class(name: String) -> Result(periods.Class, Nil) {
  case period_class(name) {
    Ok(periods.Quarter) -> Ok(periods.Quarter)
    Ok(periods.HalfYearToDate) -> Ok(periods.HalfYearToDate)
    Ok(periods.NineMonthToDate) -> Ok(periods.NineMonthToDate)
    _ -> Error(Nil)
  }
}

fn optional_string_field(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn supported_definitions() -> List(fundamentals.Definition) {
  [
    fundamentals.Revenue,
    fundamentals.NetIncome,
    fundamentals.Assets,
    fundamentals.CashAndEquivalents,
    fundamentals.OperatingCashFlow,
    fundamentals.CapitalExpendituresReported,
    fundamentals.DilutedWeightedAverageShares,
  ]
  |> list.map(fundamentals.definition)
}

fn metric_names() -> List(String) {
  supported_definitions()
  |> list.map(fn(value) { fundamentals.metric_name(value.metric) })
}

fn render_definitions(values: List(fundamentals.Definition)) -> String {
  us_text(
    "Supported direct SEC fundamentals:\n"
    <> {
      values
      |> list.map(fn(value) {
        "- "
        <> fundamentals.metric_name(value.metric)
        <> " | "
        <> period_kind_name(value.period_kind)
        <> " | "
        <> unit_kind_name(value.unit_kind)
        <> " | tags "
        <> string.join(value.tags, ", ")
      })
      |> string.join("\n")
    },
  )
}

fn render_resolution(
  company: String,
  value: identifier.Resolution(fundamentals.Candidate),
) -> String {
  us_text(case value {
    identifier.NoMatch ->
      company <> ": no fact matched the exact metric, unit, period, and form"
    identifier.Unique(candidate) ->
      company <> " unique fundamental: " <> candidate_label(candidate)
    identifier.Ambiguous(first, second, rest) ->
      company
      <> " ambiguous fundamental ("
      <> int.to_string(2 + list.length(rest))
      <> "); choose a form/accession or inspect raw facts:\n"
      <> {
        [first, second, ..rest]
        |> list.map(fn(candidate) { "- " <> candidate_label(candidate) })
        |> string.join("\n")
      }
  })
}

fn render_q4(company: String, value: derivation.DerivedQ4) -> String {
  us_text(
    company
    <> " derived fourth quarter: "
    <> decimal.to_string(value.value)
    <> " "
    <> value.unit
    <> " ("
    <> value.start
    <> " through "
    <> value.end
    <> "); annual accession "
    <> value.annual.fact.accession
    <> " minus nine-month accession "
    <> value.nine_month_ytd.fact.accession,
  )
}

fn render_trend(company: String, value: derivation.Trend) -> String {
  us_text(
    company
    <> " comparable "
    <> periods.class_name(value.period_class)
    <> " trend:\n"
    <> {
      value.points
      |> list.map(fn(candidate) {
        "- "
        <> candidate.fact.end
        <> ": "
        <> candidate.raw_value
        <> " "
        <> candidate.unit
        <> " | accession "
        <> candidate.fact.accession
      })
      |> string.join("\n")
    },
  )
}

fn render_calculated_metric(
  company: String,
  value: stock_metrics.Derived,
) -> String {
  us_text(
    company
    <> " calculated "
    <> value.calculation.name
    <> ": "
    <> decimal.to_string(value.calculation.value)
    <> " "
    <> value.output_unit
    <> " from "
    <> {
      value.sources
      |> list.map(fn(source) {
        source.name <> "@" <> source.candidate.fact.accession
      })
      |> string.join(", ")
    },
  )
}

fn render_growth(company: String, value: stock_metrics.GrowthSeries) -> String {
  us_text(
    company
    <> " "
    <> stock_metrics.growth_gap_name(value.gap)
    <> " growth:\n"
    <> {
      value.points
      |> list.map(fn(point) {
        "- "
        <> point.previous.fact.end
        <> " to "
        <> point.current.fact.end
        <> ": "
        <> decimal.to_string(point.calculation.value)
        <> " percentage points"
      })
      |> string.join("\n")
    },
  )
}

fn render_ttm(
  company: String,
  value: stock_metrics.TrailingTwelveMonths,
) -> String {
  us_text(
    company
    <> " trailing twelve months: "
    <> decimal.to_string(value.calculation.value)
    <> " "
    <> value.output_unit
    <> " ("
    <> value.start
    <> " through "
    <> value.end
    <> ")",
  )
}

fn render_composed_ttm(
  company: String,
  value: stock_metrics.ComposedTrailingTwelveMonths,
) -> String {
  us_text(
    company
    <> " composed trailing twelve months: "
    <> decimal.to_string(value.calculation.value)
    <> " "
    <> value.output_unit
    <> " ("
    <> value.start
    <> " through "
    <> value.end
    <> "; direct and derived quarter identities retained)",
  )
}

fn q4_json(
  company: xbrl.CompanyFacts,
  input: Q4Input,
  value: derivation.DerivedQ4,
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("derived")),
      #("metric", json.string(fundamentals.metric_name(value.metric))),
      #("value", json.string(decimal.to_string(value.value))),
      #("unit", json.string(value.unit)),
      #("start", json.string(value.start)),
      #("end", json.string(value.end)),
      #("method", json.string(value.method)),
      #(
        "annualPolicy",
        json.string(fundamentals.filing_policy_name(input.annual_policy)),
      ),
      #(
        "nineMonthPolicy",
        json.string(fundamentals.filing_policy_name(input.nine_month_policy)),
      ),
      #("annual", candidate_json(value.annual)),
      #("nineMonthYtd", candidate_json(value.nine_month_ytd)),
      #(
        "warning",
        json.string(
          "Derived Q4 is valid only for the retained annual and nine-month sources; it is not a directly reported SEC fact",
        ),
      ),
    ]),
  )
}

fn unresolved_q4_json(
  company: xbrl.CompanyFacts,
  input: Q4Input,
  annual: identifier.Resolution(fundamentals.Candidate),
  nine_month: identifier.Resolution(fundamentals.Candidate),
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("unresolved_sources")),
      #(
        "annualPolicy",
        json.string(fundamentals.filing_policy_name(input.annual_policy)),
      ),
      #(
        "nineMonthPolicy",
        json.string(fundamentals.filing_policy_name(input.nine_month_policy)),
      ),
      #("annual", source_resolution_json(annual)),
      #("nineMonthYtd", source_resolution_json(nine_month)),
      #(
        "warning",
        json.string(
          "No subtraction was performed because both source periods did not resolve to exactly one fact",
        ),
      ),
    ]),
  )
}

fn trend_json(
  company: xbrl.CompanyFacts,
  input: TrendInput,
  value: derivation.Trend,
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("comparable")),
      #("metric", json.string(fundamentals.metric_name(value.metric))),
      #("unit", json.string(value.unit)),
      #("taxonomy", json.string(xbrl.taxonomy(value.concept))),
      #("tag", json.string(xbrl.tag(value.concept))),
      #("periodClass", json.string(periods.class_name(value.period_class))),
      #(
        "filingPolicy",
        json.string(fundamentals.filing_policy_name(input.policy)),
      ),
      #("points", json.array(value.points, candidate_json)),
      #(
        "warning",
        json.string(
          "The series contains comparable direct facts only; no interpolation, gap filling, or cross-tag coercion was performed",
        ),
      ),
    ]),
  )
}

fn calculated_metric_json(
  company: xbrl.CompanyFacts,
  input: CalculatedMetricInput,
  value: stock_metrics.Derived,
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("calculated")),
      #("metric", json.string(value.calculation.name)),
      #("value", json.string(decimal.to_string(value.calculation.value))),
      #("unit", json.string(value.output_unit)),
      #("start", json.string(value.start)),
      #("end", json.string(value.end)),
      #("periodClass", json.string(periods.class_name(value.period_class))),
      #(
        "baseFilingPolicy",
        json.string(fundamentals.filing_policy_name(input.base_policy)),
      ),
      #("sourcePolicies", json.array(input.queries, metric_query_policy_json)),
      #("scale", json.int(input.scale)),
      #("rounding", json.string("half_even")),
      #("method", json.string(value.method)),
      #("formula", formula_json(value.formula)),
      #("inputNames", json.array(value.calculation.input_names, json.string)),
      #(
        "assumptions",
        json.array(value.calculation.assumptions, assumption_json),
      ),
      #("sources", json.array(value.sources, named_source_json)),
      #(
        "warning",
        json.string(
          "This calculated metric is valid only for the retained same-period, same-filing direct facts and disclosed formula policy",
        ),
      ),
    ]),
  )
}

fn growth_json(
  company: xbrl.CompanyFacts,
  input: GrowthInput,
  value: stock_metrics.GrowthSeries,
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("calculated")),
      #("metric", json.string(fundamentals.metric_name(value.metric))),
      #("sourceUnit", json.string(value.unit)),
      #("unit", json.string("percentage_points")),
      #("periodClass", json.string(periods.class_name(value.period_class))),
      #("comparison", json.string(stock_metrics.growth_gap_name(value.gap))),
      #(
        "filingPolicy",
        json.string(fundamentals.filing_policy_name(input.policy)),
      ),
      #("scale", json.int(input.scale)),
      #("rounding", json.string("half_even")),
      #("points", json.array(value.points, growth_point_json)),
      #(
        "warning",
        json.string(
          "Each growth point uses two retained comparable direct facts and an explicitly validated calendar gap; no missing period was bridged",
        ),
      ),
    ]),
  )
}

fn growth_point_json(value: stock_metrics.GrowthPoint) -> json.Json {
  json.object([
    #("fromEnd", json.string(value.previous.fact.end)),
    #("toEnd", json.string(value.current.fact.end)),
    #("value", json.string(decimal.to_string(value.calculation.value))),
    #("unit", json.string("percentage_points")),
    #("method", json.string(value.method)),
    #("formula", formula_json(value.formula)),
    #("inputNames", json.array(value.calculation.input_names, json.string)),
    #("assumptions", json.array(value.calculation.assumptions, assumption_json)),
    #("previous", candidate_json(value.previous)),
    #("current", candidate_json(value.current)),
  ])
}

fn ttm_json(
  company: xbrl.CompanyFacts,
  input: TtmInput,
  value: stock_metrics.TrailingTwelveMonths,
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("calculated")),
      #("metric", json.string(fundamentals.metric_name(value.metric))),
      #("calculation", json.string(value.calculation.name)),
      #("value", json.string(decimal.to_string(value.calculation.value))),
      #("unit", json.string(value.output_unit)),
      #("start", json.string(value.start)),
      #("end", json.string(value.end)),
      #("periodClass", json.string("trailing_twelve_months")),
      #(
        "filingPolicy",
        json.string(fundamentals.filing_policy_name(input.policy)),
      ),
      #("method", json.string(value.method)),
      #("formula", formula_json(value.formula)),
      #("inputNames", json.array(value.calculation.input_names, json.string)),
      #(
        "assumptions",
        json.array(value.calculation.assumptions, assumption_json),
      ),
      #("sources", json.array(value.sources, named_source_json)),
      #(
        "warning",
        json.string(
          "TTM is a sum of exactly four retained contiguous direct-quarter facts; derived quarters and gap filling are not used",
        ),
      ),
    ]),
  )
}

fn ttm_bridge_json(
  company: xbrl.CompanyFacts,
  input: TtmBridgeInput,
  value: stock_metrics.TrailingTwelveMonths,
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("calculated")),
      #("metric", json.string(fundamentals.metric_name(value.metric))),
      #("calculation", json.string(value.calculation.name)),
      #("value", json.string(decimal.to_string(value.calculation.value))),
      #("unit", json.string(value.output_unit)),
      #("start", json.string(value.start)),
      #("end", json.string(value.end)),
      #("periodClass", json.string("trailing_twelve_months")),
      #(
        "annualPolicy",
        json.string(fundamentals.filing_policy_name(input.annual_policy)),
      ),
      #(
        "currentYtdPolicy",
        json.string(fundamentals.filing_policy_name(input.current_ytd_policy)),
      ),
      #(
        "priorYtdPolicy",
        json.string(fundamentals.filing_policy_name(input.prior_ytd_policy)),
      ),
      #("method", json.string(value.method)),
      #("formula", formula_json(value.formula)),
      #("inputNames", json.array(value.calculation.input_names, json.string)),
      #(
        "assumptions",
        json.array(value.calculation.assumptions, assumption_json),
      ),
      #("sources", json.array(value.sources, named_source_json)),
      #(
        "warning",
        json.string(
          "TTM bridge is annual plus current YTD minus prior comparable YTD; all three retained sources and fiscal-window assumptions are material",
        ),
      ),
    ]),
  )
}

fn composed_ttm_json(
  company: xbrl.CompanyFacts,
  input: ComposedTtmInput,
  value: stock_metrics.ComposedTrailingTwelveMonths,
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("calculated")),
      #("metric", json.string(fundamentals.metric_name(value.metric))),
      #("calculation", json.string(value.calculation.name)),
      #("value", json.string(decimal.to_string(value.calculation.value))),
      #("unit", json.string(value.output_unit)),
      #("start", json.string(value.start)),
      #("end", json.string(value.end)),
      #("periodClass", json.string("trailing_twelve_months")),
      #(
        "annualPolicy",
        json.string(fundamentals.filing_policy_name(input.annual_policy)),
      ),
      #(
        "nineMonthPolicy",
        json.string(fundamentals.filing_policy_name(input.nine_month_policy)),
      ),
      #("method", json.string(value.method)),
      #("formula", formula_json(value.formula)),
      #("inputNames", json.array(value.calculation.input_names, json.string)),
      #(
        "assumptions",
        json.array(value.calculation.assumptions, assumption_json),
      ),
      #("quarters", json.array(value.quarters, quarter_evidence_json)),
      #(
        "warning",
        json.string(
          "Derived Q4 remains explicitly derived and expands to annual-minus-nine-month leaves; it is never relabelled as a directly reported fact",
        ),
      ),
    ]),
  )
}

fn quarter_evidence_json(value: stock_metrics.QuarterEvidence) -> json.Json {
  case value.observation {
    stock_metrics.DirectQuarter(candidate) ->
      json.object([
        #("name", json.string(value.name)),
        #("kind", json.string("direct")),
        #("start", optional_json(candidate.fact.start)),
        #("end", json.string(candidate.fact.end)),
        #("candidate", candidate_json(candidate)),
      ])
    stock_metrics.DerivedQuarter(derived) ->
      json.object([
        #("name", json.string(value.name)),
        #("kind", json.string("derived_q4")),
        #("value", json.string(decimal.to_string(derived.value))),
        #("unit", json.string(derived.unit)),
        #("start", json.string(derived.start)),
        #("end", json.string(derived.end)),
        #("method", json.string(derived.method)),
        #("annual", candidate_json(derived.annual)),
        #("nineMonthYtd", candidate_json(derived.nine_month_ytd)),
      ])
  }
}

fn unresolved_composed_ttm_json(
  company: xbrl.CompanyFacts,
  input: ComposedTtmInput,
  direct: List(ResolvedComposedQuarter),
  annual: identifier.Resolution(fundamentals.Candidate),
  nine_month: identifier.Resolution(fundamentals.Candidate),
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("unresolved_sources")),
      #("directQuarters", json.array(direct, resolved_composed_quarter_json)),
      #(
        "annual",
        bridge_source_resolution_json(
          annual,
          fundamentals.filing_policy_name(input.annual_policy),
        ),
      ),
      #(
        "nineMonthYtd",
        bridge_source_resolution_json(
          nine_month,
          fundamentals.filing_policy_name(input.nine_month_policy),
        ),
      ),
      #(
        "warning",
        json.string(
          "No composed TTM was calculated because every direct-quarter and derived-Q4 source did not resolve uniquely",
        ),
      ),
    ]),
  )
}

fn resolved_composed_quarter_json(value: ResolvedComposedQuarter) -> json.Json {
  json.object([
    #("end", json.string(value.end)),
    #(
      "filingPolicy",
      json.string(fundamentals.filing_policy_name(value.policy)),
    ),
    #("resolution", source_resolution_json(value.resolution)),
  ])
}

fn unresolved_ttm_bridge_json(
  company: xbrl.CompanyFacts,
  input: TtmBridgeInput,
  annual: identifier.Resolution(fundamentals.Candidate),
  current_ytd: identifier.Resolution(fundamentals.Candidate),
  prior_ytd: identifier.Resolution(fundamentals.Candidate),
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("unresolved_sources")),
      #(
        "annual",
        bridge_source_resolution_json(
          annual,
          fundamentals.filing_policy_name(input.annual_policy),
        ),
      ),
      #(
        "currentYtd",
        bridge_source_resolution_json(
          current_ytd,
          fundamentals.filing_policy_name(input.current_ytd_policy),
        ),
      ),
      #(
        "priorYtd",
        bridge_source_resolution_json(
          prior_ytd,
          fundamentals.filing_policy_name(input.prior_ytd_policy),
        ),
      ),
      #(
        "warning",
        json.string(
          "No TTM bridge was calculated because all three sources did not resolve uniquely",
        ),
      ),
    ]),
  )
}

fn bridge_source_resolution_json(
  value: identifier.Resolution(fundamentals.Candidate),
  policy: String,
) -> json.Json {
  json.object([
    #("filingPolicy", json.string(policy)),
    #("resolution", source_resolution_json(value)),
  ])
}

fn unresolved_growth_json(
  company: xbrl.CompanyFacts,
  input: GrowthInput,
  values: List(ResolvedPeriod),
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("unresolved_periods")),
      #("metric", json.string(requested_metric_name(input.queries))),
      #("comparison", json.string(stock_metrics.growth_gap_name(input.gap))),
      #("periods", json.array(values, resolved_period_json)),
      #(
        "warning",
        json.string(
          "No growth was calculated because every requested period did not resolve uniquely",
        ),
      ),
    ]),
  )
}

fn unresolved_ttm_json(
  company: xbrl.CompanyFacts,
  input: TtmInput,
  values: List(ResolvedPeriod),
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("unresolved_periods")),
      #("metric", json.string(requested_metric_name(input.queries))),
      #("periods", json.array(values, resolved_period_json)),
      #(
        "warning",
        json.string(
          "No TTM sum was calculated because all four direct quarters did not resolve uniquely",
        ),
      ),
    ]),
  )
}

fn requested_metric_name(
  queries: List(#(String, fundamentals.Query)),
) -> String {
  case queries {
    [#(_, query), ..] ->
      fundamentals.query_definition(query).metric
      |> fundamentals.metric_name
    [] -> "unknown"
  }
}

fn unresolved_metric_json(
  company: xbrl.CompanyFacts,
  input: CalculatedMetricInput,
  values: List(ResolvedMetricSource),
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("unresolved_sources")),
      #("metric", json.string(stock_metrics.kind_name(input.kind))),
      #("periodClass", json.string(periods.class_name(input.period_class))),
      #(
        "baseFilingPolicy",
        json.string(fundamentals.filing_policy_name(input.base_policy)),
      ),
      #("sources", json.array(values, resolved_metric_source_json)),
      #(
        "warning",
        json.string(
          "No formula was evaluated because every required source did not resolve to exactly one direct fact",
        ),
      ),
    ]),
  )
}

fn named_source_json(value: stock_metrics.NamedSource) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #("candidate", candidate_json(value.candidate)),
  ])
}

fn resolved_metric_source_json(value: ResolvedMetricSource) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #(
      "filingPolicy",
      json.string(fundamentals.filing_policy_name(value.policy)),
    ),
    #("resolution", source_resolution_json(value.resolution)),
  ])
}

fn metric_query_policy_json(value: MetricQuery) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #(
      "filingPolicy",
      json.string(fundamentals.filing_policy_name(value.policy)),
    ),
  ])
}

fn assumption_json(value: math_metric.Assumption) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #("value", json.string(value.value)),
  ])
}

fn formula_json(value: formula.Formula) -> json.Json {
  case value {
    formula.Literal(value) ->
      json.object([
        #("operation", json.string("literal")),
        #("value", json.string(decimal.to_string(value))),
      ])
    formula.Reference(name) ->
      json.object([
        #("operation", json.string("reference")),
        #("name", json.string(name)),
      ])
    formula.Add(left, right) -> binary_formula_json("add", left, right)
    formula.Subtract(left, right) ->
      binary_formula_json("subtract", left, right)
    formula.Multiply(left, right) ->
      binary_formula_json("multiply", left, right)
    formula.Divide(numerator, denominator, scale, rounding) ->
      json.object([
        #("operation", json.string("divide")),
        #("numerator", formula_json(numerator)),
        #("denominator", formula_json(denominator)),
        #("scale", json.int(scale)),
        #("rounding", json.string(rounding_name(rounding))),
      ])
    formula.Negate(value) -> unary_formula_json("negate", value)
    formula.Absolute(value) -> unary_formula_json("absolute", value)
    formula.Power(value, exponent) ->
      json.object([
        #("operation", json.string("power")),
        #("value", formula_json(value)),
        #("exponent", json.int(exponent)),
      ])
    formula.Quantize(value, scale, rounding) ->
      json.object([
        #("operation", json.string("quantize")),
        #("value", formula_json(value)),
        #("scale", json.int(scale)),
        #("rounding", json.string(rounding_name(rounding))),
      ])
    formula.Sum(values) -> aggregate_formula_json("sum", values)
    formula.Mean(values, scale, rounding) ->
      json.object([
        #("operation", json.string("mean")),
        #("values", json.array(values, formula_json)),
        #("scale", json.int(scale)),
        #("rounding", json.string(rounding_name(rounding))),
      ])
    formula.Minimum(values) -> aggregate_formula_json("minimum", values)
    formula.Maximum(values) -> aggregate_formula_json("maximum", values)
  }
}

fn binary_formula_json(
  operation: String,
  left: formula.Formula,
  right: formula.Formula,
) -> json.Json {
  json.object([
    #("operation", json.string(operation)),
    #("left", formula_json(left)),
    #("right", formula_json(right)),
  ])
}

fn unary_formula_json(operation: String, value: formula.Formula) -> json.Json {
  json.object([
    #("operation", json.string(operation)),
    #("value", formula_json(value)),
  ])
}

fn aggregate_formula_json(
  operation: String,
  values: List(formula.Formula),
) -> json.Json {
  json.object([
    #("operation", json.string(operation)),
    #("values", json.array(values, formula_json)),
  ])
}

fn rounding_name(value: decimal.RoundingMode) -> String {
  case value {
    decimal.TowardZero -> "toward_zero"
    decimal.AwayFromZero -> "away_from_zero"
    decimal.HalfUp -> "half_up"
    decimal.HalfEven -> "half_even"
  }
}

fn unresolved_trend_json(
  company: xbrl.CompanyFacts,
  input: TrendInput,
  values: List(ResolvedPeriod),
) -> json.Json {
  json.object(
    list.append(sec_metadata(company), [
      #("status", json.string("unresolved_periods")),
      #("periodClass", json.string(periods.class_name(input.period_class))),
      #(
        "filingPolicy",
        json.string(fundamentals.filing_policy_name(input.policy)),
      ),
      #("periods", json.array(values, resolved_period_json)),
      #(
        "warning",
        json.string(
          "No trend was created because every requested period did not resolve to exactly one direct fact",
        ),
      ),
    ]),
  )
}

fn source_resolution_json(
  value: identifier.Resolution(fundamentals.Candidate),
) -> json.Json {
  json.object([
    #("resolution", json.string(resolution_name(value))),
    #(
      "candidates",
      json.array(identifier.resolution_candidates(value), candidate_json),
    ),
  ])
}

fn resolved_period_json(value: ResolvedPeriod) -> json.Json {
  json.object([
    #("end", json.string(value.end)),
    #("resolution", source_resolution_json(value.resolution)),
  ])
}

fn sec_metadata(company: xbrl.CompanyFacts) -> List(#(String, json.Json)) {
  list.append(us_track_fields(), [
    #("provider", json.string("SEC EDGAR XBRL")),
    #(
      "source",
      json.string(
        "https://data.sec.gov/api/xbrl/companyfacts/CIK"
        <> finance_sec.cik_value(company.cik)
        <> ".json",
      ),
    ),
    #("access", json.string("read_only_public_data")),
    #("entitlement", json.string("sec_public_data_fair_access_terms_apply")),
    #(
      "freshness",
      json.string("sec_xbrl_real_time_typical_delay_under_one_minute"),
    ),
    #("coverage", json.string("us_gaap_non_custom_entity_wide_direct_facts")),
    #("cik", json.string(finance_sec.cik_value(company.cik))),
    #("company", json.string(company.entity_name)),
  ])
}

fn us_track_fields() -> List(#(String, json.Json)) {
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Us,
      market_scope: "us_sec_normalized_fundamentals",
      venue_mic: None,
      board: None,
      timezone: None,
      source_language: "en-US",
      providers: ["SEC EDGAR XBRL"],
      entitlement: "sec_public_data_fair_access_terms_apply",
      limitations: [
        "non_custom_taxonomies_only",
        "entity_wide_facts_only",
        "audited_direct_metric_registry_only",
      ],
    )
  track_json.result_fields(value)
}

fn us_text(value: String) -> String {
  "US track | SEC EDGAR XBRL fundamentals\n" <> value
}

fn candidate_label(value: fundamentals.Candidate) -> String {
  value.raw_value
  <> " "
  <> value.unit
  <> " | us-gaap:"
  <> xbrl.tag(value.concept)
  <> " | "
  <> value.fact.form
  <> " filed "
  <> value.fact.filed
  <> " | accession "
  <> value.fact.accession
}

fn resolution_json(
  company: xbrl.CompanyFacts,
  query: fundamentals.Query,
  resolution: identifier.Resolution(fundamentals.Candidate),
  filing_policy: String,
) -> json.Json {
  let definition = fundamentals.query_definition(query)
  json.object(
    list.append(sec_metadata(company), [
      #("metric", json.string(fundamentals.metric_name(definition.metric))),
      #("resolution", json.string(resolution_name(resolution))),
      #("filingPolicy", json.string(filing_policy)),
      #("periodClass", case fundamentals.query_period_class(query) {
        Some(class) -> json.string(periods.class_name(class))
        None -> json.string("exact_duration")
      }),
      #("definition", definition_json(definition)),
      #(
        "candidates",
        json.array(identifier.resolution_candidates(resolution), candidate_json),
      ),
      #(
        "warning",
        json.string(
          "A normalized name is valid only under the disclosed direct-tag, exact-period policy; ambiguity is not resolved automatically",
        ),
      ),
    ]),
  )
}

fn definition_json(value: fundamentals.Definition) -> json.Json {
  json.object([
    #("metric", json.string(fundamentals.metric_name(value.metric))),
    #("taxonomy", json.string("us-gaap")),
    #("acceptedTags", json.array(value.tags, json.string)),
    #("periodKind", json.string(period_kind_name(value.period_kind))),
    #("unitKind", json.string(unit_kind_name(value.unit_kind))),
    #("method", json.string(value.method)),
  ])
}

fn candidate_json(value: fundamentals.Candidate) -> json.Json {
  json.object([
    #("metric", json.string(fundamentals.metric_name(value.metric))),
    #("value", json.string(value.raw_value)),
    #("canonicalDecimal", json.string(decimal.to_string(value.value))),
    #("unit", json.string(value.unit)),
    #("taxonomy", json.string(xbrl.taxonomy(value.concept))),
    #("tag", json.string(xbrl.tag(value.concept))),
    #("start", optional_json(value.fact.start)),
    #("end", json.string(value.fact.end)),
    #("accession", json.string(value.fact.accession)),
    #("fiscalYear", optional_json(value.fact.fiscal_year)),
    #("fiscalPeriod", optional_json(value.fact.fiscal_period)),
    #("form", json.string(value.fact.form)),
    #("amendment", json.bool(string.ends_with(value.fact.form, "/A"))),
    #("filed", json.string(value.fact.filed)),
    #("frame", optional_json(value.fact.frame)),
  ])
}

fn resolution_name(
  value: identifier.Resolution(fundamentals.Candidate),
) -> String {
  case value {
    identifier.NoMatch -> "no_match"
    identifier.Unique(_) -> "unique"
    identifier.Ambiguous(_, _, _) -> "ambiguous"
  }
}

fn period_kind_name(value: fundamentals.PeriodKind) -> String {
  case value {
    fundamentals.Instant -> "instant"
    fundamentals.Duration -> "duration"
  }
}

fn unit_kind_name(value: fundamentals.UnitKind) -> String {
  case value {
    fundamentals.Monetary -> "monetary"
    fundamentals.Shares -> "shares"
  }
}

fn optional_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}
