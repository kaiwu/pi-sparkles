import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { build } from "./build.js";
import { DIST_DIR, ROOT } from "./modules.js";

const allowedHosts = new Set(["data.sec.gov", "www.sec.gov"]);
const maximumRequests = 10;
const toolTimeoutMs = 30_000;

const fundamentalsFixtures = [
  {
    id: "apple-52-week-revenue-2023",
    cik: "320193",
    metric: "revenue",
    unit: "USD",
    period: "annual",
    end: "2023-09-30",
  },
  {
    id: "microsoft-june-year-end-income-2020",
    cik: "789019",
    metric: "net_income",
    unit: "USD",
    period: "annual",
    end: "2020-06-30",
  },
  {
    id: "coca-cola-calendar-assets-2023",
    cik: "21344",
    metric: "assets",
    unit: "USD",
    period: "instant",
    end: "2023-12-31",
  },
];

if (import.meta.main) {
  try {
    await main();
  } catch (error) {
    console.error(
      JSON.stringify(
        {
          schemaVersion: 1,
          kind: "live_sec_compatibility",
          status: "failed",
          error: error instanceof Error ? error.message : String(error),
        },
        null,
        2,
      ),
    );
    process.exitCode = 1;
  }
}

async function main() {
  validateLiveContact(process.env);
  const startedAt = new Date().toISOString();
  const requests = [];
  const checks = [];
  const originalFetch = globalThis.fetch;

  globalThis.fetch = guardedFetch(originalFetch, requests);

  try {
    for (const plugin of ["sec_edgar", "sec_xbrl", "stock_fundamentals"]) {
      await build(plugin);
    }

    const edgar = await loadPlugin("sec_edgar");
    const xbrl = await loadPlugin("sec_xbrl");
    const fundamentals = await loadPlugin("stock_fundamentals");

    const company = await execute(edgar, "sec_company_search", {
      query: "AAPL",
      limit: 1,
    });
    invariant(
      company.details.candidates.some(
        (candidate) =>
          candidate.cik === "0000320193" && candidate.ticker === "AAPL",
      ),
      "SEC company association file did not resolve AAPL to CIK 0000320193",
    );
    checks.push({
      id: "company-search",
      plugin: "sec_edgar",
      status: "passed",
      candidate: company.details.candidates[0],
    });

    const submissions = await execute(edgar, "sec_company_submissions", {
      cik: "320193",
      form: "10-K",
      limit: 2,
    });
    invariant(
      submissions.details.filings.length > 0,
      "Apple submissions contained no recent 10-K filing",
    );
    invariant(
      submissions.details.filings.every((filing) => filing.form === "10-K"),
      "Exact 10-K filtering returned another form",
    );
    checks.push({
      id: "recent-submissions",
      plugin: "sec_edgar",
      status: "passed",
      cik: submissions.details.cik,
      accessions: submissions.details.filings.map((filing) => filing.accession),
    });

    const concepts = await execute(xbrl, "sec_xbrl_concepts", {
      cik: "320193",
      query: "Assets",
      taxonomy: "us-gaap",
      limit: 5,
    });
    invariant(
      concepts.details.candidates.some(
        (candidate) =>
          candidate.taxonomy === "us-gaap" && candidate.tag === "Assets",
      ),
      "Apple company facts did not expose us-gaap:Assets",
    );
    checks.push({
      id: "concept-discovery",
      plugin: "sec_xbrl",
      status: "passed",
      company: concepts.details.company,
      candidates: concepts.details.candidates.length,
    });

    const facts = await execute(xbrl, "sec_xbrl_facts", {
      cik: "320193",
      taxonomy: "us-gaap",
      tag: "Assets",
      unit: "USD",
      limit: 5,
    });
    invariant(
      facts.details.facts.length > 0,
      "Apple us-gaap:Assets contained no USD facts",
    );
    invariant(
      facts.details.facts.every(
        (fact) =>
          typeof fact.value === "string" &&
          fact.valueKind === "numeric_exact_lexeme",
      ),
      "Live XBRL numeric facts did not preserve exact source lexemes",
    );
    checks.push({
      id: "raw-xbrl-facts",
      plugin: "sec_xbrl",
      status: "passed",
      company: facts.details.company,
      returned: facts.details.facts.length,
      totalMatching: facts.details.totalMatching,
      duplicatesPreserved: facts.details.duplicatesPreserved,
    });

    for (const fixture of fundamentalsFixtures) {
      const result = await execute(
        fundamentals,
        "stock_fundamental_period",
        {
          cik: fixture.cik,
          metric: fixture.metric,
          unit: fixture.unit,
          period: fixture.period,
          end: fixture.end,
          filingPolicy: "latest_filed",
        },
      );
      invariant(
        result.details.resolution !== "no_match" &&
          result.details.candidates.length > 0,
        `${fixture.id} produced no live fundamental candidate`,
      );
      invariant(
        result.details.candidates.every(
          (candidate) =>
            typeof candidate.value === "string" &&
            typeof candidate.canonicalDecimal === "string",
        ),
        `${fixture.id} lost exact decimal representations`,
      );
      checks.push({
        id: fixture.id,
        plugin: "stock_fundamentals",
        status: "passed",
        company: result.details.company,
        metric: fixture.metric,
        period: fixture.period,
        end: fixture.end,
        resolution: result.details.resolution,
        candidates: result.details.candidates.map((candidate) => ({
          tag: candidate.tag,
          accession: candidate.accession,
          form: candidate.form,
          filed: candidate.filed,
        })),
      });
    }

    console.log(
      JSON.stringify(
        {
          schemaVersion: 1,
          kind: "live_sec_compatibility",
          status: "passed",
          startedAt,
          finishedAt: new Date().toISOString(),
          requestBudget: maximumRequests,
          requests,
          checks,
        },
        null,
        2,
      ),
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
}

function validateLiveContact(environment) {
  const contact = environment.AGENT_CONTACT?.trim() ?? "";
  if (contact === "") {
    throw new Error(
      'Live SEC tests require AGENT_CONTACT, for example: AGENT_CONTACT="you@your-real-domain.com" bun run test:live:sec',
    );
  }
  if (
    /example\.(com|net|org)$/i.test(contact) ||
    contact.includes("your-real-domain")
  ) {
    throw new Error(
      "AGENT_CONTACT must identify a real contact, not a placeholder",
    );
  }
}

function guardedFetch(fetchImplementation, requests) {
  return async (input, init) => {
    const url = new URL(
      typeof input === "string" || input instanceof URL ? input : input.url,
    );
    const method = (init?.method ?? "GET").toUpperCase();
    invariant(url.protocol === "https:", "Live SEC requests must use HTTPS");
    invariant(
      allowedHosts.has(url.hostname),
      `Live SEC runner blocked unexpected host ${url.hostname}`,
    );
    invariant(method === "GET", `Live SEC runner blocked ${method} request`);
    invariant(
      requests.length < maximumRequests,
      `Live SEC run reached its ${maximumRequests}-request budget`,
    );

    const request = {
      method,
      url: url.toString(),
      status: "pending",
      durationMs: 0,
    };
    requests.push(request);
    const started = performance.now();
    try {
      const response = await fetchImplementation(input, {
        ...init,
        redirect: "error",
      });
      request.status = response.status;
      return response;
    } catch (error) {
      request.status = "transport_error";
      throw error;
    } finally {
      request.durationMs = Math.round(performance.now() - started);
    }
  };
}

async function loadPlugin(shortName) {
  const tools = new Map();
  const artifact = pathToFileURL(join(DIST_DIR, shortName, "index.js"));
  artifact.searchParams.set("live-sec", Date.now().toString());
  const module = await import(artifact.href);
  await module.default({
    registerCommand() {},
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  });
  return tools;
}

async function execute(tools, name, input) {
  const definition = tools.get(name);
  invariant(definition, `Plugin did not register ${name}`);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), toolTimeoutMs);
  try {
    return await definition.execute(
      `live-${name}`,
      input,
      controller.signal,
      undefined,
      { cwd: ROOT, mode: "text", hasUI: false },
    );
  } finally {
    clearTimeout(timeout);
  }
}

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}
