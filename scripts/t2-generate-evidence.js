import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { PLUGINS_DIR } from "./modules.js";

export const EVIDENCE_PLUGINS = [
  {
    name: "cn_stock_share_structure",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    kinds: ["share_capital", "share_class", "reconciliation"],
    fields: ["quantity", "unit", "denominator_scope", "report_date"],
    inspect: "cn_share_structure",
    drill: "cn_share_structure_record",
    title: "CN share structure",
  },
  {
    name: "cn_stock_shareholders",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    kinds: ["top_shareholder", "top_tradable_holder", "shareholder_count"],
    fields: ["holder_label", "report_date", "source_document"],
    inspect: "cn_shareholders",
    drill: "cn_shareholder_record",
    title: "CN shareholder disclosures",
  },
  {
    name: "cn_stock_restricted_shares",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    kinds: ["unlock_plan", "unlock_actual", "unlock_revision"],
    fields: ["quantity", "state", "announcement_date"],
    inspect: "cn_restricted_shares",
    drill: "cn_restricted_share_record",
    title: "CN restricted-share events",
  },
  {
    name: "cn_stock_pledges",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    kinds: ["pledge", "release", "freeze"],
    fields: ["holder_label", "quantity", "event_date"],
    inspect: "cn_share_pledges",
    drill: "cn_share_pledge_record",
    title: "CN share pledge events",
  },
  {
    name: "cn_stock_insiders",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    kinds: [
      "increase_plan",
      "reduction_plan",
      "transaction",
      "completion",
      "cancellation",
    ],
    fields: ["holder_label", "event_type", "announcement_date"],
    inspect: "cn_insider_disclosures",
    drill: "cn_insider_record",
    title: "CN insider and major-holder disclosures",
  },
  {
    name: "cn_stock_public_info",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    kinds: ["unusual_movement", "dragon_tiger_seat"],
    fields: ["published_reason", "trade_window", "amount"],
    inspect: "cn_exchange_public_info",
    drill: "cn_exchange_public_info_record",
    title: "CN exchange public information",
  },
  {
    name: "cn_stock_margin",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    kinds: [
      "eligibility",
      "financing_balance",
      "financing_purchase",
      "financing_repayment",
      "securities_lending_balance",
      "securities_lending_sale",
      "market_aggregate",
    ],
    fields: ["field_label", "value", "observation_date"],
    inspect: "cn_margin_records",
    drill: "cn_margin_record",
    title: "CN financing and securities-lending facts",
  },
  {
    name: "cn_stock_connect",
    track: "cn",
    mics: ["XSHG", "XSHE"],
    kinds: ["eligibility", "quota", "status_change"],
    fields: ["program", "direction", "status", "effective_date"],
    inspect: "cn_stock_connect",
    drill: "cn_stock_connect_record",
    title: "Mainland Stock Connect facts",
  },
  {
    name: "cn_stock_indices",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    kinds: ["index_identity", "constituent", "rebalance"],
    fields: ["index_code", "effective_date", "knowledge_date"],
    inspect: "cn_index_records",
    drill: "cn_index_record",
    title: "CN index identities and membership",
  },
  {
    name: "cn_regulatory",
    track: "cn",
    mics: ["XSHG", "XSHE", "XBSE"],
    kinds: [
      "rule",
      "inquiry_letter",
      "supervision_letter",
      "disciplinary_action",
      "enforcement_release",
    ],
    fields: ["authority", "document_id", "original_title", "published_date"],
    inspect: "cn_regulatory_documents",
    drill: "cn_regulatory_record",
    title: "CN regulatory documents",
  },
  {
    name: "hk_stock_corporate_actions",
    track: "hk",
    mics: ["XHKG"],
    kinds: [
      "cash_dividend",
      "stock_dividend",
      "split",
      "consolidation",
      "rights_issue",
      "bonus_issue",
    ],
    fields: ["action_id", "announcement_date", "terms"],
    inspect: "hk_corporate_actions",
    drill: "hk_corporate_action_record",
    title: "HK corporate actions",
  },
  {
    name: "hk_stock_board_lot",
    track: "hk",
    mics: ["XHKG"],
    kinds: ["board_lot", "odd_lot_context", "correction"],
    fields: ["lot_quantity", "effective_from", "source_rule"],
    inspect: "hk_board_lots",
    drill: "hk_board_lot_record",
    title: "HK board-lot observations",
  },
  {
    name: "hk_stock_shareholders",
    track: "hk",
    mics: ["XHKG"],
    kinds: ["substantial_shareholder_notice", "amendment"],
    fields: ["holder_label", "event_date", "disclosure_date"],
    inspect: "hk_shareholder_notices",
    drill: "hk_shareholder_notice_record",
    title: "HK substantial-shareholder notices",
  },
  {
    name: "hk_stock_connect",
    track: "hk",
    mics: ["XHKG"],
    kinds: ["eligibility", "quota", "status_change"],
    fields: ["program", "direction", "status", "effective_date"],
    inspect: "hk_stock_connect",
    drill: "hk_stock_connect_record",
    title: "HK Stock Connect facts",
  },
  {
    name: "sec_insiders",
    track: "us",
    mics: ["XNYS", "XNAS"],
    kinds: ["form3_holding", "form4_transaction", "form5_transaction", "amendment"],
    fields: ["accession", "reporting_owner", "transaction_code", "quantity"],
    inspect: "sec_insider_filings",
    drill: "sec_insider_record",
    title: "SEC Forms 3, 4, and 5",
  },
  {
    name: "sec_ownership",
    track: "us",
    mics: ["XNYS", "XNAS"],
    kinds: ["schedule_13d", "schedule_13g", "form_13f", "amendment"],
    fields: ["accession", "filer", "security_id", "quantity"],
    inspect: "sec_ownership_filings",
    drill: "sec_ownership_record",
    title: "SEC ownership filings",
  },
  {
    name: "company_governance",
    track: "us",
    mics: ["XNYS", "XNAS"],
    kinds: [
      "board",
      "committee",
      "beneficial_ownership",
      "compensation",
      "auditor",
      "related_party",
      "capital_allocation",
      "restatement",
      "litigation",
    ],
    fields: ["source_document", "period", "information_state"],
    inspect: "company_governance",
    drill: "company_governance_record",
    title: "Company governance evidence",
  },
  {
    name: "industry_research",
    track: "us",
    mics: ["XNYS", "XNAS"],
    kinds: [
      "taxonomy",
      "market_structure",
      "participant",
      "value_chain",
      "capacity",
      "supply_demand",
      "regulation",
      "metric",
      "revision",
    ],
    fields: ["taxonomy_code", "effective_date", "source_document"],
    inspect: "industry_research",
    drill: "industry_research_record",
    title: "Industry research evidence",
  },
];

