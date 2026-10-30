import assert from "node:assert/strict";
import test from "node:test";
import { prepareRuleInput } from "./rule-input.ts";

const existing = {
  id: "rule-1",
  operation: "consultar_comunicacoes",
  effect: "allow",
  court: "TJSP",
};
const selectedOperation = {
  operation: "consultar_comunicacoes",
  scope: "court",
};

test("changing only the effect preserves a previously authorized court even when the catalog is unavailable", () => {
  const body = prepareRuleInput({
    rule: existing,
    operation: existing.operation,
    effect: "deny",
    selectedOperation,
    courtScope: "specific",
    court: "TJSP",
    courts: null,
  });
  assert.deepEqual(body, { effect: "deny" });
});

test("a new or changed court requires a currently available supported catalog entry", () => {
  const input = {
    rule: existing,
    operation: existing.operation,
    effect: "deny",
    selectedOperation,
    courtScope: "specific",
    court: "TJRJ",
    courts: null,
  };
  assert.throws(() => prepareRuleInput(input));
  assert.deepEqual(
    prepareRuleInput({
      ...input,
      courts: [{ code: "TJRJ", name: "Rio de Janeiro" }],
    }),
    { effect: "deny", court: "TJRJ" },
  );
});
