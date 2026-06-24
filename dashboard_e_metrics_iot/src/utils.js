/** Erro relativo percentual entre medido e referência. */
export const err = (meas, ref) => ((meas - ref) / ref * 100);

/** Formata número com [d] casas decimais; retorna o valor intacto se não for número. */
export const fmt = (v, d = 2) => (typeof v === "number" ? v.toFixed(d) : v);

/** Formata número com sinal explícito (+/-). */
export const sign = (v) => v >= 0 ? `+${fmt(v)}` : fmt(v);

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
      fp: num("fp"), thd: num("thd"),
      v_esp: num("v_esp"), v_ref: num("v_ref"),
      i_esp: num("i_esp"), i_ref: num("i_ref"),
      p_esp: num("p_esp"), p_ref: num("p_ref"),
      wh_esp: num("wh_esp"), wh_ref: num("wh_ref"),
    };
  });
}
