import test from "node:test";
import assert from "node:assert/strict";
import { metricPresentation, statePresentation } from "./presentation.mjs";

test("zero permanece uma contagem concluída, diferente de ausência de resultado", () => {
  assert.equal(metricPresentation(0).value, "0");
  assert.equal(metricPresentation(null).value, "—");
});

test("máscara não retorna o número protegido nem quando o chamador recebe um valor", () => {
  assert.equal(metricPresentation(824, true).value, "*");
  assert.equal(metricPresentation("*").value, "*");
  assert.equal(metricPresentation(null, true).value, "*");
  assert.equal(metricPresentation(0, true).value, "*");
});

test("contagens positivas usam apresentação numérica sem alterar seu significado", () => {
  assert.equal(metricPresentation(1234).value, "1.234");
});

test("parcial, falha, andamento, indisponibilidade e ausência de trabalho não viram sucesso vazio", () => {
  const states = [
    "succeeded",
    "partial",
    "running",
    "failed",
    "no_work",
    "unavailable",
    "masked",
  ];
  const labels = states.map((state) => statePresentation(state).label);
  assert.equal(new Set(labels).size, states.length);
});

test("um estado futuro não é convertido em um estado conhecido", () => {
  assert.match(statePresentation("novo_estado").label, /novo_estado/);
});
