// Source for the DSH browser half. The bundler wraps this factory in DSH's
// closure module protocol and ships it as client.js beside the host plugin.

export function dshClientFactorySource(packageName) {
  return `window.__ModuleLoader__.load({ id: ${JSON.stringify(packageName)}, factory: (require) => {
var module = { exports: {} }; var exports = module.exports;
var React = require("react");
var TRACK_STATUS_KEY = "finance-track";
function FinanceTrackOverlay(props) {
  var text = props.useSessions(function (state) {
    var current = state.current;
    if (current === undefined) return undefined;
    var summary = state.byId[current];
    return summary && summary.projectionValues && summary.projectionValues.piSparklesStatus
      ? summary.projectionValues.piSparklesStatus.values[TRACK_STATUS_KEY]
      : undefined;
  });
  if (typeof text !== "string" || text.length === 0) return null;
  return React.createElement("div", {
    role: "status",
    "aria-label": "Active finance track",
    title: "Pi Sparkles active finance navigation track",
    style: {
      position: "absolute",
      right: "16px",
      bottom: "16px",
      maxWidth: "calc(100vw - 32px)",
      padding: "6px 10px",
      borderRadius: "999px",
      border: "1px solid var(--dsw-alias-border-l2)",
      background: "var(--dsw-alias-bg-base)",
      color: "var(--dsw-alias-text-primary)",
      boxShadow: "0 4px 18px rgba(0, 0, 0, 0.16)",
      fontFamily: "var(--dsw-font-mono, ui-monospace, monospace)",
      fontSize: "12px",
      lineHeight: "18px",
      whiteSpace: "nowrap",
      overflow: "hidden",
      textOverflow: "ellipsis"
    }
  }, text);
}
var inject = ["slots", "sessions"];
function apply(ctx) {
  ctx.slots.inject("shell.overlay", function () {
    return ctx.slots.register({
      name: "shell.overlay",
      id: "pi-sparkles-finance-track",
      order: 100,
      label: "Pi Sparkles finance track"
    }, FinanceTrackOverlay);
  });
}
module.exports = { inject: inject, apply: apply };
return module.exports; } });\n`;
}
