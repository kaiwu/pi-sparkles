const AXIS_WIDTH = 10;
const SLOT_WIDTH = 2;
const PRICE_ROWS = 9;
const VOLUME_ROWS = 3;
const MIN_CHART_WIDTH = AXIS_WIDTH + SLOT_WIDTH;

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function chartDetails(result) {
  const details = result?.details;
  return isRecord(details) &&
    details.schema === "pi-sparkles/finance-chart-result" &&
    details.schemaVersion === 2 &&
    Array.isArray(details.bars)
    ? details
    : null;
}

function resultText(result) {
  return Array.isArray(result?.content)
    ? result.content
        .filter((item) => item?.type === "text" && typeof item.text === "string")
        .map((item) => item.text)
        .join("\n")
    : "";
}

function clip(text, width) {
  if (width <= 0) return "";
  const value = String(text);
  return value.length <= width ? value : value.slice(0, width);
}

function finite(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function axisLabel(value) {
  if (!Number.isFinite(value)) return "?";
  const absolute = Math.abs(value);
  const text =
    absolute !== 0 && (absolute >= 1e7 || absolute < 1e-4)
      ? value.toExponential(2)
      : value.toFixed(absolute >= 1000 ? 0 : absolute >= 10 ? 2 : 4);
  return text.length <= AXIS_WIDTH - 2
    ? text
    : value.toExponential(1).slice(0, AXIS_WIDTH - 2);
}

function rowFor(value, minimum, maximum, rows) {
  if (maximum === minimum) return Math.floor((rows - 1) / 2);
  return Math.max(
    0,
    Math.min(rows - 1, Math.round(((maximum - value) / (maximum - minimum)) * (rows - 1))),
  );
}

function put(matrix, row, column, character, { replace = true } = {}) {
  if (
    row < 0 ||
    row >= matrix.length ||
    column < 0 ||
    column >= matrix[row].length ||
    (!replace && matrix[row][column] !== " ")
  ) {
    return;
  }
  matrix[row][column] = character;
}

function numericBars(bars) {
  const parsed = [];
  for (const bar of bars) {
    const open = finite(bar?.open);
    const high = finite(bar?.high);
    const low = finite(bar?.low);
    const close = finite(bar?.close);
    const volume = finite(bar?.volume);
    if (
      typeof bar?.date !== "string" ||
      open === null ||
      high === null ||
      low === null ||
      close === null ||
      volume === null
    ) {
      return null;
    }
    parsed.push({ ...bar, open, high, low, close, volume });
  }
  return parsed;
}

function visibleSlice(details, width) {
  const capacity = Math.max(1, Math.floor((width - AXIS_WIDTH) / SLOT_WIDTH));
  const start = Math.max(0, details.bars.length - capacity);
  return { start, bars: details.bars.slice(start), capacity };
}

function matchingPoints(details, panel, dates) {
  const points = [];
  for (const [seriesIndex, indicator] of (details.indicators ?? []).entries()) {
    if (indicator?.panel !== panel || !Array.isArray(indicator.points)) continue;
    for (const point of indicator.points) {
      if (point?.state !== "calculated" || !dates.has(point.date)) continue;
      const value = finite(point.value);
      if (value !== null) points.push({ ...point, value, seriesIndex });
    }
  }
  return points;
}

function priceChart(details, visible, plotWidth) {
  const matrix = Array.from({ length: PRICE_ROWS }, () => Array(plotWidth).fill(" "));
  const dates = new Map(visible.map((bar, index) => [bar.date, index]));
  const overlays = matchingPoints(details, "price_overlay", dates);
  const priceValues = visible.flatMap((bar) => [bar.low, bar.high]);
  for (const point of overlays) priceValues.push(point.value);
  const minimum = Math.min(...priceValues);
  const maximum = Math.max(...priceValues);

  for (const [index, bar] of visible.entries()) {
    const x = index * SLOT_WIDTH + 1;
    const high = rowFor(bar.high, minimum, maximum, PRICE_ROWS);
    const low = rowFor(bar.low, minimum, maximum, PRICE_ROWS);
    const open = rowFor(bar.open, minimum, maximum, PRICE_ROWS);
    const close = rowFor(bar.close, minimum, maximum, PRICE_ROWS);
    for (let row = Math.min(high, low); row <= Math.max(high, low); row += 1) {
      put(matrix, row, x, "|", { replace: false });
    }
    const body = bar.close > bar.open ? "#" : bar.close < bar.open ? "=" : "-";
    for (let row = Math.min(open, close); row <= Math.max(open, close); row += 1) {
      put(matrix, row, x, body);
      put(matrix, row, x - 1, body);
    }
  }

  for (const point of overlays) {
    const index = dates.get(point.date);
    put(
      matrix,
      rowFor(point.value, minimum, maximum, PRICE_ROWS),
      index * SLOT_WIDTH,
      String((point.seriesIndex % 9) + 1),
    );
  }
  for (const trade of details.trades ?? []) {
    const index = dates.get(trade?.date);
    const price = finite(trade?.price);
    if (index === undefined || price === null) continue;
    put(
      matrix,
      rowFor(price, minimum, maximum, PRICE_ROWS),
      index * SLOT_WIDTH + 1,
      trade.side === "buy" ? "B" : "S",
    );
  }

  return matrix.map((row, index) => {
    const value = maximum - ((maximum - minimum) * index) / (PRICE_ROWS - 1);
    return `${axisLabel(value).padStart(AXIS_WIDTH - 2)} |${row.join("")}`;
  });
}

function volumeChart(details, visible, plotWidth) {
  const matrix = Array.from({ length: VOLUME_ROWS }, () => Array(plotWidth).fill(" "));
  const maximum = Math.max(0, ...visible.map((bar) => bar.volume));
  for (const [index, bar] of visible.entries()) {
    const height = maximum === 0 ? 0 : Math.max(1, Math.round((bar.volume / maximum) * VOLUME_ROWS));
    for (let row = VOLUME_ROWS - 1; row >= VOLUME_ROWS - height; row -= 1) {
      put(matrix, row, index * SLOT_WIDTH + 1, "#");
    }
  }
  return matrix.map((row, index) =>
    `${index === 0 ? "volume".padStart(AXIS_WIDTH - 2) : " ".repeat(AXIS_WIDTH - 2)} |${row.join("")}`,
  );
}

function lowerChart(details, visible, plotWidth) {
  const dates = new Map(visible.map((bar, index) => [bar.date, index]));
  const points = matchingPoints(details, "lower_panel", dates);
  if (points.length === 0) return [];
  const rows = 3;
  const matrix = Array.from({ length: rows }, () => Array(plotWidth).fill(" "));
  const minimum = Math.min(...points.map((point) => point.value));
  const maximum = Math.max(...points.map((point) => point.value));
  for (const point of points) {
    put(
      matrix,
      rowFor(point.value, minimum, maximum, rows),
      dates.get(point.date) * SLOT_WIDTH + 1,
      String((point.seriesIndex % 9) + 1),
    );
  }
  return matrix.map((row, index) => {
    const value = maximum - ((maximum - minimum) * index) / (rows - 1);
    return `${axisLabel(value).padStart(AXIS_WIDTH - 2)} :${row.join("")}`;
  });
}

function gapLine(details, visible, plotWidth) {
  const gaps = details.gaps ?? [];
  if (gaps.length === 0 || visible.length === 0) return [];
  const row = Array(plotWidth).fill(" ");
  const first = visible[0].date;
  const last = visible.at(-1).date;
  for (const gap of gaps) {
    if (typeof gap?.date !== "string" || gap.date < first || gap.date > last) continue;
    let index = visible.findIndex((bar) => bar.date >= gap.date);
    if (index < 0) index = visible.length - 1;
    row[index * SLOT_WIDTH + 1] = "!";
  }
  return row.includes("!") ? [`${"gaps".padStart(AXIS_WIDTH - 2)} !${row.join("")}`] : [];
}

function summaryLine(details, visible, hidden) {
  const first = visible[0]?.date ?? "?";
  const last = visible.at(-1)?.date ?? "?";
  return `OHLCV ${details.track}/${details.mic} ${details.instrumentId} | ${first}..${last} | ${visible.length}/${details.bars.length} bars | ${hidden} earlier hidden`;
}

function renderChart(result, width) {
  const details = chartDetails(result);
  if (details === null || details.bars.length === 0) return null;
  const safeWidth = Number.isInteger(width) && width > 0 ? width : 80;
  if (safeWidth < MIN_CHART_WIDTH) {
    return [clip(`OHLCV ${details.track}/${details.mic} ${details.instrumentId} | ${details.bars.length} bars`, safeWidth)];
  }
  const selected = visibleSlice(details, safeWidth);
  const visible = numericBars(selected.bars);
  if (visible === null || visible.length === 0) return null;
  const plotWidth = visible.length * SLOT_WIDTH;
  const lines = [
    summaryLine(details, visible, selected.start),
    ...priceChart(details, visible, plotWidth),
    `${" ".repeat(AXIS_WIDTH - 2)} +${"-".repeat(plotWidth)}`,
    ...volumeChart(details, visible, plotWidth),
    ...lowerChart(details, visible, plotWidth),
    ...gapLine(details, visible, plotWidth),
    "legend # up  = down  - flat  | wick  B/S trade  ! supplied gap  1-4 indicator",
  ];
  return lines.map((line) => clip(line, safeWidth));
}

class FinanceChartResult {
  constructor() {
    this.result = null;
    this.expanded = false;
  }

  setResult(result, expanded) {
    this.result = result;
    this.expanded = expanded;
  }

  invalidate() {}

  render(width) {
    const chart = renderChart(this.result, width);
    const text = resultText(this.result);
    if (chart === null) {
      return text === "" ? ["Chart result unavailable"] : text.split("\n").map((line) => clip(line, width));
    }
    if (!this.expanded || text === "") return chart;
    return [...chart, "", ...text.split("\n")].map((line) => clip(line, width));
  }
}

export function render_result(result, expanded, _theme, lastComponent) {
  const component = lastComponent instanceof FinanceChartResult
    ? lastComponent
    : new FinanceChartResult();
  component.setResult(result, expanded === true);
  return component;
}
