import { describe, expect, test } from "bun:test";
import { dshClientFactorySource } from "../../dsh/client.js";

function fakeReact() {
  const hooks = [];
  let cursor = 0;
  return {
    begin() {
      cursor = 0;
    },
    createElement(type, props, ...children) {
      return {
        type,
        props: props ?? {},
        children,
      };
    },
    useRef(value) {
      const index = cursor++;
      if (hooks[index] === undefined) hooks[index] = { current: value };
      return hooks[index];
    },
    useState(value) {
      const index = cursor++;
      if (hooks[index] === undefined) hooks[index] = value;
      return [
        hooks[index],
        (next) => {
          hooks[index] = typeof next === "function" ? next(hooks[index]) : next;
        },
      ];
    },
    useEffect(effect) {
      effect();
    },
  };
}

function loadChartComponent(React) {
  let loaded;
  const window = {
    innerWidth: 1280,
    innerHeight: 720,
    ResizeObserver: class {
      constructor(callback) {
        this.callback = callback;
      }
      observe() {}
      disconnect() {}
    },
    __ModuleLoader__: {
      load(definition) {
        loaded = definition.factory((name) => {
          if (name === "react") return React;
          throw new Error(`unexpected client module: ${name}`);
        });
      },
    },
  };
  new Function("window", dshClientFactorySource("@fixture/chart-client"))(window);
  const registered = new Map();
  loaded.apply({
    slots: {
      inject(_name, callback) {
        callback();
      },
      register(definition, component) {
        registered.set(`${definition.name}:${definition.key ?? ""}`, {
          definition,
          component,
        });
        return () => {};
      },
    },
  });
  return registered.get("tool.call.toolview:chart_ohlcv");
}

function chartBlock(count = 100) {
  return {
    kind: "tool-result",
    content: [{ type: "text", text: "exact chart fallback" }],
    meta: {
      schema: "pi-sparkles/dsh-finance-chart-meta",
      schemaVersion: 1,
      valid: true,
      chart: {
        track: "us",
        instrumentId: "US-AAPL",
        mic: "XNAS",
        timezone: "America/New_York",
        priceUnit: "USD",
        volumeUnit: "shares",
        adjustment: { kind: "raw", label: null },
        presentation: { kind: "responsive_ohlcv_view" },
        bars: Array.from({ length: count }, (_, index) => ({
          date: `D${String(index + 1).padStart(3, "0")}`,
          sessionType: "regular",
          open: String(100 + index),
          high: String(102 + index),
          low: String(99 + index),
          close: String(101 + index),
          volume: String(1000 + index * 10),
        })),
        indicators: [],
        trades: [],
        gaps: [],
        inputOmissions: [],
      },
    },
  };
}

function textContent(node) {
  if (node === null || node === undefined || typeof node === "boolean") return "";
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(textContent).join(" ");
  return textContent(node.children);
}

describe("DSH inline finance chart client", () => {
  test("registers the exact keyed tool view and renders a latest width-proportional suffix", () => {
    const React = fakeReact();
    const entry = loadChartComponent(React);
    expect(entry.definition).toMatchObject({
      name: "tool.call.toolview",
      key: "chart_ohlcv",
      label: "Pi Sparkles inline OHLCV chart",
    });

    React.begin();
    let rendered = entry.component({ block: chartBlock() });
    expect(rendered.type).toBe("section");
    expect(rendered.props).toMatchObject({
      role: "figure",
      "data-dsh-sparkles-chart": "inline",
      "data-visible-bars": "72",
    });
    expect(rendered.props["aria-label"]).toContain("D029 through D100");
    expect(textContent(rendered)).toContain("72/100 bars");
    expect(textContent(rendered)).toContain("Exact table output");

    rendered.props.ref.current = {
      getBoundingClientRect() {
        return { width: 300 };
      },
    };
    React.begin();
    entry.component({ block: chartBlock() });
    React.begin();
    rendered = entry.component({ block: chartBlock() });
    expect(rendered.props["data-visible-bars"]).toBe("25");
    expect(rendered.props["aria-label"]).toContain("D076 through D100");
    expect(textContent(rendered)).toContain("75 earlier hidden");
  });

  test("keeps malformed metadata inline as ordinary text output", () => {
    const React = fakeReact();
    const entry = loadChartComponent(React);
    React.begin();
    const rendered = entry.component({
      block: {
        kind: "tool-result",
        content: [{ type: "text", text: "safe exact fallback" }],
        meta: { schema: "unknown" },
      },
    });
    expect(rendered.props["data-dsh-sparkles-chart"]).toBe("fallback");
    expect(textContent(rendered)).toContain("safe exact fallback");
  });
});
