import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { PLUGINS_DIR } from "./modules.js";

export const CALCULATION_PLUGINS = [
  {
    name: "cn_stock_financials",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    operations: ["net_margin"],
    tool: "cn_financial_metrics",
    title: "CN financial metric",
  },
  {
    name: "cn_stock_block_trades",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    operations: ["percent_change"],
    tool: "cn_block_trade_comparison",
    title: "CN block-trade premium/discount",
  },
  {
    name: "earnings_release",
    track: "us",
    mics: ["XNYS", "XNAS"],
    operations: ["difference", "percent_change"],
    tool: "earnings_release_compare",
    title: "earnings-release comparison",
  },
  {
    name: "company_guidance",
    track: "us",
    mics: ["XNYS", "XNAS"],
    operations: ["difference", "percent_change"],
    tool: "company_guidance_compare",
    title: "company-guidance comparison",
  },
  {
    name: "consensus_estimates",
    track: "us",
    mics: ["XNYS", "XNAS"],
    operations: ["mean", "difference", "percent_change"],
    tool: "consensus_estimate_calculation",
    title: "consensus estimate calculation",
  },
  {
    name: "stock_comps",
    track: "us",
    mics: ["XNYS", "XNAS"],
    operations: ["ratio"],
    tool: "inspect_comparable_table",
    title: "comparable-company ratio",
  },
  {
    name: "stock_valuation",
    track: "us",
    mics: ["XNYS", "XNAS"],
    operations: ["enterprise_to_equity_per_share"],
    tool: "inspect_valuation",
    title: "enterprise-to-equity valuation",
  },
  {
    name: "stock_quality",
    track: "us",
    mics: ["XNYS", "XNAS"],
    operations: ["ratio", "difference"],
    tool: "quality_dimensions",
    title: "quality dimension",
  },
  {
    name: "stock_growth",
    track: "us",
    mics: ["XNYS", "XNAS"],
    operations: ["percent_change"],
    tool: "growth_metrics",
    title: "growth metric",
  },
  {
    name: "cn_stock_valuation",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    operations: ["enterprise_to_equity_per_share"],
    tool: "cn_inspect_valuation",
    title: "CN enterprise-to-equity valuation",
  },
  {
    name: "hk_stock_ah_comparison",
    track: "hk",
    mics: ["XHKG"],
    operations: ["premium_discount_fx"],
    tool: "hk_ah_price_comparison",
    title: "A/H price comparison",
  },
];

function gleamList(values) {
  return `[${values.map((value) => JSON.stringify(value)).join(", ")}]`;
}

function toml(spec) {
  return `name = "pi_sparkles_${spec.name}"
version = "0.1.0"
target = "javascript"
description = "Exact receipt-bound ${spec.title} for Pi"

licences = ["Apache-2.0"]
gleam = ">= 1.18.0"

[dependencies]
gleam_stdlib = ">= 0.69.0 and < 2.0.0"
gleam_javascript = ">= 1.0.0 and < 2.0.0"
gleam_json = ">= 3.1.0 and < 4.0.0"
finance_local_import = { path = "../../finance/finance_local_import" }
finance_research_calculation = { path = "../../finance/finance_research_calculation" }
pi_gleam = { path = "../../pi_gleam" }

[javascript]
runtime = "bun"

[metadata.pi]
tested_version = "0.83.0"

[metadata.finance]
provider = "caller-selected exact source receipts in a bounded user-owned import"
access = "calculation-only"
track = "${spec.track}"
`;
}

