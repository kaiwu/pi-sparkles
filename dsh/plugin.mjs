// DeepSeek Harness all-in-one plugin factory for pi-sparkles.
//
// The bundler (scripts/dsh-bundle.js) generates an entry that imports every
// compiled Pi plugin bundle and calls createPlugin with the ordered
// `[shortName, extensionFactory]` list. The resulting Cordis plugin mounts a
// Pi ExtensionApi facade (pi-api.mjs) over the Harness `ctx`, runs every
// extension factory once, and fires the `session_start` hook so plugins
// initialize with defaults. Registration collisions are detected per plugin
// with the same named-registration guard the Pi aggregate uses.

import { createPiApi } from "./pi-api.mjs";

const NAMED_REGISTRATIONS = new Map([
  ["registerTool", (args) => args[0]?.name],
  ["registerCommand", (args) => args[0]],
  ["registerShortcut", (args) => args[0]],
  ["registerFlag", (args) => args[0]],
  ["registerProvider", (args) => args[0]],
  ["registerMessageRenderer", (args) => args[0]],
  ["registerEntryRenderer", (args) => args[0]],
]);

function scopedApi(api, pluginName, registrations) {
  return new Proxy(api, {
    get(target, property, receiver) {
      const value = Reflect.get(target, property, receiver);
      if (typeof value !== "function") return value;
      const extractName = NAMED_REGISTRATIONS.get(property);
      if (!extractName) return value.bind(target);
      return (...args) => {
        const name = extractName(args);
        if (typeof name !== "string" || name.trim().length === 0) {
          throw new Error(
            `${pluginName} called ${String(property)} without a stable name`,
          );
        }
        const key = `${String(property)}:${name}`;
        const previous = registrations.get(key);
        if (previous !== undefined) {
          throw new Error(
            `Registration collision for ${String(property)} '${name}': ${previous} and ${pluginName}`,
          );
        }
        registrations.set(key, pluginName);
        return Reflect.apply(value, target, args);
      };
    },
  });
}

/**
 * Build the Cordis plugin object.
 * @param {Array<[string, (api: object) => Promise<void>]>} extensions
 *   ordered `[pluginShortName, extensionFactory]` entries.
 * @param {string} pluginName - Cordis plugin name.
 * @returns the Cordis plugin `{ name, inject, apply }`.
 */
export function createPlugin(extensions, pluginName = "dsh-sparkles") {
  const debug = typeof process !== "undefined" && process.env?.DSH_PI_SPARKLES_DEBUG === "1";
  const trace = (...args) => {
    if (debug) console.error("[dsh-sparkles]", ...args);
  };
  return {
    name: pluginName,
    inject: ["tools", "commands"],
    async apply(ctx, config) {
      const registrations = new Map();
      const api = createPiApi({ ctx, config: config ?? {} });
      for (const [shortName, extension] of extensions) {
        if (typeof extension !== "function") {
          throw new Error(`${shortName} has no extension factory`);
        }
        trace(`loading ${shortName}`);
        await extension(scopedApi(api, shortName, registrations));
      }
      ctx.on("dispose", () => {
        try {
          api._fireSessionShutdown();
        } catch {
          // shutdown hooks are best-effort
        }
      });
      // Pi fires session_start when a session begins; in DSH the plugin owns a
      // single logical session per process, so fire once after registration.
      api._fireSessionStart();
      trace(
        `registered ${registrations.size} named registrations from ${extensions.length} extensions`,
      );
    },
  };
}
