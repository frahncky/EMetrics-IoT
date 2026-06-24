import assert from "node:assert/strict";
import test from "node:test";
import {
  err, fmt, sign, computeStats, formatDuration, parseCsvToData,
} from "./utils.js";

// ─── err / fmt / sign ────────────────────────────────────────────────────────

test("err calcula erro relativo percentual corretamente", () => {
  assert.equal(err(110, 100), 10);
  assert.equal(err(95, 100), -5);
});

test("fmt formata número com casas decimais", () => {
  assert.equal(fmt(3.14159, 2), "3.14");
  assert.equal(fmt(1, 0), "1");
  assert.equal(fmt("texto"), "texto");
});

test("sign adiciona sinal explícito", () => {
  assert.equal(sign(1.5), "+1.50");
  assert.equal(sign(-2.3), "-2.30");
  assert.equal(sign(0), "+0.00");
});

// ─── computeStats ─────────────────────────────────────────────────────────────

test("computeStats calcula média, std e max corretamente", () => {
  const { mean, std, max } = computeStats([2, -4, 6]);
  assert.ok(Math.abs(mean - 4 / 3) < 1e-9, "média incorreta");
  assert.ok(std > 0, "std deve ser positivo");
  assert.equal(max, 6);
});

test("computeStats com um único valor retorna std zero", () => {
  const { mean, std, max } = computeStats([5]);
  assert.equal(mean, 5);
  assert.equal(std, 0);
  assert.equal(max, 5);
});

// ─── formatDuration ──────────────────────────────────────────────────────────

test("formatDuration formata segundos simples", () => {
  assert.equal(formatDuration(5000), "5s");
});

test("formatDuration formata minutos e segundos", () => {
  assert.equal(formatDuration(125000), "2min 05s");
});

test("formatDuration formata horas", () => {
  assert.equal(formatDuration(3700000), "1h 01min");
});

test("formatDuration retorna 0s para valor negativo", () => {
  assert.equal(formatDuration(-1000), "0s");
});

// ─── parseCsvToData ───────────────────────────────────────────────────────────

const VALID_CSV =
  "load,fp,thd,v_esp,v_ref,i_esp,i_ref,p_esp,p_ref,wh_esp,wh_ref\n" +
  "Resistiva,1.00,3,219.8,220.1,4.52,4.54,993,998,82.7,83.2";

test("parseCsvToData lê CSV válido corretamente", () => {
  const rows = parseCsvToData(VALID_CSV);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].load, "Resistiva");
  assert.equal(rows[0].fp, 1.0);
  assert.equal(rows[0].v_esp, 219.8);
});

test("parseCsvToData lança erro quando CSV não tem dados", () => {
  assert.throws(
    () => parseCsvToData("load,fp,thd,v_esp,v_ref,i_esp,i_ref,p_esp,p_ref,wh_esp,wh_ref"),
    /precisa ter cabeçalho/,
  );
});

test("parseCsvToData lança erro quando coluna obrigatória está ausente", () => {
  assert.throws(
    () => parseCsvToData("load,fp\nResistiva,1.0"),
    /Colunas faltando/,
  );
});

test("parseCsvToData lança erro para valor não numérico", () => {
  const bad =
    "load,fp,thd,v_esp,v_ref,i_esp,i_ref,p_esp,p_ref,wh_esp,wh_ref\n" +
    "Resistiva,INVALIDO,3,219.8,220.1,4.52,4.54,993,998,82.7,83.2";
  assert.throws(() => parseCsvToData(bad), /valor inválido/);
});
