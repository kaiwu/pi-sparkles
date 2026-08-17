// Source for the DSH browser half. The bundler wraps this factory in DSH's
// closure module protocol and ships it as client.js beside the host plugin.

export function dshClientFactorySource(packageName) {
  return `window.__ModuleLoader__.load({ id: ${JSON.stringify(packageName)}, factory: (require) => {
var module = { exports: {} }; var exports = module.exports;
var React = require("react");
var TRACK_STATUS_KEY = "finance-track";
var OVERLAY_PADDING = 8;
function clamp(value, minimum, maximum) {
  return Math.min(Math.max(value, minimum), Math.max(minimum, maximum));
}
function overlayBounds(node) {
  var parent = node.offsetParent;
  if (parent && typeof parent.getBoundingClientRect === "function") {
    var rect = parent.getBoundingClientRect();
    return { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
  }
  return { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight };
}
function clampedPosition(node, left, top, bounds) {
  var rect = node.getBoundingClientRect();
  return {
    left: clamp(left, OVERLAY_PADDING, bounds.width - rect.width - OVERLAY_PADDING),
    top: clamp(top, OVERLAY_PADDING, bounds.height - rect.height - OVERLAY_PADDING)
  };
}
function FinanceTrackOverlay(props) {
  var text = props.useSessions(function (state) {
    var current = state.current;
    if (current === undefined) return undefined;
    var summary = state.byId[current];
    return summary && summary.projectionValues && summary.projectionValues.piSparklesStatus
      ? summary.projectionValues.piSparklesStatus.values[TRACK_STATUS_KEY]
      : undefined;
  });
  var positionState = React.useState(null);
  var position = positionState[0];
  var setPosition = positionState[1];
  var draggingState = React.useState(false);
  var dragging = draggingState[0];
  var setDragging = draggingState[1];
  var drag = React.useRef(null);
  if (typeof text !== "string" || text.length === 0) return null;
  function onPointerDown(event) {
    if (event.button !== 0) return;
    var node = event.currentTarget;
    var rect = node.getBoundingClientRect();
    var bounds = overlayBounds(node);
    drag.current = {
      pointerId: event.pointerId,
      clientX: event.clientX,
      clientY: event.clientY,
      left: rect.left - bounds.left,
      top: rect.top - bounds.top,
      bounds: bounds
    };
    if (typeof node.setPointerCapture === "function") {
      node.setPointerCapture(event.pointerId);
    }
    setDragging(true);
    event.preventDefault();
  }
  function onPointerMove(event) {
    var active = drag.current;
    if (!active || active.pointerId !== event.pointerId) return;
    var node = event.currentTarget;
    setPosition(clampedPosition(
      node,
      active.left + event.clientX - active.clientX,
      active.top + event.clientY - active.clientY,
      active.bounds
    ));
    event.preventDefault();
  }
  function finishPointer(event) {
    var active = drag.current;
    if (!active || active.pointerId !== event.pointerId) return;
    drag.current = null;
    setDragging(false);
    var node = event.currentTarget;
    if (
      typeof node.hasPointerCapture === "function" &&
      node.hasPointerCapture(event.pointerId) &&
      typeof node.releasePointerCapture === "function"
    ) {
      node.releasePointerCapture(event.pointerId);
    }
  }
  function losePointer(event) {
    var active = drag.current;
    if (!active || active.pointerId !== event.pointerId) return;
    drag.current = null;
    setDragging(false);
  }
  function onKeyDown(event) {
    if (event.key === "Home") {
      setPosition(null);
      event.preventDefault();
      return;
    }
    var delta = event.shiftKey ? 32 : 8;
    var dx = event.key === "ArrowLeft" ? -delta : event.key === "ArrowRight" ? delta : 0;
    var dy = event.key === "ArrowUp" ? -delta : event.key === "ArrowDown" ? delta : 0;
    if (dx === 0 && dy === 0) return;
    var node = event.currentTarget;
    var rect = node.getBoundingClientRect();
    var bounds = overlayBounds(node);
    setPosition(clampedPosition(
      node,
      rect.left - bounds.left + dx,
      rect.top - bounds.top + dy,
      bounds
    ));
    event.preventDefault();
  }
  var style = {
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
    textOverflow: "ellipsis",
    cursor: dragging ? "grabbing" : "grab",
    touchAction: "none",
    userSelect: "none"
  };
  if (position !== null) {
    style.left = position.left + "px";
    style.top = position.top + "px";
    style.right = "auto";
    style.bottom = "auto";
  }
  return React.createElement("div", {
    role: "status",
    "aria-label": "Active finance track. Drag or use arrow keys to move; press Home to reset.",
    "data-dsh-sparkles-overlay": "finance-track",
    "data-dragging": dragging ? "true" : "false",
    tabIndex: 0,
    title: "Drag to move · Arrow keys move · Double-click or Home resets",
    onPointerDown: onPointerDown,
    onPointerMove: onPointerMove,
    onPointerUp: finishPointer,
    onPointerCancel: finishPointer,
    onLostPointerCapture: losePointer,
    onDoubleClick: function () { setPosition(null); },
    onKeyDown: onKeyDown,
    style: style
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
