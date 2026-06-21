import { useState, useCallback } from "react";
import {
  ScatterChart, Scatter, LineChart, Line, BarChart, Bar,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
  ReferenceLine, ErrorBar
} from "recharts";

// ─── Paleta de cores (tema instrumento técnico) ───────────────────────────────
const C = {
  bg:       "#0d1117",
  surface:  "#161b22",
  border:   "#21262d",
  text:     "#e6edf3",
  muted:    "#7d8590",
  amber:    "#e6a817",
  cyan:     "#39d0f0",
  green:    "#3fb950",
  red:      "#f85149",
  purple:   "#bc8cff",
};

// ─── Dados de exemplo (substituir pelos dados reais do ESP32 / medidor) ───────
const INITIAL_DATA = [
  { load: "Resistiva",       fp: 1.00, v_esp: 219.8, v_ref: 220.1, i_esp: 4.52, i_ref: 4.54, p_esp: 993,  p_ref: 998,  wh_esp: 82.7, wh_ref: 83.2, thd: 3  },
  { load: "Indutiva leve",   fp: 0.82, v_esp: 218.9, v_ref: 219.5, i_esp: 2.31, i_ref: 2.29, p_esp: 415,  p_ref: 412,  wh_esp: 34.6, wh_ref: 34.3, thd: 5  },
  { load: "Indutiva pesada", fp: 0.65, v_esp: 217.5, v_ref: 218.2, i_esp: 3.88, i_ref: 3.91, p_esp: 550,  p_ref: 555,  wh_esp: 45.8, wh_ref: 46.3, thd: 6  },
  { load: "LED (chaveada)",  fp: 0.58, v_esp: 219.1, v_ref: 219.8, i_esp: 0.98, i_ref: 0.95, p_esp: 124,  p_ref: 121,  wh_esp: 10.3, wh_ref: 10.1, thd: 42 },
  { load: "Fonte PC",        fp: 0.72, v_esp: 218.4, v_ref: 219.0, i_esp: 1.85, i_ref: 1.82, p_esp: 290,  p_ref: 287,  wh_esp: 24.2, wh_ref: 23.9, thd: 28 },
  { load: "Motor em vazio",  fp: 0.35, v_esp: 217.9, v_ref: 218.5, i_esp: 2.10, i_ref: 2.08, p_esp: 161,  p_ref: 158,  wh_esp: 13.4, wh_ref: 13.2, thd: 8  },
  { load: "Mista",           fp: 0.78, v_esp: 218.7, v_ref: 219.3, i_esp: 3.20, i_ref: 3.18, p_esp: 544,  p_ref: 541,  wh_esp: 45.4, wh_ref: 45.1, thd: 15 },
];

// ─── Utilitários ──────────────────────────────────────────────────────────────
const err = (meas, ref) => ((meas - ref) / ref * 100);
const fmt = (v, d = 2) => (typeof v === "number" ? v.toFixed(d) : v);
const sign = (v) => v >= 0 ? `+${fmt(v)}` : fmt(v);

function computeStats(values) {
  const n = values.length;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const std = Math.sqrt(values.map(v => (v - mean) ** 2).reduce((a, b) => a + b, 0) / n);
  const max = Math.max(...values.map(Math.abs));
  return { mean, std, max };
}

// ─── Componentes de UI ────────────────────────────────────────────────────────
function Card({ title, children, accent }) {
  return (
    <div style={{
      background: C.surface, border: `1px solid ${accent || C.border}`,
      borderRadius: 10, padding: "18px 22px", marginBottom: 20,
    }}>
      {title && <div style={{ color: C.muted, fontSize: 11, fontWeight: 700,
        letterSpacing: "0.12em", textTransform: "uppercase", marginBottom: 14 }}>{title}</div>}
      {children}
    </div>
  );
}

function KPI({ label, value, unit, color, sub }) {
  return (
    <div style={{ textAlign: "center", padding: "10px 6px" }}>
      <div style={{ fontSize: 28, fontWeight: 800, color: color || C.text, fontFamily: "monospace" }}>
        {value}<span style={{ fontSize: 14, color: C.muted, marginLeft: 4 }}>{unit}</span>
      </div>
      <div style={{ fontSize: 12, color: C.muted, marginTop: 4 }}>{label}</div>
      {sub && <div style={{ fontSize: 11, color: C.muted, marginTop: 2 }}>{sub}</div>}
    </div>
  );
}

