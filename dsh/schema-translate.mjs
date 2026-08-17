// Pi JSON Schema → DeepSeek Harness raw JSON-Schema translator.
//
// Pi plugins register tools with full JSON Schema (pi_gleam/pi/schema.gleam):
// types, properties/required/additionalProperties, items, enum/const,
// anyOf (nullable/one_of), description/title/default/examples, and length/
// range constraints (minLength/maxLength/minimum/maximum/minItems/maxItems).
//
// DeepSeek Harness (dsh-tools) stores a tool's `parameters` as RAW JSON
// Schema (it is what `defineTool` compiles and what the registry validates
// model arguments against at call time). That schema must use only the subset
// dsh-tools supports: type (single string among object/array/string/number/
// integer/boolean/null), oneOf, properties, required, additionalProperties,
// items, enum, const, plus the description/title/default/examples
// annotations. Unsupported keywords (anyOf, minLength/maxLength, minimum/
// maximum, minItems/maxItems, prefixItems, pattern, format, ...) are rejected
// at validation time, so this module translates them away.
//
// The Pi-side decoders embedded in every plugin bundle still enforce the FULL
// contract when the tool runs, so dropping constraint keywords here only
// loosens the model-facing argument schema — never the runtime validation.

const SUPPORTED_KEYS = new Set([
  "type",
  "oneOf",
  "properties",
  "required",
  "additionalProperties",
  "items",
  "enum",
  "const",
  "description",
  "title",
  "default",
  "examples",
]);

const PRIMITIVE_TYPES = new Set([
  "string",
  "integer",
  "number",
  "boolean",
  "null",
]);

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function boundedHint(label, minimum, maximum) {
  const hasMinimum = typeof minimum === "number" && Number.isFinite(minimum);
  const hasMaximum = typeof maximum === "number" && Number.isFinite(maximum);
  if (hasMinimum && hasMaximum) {
    return minimum === maximum
      ? `${label} exactly ${minimum}`
      : `${label} ${minimum}..${maximum}`;
  }
  if (hasMinimum) return `${label} >= ${minimum}`;
  if (hasMaximum) return `${label} <= ${maximum}`;
  return undefined;
}

/**
 * Preserve constraints which DSH cannot represent as schema keywords as
 * concise annotations. The Pi decoder remains authoritative at execution;
 * these hints keep the DSH model from seeing a misleadingly loose contract.
 */
function unsupportedConstraintHints(source) {
  const hints = [];
  if (source.type === "string") {
    const length = boundedHint("length", source.minLength, source.maxLength);
    if (length !== undefined) hints.push(length);
    if (typeof source.pattern === "string") hints.push(`pattern ${source.pattern}`);
    if (typeof source.format === "string") hints.push(`format ${source.format}`);
  } else if (source.type === "number" || source.type === "integer") {
    const value = boundedHint("value", source.minimum, source.maximum);
    if (value !== undefined) hints.push(value);
  } else if (source.type === "array") {
    const items = boundedHint("items", source.minItems, source.maxItems);
    if (items !== undefined) hints.push(items);
  }
  return hints;
}

/** Copy supported annotations and retain unsupported constraints as text. */
function copyAnnotations(source, target) {
  for (const key of ["title", "default", "examples"]) {
    if (Object.hasOwn(source, key)) target[key] = source[key];
  }
  const hints = unsupportedConstraintHints(source);
  const description =
    typeof source.description === "string" && source.description.length > 0
      ? source.description
      : undefined;
  if (hints.length > 0) {
    const constraintText = `Call constraints: ${hints.join("; ")}.`;
    target.description =
      description === undefined ? constraintText : `${description}\n\n${constraintText}`;
  } else if (description !== undefined) {
    target.description = description;
  }
}

/**
 * Translate one Pi schema node into the supported raw JSON-Schema subset.
 * The result only ever uses keys in SUPPORTED_KEYS.
 */
