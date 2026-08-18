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

function chartBlock(count = 100, track = "us") {
  return {
    kind: "tool-result",
    content: [{ type: "text", text: "exact chart fallback" }],
    meta: {
      schema: "pi-sparkles/dsh-finance-chart-meta",
      schemaVersion: 1,
      valid: true,
      chart: {
        track,
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

function findByKey(node, key) {
  if (node === null || node === undefined || typeof node !== "object") return undefined;
  if (!Array.isArray(node) && node.props?.key === key) return node;
  const children = Array.isArray(node) ? node : node.children;
  if (!Array.isArray(children)) return findByKey(children, key);
  for (const child of children) {
    const match = findByKey(child, key);
    if (match !== undefined) return match;
  }
  return undefined;
}

function findByTitle(node, title) {
  if (node === null || node === undefined || typeof node !== "object") return undefined;
  if (!Array.isArray(node) && node.props?.title === title) return node;
  const children = Array.isArray(node) ? node : node.children;
  if (!Array.isArray(children)) return findByTitle(children, title);
  for (const child of children) {
    const match = findByTitle(child, title);
    if (match !== undefined) return match;
  }
  return undefined;
}

describe("DSH inline finance chart client", () => {
  test("registers the exact keyed tool view and opens each result at its full returned range", () => {
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
      "data-visible-bars": "100",
    });
    expect(rendered.props["aria-label"]).toContain("D001 through D100");
    expect(textContent(rendered)).toContain("100/100 bars");
    expect(textContent(rendered)).toContain("Exact table output");

    findByTitle(rendered, "Show fewer bars").props.onClick();
    React.begin();
    rendered = entry.component({ block: chartBlock() });
    expect(rendered.props["data-visible-bars"]).toBe("70");
    expect(rendered.props["aria-label"]).toContain("D031 through D100");

    React.begin();
    rendered = entry.component({ block: chartBlock(240) });
    expect(rendered.props["data-visible-bars"]).toBe("240");
    expect(rendered.props["aria-label"]).toContain("D001 through D240");
    expect(textContent(rendered)).toContain("240/240 bars");
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

  test("uses Mainland red-up/green-down and Hong Kong/US green-up/red-down", () => {
    const cases = [
      {
        track: "cn",
        up: "#ef5b5b",
        down: "#20b486",
        legend: "red up · green down · gray flat",
      },
      {
        track: "hk",
        up: "#20b486",
        down: "#ef5b5b",
        legend: "green up · red down · gray flat",
      },
      {
        track: "us",
        up: "#20b486",
        down: "#ef5b5b",
        legend: "green up · red down · gray flat",
      },
    ];

    for (const { track, up, down, legend } of cases) {
      const React = fakeReact();
      const entry = loadChartComponent(React);
      const block = chartBlock(3, track);
      block.meta.chart.bars[1].close = "99";
      block.meta.chart.bars[2].close = block.meta.chart.bars[2].open;

      React.begin();
      const rendered = entry.component({ block });

      expect(findByKey(rendered, "body-0")?.props.fill).toBe(up);
      expect(findByKey(rendered, "wick-0")?.props.stroke).toBe(up);
      expect(findByKey(rendered, "body-1")?.props.fill).toBe(down);
      expect(findByKey(rendered, "wick-1")?.props.stroke).toBe(down);
      expect(findByKey(rendered, "body-2")?.props.fill).toBe("#94a3b8");
      expect(textContent(rendered)).toContain(legend);
    }
  });

  test("renders RSI and ATR in separate exact-unit lower panes", () => {
    const React = fakeReact();
    const entry = loadChartComponent(React);
    const block = chartBlock(3, "cn");
    block.meta.chart.indicators = [
      {
        indicatorId: "rsi_2",
        label: "RSI 2",
        panel: "lower_panel",
        unit: "dimensionless_0_100",
        points: block.meta.chart.bars.map((bar, index) => ({
          state: "calculated",
          date: bar.date,
          value: String(40 + index * 5),
        })),
      },
      {
        indicatorId: "atr_2",
        label: "ATR 2",
        panel: "lower_panel",
        unit: "CNY",
        points: block.meta.chart.bars.map((bar, index) => ({
          state: "calculated",
          date: bar.date,
          value: String(0.5 + index * 0.1),
        })),
      },
    ];

    React.begin();
    const rendered = entry.component({ block });
    const svg = rendered.children.find((child) => child?.type === "svg");

    expect(svg.props.height).toBe("428");
    expect(findByKey(rendered, "lower-indicator-0-0")?.type).toBe("polyline");
    expect(findByKey(rendered, "lower-indicator-1-0")?.type).toBe("polyline");
    expect(textContent(findByKey(rendered, "lower-unit-0"))).toContain("dimensionless_0_100");
    expect(textContent(findByKey(rendered, "lower-unit-1"))).toContain("CNY");
  });
});