function rootModule(spec) {
  const moduleName = `pi_sparkles_${spec.name}`;
  return `import finance_local_import
import finance_research_calculation as calculation
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool
import ${moduleName}/domain

pub type Input {
  Input(path: String, expected_sha256: String, maximum_bytes: Int)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "${spec.tool}",
    "Calculate ${spec.title}",
    "Read one exact content-bound request from a caller-owned UTF-8 file and perform only the named exact-decimal ${spec.title} mechanics with complete source leaves, context proof, expression, and canonical receipt",
    "The caller selects every source, operation, period, assumption, unit, currency, scale, and rounding policy; the LLM owns interpretation and every investment decision",
    tool.parameters(input_schema(), input_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      use outcome <- promise.await(finance_local_import.read(input.path, input.maximum_bytes, raw.dynamic(signal)))
      case outcome {
        finance_local_import.Loaded(text, _) -> complete(calculation.calculate(domain.descriptor(), calculation.input(input.path, input.expected_sha256), text))
        finance_local_import.Truncated(_, total) -> tool.reject("Calculation import exceeds maximumBytes; total bytes: " <> int.to_string(total))
        finance_local_import.Cancelled -> tool.reject("Calculation import was cancelled")
        finance_local_import.Missing -> tool.reject("Calculation import file was not found")
        finance_local_import.InvalidUtf8 -> tool.reject("Calculation import requires strict UTF-8")
        finance_local_import.Failure(code) -> tool.reject("Calculation import failed safely: " <> code)
        finance_local_import.InvalidResult -> tool.reject("Calculation import effect returned an invalid result")
      }
    },
  )
  promise.resolve(Nil)
}

fn complete(value: Result(calculation.Response, calculation.CalculationError)) -> Promise(tool.ToolResult) {
  case value {
    Ok(value) -> tool.text_result(calculation.summary(value), calculation.details(value)) |> promise.resolve
    Error(error) -> tool.reject(calculation.error_message(error))
  }
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("path", schema.string() |> schema.with_string_length(1, 4096)),
    schema.Required("expectedSha256", schema.string() |> schema.with_string_length(64, 64)),
    schema.Required("maximumBytes", schema.integer() |> schema.with_number_range(1.0, 5_000_000.0)),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use path <- decode.field("path", decode.string)
  use expected_sha256 <- decode.field("expectedSha256", decode.string)
  use maximum_bytes <- decode.field("maximumBytes", decode.int)
  decode.success(Input(path, expected_sha256, maximum_bytes))
}
`;
}

function domainModule(spec) {
  return `import finance_research_calculation as calculation

pub fn descriptor() -> calculation.Descriptor {
  calculation.Descriptor(
    "${spec.name}_v1",
    "${spec.track}",
    ${gleamList(spec.mics)},
    ${gleamList(spec.operations)},
  )
}
`;
}

function updateReadme(spec, directory) {
  const path = join(directory, "README.md");
  const source = readFileSync(path, "utf8").replace(
    /Status: \*\*Designing\*\*[^\n]*/,
    "Status: **Implemented in building T2** · exact receipt-bound calculation product",
  );
  const addition = `
## Implemented T2 calculation path

\`${spec.tool}\` reads one versioned \`${spec.name}_v1\` request from a
caller-owned regular UTF-8 file under an exact SHA-256 and explicit byte budget.
It accepts only ${spec.operations.map((value) => `\`${value}\``).join(", ")}
and retains exact decimal lexemes, separately labelled market legs, MICs,
units/currencies, periods, accession/taxonomy/tag contexts, source receipts,
caller assumptions, expression trees, output scale and rounding. Wrong tracks,
contexts or units, duplicate/missing operands, zero denominators, invalid
decimals and unsupported operations fail closed. The result is a mechanical
calculation receipt, never a score, base case, fair-value label,
recommendation, or trade decision.
`;
  if (!source.includes("## Implemented T2 calculation path")) {
    writeFileSync(path, `${source.trimEnd()}\n${addition}`);
  }
}

export function generateCalculationPlugins() {
  for (const spec of CALCULATION_PLUGINS) {
    const directory = join(PLUGINS_DIR, spec.name);
    if (!existsSync(join(directory, "README.md"))) {
      throw new Error(`Missing reviewed design: ${spec.name}`);
    }
    const moduleDirectory = join(directory, "src", `pi_sparkles_${spec.name}`);
    mkdirSync(moduleDirectory, { recursive: true });
    writeFileSync(join(directory, "gleam.toml"), toml(spec));
    writeFileSync(
      join(directory, "src", `pi_sparkles_${spec.name}.gleam`),
      rootModule(spec),
    );
    writeFileSync(join(moduleDirectory, "domain.gleam"), domainModule(spec));
    updateReadme(spec, directory);
  }
}

if (import.meta.main) generateCalculationPlugins();