export function translateValueSchema(schema) {
  if (!isPlainObject(schema)) return {};

  // anyOf is not a supported keyword; oneOf is. Single-branch anyOf unwraps.
  if (Object.hasOwn(schema, "anyOf")) {
    const branches = Array.isArray(schema.anyOf) ? schema.anyOf : [];
    if (branches.length === 1) return translateValueSchema(branches[0]);
    if (branches.length >= 2) {
      const translated = { oneOf: branches.map((branch) => translateValueSchema(branch)) };
      copyAnnotations(schema, translated);
      return translated;
    }
    return {};
  }

  const type = schema.type;
  if (typeof type !== "string") {
    // Unconstrained JSON: an annotation-only schema (no type) matches anything.
    return annotationOnly(schema);
  }

  switch (type) {
    case "object": {
      const result = { type: "object" };
      copyAnnotations(schema, result);
      const additional = schema.additionalProperties;
      result.additionalProperties =
        typeof additional === "boolean" ? additional : true;
      if (isPlainObject(schema.properties)) {
        const required = new Set(Array.isArray(schema.required) ? schema.required : []);
        const properties = {};
        for (const [name, child] of Object.entries(schema.properties)) {
          Object.defineProperty(properties, name, {
            value: translateValueSchema(child),
            enumerable: true,
            configurable: true,
            writable: true,
          });
        }
        result.properties = properties;
        if (required.size > 0) result.required = [...required];
      }
      return result;
    }
    case "array": {
      const result = { type: "array" };
      copyAnnotations(schema, result);
      if (isPlainObject(schema.items)) result.items = translateValueSchema(schema.items);
      else if (Array.isArray(schema.prefixItems) && schema.prefixItems.length > 0) {
        // Tuples have no exact DSH spelling: keep per-position typing as
        // element guidance via oneOf (order and length stay Pi-decoder
        // enforced at call time).
        const branches = schema.prefixItems.map((item) => translateValueSchema(item));
        result.items =
          branches.length === 1 ? branches[0] : { oneOf: branches };
      }
      return result;
    }
    case "string":
    case "integer":
    case "number":
    case "boolean":
    case "null": {
      const result = { type };
      copyAnnotations(schema, result);
      if (Object.hasOwn(schema, "enum") && Array.isArray(schema.enum)) {
        result.enum = schema.enum;
      }
      if (Object.hasOwn(schema, "const")) result.const = schema.const;
      return result;
    }
    default:
      return annotationOnly(schema);
  }
}

function annotationOnly(schema) {
  const result = {};
  copyAnnotations(schema, result);
  return result;
}

/**
 * Translate a Pi tool `parameters` schema into the raw JSON-Schema object the
 * DSH registry expects. Pi roots are object schemas; anything else degrades
 * to an empty object parameter schema.
 */
export function translateParameters(parameters) {
  if (isPlainObject(parameters) && parameters.type === "object") {
    return translateValueSchema(parameters);
  }
  return { type: "object", properties: {}, additionalProperties: false };
}

/**
 * The shared output contract for every bridged Pi tool. Pi tool results are
 * `{ content: [{ type: "text", text }], details }`; DSH validates the value
 * against this raw-JSON-Schema subset and renders the text.
 */
export const OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    content: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          type: { type: "string" },
          text: { type: "string" },
        },
        required: ["type", "text"],
      },
    },
    details: { description: "Rich per-tool details (presentation data)." },
  },
  required: ["content"],
};

/** Render a bridged tool value to DSH model-visible content blocks. */
export function renderToolValue(value) {
  const content = Array.isArray(value?.content) ? value.content : [];
  const blocks = content
    .filter((item) => item?.type === "text" && typeof item.text === "string")
    .map((item) => ({ type: "text", text: item.text }));
  return blocks.length === 0
    ? [{ type: "text", text: "(no output)" }]
    : blocks;
}

/** Walk a translated schema and confirm only supported keys remain. */
export function assertRawSubset(schema, path = "schema", errors = []) {
  if (!isPlainObject(schema)) {
    errors.push(`${path} must be a schema object`);
    return errors;
  }
  for (const key of Object.keys(schema)) {
    if (!SUPPORTED_KEYS.has(key)) errors.push(`${path}.${key} is not a supported keyword`);
  }
  const hasType = Object.hasOwn(schema, "type");
  const hasOneOf = Object.hasOwn(schema, "oneOf");
  if (hasType && hasOneOf) errors.push(`${path} cannot declare both type and oneOf`);
  if (!hasType && !hasOneOf) {
    for (const key of ["properties", "required", "additionalProperties", "items", "enum", "const"]) {
      if (Object.hasOwn(schema, key)) errors.push(`${path}.${key} requires type or oneOf`);
    }
  }
  if (hasType) {
    if (typeof schema.type !== "string" || !PRIMITIVE_TYPES.has(schema.type) && schema.type !== "object" && schema.type !== "array") {
      errors.push(`${path}.type must be one of object/array/string/number/integer/boolean/null`);
    }
  }
  if (hasOneOf) {
    if (!Array.isArray(schema.oneOf) || schema.oneOf.length < 2) {
      errors.push(`${path}.oneOf must be an array of at least two schemas`);
    } else {
      schema.oneOf.forEach((branch, index) =>
        assertRawSubset(branch, `${path}.oneOf[${index}]`, errors),
      );
    }
  }
  if (isPlainObject(schema.properties)) {
    for (const [name, child] of Object.entries(schema.properties)) {
      assertRawSubset(child, `${path}.properties.${name}`, errors);
    }
  }
  if (Object.hasOwn(schema, "items")) {
    assertRawSubset(schema.items, `${path}.items`, errors);
  }
  return errors;
}
