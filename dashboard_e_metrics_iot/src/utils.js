/** Erro relativo percentual entre medido e referência. */
export const err = (meas, ref) => ((meas - ref) / ref * 100);

/** Formata número com [d] casas decimais; retorna o valor intacto se não for número. */
export const fmt = (v, d = 2) => (typeof v === "number" ? v.toFixed(d) : v);

/** Formata número com sinal explícito (+/-). */
export const sign = (v) => v >= 0 ? `+${fmt(v)}` : fmt(v);

/**
 * Normaliza fator de potência em escala decimal.
 * Aceita valores já em decimal ou em percentual (ex: 98 -> 0.98).
 */
export function normalizePowerFactor(value) {
  if (value == null) return null;
  const number = Number(value);
  if (!Number.isFinite(number)) return null;

  const magnitude = Math.abs(number);
  const normalized = magnitude > 1 && magnitude <= 100 ? magnitude / 100 : magnitude;
  return Math.min(1, normalized);
}

/**
 * Normaliza o tipo de carga informado pelo payload para uma chave canônica.
 */
export function normalizeLoadType(value) {
  const text = String(value ?? "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");

  if (!text) return null;
  if (/(resistiv|ohmic|ohmico)/.test(text)) return "resistive";
  if (/(mista|mixed|mixta|mxt)/.test(text)) return "mixed";
  if (/(capacitiv|leading|adiantad|cap\b)/.test(text)) return "capacitive";
  if (/(indutiv|inductive|lagging|atrasad|ind\b)/.test(text)) return "inductive";
  return null;
}

/**
 * Formata o tipo de carga para exibição na interface.
 */
export function loadTypeLabel(value) {
  const normalized = normalizeLoadType(value);
  if (normalized === "resistive") return "Resistiva";
  if (normalized === "mixed") return "Mista";
  if (normalized === "capacitive") return "Capacitiva";
  if (normalized === "inductive") return "Indutiva";
  return "—";
}

/**
 * Infere o tipo de carga a partir da telemetria disponível.
 * Retorna a melhor classificação possível sem inventar sinal quando os dados
 * do PZEM não permitem distinguir capacitiva de indutiva.
 */
export function inferLoadType(sample, fallbackDirection = null) {
  const explicitLoadType = normalizeLoadType(sample?.loadType);
  if (explicitLoadType) {
    return { type: explicitLoadType, source: "payload", confidence: 1 };
  }

  const reactivePower = Number(sample?.reactivePower);
  if (
    sample?.reactivePowerSource === "payload"
    && Number.isFinite(reactivePower)
    && Math.abs(reactivePower) > 0.05
  ) {
    return {
      type: reactivePower < 0 ? "capacitive" : "inductive",
      source: "signedReactivePower",
      confidence: 0.95,
    };
  }

  const currentAngleDeg = Number(sample?.currentAngleDeg);
  if (Number.isFinite(currentAngleDeg) && Math.abs(currentAngleDeg) > 0.2) {
    return {
      type: currentAngleDeg > 0 ? "capacitive" : "inductive",
      source: "currentAngleDeg",
      confidence: 0.9,
    };
  }

  const pf = normalizePowerFactor(sample?.pf);
  if (pf != null && pf >= 0.98) {
    return { type: "resistive", source: "powerFactor", confidence: 0.8 };
  }

  if (fallbackDirection === "capacitive" || fallbackDirection === "inductive") {
    return { type: fallbackDirection, source: "fallbackDirection", confidence: 0.55 };
  }

  return { type: null, source: "insufficient-data", confidence: 0 };
}

/**
 * Resolve o tipo de carga mais útil para exibição a partir da telemetria.
 */
export function resolveLoadType(sample, fallbackDirection = null) {
  return inferLoadType(sample, fallbackDirection).type;
}

/**
 * Calcula média, desvio padrão e valor absoluto máximo de um array de números.
 * @param {number[]} values
 */
export function computeStats(values) {
  const n = values.length;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const std = Math.sqrt(
    values.map(v => (v - mean) ** 2).reduce((a, b) => a + b, 0) / n,
  );
  const max = Math.max(...values.map(Math.abs));
  return { mean, std, max };
}

/**
 * Formata uma duração em milissegundos para string legível (ex: "2min 05s").
 * @param {number} milliseconds
 */
export function formatDuration(milliseconds) {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours) return `${hours}h ${String(minutes).padStart(2, "0")}min`;
  if (minutes) return `${minutes}min ${String(seconds).padStart(2, "0")}s`;
  return `${seconds}s`;
}

/**
 * Analisa texto CSV da bancada de testes.
 * Formato esperado: load,fp,thd,v_esp,v_ref,i_esp,i_ref,p_esp,p_ref,wh_esp,wh_ref
 * @param {string} csvText
 */
export function parseCsvToData(csvText) {
  const lines = csvText.trim().split(/\r?\n/);
  if (lines.length < 2) {
    throw new Error("CSV precisa ter cabeçalho e ao menos uma linha de dados.");
  }
  const header = lines[0].split(",").map(h => h.trim().toLowerCase());
  const required = ["load", "fp", "thd", "v_esp", "v_ref", "i_esp", "i_ref", "p_esp", "p_ref", "wh_esp", "wh_ref"];
  const missing = required.filter(k => !header.includes(k));
  if (missing.length > 0) {
    throw new Error(`Colunas faltando no CSV: ${missing.join(", ")}`);
  }
  return lines.slice(1).map((line, idx) => {
    const cols = line.split(",").map(c => c.trim());
    const row = {};
    header.forEach((h, i) => { row[h] = cols[i]; });
    const num = (k) => {
      const v = parseFloat(row[k]);
      if (isNaN(v)) throw new Error(`Linha ${idx + 2}: valor inválido em "${k}": "${row[k]}"`);
      return v;
    };
    return {
      load: row["load"] || `Carga ${idx + 1}`,
      fp: normalizePowerFactor(row["fp"]) ?? num("fp"), thd: num("thd"),
      v_esp: num("v_esp"), v_ref: num("v_ref"),
      i_esp: num("i_esp"), i_ref: num("i_ref"),
      p_esp: num("p_esp"), p_ref: num("p_ref"),
      wh_esp: num("wh_esp"), wh_ref: num("wh_ref"),
    };
  });
}
