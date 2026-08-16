import { describe, expect, test } from "bun:test";
import {
  assertRawSubset,
  OUTPUT_SCHEMA,
  renderToolValue,
  translateParameters,
  translateValueSchema,
} from "../../dsh/schema-translate.mjs";

// Mirrors of the Pi schema constructors (pi_gleam/src/pi/schema_ffi.mjs).
const string = (extra = {}) => ({ type: "string", ...extra });
const integer = () => ({ type: "integer" });
const stringEnum = (values) => ({ type: "string", enum: values });
const array = (items) => ({ type: "array", items });
const nullable = (schema) => ({ anyOf: [schema, { type: "null" }] });
const object = (properties, additionalProperties = false) => ({
  type: "object",
  properties,
  required: Object.entries(properties)
    .filter(([, schema]) => schema.__required)
    .map(([name]) => name),
  additionalProperties,
});
const prop = (schema, required = false) => (required ? { ...schema, __required: true } : schema);

describe("translateValueSchema", () => {
  test("keeps supported primitives and annotations", () => {
    expect(translateValueSchema(string({ description: "a code" }))).toEqual({
      type: "string",
      description: "a code",
    });
    expect(translateValueSchema(stringEnum(["cn", "hk", "us"]))).toEqual({
      type: "string",
      enum: ["cn", "hk", "us"],
    });
    expect(translateValueSchema(integer())).toEqual({ type: "integer" });
    expect(translateValueSchema({ type: "string", const: "us" })).toEqual({
      type: "string",
      const: "us",
    });
  });

  test("maps anyOf to oneOf", () => {
    expect(translateValueSchema(nullable(string()))).toEqual({
      oneOf: [{ type: "string" }, { type: "null" }],
    });
    expect(translateValueSchema({ anyOf: [string()] })).toEqual({ type: "string" });
  });

  test("drops unsupported constraint keywords but keeps types", () => {
    expect(
      translateValueSchema({
        type: "string",
        minLength: 1,
        maxLength: 40,
        pattern: "^[A-Z]+$",
      }),
    ).toEqual({ type: "string" });
    expect(
      translateValueSchema({ type: "number", minimum: 0, maximum: 100 }),
    ).toEqual({ type: "number" });
    expect(
      translateValueSchema({ type: "array", items: string(), minItems: 1, maxItems: 10 }),
    ).toEqual({ type: "array", items: { type: "string" } });
  });

  test("translates tuples to element-guidance arrays", () => {
    expect(
      translateValueSchema({
        type: "array",
        prefixItems: [string(), integer()],
        minItems: 2,
        maxItems: 2,
      }),
    ).toEqual({ type: "array", items: { oneOf: [{ type: "string" }, { type: "integer" }] } });
  });

  test("translates records to open objects", () => {
    expect(
      translateValueSchema({ type: "object", additionalProperties: string() }),
    ).toEqual({ type: "object", additionalProperties: true });
  });

  test("keeps object shape and required as an array", () => {
    expect(
      translateValueSchema({
        type: "object",
        properties: {
          a: string(),
          b: nullable(integer()),
        },
        required: ["a"],
        additionalProperties: false,
      }),
    ).toEqual({
      type: "object",
      additionalProperties: false,
      properties: {
        a: { type: "string" },
        b: { oneOf: [{ type: "integer" }, { type: "null" }] },
      },
      required: ["a"],
    });
  });

  test("spells unconstrained JSON as an annotation-only schema", () => {
    expect(translateValueSchema({})).toEqual({});
    expect(translateValueSchema({ description: "anything" })).toEqual({
      description: "anything",
    });
  });
});

describe("translateParameters", () => {
  test("passes a Pi object root through as raw JSON schema", () => {
    const parameters = object({
      ticker: prop(string(), true),
      limit: prop(integer()),
    });
    expect(translateParameters(parameters)).toEqual({
      type: "object",
      additionalProperties: false,
      properties: {
        ticker: { type: "string" },
        limit: { type: "integer" },
      },
      required: ["ticker"],
    });
  });

  test("degrades non-object roots to an empty object schema", () => {
    expect(translateParameters(undefined)).toEqual({
      type: "object",
      properties: {},
      additionalProperties: false,
    });
    expect(translateParameters({ type: "string" })).toEqual({
      type: "object",
      properties: {},
      additionalProperties: false,
    });
  });

  test("nested objects keep their own required arrays", () => {
    const parameters = object({
      identity: prop(
        {
          type: "object",
          properties: { symbol: string(), mic: string() },
          required: ["symbol"],
          additionalProperties: false,
        },
        true,
      ),
    });
    expect(translateParameters(parameters)).toEqual({
      type: "object",
      additionalProperties: false,
      properties: {
        identity: {
          type: "object",
          additionalProperties: false,
          properties: { symbol: { type: "string" }, mic: { type: "string" } },
          required: ["symbol"],
        },
      },
      required: ["identity"],
    });
  });
});

describe("raw subset assertion (mirror dsh-tools rules)", () => {
  test("translated parameters always pass the supported subset", () => {
    const cases = [
      object({ a: prop(nullable(string()), true), b: prop(array(string())) }),
      { type: "object", additionalProperties: string() },
      { type: "array", items: { type: "object", additionalProperties: true } },
      {},
      { anyOf: [string(), integer()] },
    ];
    for (const schema of cases) {
      expect(assertRawSubset(translateValueSchema(schema))).toEqual([]);
    }
    expect(assertRawSubset(translateParameters(object({ a: prop(string(), true) })))).toEqual([]);
  });

  test("output schema conforms to the raw subset", () => {
    expect(assertRawSubset(OUTPUT_SCHEMA)).toEqual([]);
    // Guardrails we must never trip:
    expect(assertRawSubset({ type: "string", minLength: 1 })).not.toEqual([]);
    expect(assertRawSubset({ anyOf: [{ type: "string" }, { type: "null" }] })).not.toEqual([]);
  });

  test("renderToolValue joins text content", () => {
    expect(
      renderToolValue({
        content: [{ type: "text", text: "one" }, { type: "text", text: "two" }],
        details: {},
      }),
    ).toBe("one\ntwo");
    expect(renderToolValue({ content: [], details: {} })).toBe("(no output)");
  });
});