const TT = ({ active, payload, label }) => {
  if (!active || !payload?.length) return null;
  return (
    <div style={{ background: "#1c2128", border: `1px solid ${C.border}`, borderRadius: 8,
      padding: "10px 14px", fontSize: 13 }}>
      <div style={{ color: C.amber, fontWeight: 700, marginBottom: 6 }}>{label || payload[0]?.payload?.load}</div>
      {payload.map((p, i) => (
        <div key={i} style={{ color: p.color || C.text }}>{p.name}: {fmt(p.value, 2)}</div>
      ))}
    </div>
  );
};

// ─── Tabela de dados brutos ───────────────────────────────────────────────────
function DataTable({ data }) {
  const rows = data.map(d => ({
    ...d,
    errV: err(d.v_esp, d.v_ref),
    errI: err(d.i_esp, d.i_ref),
    errP: err(d.p_esp, d.p_ref),
    errWh: err(d.wh_esp, d.wh_ref),
  }));

  const cols = [
    { key: "load", label: "Carga", w: 140 },
    { key: "fp",   label: "FP",   w: 55,  fmt: v => fmt(v, 2) },
    { key: "thd",  label: "THD%", w: 55,  fmt: v => `${v}%` },
    { key: "errV", label: "ΔV%",  w: 70,  err: true },
    { key: "errI", label: "ΔI%",  w: 70,  err: true },
    { key: "errP", label: "ΔP%",  w: 70,  err: true },
    { key: "errWh",label: "ΔWh%", w: 70,  err: true },
  ];

  const errColor = v => Math.abs(v) > 2 ? C.red : Math.abs(v) > 1 ? C.amber : C.green;

  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
        <thead>
          <tr>
            {cols.map(c => (
              <th key={c.key} style={{ color: C.muted, textAlign: c.key === "load" ? "left" : "right",
                padding: "8px 10px", borderBottom: `1px solid ${C.border}`,
                fontWeight: 600, fontSize: 11, letterSpacing: "0.06em" }}>
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} style={{ borderBottom: `1px solid ${C.border}` }}>
              {cols.map(c => {
                const val = r[c.key];
                const display = c.fmt ? c.fmt(val) : c.err ? sign(val) : val;
                return (
                  <td key={c.key} style={{
                    padding: "9px 10px",
                    textAlign: c.key === "load" ? "left" : "right",
                    color: c.err ? errColor(val) : C.text,
                    fontFamily: c.key === "load" ? "inherit" : "monospace",
                    fontWeight: c.err && Math.abs(val) > 1 ? 700 : 400,
                  }}>{display}</td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ─── Editor de dados ──────────────────────────────────────────────────────────
function DataEditor({ data, onChange }) {
  const [editing, setEditing] = useState(null); // {row, col, value}

  const fields = [
    { key: "load", label: "Carga", type: "text" },
    { key: "fp",   label: "FP",   type: "number" },
    { key: "thd",  label: "THD%", type: "number" },
    { key: "v_esp", label: "V_ESP", type: "number" },
    { key: "v_ref", label: "V_REF", type: "number" },
    { key: "i_esp", label: "I_ESP", type: "number" },
    { key: "i_ref", label: "I_REF", type: "number" },
    { key: "p_esp", label: "P_ESP", type: "number" },
    { key: "p_ref", label: "P_REF", type: "number" },
    { key: "wh_esp", label: "Wh_ESP", type: "number" },
    { key: "wh_ref", label: "Wh_REF", type: "number" },
  ];

  const commit = () => {
    if (!editing) return;
    const newData = data.map((row, i) => i !== editing.row ? row : {
      ...row,
      [editing.col]: editing.type === "number" ? parseFloat(editing.value) : editing.value,
    });
    onChange(newData);
    setEditing(null);
  };

  const addRow = () => onChange([...data, {
    load: "Nova carga", fp: 1.0, thd: 0,
    v_esp: 220, v_ref: 220, i_esp: 1, i_ref: 1,
    p_esp: 220, p_ref: 220, wh_esp: 18.3, wh_ref: 18.3,
  }]);

  const delRow = idx => onChange(data.filter((_, i) => i !== idx));

  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12 }}>
        <thead>
          <tr>
            {fields.map(f => (
              <th key={f.key} style={{ color: C.muted, padding: "6px 8px",
                borderBottom: `1px solid ${C.border}`, fontSize: 10,
                letterSpacing: "0.06em", textAlign: "right",
                ...(f.key === "load" ? { textAlign: "left" } : {}) }}>
                {f.label}
              </th>
            ))}
            <th style={{ color: C.muted, padding: "6px 8px", borderBottom: `1px solid ${C.border}`, fontSize: 10 }}>✕</th>
          </tr>
        </thead>
        <tbody>
          {data.map((row, ri) => (
            <tr key={ri} style={{ borderBottom: `1px solid ${C.border}` }}>
              {fields.map(f => (
                <td key={f.key} style={{ padding: "4px 4px" }}>
                  {editing?.row === ri && editing?.col === f.key ? (
                    <input
                      autoFocus
                      type={f.type}
                      value={editing.value}
                      onChange={e => setEditing({ ...editing, value: e.target.value })}
                      onBlur={commit}
                      onKeyDown={e => e.key === "Enter" && commit()}
                      style={{
                        background: "#0d1117", border: `1px solid ${C.amber}`,
                        color: C.text, borderRadius: 4, padding: "3px 6px",
                        width: f.key === "load" ? 130 : 72, fontSize: 12, outline: "none",
                      }}
                    />
                  ) : (
                    <div
                      onClick={() => setEditing({ row: ri, col: f.key, value: row[f.key], type: f.type })}
                      style={{
                        cursor: "pointer", padding: "4px 6px", borderRadius: 4,
                        textAlign: f.key === "load" ? "left" : "right",
                        color: C.text, fontFamily: f.key === "load" ? "inherit" : "monospace",
                        background: "transparent",
                        transition: "background 0.15s",
                      }}
                      onMouseEnter={e => e.currentTarget.style.background = "#21262d"}
                      onMouseLeave={e => e.currentTarget.style.background = "transparent"}
                    >
                      {fmt(row[f.key], f.key === "load" ? 0 : 2)}
                    </div>
                  )}
                </td>
              ))}
              <td style={{ textAlign: "center" }}>
                <button onClick={() => delRow(ri)}
                  style={{ background: "none", border: "none", color: C.red,
                    cursor: "pointer", fontSize: 14, padding: "4px 8px" }}>✕</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <button onClick={addRow} style={{
        marginTop: 12, background: "none", border: `1px dashed ${C.border}`,
        color: C.muted, borderRadius: 6, padding: "7px 18px", cursor: "pointer",
        fontSize: 12, width: "100%", transition: "border-color 0.15s, color 0.15s",
      }}
        onMouseEnter={e => { e.currentTarget.style.borderColor = C.amber; e.currentTarget.style.color = C.amber; }}
        onMouseLeave={e => { e.currentTarget.style.borderColor = C.border; e.currentTarget.style.color = C.muted; }}>
        + Adicionar carga
      </button>
    </div>
  );
}

// ─── App principal ────────────────────────────────────────────────────────────
export default function App() {
  const [data, setData] = useState(INITIAL_DATA);
  const [tab, setTab] = useState("dashboard"); // dashboard | editor

  const derived = data.map(d => ({
    ...d,
    errV:  err(d.v_esp,  d.v_ref),
    errI:  err(d.i_esp,  d.i_ref),
    errP:  err(d.p_esp,  d.p_ref),
    errWh: err(d.wh_esp, d.wh_ref),
  }));

  const statsP  = computeStats(derived.map(d => d.errP));
  const statsWh = computeStats(derived.map(d => d.errWh));
  const statsV  = computeStats(derived.map(d => d.errV));
  const statsI  = computeStats(derived.map(d => d.errI));

  // Gráfico Bland-Altman (P)
  const baData = derived.map(d => ({
    load: d.load,
    mean: (d.p_esp + d.p_ref) / 2,
    diff: d.p_esp - d.p_ref,
  }));
  const baMean = baData.reduce((a, b) => a + b.diff, 0) / baData.length;
  const baStd  = Math.sqrt(baData.map(d => (d.diff - baMean) ** 2).reduce((a, b) => a + b, 0) / baData.length);

  // Erro P vs FP
  const errFpData = derived.map(d => ({ fp: d.fp, errP: d.errP, thd: d.thd, load: d.load }));

  // Erro P vs THD
  const errThdData = derived.map(d => ({ thd: d.thd, errP: d.errP, load: d.load }));

  // Barras de erro por grandeza
  const barData = derived.map(d => ({
    load: d.load.replace(" ", "\n"),
    ΔV: parseFloat(fmt(d.errV)),
    ΔI: parseFloat(fmt(d.errI)),
    ΔP: parseFloat(fmt(d.errP)),
    ΔWh: parseFloat(fmt(d.errWh)),
  }));

  const tabs = [
    { id: "dashboard", label: "Dashboard" },
    { id: "editor",    label: "Editar Dados" },
  ];

  const kpiColor = (v) => Math.abs(v) > 1.5 ? C.red : Math.abs(v) > 0.8 ? C.amber : C.green;

  return (
    <div style={{ background: C.bg, minHeight: "100vh", color: C.text,
      fontFamily: "'Inter', 'Segoe UI', sans-serif", padding: "24px 20px", maxWidth: 1100, margin: "0 auto" }}>

      {/* Header */}
      <div style={{ marginBottom: 24 }}>
        <div style={{ fontSize: 11, color: C.amber, letterSpacing: "0.16em",
          textTransform: "uppercase", fontWeight: 700, marginBottom: 6 }}>
          ESP32 + PZEM-004T
        </div>
        <h1 style={{ fontSize: 26, fontWeight: 800, margin: 0, color: C.text }}>
          Validação do Medidor de Energia
        </h1>
        <p style={{ color: C.muted, fontSize: 13, marginTop: 6 }}>
          Comparação com medidor comercial de referência · Análise de erro relativo
        </p>
      </div>

      {/* Tabs */}
      <div style={{ display: "flex", gap: 4, marginBottom: 24,
        borderBottom: `1px solid ${C.border}`, paddingBottom: 0 }}>
        {tabs.map(t => (
          <button key={t.id} onClick={() => setTab(t.id)} style={{
            background: "none", border: "none", color: tab === t.id ? C.amber : C.muted,
            fontWeight: tab === t.id ? 700 : 400, fontSize: 14, cursor: "pointer",
            padding: "8px 18px", borderBottom: `2px solid ${tab === t.id ? C.amber : "transparent"}`,
            marginBottom: -1, transition: "color 0.15s",
          }}>{t.label}</button>
        ))}
      </div>

      {tab === "editor" && (
        <Card title="Dados de medição (clique para editar)">
          <DataEditor data={data} onChange={setData} />
        </Card>
      )}

      {tab === "dashboard" && (<>

        {/* KPIs */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12, marginBottom: 20 }}>
          {[
            { label: "Erro médio ΔP", value: sign(statsP.mean), unit: "%", color: kpiColor(statsP.mean), sub: `σ = ${fmt(statsP.std)} %` },
            { label: "Erro máx |ΔP|", value: fmt(statsP.max), unit: "%", color: kpiColor(statsP.max), sub: "pior caso" },
            { label: "Erro médio ΔWh", value: sign(statsWh.mean), unit: "%", color: kpiColor(statsWh.mean), sub: `σ = ${fmt(statsWh.std)} %` },
            { label: "Erro máx |ΔWh|", value: fmt(statsWh.max), unit: "%", color: kpiColor(statsWh.max), sub: "pior caso" },
          ].map((k, i) => (
            <div key={i} style={{ background: C.surface, border: `1px solid ${C.border}`,
              borderRadius: 10, padding: "14px 10px" }}>
              <KPI {...k} />
            </div>
          ))}
        </div>

        {/* Tabela resumo */}
        <Card title="Erros relativos por grandeza e carga">
          <DataTable data={data} />
          <div style={{ display: "flex", gap: 20, marginTop: 14, fontSize: 11, color: C.muted }}>
            <span style={{ color: C.green }}>● |Δ| ≤ 1%</span>
            <span style={{ color: C.amber }}>● 1% &lt; |Δ| ≤ 2%</span>
            <span style={{ color: C.red }}>● |Δ| &gt; 2%</span>
            <span style={{ color: C.muted, marginLeft: "auto" }}>
              ΔP médio: {sign(statsP.mean)}% · ΔV médio: {sign(statsV.mean)}% · ΔI médio: {sign(statsI.mean)}%
            </span>
          </div>
        </Card>

        {/* Erro por grandeza — barras */}
        <Card title="Erro relativo (%) por grandeza e tipo de carga">
          <ResponsiveContainer width="100%" height={240}>
            <BarChart data={barData} margin={{ top: 4, right: 16, left: -10, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
              <XAxis dataKey="load" tick={{ fill: C.muted, fontSize: 10 }} />
              <YAxis tickFormatter={v => `${v}%`} tick={{ fill: C.muted, fontSize: 11 }} />
              <Tooltip content={<TT />} />
              <Legend wrapperStyle={{ fontSize: 12, color: C.muted }} />
              <ReferenceLine y={0} stroke={C.border} />
              <ReferenceLine y={1}  stroke={C.green} strokeDasharray="4 4" strokeOpacity={0.5} />
              <ReferenceLine y={-1} stroke={C.green} strokeDasharray="4 4" strokeOpacity={0.5} />
              <Bar dataKey="ΔV"  fill={C.cyan}   radius={[3,3,0,0]} />
              <Bar dataKey="ΔI"  fill={C.purple} radius={[3,3,0,0]} />
              <Bar dataKey="ΔP"  fill={C.amber}  radius={[3,3,0,0]} />
              <Bar dataKey="ΔWh" fill={C.green}  radius={[3,3,0,0]} />
            </BarChart>
          </ResponsiveContainer>
        </Card>

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>

          {/* Erro P vs FP */}
          <Card title="Erro ΔP (%) × Fator de Potência">
            <ResponsiveContainer width="100%" height={220}>
              <ScatterChart margin={{ top: 4, right: 16, left: -10, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="fp" name="FP" type="number" domain={[0.3, 1.05]}
                  tick={{ fill: C.muted, fontSize: 11 }} label={{ value: "FP", position: "insideBottomRight", fill: C.muted, fontSize: 11 }} />
                <YAxis dataKey="errP" name="ΔP%" tickFormatter={v => `${v}%`}
                  tick={{ fill: C.muted, fontSize: 11 }} />
                <Tooltip content={<TT />} />
                <ReferenceLine y={0} stroke={C.border} />
                <ReferenceLine y={1}  stroke={C.green} strokeDasharray="4 4" strokeOpacity={0.5} />
                <ReferenceLine y={-1} stroke={C.green} strokeDasharray="4 4" strokeOpacity={0.5} />
                <Scatter data={errFpData} fill={C.amber} r={6} />
              </ScatterChart>
            </ResponsiveContainer>
            <div style={{ fontSize: 11, color: C.muted, marginTop: 8 }}>
              Correlação entre FP baixo e erro elevado indica problema de sincronismo de fase entre canais V/I.
            </div>
          </Card>

          {/* Erro P vs THD */}
          <Card title="Erro ΔP (%) × Distorção Harmônica (THD%)">
            <ResponsiveContainer width="100%" height={220}>
              <ScatterChart margin={{ top: 4, right: 16, left: -10, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="thd" name="THD%" type="number"
                  tick={{ fill: C.muted, fontSize: 11 }} label={{ value: "THD (%)", position: "insideBottomRight", fill: C.muted, fontSize: 11 }} />
                <YAxis dataKey="errP" name="ΔP%" tickFormatter={v => `${v}%`}
                  tick={{ fill: C.muted, fontSize: 11 }} />
                <Tooltip content={<TT />} />
                <ReferenceLine y={0} stroke={C.border} />
                <ReferenceLine y={1}  stroke={C.green} strokeDasharray="4 4" strokeOpacity={0.5} />
                <ReferenceLine y={-1} stroke={C.green} strokeDasharray="4 4" strokeOpacity={0.5} />
                <Scatter data={errThdData} fill={C.cyan} r={6} />
              </ScatterChart>
            </ResponsiveContainer>
            <div style={{ fontSize: 11, color: C.muted, marginTop: 8 }}>
              THD elevado em cargas não-lineares pode saturar o ADC ou causar aliasing se fs &lt; 2·fmax.
            </div>
          </Card>

        </div>

        {/* Bland-Altman */}
        <Card title="Gráfico Bland-Altman — Potência Ativa P (W)">
          <ResponsiveContainer width="100%" height={220}>
            <ScatterChart margin={{ top: 4, right: 16, left: -10, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
              <XAxis dataKey="mean" name="Média (W)" type="number"
                tick={{ fill: C.muted, fontSize: 11 }}
                label={{ value: "Média (W)", position: "insideBottomRight", fill: C.muted, fontSize: 11 }} />
              <YAxis dataKey="diff" name="Diferença (W)" tickFormatter={v => `${v}W`}
                tick={{ fill: C.muted, fontSize: 11 }} />
              <Tooltip content={<TT />} />
              <ReferenceLine y={baMean}            stroke={C.amber} strokeWidth={2} label={{ value: `Bias: ${fmt(baMean,1)}W`, fill: C.amber, fontSize: 11, position: "right" }} />
              <ReferenceLine y={baMean + 1.96*baStd} stroke={C.red}   strokeDasharray="5 5" label={{ value: `+1.96σ`, fill: C.red, fontSize: 10, position: "right" }} />
              <ReferenceLine y={baMean - 1.96*baStd} stroke={C.red}   strokeDasharray="5 5" label={{ value: `−1.96σ`, fill: C.red, fontSize: 10, position: "right" }} />
              <ReferenceLine y={0} stroke={C.border} />
              <Scatter data={baData} fill={C.purple} r={6} />
            </ScatterChart>
          </ResponsiveContainer>
          <div style={{ display: "flex", gap: 24, marginTop: 10, fontSize: 12 }}>
            <span style={{ color: C.amber }}>Bias: {fmt(baMean, 2)} W</span>
            <span style={{ color: C.muted }}>±1.96σ: [{fmt(baMean - 1.96*baStd, 2)}, {fmt(baMean + 1.96*baStd, 2)}] W</span>
            <span style={{ color: C.muted, marginLeft: "auto", fontSize: 11 }}>
              Pontos fora do intervalo = outliers a investigar
            </span>
          </div>
        </Card>

        {/* Diagnóstico */}
        <Card title="Guia de diagnóstico — padrão de erro → causa provável" accent={`${C.amber}44`}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, fontSize: 13 }}>
            {[
              { pattern: "ΔV e ΔI altos, ΔP proporcional", cause: "Ganho do ADC ou calibração do sensor de corrente/tensão", color: C.red },
              { pattern: "ΔP alto, ΔV e ΔI baixos", cause: "Falha no cálculo de potência (janela de integração ou sincronismo)", color: C.red },
              { pattern: "Erro alto só em cargas não-lineares (THD > 20%)", cause: "Taxa de amostragem insuficiente ou ausência de filtro anti-aliasing", color: C.amber },
              { pattern: "ΔP correto, mas FP errado", cause: "Defasagem de fase entre canais V e I (delay de hardware)", color: C.amber },
              { pattern: "Deriva crescente em ΔWh ao longo do tempo", cause: "Acúmulo de erro numérico ou perda de amostras (overflow buffer)", color: C.amber },
              { pattern: "Erro aleatório sem padrão claro", cause: "Ruído no ADC, impedância de fonte, ou interferência EMI", color: C.muted },
            ].map((d, i) => (
              <div key={i} style={{ background: C.bg, borderRadius: 8, padding: "12px 14px",
                borderLeft: `3px solid ${d.color}` }}>
                <div style={{ color: d.color, fontWeight: 700, fontSize: 12, marginBottom: 4 }}>{d.pattern}</div>
                <div style={{ color: C.muted, fontSize: 12 }}>{d.cause}</div>
              </div>
            ))}
          </div>
        </Card>

      </>)}
    </div>
  );
}
