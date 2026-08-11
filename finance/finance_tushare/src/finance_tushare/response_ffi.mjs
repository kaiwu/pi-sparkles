const numberKey = "__finance_tushare_number__";

export function normalize_numbers(source) {
  try {
    let supportsSource = false;
    JSON.parse("0", (_key, value, context) => {
      supportsSource = context?.source === "0";
      return value;
    });
    if (!supportsSource) return "";
    return JSON.stringify(
      JSON.parse(source, (_key, value, context) =>
        typeof value === "number" ? { [numberKey]: context.source } : value,
      ),
    );
  } catch {
    return "";
  }
}
