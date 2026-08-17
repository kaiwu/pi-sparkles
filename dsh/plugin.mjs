// DeepSeek Harness all-in-one plugin factory for pi-sparkles.
//
// The bundler (scripts/dsh-bundle.js) generates an entry that imports every
// compiled Pi plugin bundle and calls createPlugin with the ordered
// `[shortName, extensionFactory]` list. The resulting Cordis plugin mounts a
// Pi ExtensionApi facade (pi-api.mjs) over the Harness `ctx` and runs every
// extension factory once. Pi session lifecycle hooks follow DSH agent/session
// events; they are never synthesized at process/plugin scope. Registration
// collisions are detected per plugin with the same named-registration guard
// the Pi aggregate uses.

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
 * @param {Array<[string, object|Function]>|string} dshExtensionsOrName
 *   DSH-native Cordis plugins, or the plugin name for the legacy two-argument form.
 * @param {string} pluginName - Cordis plugin name.
 * @returns the Cordis plugin `{ name, inject, apply }`.
 */
export function createPlugin(
  extensions,
  dshExtensionsOrName = [],
  pluginName = "dsh-sparkles",
) {
  const dshExtensions = Array.isArray(dshExtensionsOrName)
    ? dshExtensionsOrName
    : [];
  const resolvedPluginName =
    typeof dshExtensionsOrName === "string"
      ? dshExtensionsOrName
      : pluginName;
  const debug = typeof process !== "undefined" && process.env?.DSH_PI_SPARKLES_DEBUG === "1";
  const trace = (...args) => {
    if (debug) console.error("[dsh-sparkles]", ...args);
  };
  return {
    name: resolvedPluginName,
    inject: ["tools", "commands", "agents"],
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
      for (const [shortName, extension] of dshExtensions) {
        if (
          typeof extension !== "function" &&
          (typeof extension !== "object" || extension === null)
        ) {
          throw new Error(`${shortName} has no DSH Cordis plugin export`);
        }
        trace(`loading DSH-native ${shortName}`);
        const dshConfig = config?.dsh;
        const extensionConfig =
          typeof dshConfig === "object" &&
          dshConfig !== null &&
          Object.hasOwn(dshConfig, shortName)
            ? dshConfig[shortName]
            : {};
        await ctx.plugin(extension, extensionConfig);
      }
      ctx.on("agent/session-start", async ({ agent, source }) => {
        const reason = source === "resume" ? "resume" : "startup";
        await api._fireSessionStart(agent, reason);
      });
      ctx.on("agent/disposed", async ({ agent }) => {
        await api._fireSessionShutdown(agent, "quit");
      });
      trace(
        `registered ${registrations.size} named registrations from ${extensions.length} Pi extensions and ${dshExtensions.length} DSH-native extensions`,
      );
    },
  };
}