function gleamList(values) {
  return `[${values.map((value) => JSON.stringify(value)).join(", ")}]`;
}

function toml(spec) {
  return `name = "pi_sparkles_${spec.name}"
version = "0.1.0"
target = "javascript"
description = "Content-bound ${spec.title} imports for Pi"

licences = ["Apache-2.0"]
gleam = ">= 1.18.0"

[dependencies]
gleam_stdlib = ">= 0.69.0 and < 2.0.0"
gleam_javascript = ">= 1.0.0 and < 2.0.0"
gleam_json = ">= 3.1.0 and < 4.0.0"
finance_local_import = { path = "../../finance/finance_local_import" }
finance_research_contract = { path = "../../finance/finance_research_contract" }
pi_gleam = { path = "../../pi_gleam" }

[javascript]
runtime = "bun"

[metadata.pi]
tested_version = "0.83.0"

[metadata.finance]
provider = "bounded user-owned import with exact source metadata"
access = "read-only local import"
track = "${spec.track}"
`;
}

function rootModule(spec) {
  const moduleName = `pi_sparkles_${spec.name}`;
  return `import finance_local_import
import finance_research_contract as research
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool
import ${moduleName}/domain

pub type InspectInput {
  InspectInput(path: String, expected_sha256: String, maximum_bytes: Int, offset: Int, limit: Int)
}

pub type DrillInput {
  DrillInput(path: String, expected_sha256: String, maximum_bytes: Int, record_id: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_inspect(api)
  register_drill(api)
  promise.resolve(Nil)
}

fn register_inspect(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "${spec.inspect}",
    "Inspect ${spec.title}",
    "Read and validate one exact content-bound ${spec.track} research packet from a caller-owned regular UTF-8 file; return compact source facts, omissions, and stable record handles without interpretation",
    "Supply a versioned import file and exact SHA-256; the LLM owns source interpretation and every investment decision",
    tool.parameters(inspect_schema(), inspect_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      use outcome <- promise.await(finance_local_import.read(input.path, input.maximum_bytes, raw.dynamic(signal)))
      case outcome {
        finance_local_import.Loaded(text, _) -> complete(research.inspect(domain.descriptor(), research.input(input.path, input.expected_sha256, input.offset, input.limit), text))
        finance_local_import.Truncated(_, total) -> tool.reject("Import exceeds maximumBytes; total bytes: " <> int.to_string(total))
        finance_local_import.Cancelled -> tool.reject("Import was cancelled")
        finance_local_import.Missing -> tool.reject("Import file was not found")
        finance_local_import.InvalidUtf8 -> tool.reject("Import requires strict UTF-8")
        finance_local_import.Failure(code) -> tool.reject("Import failed safely: " <> code)
        finance_local_import.InvalidResult -> tool.reject("Import effect returned an invalid result")
      }
    },
  )
}

fn register_drill(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "${spec.drill}",
    "Drill one ${spec.title} record",
    "Reread the same exact content-bound import and return one complete record with source fields and correction lineage",
    "Use the packet hash and recordId returned by ${spec.inspect}; no latest-record or preferred-source choice is made",
    tool.parameters(drill_schema(), drill_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      use outcome <- promise.await(finance_local_import.read(input.path, input.maximum_bytes, raw.dynamic(signal)))
      case outcome {
        finance_local_import.Loaded(text, _) -> complete(research.drill(domain.descriptor(), research.drill_input(input.path, input.expected_sha256, input.record_id), text))
        finance_local_import.Truncated(_, total) -> tool.reject("Import exceeds maximumBytes; total bytes: " <> int.to_string(total))
        finance_local_import.Cancelled -> tool.reject("Import was cancelled")
        finance_local_import.Missing -> tool.reject("Import file was not found")
        finance_local_import.InvalidUtf8 -> tool.reject("Import requires strict UTF-8")
        finance_local_import.Failure(code) -> tool.reject("Import failed safely: " <> code)
        finance_local_import.InvalidResult -> tool.reject("Import effect returned an invalid result")
      }
    },
  )
}

fn complete(value: Result(research.Response, research.ContractError)) -> Promise(tool.ToolResult) {
  case value {
    Ok(value) -> tool.text_result(research.summary(value), research.details(value)) |> promise.resolve
    Error(error) -> tool.reject(research.error_message(error))
  }
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Required("path", bounded_string(1, 4096)),
    schema.Required("expectedSha256", bounded_string(64, 64)),
    schema.Required("maximumBytes", schema.integer() |> schema.with_number_range(1.0, 5_000_000.0)),
    schema.Required("offset", schema.integer() |> schema.with_number_range(0.0, 10_000.0)),
    schema.Required("limit", schema.integer() |> schema.with_number_range(1.0, 100.0)),
  ])
}

fn drill_schema() -> schema.Schema {
  schema.object([
    schema.Required("path", bounded_string(1, 4096)),
    schema.Required("expectedSha256", bounded_string(64, 64)),
    schema.Required("maximumBytes", schema.integer() |> schema.with_number_range(1.0, 5_000_000.0)),
    schema.Required("recordId", bounded_string(1, 4000)),
  ])
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn inspect_decoder() -> decode.Decoder(InspectInput) {
  use path <- decode.field("path", decode.string)
  use expected_sha256 <- decode.field("expectedSha256", decode.string)
  use maximum_bytes <- decode.field("maximumBytes", decode.int)
  use offset <- decode.field("offset", decode.int)
  use limit <- decode.field("limit", decode.int)
  decode.success(InspectInput(path, expected_sha256, maximum_bytes, offset, limit))
}

fn drill_decoder() -> decode.Decoder(DrillInput) {
  use path <- decode.field("path", decode.string)
  use expected_sha256 <- decode.field("expectedSha256", decode.string)
  use maximum_bytes <- decode.field("maximumBytes", decode.int)
  use record_id <- decode.field("recordId", decode.string)
  decode.success(DrillInput(path, expected_sha256, maximum_bytes, record_id))
}
`;
}

function domainModule(spec) {
  return `import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "${spec.name}_v1",
    "${spec.track}",
    ${gleamList(spec.mics)},
    ${gleamList(spec.kinds)},
    ${gleamList(spec.fields)},
  )
}
`;
}

function updateReadme(spec, directory) {
  const path = join(directory, "README.md");
  const source = readFileSync(path, "utf8")
    .replace(
      /Status: \*\*Designing\*\*[^\n]*/,
      "Status: **Implemented in building T2** · bounded content-bound import product",
    );
  const addition = `
## Implemented T2 import path

The package now exposes \`${spec.inspect}\` and \`${spec.drill}\`. Both use the
shared versioned \`${spec.name}_v1\` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
\`${spec.track}\`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
`;
  if (!source.includes("## Implemented T2 import path")) {
    writeFileSync(path, `${source.trimEnd()}\n${addition}`);
  }
}

export function generateEvidencePlugins() {
  for (const spec of EVIDENCE_PLUGINS) {
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

if (import.meta.main) generateEvidencePlugins();
