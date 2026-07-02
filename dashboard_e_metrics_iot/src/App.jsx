import { useEffect, useMemo, useRef, useState } from "react";
import {
  ScatterChart, Scatter, LineChart, Line, AreaChart, Area, BarChart, Bar,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
  ReferenceLine, Brush
} from "recharts";
import {
  connectMqtt,
  publishCommand,
  DEFAULT_MQTT_CONFIG,
} from "./services/mqttService";
import { err, fmt, sign, computeStats, parseCsvToData, loadTypeLabel, normalizeLoadType, normalizePowerFactor, resolveLoadType } from "./utils";

// ─── Paleta de cores (tema instrumento técnico) ───────────────────────────────
const C = {
  bg:       "#121719",
  surface:  "#1a2023",
  border:   "#2b3538",
  text:     "#edf1ef",
  muted:    "#9aa5a4",
  amber:    "#c5a16c",
  cyan:     "#79aeb9",
  green:    "#7eae90",
  red:      "#d17a76",
  purple:   "#a89abc",
};

const MQTT_SETTINGS_KEY = "emetrics.mqtt-settings";
const ALERT_SETTINGS_KEY = "emetrics.alert-settings";
const COMMAND_TOPIC_KEY = "emetrics.cmd-topic";
const DEFAULT_COMMAND_TOPIC = "emetrics/pzem/history/request";
const DEVICE_TIMEOUT_MS = 15000;
const DEFAULT_ALERT_SETTINGS = {
  voltageMin: 200,
  voltageMax: 240,
  energyLimit: 10,
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

// ─── Utilitários (importados de utils.js) ────────────────────────────────────

// Botão de importação CSV para o editor de dados
function CsvImportButton({ onImport }) {
  const [error, setError] = useState(null);
  const inputRef = useRef(null);

  const handleFile = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
      try {
        const rows = parseCsvToData(ev.target.result);
        onImport(rows);
        setError(null);
      } catch (err) {
        setError(err.message);
      }
    };
    reader.readAsText(file);
    e.target.value = "";
  };

  return (
    <div style={{ marginBottom: 10 }}>
      <input ref={inputRef} type="file" accept=".csv,text/csv" onChange={handleFile}
        style={{ display: "none" }} />
      <button onClick={() => inputRef.current.click()} style={{
        background: "none", border: `1px solid ${C.cyan}`, color: C.cyan,
        borderRadius: 6, padding: "7px 18px", cursor: "pointer", fontSize: 12,
        transition: "background 0.15s",
      }}
        onMouseEnter={e => e.currentTarget.style.background = "#79aeb922"}
        onMouseLeave={e => e.currentTarget.style.background = "none"}>
        Importar CSV da bancada
      </button>
      {error && <div style={{ color: C.red, fontSize: 11, marginTop: 6 }}>{error}</div>}
      <span style={{ color: C.muted, fontSize: 10, marginLeft: 12 }}>
        Formato: load,fp,thd,v_esp,v_ref,i_esp,i_ref,p_esp,p_ref,wh_esp,wh_ref
      </span>
    </div>
  );
}

// ─── Componentes de UI ────────────────────────────────────────────────────────
function Card({ title, children, accent, action }) {
  return (
    <div style={{
      background: C.surface, border: `1px solid ${accent || C.border}`,
      borderRadius: 10, padding: "18px 22px", marginBottom: 20, position: "relative",
    }}>
      {title && <div style={{ color: C.muted, fontSize: 11, fontWeight: 700,
        letterSpacing: "0.12em", textTransform: "uppercase", marginBottom: 14,
        paddingRight: action ? 160 : 0 }}>{title}</div>}
      {action && <div className="chart-card-action">{action}</div>}
      {children}
    </div>
  );
}

const EXPORT_REVOKE_DELAY_MS = 60_000;
const BATCH_DOWNLOAD_DELAY_MS = 180;

function wait(ms) {
  return new Promise(resolve => window.setTimeout(resolve, ms));
}

function waitForChartPaint() {
  return new Promise(resolve => {
    const raf = window.requestAnimationFrame || (callback => window.setTimeout(callback, 16));
    raf(() => raf(resolve));
  });
}

function hasRenderableChartSeries(svg) {
  const selectors = [
    ".recharts-line-curve",
    ".recharts-area-area",
    ".recharts-area-curve",
    ".recharts-bar-rectangle",
    ".recharts-scatter-symbol",
    ".recharts-symbols",
    ".recharts-dot",
  ];

  const elements = selectors.flatMap(selector => Array.from(svg.querySelectorAll(selector)));
  return elements.some(element => {
    const style = window.getComputedStyle(element);
    if (style.display === "none" || style.visibility === "hidden" || style.opacity === "0") return false;

    const d = element.getAttribute("d")?.trim();
    if (d && /\d/.test(d) && !/^M\s*0(?:[,.]\s*0)?\s*$/i.test(d)) return true;

    const points = element.getAttribute("points")?.trim();
    if (points && /\d/.test(points)) return true;

    const width = Number(element.getAttribute("width"));
    const height = Number(element.getAttribute("height"));
    if (width > 0 || height > 0) return true;

    try {
      const box = element.getBBox?.();
      return Boolean(box && (box.width > 0 || box.height > 0));
    } catch (_) {
      return false;
    }
  });
}

function renderChartToCanvas(chartElement) {
  const svg = chartElement?.querySelector("svg.recharts-surface");
  if (!svg) return Promise.reject(new Error("Gráfico indisponível para exportação."));
  if (!hasRenderableChartSeries(svg)) return Promise.reject(new Error("Este gráfico ainda não tem pontos suficientes para exportação."));

  const svgRect = svg.getBoundingClientRect();
  if (!svgRect.width || !svgRect.height) return Promise.reject(new Error("Gráfico sem dimensões para exportação."));

  const viewBox = svg.viewBox.baseVal;
  const vbW0 = viewBox.width || svgRect.width;
  const vbH0 = viewBox.height || svgRect.height;
  // Ratio: screen pixel → SVG user unit
  const px2ux = vbW0 / svgRect.width;
  const px2uy = vbH0 / svgRect.height;

  // Temporarily reveal SVG overflow so getBoundingClientRect() returns the
  // actual unclipped positions of elements (e.g. rotated tick labels with
  // angle={-24} that extend below the SVG viewport). getBoundingClientRect()
  // forces a sync layout, so the updated overflow is reflected immediately.
  const savedOverflow = svg.style.overflow;
  svg.style.overflow = "visible";

  let minX = svgRect.left, minY = svgRect.top;
  let maxX = svgRect.right, maxY = svgRect.bottom;
  for (const el of svg.querySelectorAll("*")) {
    try {
      const r = el.getBoundingClientRect();
      if (!r.width && !r.height) continue;
      if (r.left   < minX) minX = r.left;
      if (r.top    < minY) minY = r.top;
      if (r.right  > maxX) maxX = r.right;
      if (r.bottom > maxY) maxY = r.bottom;
    } catch (_) { /* skip */ }
  }

  svg.style.overflow = savedOverflow;

  // Convert screen overflow (px) to SVG user units, then add padding
  const pad = 20;
  const extraL = Math.max(0, svgRect.left  - minX) * px2ux + pad;
  const extraT = Math.max(0, svgRect.top   - minY) * px2uy + pad;
  const extraR = Math.max(0, maxX - svgRect.right)  * px2ux + pad;
  const extraB = Math.max(0, maxY - svgRect.bottom) * px2uy + pad;

  const vbX = viewBox.x - extraL;
  const vbY = viewBox.y - extraT;
  const vbW = vbW0 + extraL + extraR;
  const vbH = vbH0 + extraT + extraB;

  const svgCopy = svg.cloneNode(true);
  svgCopy.setAttribute("xmlns", "http://www.w3.org/2000/svg");
  svgCopy.setAttribute("overflow", "visible");
  svgCopy.setAttribute("viewBox", `${vbX} ${vbY} ${vbW} ${vbH}`);
  svgCopy.setAttribute("width", String(vbW));
  svgCopy.setAttribute("height", String(vbH));
  svgCopy.style.fontFamily = "Inter, Segoe UI, sans-serif";

  const svgBlob = new Blob([new XMLSerializer().serializeToString(svgCopy)], {
    type: "image/svg+xml;charset=utf-8",
  });
  const svgUrl = URL.createObjectURL(svgBlob);

  // Recharts renders the Legend as an HTML div outside the SVG — capture it before async rendering
  const legendItems = Array.from(
    chartElement.querySelectorAll(".recharts-legend-item"),
  ).map((item) => ({
    color: (
      item.querySelector(".recharts-legend-icon")?.getAttribute("fill") ||
      item.querySelector(".recharts-legend-icon")?.getAttribute("stroke") ||
      item.querySelector("[fill]:not([fill='none'])")?.getAttribute("fill") ||
      C.muted
    ),
    label: item.querySelector(".recharts-legend-item-text")?.textContent?.trim() || "",
  }));

  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => {
      const scale = Math.min(window.devicePixelRatio || 1, 2);
      const LEGEND_H = legendItems.length > 0 ? 32 : 0;
      const totalH = vbH + LEGEND_H;

      const canvas = document.createElement("canvas");
      canvas.width = Math.round(vbW * scale);
      canvas.height = Math.round(totalH * scale);
      const ctx = canvas.getContext("2d");
      if (!ctx) { URL.revokeObjectURL(svgUrl); reject(new Error("Canvas indisponível para exportação.")); return; }
      ctx.scale(scale, scale);
      ctx.fillStyle = C.surface;
      ctx.fillRect(0, 0, vbW, totalH);
      ctx.drawImage(image, 0, 0, vbW, vbH);

      if (legendItems.length > 0) {
        const ICON = 10;
        const GAP = 6;
        const ITEM_GAP = 18;
        ctx.font = "12px Inter, Segoe UI, sans-serif";
        const totalWidth = legendItems.reduce(
          (acc, { label }) => acc + ICON + GAP + ctx.measureText(label).width + ITEM_GAP, 0,
        ) - ITEM_GAP;
        let x = (vbW - totalWidth) / 2;
        const y = vbH + (LEGEND_H - ICON) / 2;
        for (const { color, label } of legendItems) {
          ctx.fillStyle = color;
          ctx.fillRect(x, y, ICON, ICON);
          ctx.fillStyle = C.muted;
          ctx.fillText(label, x + ICON + GAP, y + ICON - 1);
          x += ICON + GAP + ctx.measureText(label).width + ITEM_GAP;
        }
      }

      URL.revokeObjectURL(svgUrl);
      resolve({ canvas, scale });
    };
    image.onerror = () => { URL.revokeObjectURL(svgUrl); reject(new Error("Não foi possível preparar o gráfico para exportação.")); };
    image.src = svgUrl;
  });
}

function triggerBlobDownload(blob, fileName) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName;
  document.body.append(a);
  a.click();
  a.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), EXPORT_REVOKE_DELAY_MS);
}

async function downloadChart(chartElement, baseName, format) {
  await waitForChartPaint();
  const base = baseName.replace(/\.\w+$/, "");
  const { canvas } = await renderChartToCanvas(chartElement);

  if (format === "jpeg") {
    return new Promise((resolve, reject) => {
      canvas.toBlob((blob) => {
        if (!blob) { reject(new Error("Não foi possível gerar o JPEG.")); return; }
        triggerBlobDownload(blob, `${base}.jpg`);
        resolve();
      }, "image/jpeg", 0.92);
    });
  }

  if (format === "eps") {
    return new Promise((resolve, reject) => {
      canvas.toBlob(async (jpegBlob) => {
        if (!jpegBlob) { reject(new Error("Não foi possível gerar o EPS.")); return; }
        try {
          const buf = await jpegBlob.arrayBuffer();
          const bytes = new Uint8Array(buf);
          const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
          const w = canvas.width;
          const h = canvas.height;
          const eps = [
            "%!PS-Adobe-3.0 EPSF-3.0",
            `%%BoundingBox: 0 0 ${w} ${h}`,
            `%%HiResBoundingBox: 0 0 ${w} ${h}`,
            "%%LanguageLevel: 3",
            "%%Pages: 1",
            "%%EndComments",
            "%%Page: 1 1",
            "gsave",
            "/DeviceRGB setcolorspace",
            "<<",
            "  /ImageType 1",
            `  /Width ${w}`,
            `  /Height ${h}`,
            "  /BitsPerComponent 8",
            "  /Decode [0 1 0 1 0 1]",
            `  /ImageMatrix [${w} 0 0 ${-h} 0 ${h}]`,
            "  /DataSource currentfile /ASCIIHexDecode filter /DCTDecode filter",
            ">> image",
            hex,
            ">",
            "grestore",
            "showpage",
            "%%EOF",
          ].join("\n");
          triggerBlobDownload(new Blob([eps], { type: "application/postscript" }), `${base}.eps`);
          resolve();
        } catch (_) {
          reject(new Error("Não foi possível gerar o EPS."));
        }
      }, "image/jpeg", 0.92);
    });
  }

  // default: png
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (!blob) { reject(new Error("Não foi possível gerar o PNG.")); return; }
      triggerBlobDownload(blob, `${base}.png`);
      resolve();
    }, "image/png");
  });
}

const EXPORT_FORMATS = [
  { id: "png",  label: "PNG"  },
  { id: "jpeg", label: "JPG"  },
  { id: "eps",  label: "EPS"  },
];

function ChartCard({ title, children, accent, fileName }) {
  const chartRef = useRef(null);
  const [exporting, setExporting] = useState(null);

  const exportChart = async (format) => {
    setExporting(format);
    try {
      await downloadChart(chartRef.current, fileName, format);
    } catch (error) {
      window.alert(error.message || "Não foi possível exportar o gráfico.");
    } finally {
      setExporting(null);
    }
  };

  return (
    <Card
      title={title}
      accent={accent}
      action={
        <div className="chart-export-group">
          {EXPORT_FORMATS.map(({ id, label }) => (
            <button
              key={id}
              className="chart-download-button"
              onClick={() => exportChart(id)}
              disabled={exporting !== null}
              title={"Baixar gráfico em " + label}
              type="button"
            >
              {exporting === id ? "…" : label}
            </button>
          ))}
        </div>
      }
    >
      <div ref={chartRef}>{children}</div>
    </Card>
  );
}

function KPI({ label, value, unit, color, sub }) {
  return (
    <div style={{ textAlign: "center", padding: "10px 6px" }}>
      <div style={{ fontSize: 24, fontWeight: 750, color: color || C.text, fontFamily: "monospace" }}>
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
    <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 8,
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
                        background: C.bg, border: `1px solid ${C.amber}`,
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
                      onMouseEnter={e => e.currentTarget.style.background = C.border}
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

function loadSettings(key, fallback) {
  try {
    const saved = window.localStorage.getItem(key);
    if (!saved) return fallback;

    const merged = { ...fallback, ...JSON.parse(saved) };
    // Migra a configuração vazia criada pelas primeiras versões do painel
    // para o endpoint padrão do broker usado pelo projeto.
    if (fallback.url && !String(merged.url ?? "").trim()) {
      merged.url = fallback.url;
    }
    return merged;
  } catch (_) {
    return fallback;
  }
}

function MetricCard({ label, value, unit, accent = C.text }) {
  return (
    <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: 10, padding: "16px" }}>
      <div style={{ color: C.muted, fontSize: 11, fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase" }}>{label}</div>
      <div style={{ color: accent, fontFamily: "monospace", fontSize: 23, fontWeight: 750, marginTop: 8 }}>
        {value}<span style={{ color: C.muted, fontSize: 13, marginLeft: 5 }}>{unit}</span>
      </div>
    </div>
  );
}

function StatusBadge({ label, tone }) {
  const colors = {
    good: C.green,
    warning: C.amber,
    bad: C.red,
    muted: C.muted,
  };
  const color = colors[tone] || C.muted;
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 7, color, fontSize: 12, fontWeight: 700 }}>
      <span style={{ width: 7, height: 7, borderRadius: "50%", background: color }} />
      {label}
    </span>
  );
}

function SettingsField({ label, type = "text", value, onChange, placeholder, help, min, max, disabled }) {
  return (
    <label style={{ display: "block", color: C.muted, fontSize: 11, fontWeight: 700, letterSpacing: "0.06em", textTransform: "uppercase" }}>
      {label}
      <input
        type={type}
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        min={min}
        max={max}
        disabled={disabled}
        style={{ width: "100%", marginTop: 6, background: C.bg, border: `1px solid ${C.border}`, borderRadius: 6, color: C.text, padding: "9px 10px", outline: "none" }}
      />
      {help && <span style={{ display: "block", color: C.muted, fontSize: 10, fontWeight: 400, letterSpacing: 0, marginTop: 4, textTransform: "none" }}>{help}</span>}
    </label>
  );
}


function LiveChartPlaceholder({ label }) {
  return (
    <div style={{ color: C.muted, display: "grid", minHeight: 240, placeItems: "center", fontSize: 13, textAlign: "center" }}>
      {label}
    </div>
  );
}

function clampNumber(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function normalizeDegrees(value) {
  if (!Number.isFinite(value)) return 0;
  const normalized = ((((value + 180) % 360) + 360) % 360) - 180;
  return normalized === -180 ? 180 : normalized;
}

function phasorPoint(cx, cy, length, angleDeg) {
  const radians = angleDeg * Math.PI / 180;
  return {
    x: cx + Math.cos(radians) * length,
    y: cy - Math.sin(radians) * length,
  };
}

function signedAngle(value) {
  if (!Number.isFinite(value) || Math.abs(value) < 0.05) return "0.0°";
  return `${value > 0 ? "+" : ""}${fmt(value, 1)}°`;
}

function normalizeLoadDirection(value) {
  const text = String(value ?? "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");

  if (!text) return null;
  if (/(capacitiv|leading|adiantad|cap\b)/.test(text)) return "capacitive";
  if (/(indutiv|inductive|lagging|atrasad|ind\b)/.test(text)) return "inductive";
  return null;
}

function directionLabel(direction) {
  if (direction === "capacitive") return "Capacitiva";
  if (direction === "inductive") return "Indutiva";
  return "—";
}

function angleForDirection(magnitude, direction) {
  if (!Number.isFinite(magnitude)) return 0;
  return direction === "capacitive" ? Math.abs(magnitude) : -Math.abs(magnitude);
}

function detectDirectionFromSample(sample) {
  const loadTypeDirection = normalizeLoadDirection(sample?.loadType);
  if (loadTypeDirection) return { direction: loadTypeDirection, source: "loadType" };

  const reactivePower = Number(sample?.reactivePower);
  if (
    sample?.reactivePowerSource === "payload"
    && Number.isFinite(reactivePower)
    && Math.abs(reactivePower) > 0.05
  ) {
    return {
      direction: reactivePower < 0 ? "capacitive" : "inductive",
      source: "signedReactivePower",
    };
  }

  const currentAngleDeg = Number(sample?.currentAngleDeg);
  if (Number.isFinite(currentAngleDeg) && Math.abs(currentAngleDeg) > 0.2) {
    return {
      direction: currentAngleDeg > 0 ? "capacitive" : "inductive",
      source: "currentAngleDeg",
    };
  }

  return { direction: null, source: null };
}

function resolveDirectionFromHistory(telemetry, history = []) {
  const recent = [...history, telemetry].slice(-20);
  let scoreCap = 0;
  let scoreInd = 0;
  let votes = 0;
  let usedSource = null;

  recent.forEach((sample, index) => {
    const { direction, source } = detectDirectionFromSample(sample);
    if (!direction) return;
    const weight = index + 1;
    votes += 1;
    if (!usedSource) usedSource = source;
    if (direction === "capacitive") scoreCap += weight;
    else scoreInd += weight;
  });

  if (!votes) return { direction: null, source: null };

  const scoreDiff = Math.abs(scoreCap - scoreInd);
  const scoreTotal = scoreCap + scoreInd;
  const confidence = scoreTotal > 0 ? scoreDiff / scoreTotal : 0;
  if (confidence < 0.15) return { direction: null, source: null };

  const direction = scoreCap > scoreInd ? "capacitive" : "inductive";
  return {
    direction,
    source: `Histórico recente (${votes} amostras${usedSource ? `, base ${usedSource}` : ""})`,
  };
}

function resolvePhasor(telemetry, history = [], directionMode = "auto") {
  if (!telemetry) return null;

  const voltage = Number(telemetry.voltage);
  const current = Number(telemetry.current);
  if (!Number.isFinite(voltage) || !Number.isFinite(current)) return null;

  const apparentPower = Number.isFinite(telemetry.apparentPower)
    ? telemetry.apparentPower
    : voltage * current;
  const activePower = Number(telemetry.power);
  const pfFromPower = apparentPower > 0 && Number.isFinite(activePower)
    ? normalizePowerFactor(activePower / apparentPower)
    : null;
  const rawPf = normalizePowerFactor(telemetry.pf);
  const pf = rawPf ?? pfFromPower;
  const derivedPhase = pf == null ? null : Math.acos(pf) * 180 / Math.PI;
  const reactivePower = Number.isFinite(telemetry.reactivePower)
    ? telemetry.reactivePower
    : Math.sqrt(Math.max(0, apparentPower ** 2 - activePower ** 2));
  const manualDirection = directionMode === "inductive"
    ? "inductive"
    : directionMode === "capacitive"
      ? "capacitive"
      : null;
  const currentDirection = detectDirectionFromSample({
    loadType: telemetry.loadType,
    reactivePower,
    reactivePowerSource: telemetry.reactivePowerSource,
    currentAngleDeg: telemetry.currentAngleDeg,
  });
  const historyDirection = resolveDirectionFromHistory(telemetry, history);
  const detectedDirection = currentDirection.direction ?? historyDirection.direction;
  const explicitLoadType = normalizeLoadType(telemetry.loadType);
  const loadType = resolveLoadType({
    loadType: explicitLoadType,
    reactivePower,
    currentAngleDeg: telemetry.currentAngleDeg,
    pf,
  }, detectedDirection);
  const direction = manualDirection ?? detectedDirection ?? (loadType === "resistive" || loadType === "mixed" ? null : "inductive");
  const explicitCurrentAngle = Number.isFinite(telemetry.currentAngleDeg)
    ? normalizeDegrees(telemetry.currentAngleDeg)
    : null;
  const phaseAngle = Number.isFinite(telemetry.phaseAngleDeg)
    ? telemetry.phaseAngleDeg
    : null;
  const angleMagnitude = Math.abs(
    explicitCurrentAngle ?? phaseAngle ?? derivedPhase ?? 0,
  );
  const currentAngleDeg = normalizeDegrees(
    manualDirection
      ? angleForDirection(angleMagnitude, manualDirection)
      : explicitCurrentAngle ?? (direction ? angleForDirection(angleMagnitude, direction) : 0),
  );
  const phaseAngleDeg = Math.abs(currentAngleDeg);
  const relation = currentAngleDeg < -0.05
    ? "Corrente em atraso (indutiva)"
    : currentAngleDeg > 0.05
      ? "Corrente adiantada (capacitiva)"
      : "Tensão e corrente em fase";
  const source = manualDirection
    ? "Direção manual"
    : explicitCurrentAngle != null
      ? "Ângulo informado pelo payload"
      : explicitLoadType != null
        ? "Tipo de carga informado pelo payload"
        : currentDirection.source === "signedReactivePower"
          ? "Direção por Q assinado"
          : currentDirection.source === "currentAngleDeg"
            ? "Direção por ângulo da corrente"
            : historyDirection.source ?? "Fallback indutivo pelo FP";

  return {
    voltage,
    current,
    apparentPower,
    activePower,
    reactivePower,
    pf,
    phaseAngleDeg,
    currentAngleDeg,
    direction,
    loadType,
    relation,
    source,
  };
}

function PhasorStat({ label, value, unit, color = C.text, sub }) {
  return (
    <div className="phasor-stat">
      <div className="phasor-stat-label">{label}</div>
      <div className="phasor-stat-value" style={{ color }}>
        {value}<span>{unit}</span>
      </div>
      {sub && <div className="phasor-stat-sub">{sub}</div>}
    </div>
  );
}

function PhasorDiagram({ telemetry, history = [] }) {
  const [directionMode, setDirectionMode] = useState("auto");
  const phasor = useMemo(
    () => resolvePhasor(telemetry, history, directionMode),
    [telemetry, history, directionMode],
  );
  const phasorLoadType = loadTypeLabel(phasor?.loadType);

  if (!phasor) {
    return (
      <Card title="Diagrama fasorial em tempo real" accent={`${C.cyan}44`}>
        <LiveChartPlaceholder label="Aguardando telemetria para desenhar tensão e corrente." />
      </Card>
    );
  }

  const cx = 210;
  const cy = 210;
  const outerRadius = 170;
  const voltageLength = phasor.voltage > 0 ? outerRadius : 0;
  const currentLength = phasor.current > 0 ? 118 : 0;
  const voltageEnd = phasorPoint(cx, cy, voltageLength, 0);
  const currentEnd = phasorPoint(cx, cy, currentLength, phasor.currentAngleDeg);
  const voltageLabel = phasorPoint(cx, cy, voltageLength + 16, 0);
  const currentLabel = phasorPoint(cx, cy, currentLength + 22, phasor.currentAngleDeg);
  const arcRadius = 55;
  const arcStart = phasorPoint(cx, cy, arcRadius, 0);
  const arcEnd = phasorPoint(cx, cy, arcRadius, phasor.currentAngleDeg);
  const arcLabel = phasorPoint(cx, cy, arcRadius + 20, phasor.currentAngleDeg / 2);
  const sweepFlag = phasor.currentAngleDeg < 0 ? 1 : 0;
  const currentTone = phasor.direction === "capacitive" ? "#a35cff" : "#ff9f1c";
  const voltageTone = "#2f6bff";
  const gridTone = "#edf5ff";
  const axisTone = "#f4f8ff";
  const modeOptions = [
    ["auto", "Auto"],
    ["inductive", "Indutiva"],
    ["capacitive", "Capacitiva"],
  ];

  return (
    <Card title="Diagrama fasorial em tempo real" accent={`${C.cyan}44`}>
      <div className="phasor-card-grid">
        <div className="phasor-plot-shell">
          <svg
            className="phasor-svg"
            viewBox="0 0 420 420"
            role="img"
            aria-label={`Diagrama fasorial com tensão em 0 graus e corrente em ${signedAngle(phasor.currentAngleDeg)}`}
          >
            <defs>
              <marker id="phasorVoltageArrow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto" markerUnits="userSpaceOnUse">
                <path d="M 0 0 L 10 5 L 0 10 z" fill={voltageTone} />
              </marker>
              <marker id="phasorCurrentArrow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto" markerUnits="userSpaceOnUse">
                <path d="M 0 0 L 10 5 L 0 10 z" fill={currentTone} />
              </marker>
            </defs>

            <rect x="0" y="0" width="420" height="420" fill="#162238" />
            {[42.5, 85, 127.5, 170].map(radius => (
              <circle key={radius} cx={cx} cy={cy} r={radius} fill="none" stroke={gridTone} strokeOpacity="0.88" strokeWidth="1.2" />
            ))}
            <line x1="20" y1={cy} x2="400" y2={cy} stroke={axisTone} strokeOpacity="0.95" strokeWidth="1.3" />
            <line x1={cx} y1="18" x2={cx} y2="402" stroke={axisTone} strokeOpacity="0.95" strokeWidth="1.3" />

            {phasor.phaseAngleDeg > 0.4 && (
              <>
                <path
                  d={`M ${arcStart.x} ${arcStart.y} A ${arcRadius} ${arcRadius} 0 0 ${sweepFlag} ${arcEnd.x} ${arcEnd.y}`}
                  fill="none"
                  stroke={C.amber}
                  strokeWidth="2.6"
                  strokeLinecap="round"
                />
                <text x={arcLabel.x} y={arcLabel.y} textAnchor="middle" fill={C.amber} fontSize="12" fontWeight="800">
                  {fmt(phasor.phaseAngleDeg, 1)}°
                </text>
              </>
            )}

            <line
              x1={cx}
              y1={cy}
              x2={voltageEnd.x}
              y2={voltageEnd.y}
              stroke={voltageTone}
              strokeWidth="3.4"
              strokeLinecap="round"
              markerEnd="url(#phasorVoltageArrow)"
            />
            <line
              x1={cx}
              y1={cy}
              x2={currentEnd.x}
              y2={currentEnd.y}
              stroke={currentTone}
              strokeWidth="3.4"
              strokeLinecap="round"
              markerEnd="url(#phasorCurrentArrow)"
            />
            <circle cx={cx} cy={cy} r="4" fill="#00d0b6" />
            <text x={Math.min(voltageLabel.x, 348)} y={voltageLabel.y - 8} fill={voltageTone} fontSize="12" fontWeight="800">
              V
            </text>
            <text
              x={currentLabel.x}
              y={currentLabel.y + (phasor.currentAngleDeg < 0 ? 14 : -4)}
              textAnchor={currentLabel.x < cx ? "end" : "start"}
              fill={currentTone}
              fontSize="12"
              fontWeight="800"
            >
              I
            </text>
          </svg>
        </div>

        <div className="phasor-details">
          <div className="phasor-header-row">
            <div>
              <div className="phasor-relation">{phasor.relation}</div>
              <div className="phasor-source">{phasor.source} · tensão usada como referência em 0°.</div>
            </div>
            <div className="phasor-mode-toggle" aria-label="Direção da carga no fasorial">
              {[
                ["auto", "Auto"],
                ["inductive", "Indutiva"],
                ["capacitive", "Capacitiva"],
              ].map(([mode, label]) => (
                <button
                  key={mode}
                  type="button"
                  className={directionMode === mode ? "active" : ""}
                  onClick={() => setDirectionMode(mode)}
                >
                  {label}
                </button>
              ))}
            </div>
          </div>
          <div className="phasor-angle-panel">
            <div>
              <div className="phasor-angle-label">Ângulo da corrente</div>
              <div className="phasor-angle-value">{signedAngle(phasor.currentAngleDeg)}</div>
            </div>
            <div className="phasor-direction-pill" data-direction={phasor.direction}>
              {directionLabel(phasor.direction)}
            </div>
          </div>
          <div className="phasor-stat-grid">
            <PhasorStat label="Fator de potência" value={phasor.pf == null ? "—" : fmt(phasor.pf, 3)} unit="" color={C.green} />
            <PhasorStat label="Tipo de carga" value={phasorLoadType} unit="" color={phasor.loadType === "capacitive" ? C.cyan : phasor.loadType === "inductive" ? C.purple : C.amber} />
            <PhasorStat label="Tensão RMS" value={fmt(phasor.voltage, 2)} unit="V" color={C.cyan} />
            <PhasorStat label="Corrente RMS" value={fmt(phasor.current, 3)} unit="A" color={C.purple} />
            <PhasorStat label="Potência reativa" value={fmt(phasor.reactivePower, 2)} unit="VAr" color={phasor.reactivePower < 0 ? C.purple : C.cyan} />
          </div>
        </div>
      </div>
    </Card>
  );
}
function MonitorDashboard({
  telemetry,
  history,
  connection,
  deviceOnline,
  config,
  alertSettings,
  alerts,
  onConfigChange,
  onAlertSettingsChange,
  onConnect,
  onDisconnect,
  onRequestNotifications,
  onClearHistory,
}) {
  const format = (value, digits = 2) => Number.isFinite(value) ? value.toFixed(digits) : "—";
  const latestMeasurement = telemetry?.measuredAt ?? telemetry?.receivedAt;
  const lastUpdate = latestMeasurement
    ? latestMeasurement.toLocaleTimeString("pt-BR")
    : "Aguardando a primeira leitura";
  const mqttTone = connection.phase === "connected" ? "good" : connection.phase === "connecting" ? "warning" : connection.phase === "error" ? "bad" : "muted";
  const brushProps = { height: 20, stroke: C.border, travellerWidth: 8, fill: C.bg };

  return (
    <>
      <Card title="Estado do monitoramento" accent={connection.phase === "error" ? `${C.red}66` : undefined}>
        <div className="status-row">
          <StatusBadge label={connection.label} tone={mqttTone} />
          <StatusBadge label={deviceOnline ? "ESP32 online" : telemetry ? "ESP32 sem telemetria" : "ESP32 aguardando"} tone={deviceOnline ? "good" : telemetry ? "bad" : "warning"} />
          <button className="secondary-button" onClick={onClearHistory} style={{ marginLeft: "auto" }}>
            Limpar histórico
          </button>
          <span style={{ color: C.muted, fontSize: 12 }}>Última leitura: {lastUpdate}</span>
        </div>
        {connection.message && <div style={{ color: connection.phase === "error" ? C.red : C.muted, fontSize: 12, marginTop: 12 }}>{connection.message}</div>}
        <div className="connection-row" style={{ borderTop: `1px solid ${C.border}`, marginTop: 14, paddingTop: 14 }}>
          <SettingsField label="URL MQTT WebSocket" value={config.url} onChange={event => onConfigChange({ ...config, url: event.target.value })} placeholder="wss://broker.exemplo.com/mqtt" />
          <SettingsField label="Tópico" value={config.topic} onChange={event => onConfigChange({ ...config, topic: event.target.value })} placeholder="emetrics/pzem" />
          <SettingsField label="Usuário" value={config.username} onChange={event => onConfigChange({ ...config, username: event.target.value })} />
          <SettingsField label="Senha" type="password" value={config.password} onChange={event => onConfigChange({ ...config, password: event.target.value })} />
          <div className="connection-actions">
            <button className="primary-button" onClick={onConnect} disabled={connection.phase === "connecting"}>Conectar</button>
            <button className="secondary-button" onClick={onDisconnect}>Desconectar</button>
          </div>
        </div>
      </Card>

      <div className="metric-grid" style={{ marginBottom: 20 }}>
        <MetricCard label="Tensão" value={format(telemetry?.voltage)} unit="V" accent={telemetry && (telemetry.voltage < alertSettings.voltageMin || telemetry.voltage > alertSettings.voltageMax) ? C.red : C.cyan} />
        <MetricCard label="Corrente" value={format(telemetry?.current, 3)} unit="A" accent={C.purple} />
        <MetricCard label="Frequência" value={format(telemetry?.frequency, 2)} unit="Hz" accent={C.cyan} />
        <MetricCard label="Energia acumulada" value={format(telemetry?.energy, 3)} unit="kWh" accent={telemetry && telemetry.energy > alertSettings.energyLimit ? C.red : C.green} />
        <MetricCard label="Temperatura ESP32" value={format(telemetry?.temperature, 1)} unit="°C" accent={C.amber} />
        <MetricCard label="Potência aparente" value={format(telemetry?.apparentPower, 2)} unit="VA" accent={C.cyan} />
        <MetricCard label="Potência ativa" value={format(telemetry?.power, 2)} unit="W" accent={C.amber} />
        <MetricCard label="Potência reativa*" value={format(telemetry?.reactivePower, 2)} unit="VAr" accent={C.purple} />
        <MetricCard label="Fator de potência" value={format(telemetry?.pf, 3)} unit="" accent={C.green} />
        <MetricCard label="Erros CRC" value={telemetry?.crcErrors != null ? String(telemetry.crcErrors) : "—"} unit="" accent={telemetry?.crcErrors > 0 ? C.red : C.green} />
      </div>

      <PhasorDiagram telemetry={telemetry} history={history} />

      <div className="live-chart-grid" style={{ display: "grid", gap: 16 }}>
        <ChartCard title="Tensão — tendência ao vivo" fileName="tendencia_tensao.png">
          {history.length ? (
            <ResponsiveContainer width="100%" height={260}>
              <LineChart data={history} margin={{ top: 8, right: 14, left: -8, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis tick={{ fill: C.cyan, fontSize: 11 }} tickFormatter={v => `${v}V`} />
                <Tooltip content={<TT />} />
                <Line type="monotone" dataKey="voltage" name="Tensão" stroke={C.cyan} strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                <Brush dataKey="time" {...brushProps} />
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <LiveChartPlaceholder label="Aguardando leituras de tensão." />
          )}
        </ChartCard>

        <ChartCard title="Corrente — tendência ao vivo" fileName="tendencia_corrente.png">
          {history.length ? (
            <ResponsiveContainer width="100%" height={260}>
              <LineChart data={history} margin={{ top: 8, right: 14, left: -8, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis tick={{ fill: C.purple, fontSize: 11 }} tickFormatter={v => `${v}A`} />
                <Tooltip content={<TT />} />
                <Line type="monotone" dataKey="current" name="Corrente" stroke={C.purple} strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                <Brush dataKey="time" {...brushProps} />
              </LineChart>
            </ResponsiveContainer>
          ) : <LiveChartPlaceholder label="Aguardando leituras de corrente." />}
        </ChartCard>

        <ChartCard title="Potências elétricas — últimas leituras" fileName="potencias_eletricas.png">
          {history.length ? (
            <ResponsiveContainer width="100%" height={280}>
              <LineChart data={history} margin={{ top: 8, right: 16, left: -8, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis tick={{ fill: C.muted, fontSize: 11 }} />
                <Tooltip content={<TT />} />
                <Legend wrapperStyle={{ fontSize: 12, color: C.muted }} />
                <Line type="monotone" dataKey="power" name="Ativa (W)" stroke={C.amber} strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                <Line type="monotone" dataKey="apparentPower" name="Aparente (VA)" stroke={C.cyan} strokeWidth={2} dot={false} />
                <Line type="monotone" dataKey="reactivePower" name="Reativa* (VAr)" stroke={C.purple} strokeWidth={2} dot={false} />
                <Brush dataKey="time" {...brushProps} />
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <LiveChartPlaceholder label="Aguardando leituras de potência." />
          )}
        </ChartCard>

        <ChartCard title="Fator de potência — tendência ao vivo" fileName="tendencia_fator_potencia.png">
          {history.length ? (
            <ResponsiveContainer width="100%" height={260}>
              <LineChart data={history} margin={{ top: 8, right: 14, left: -8, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis domain={[0, 1.1]} tick={{ fill: C.green, fontSize: 11 }} />
                <Tooltip content={<TT />} />
                <ReferenceLine y={1} stroke={C.border} strokeDasharray="4 4" />
                <Line type="monotone" dataKey="pf" name="Fator de potência" stroke={C.green} strokeWidth={2} dot={false} />
                <Brush dataKey="time" {...brushProps} />
              </LineChart>
            </ResponsiveContainer>
          ) : <LiveChartPlaceholder label="Aguardando leituras de fator de potência." />}
        </ChartCard>

        <ChartCard title="Energia acumulada (kWh)" fileName="energia_acumulada.png">
          {history.length ? (
            <ResponsiveContainer width="100%" height={260}>
              <AreaChart data={history} margin={{ top: 8, right: 16, left: -8, bottom: 0 }}>
                <defs>
                  <linearGradient id="energyFill" x1="0" x2="0" y1="0" y2="1">
                    <stop offset="5%" stopColor={C.green} stopOpacity={0.5} />
                    <stop offset="95%" stopColor={C.green} stopOpacity={0.02} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis tick={{ fill: C.green, fontSize: 11 }} tickFormatter={v => `${v} kWh`} />
                <Tooltip content={<TT />} />
                <Area type="monotone" dataKey="energy" name="Energia" stroke={C.green} strokeWidth={2} dot={false} fill="url(#energyFill)" />
                <Brush dataKey="time" {...brushProps} />
              </AreaChart>
            </ResponsiveContainer>
          ) : <LiveChartPlaceholder label="Aguardando leituras de energia acumulada." />}
        </ChartCard>

        <ChartCard title="Temperatura ESP32 — deriva térmica" fileName="temperatura_esp32.png">
          {history.some(h => h.temperature != null) ? (
            <ResponsiveContainer width="100%" height={220}>
              <LineChart data={history} margin={{ top: 8, right: 14, left: -8, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
                <XAxis dataKey="time" tick={{ fill: C.muted, fontSize: 10 }} minTickGap={28} />
                <YAxis tick={{ fill: C.amber, fontSize: 11 }} tickFormatter={v => `${v}°C`} />
                <Tooltip content={<TT />} />
                <Line type="monotone" dataKey="temperature" name="Temp. (°C)" stroke={C.amber} strokeWidth={2} dot={false} />
                <Brush dataKey="time" {...brushProps} />
              </LineChart>
            </ResponsiveContainer>
          ) : <LiveChartPlaceholder label="Aguardando leituras de temperatura do ESP32." />}
        </ChartCard>
      </div>

      <div style={{ color: C.muted, fontSize: 11, margin: "-6px 0 18px" }}>
        * Q positivo indica carga indutiva e Q negativo indica carga capacitiva quando o payload envia sinal; sem sinal, use o modo do fasorial.
      </div>

      <Card title="Limites de alerta">
        <div className="alert-settings-row">
          <SettingsField label="Tensão mínima" type="number" value={alertSettings.voltageMin} onChange={event => onAlertSettingsChange({ ...alertSettings, voltageMin: Number(event.target.value) })} />
          <SettingsField label="Tensão máxima" type="number" value={alertSettings.voltageMax} onChange={event => onAlertSettingsChange({ ...alertSettings, voltageMax: Number(event.target.value) })} />
          <SettingsField label="Limite de energia (kWh)" type="number" value={alertSettings.energyLimit} onChange={event => onAlertSettingsChange({ ...alertSettings, energyLimit: Number(event.target.value) })} />
          <div className="connection-actions">
            <button className="secondary-button" onClick={onRequestNotifications}>Ativar notificações</button>
          </div>
        </div>
      </Card>

      <Card title={`Alertas recentes${alerts.length ? ` (${alerts.length})` : ""}`} accent={alerts.some(alert => alert.severity === "critical") ? `${C.red}66` : undefined}>
        {alerts.length ? (
          <div style={{ display: "grid", gap: 8 }}>
            {alerts.map(alert => (
              <div key={alert.id} style={{ background: C.bg, borderLeft: `3px solid ${alert.severity === "critical" ? C.red : C.amber}`, borderRadius: 6, padding: "10px 12px" }}>
                <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
                  <span style={{ color: alert.severity === "critical" ? C.red : C.amber, fontWeight: 700, fontSize: 12 }}>{alert.title}</span>
                  <span style={{ color: C.muted, fontSize: 11 }}>{alert.createdAt.toLocaleTimeString("pt-BR")}</span>
                </div>
                <div style={{ color: C.muted, fontSize: 12, marginTop: 4 }}>{alert.message}</div>
              </div>
            ))}
          </div>
        ) : <div style={{ color: C.muted, fontSize: 13 }}>Nenhum alerta desde que este painel foi aberto.</div>}
      </Card>
    </>
  );
}

// ─── Aba de configurações do dispositivo ──────────────────────────────────────
function DeviceSettingsTab({ connectionPhase, commandTopic, onCommandTopicChange, onPublish, deviceConfig }) {
  const [measurementMs, setMeasurementMs] = useState("2000");
  const [sdLogMs, setSdLogMs] = useState("2000");
  const [mqttPublishMs, setMqttPublishMs] = useState("2000");
  const [sdRetentionDays, setSdRetentionDays] = useState("30");
  const [hybridEnabled, setHybridEnabled] = useState(false);
  const [hybridAcquireMs, setHybridAcquireMs] = useState("10000");
  const [hybridTxMs, setHybridTxMs] = useState("3000");
  const [feedback, setFeedback] = useState({});
  const syncedRef = useRef(false);

  useEffect(() => {
    if (!deviceConfig || syncedRef.current) return;
    syncedRef.current = true;
    if (deviceConfig.measurementIntervalMs != null) setMeasurementMs(String(deviceConfig.measurementIntervalMs));
    if (deviceConfig.sdLogIntervalMs != null) setSdLogMs(String(deviceConfig.sdLogIntervalMs));
    if (deviceConfig.mqttPublishIntervalMs != null) setMqttPublishMs(String(deviceConfig.mqttPublishIntervalMs));
    if (deviceConfig.sdRetentionDays != null) setSdRetentionDays(String(deviceConfig.sdRetentionDays));
    if (deviceConfig.hybridWifiEnabled != null) setHybridEnabled(deviceConfig.hybridWifiEnabled);
    if (deviceConfig.hybridAcquireMs != null) setHybridAcquireMs(String(deviceConfig.hybridAcquireMs));
    if (deviceConfig.hybridTxMs != null) setHybridTxMs(String(deviceConfig.hybridTxMs));
  }, [deviceConfig]);

  const isConnected = connectionPhase === "connected";

  const setFeedbackFor = (key, text, ok) => {
    setFeedback(prev => ({ ...prev, [key]: { text, ok } }));
    window.setTimeout(() => setFeedback(prev => ({ ...prev, [key]: null })), 3500);
  };

  const validateIntervalMs = (v) => {
    const n = Number(v);
    return Number.isInteger(n) && n >= 100 && n <= 60000;
  };

  const applyIntervals = () => {
    if (!validateIntervalMs(measurementMs) || !validateIntervalMs(sdLogMs) || !validateIntervalMs(mqttPublishMs)) {
      setFeedbackFor("intervals", "Valores devem estar entre 100 e 60000 ms.", false);
      return;
    }
    try {
      onPublish({ command: "configureIntervals", measurementIntervalMs: Number(measurementMs), sdLogIntervalMs: Number(sdLogMs), mqttPublishIntervalMs: Number(mqttPublishMs) });
      setFeedbackFor("intervals", "Comando enviado.", true);
    } catch (e) {
      setFeedbackFor("intervals", e.message, false);
    }
  };

  const applyStorage = () => {
    const days = Number(sdRetentionDays);
    if (!Number.isInteger(days) || days < 1 || days > 365) {
      setFeedbackFor("storage", "Retenção deve estar entre 1 e 365 dias.", false);
      return;
    }
    try {
      onPublish({ command: "configureStorage", sdRetentionDays: days });
      setFeedbackFor("storage", "Comando enviado.", true);
    } catch (e) {
      setFeedbackFor("storage", e.message, false);
    }
  };

  const applyHybridWifi = () => {
    const acq = Number(hybridAcquireMs);
    const tx = Number(hybridTxMs);
    if (!Number.isFinite(acq) || acq < 0 || !Number.isFinite(tx) || tx < 0) {
      setFeedbackFor("wifi", "Valores de tempo inválidos.", false);
      return;
    }
    try {
      onPublish({ command: "setHybridWifi", enabled: hybridEnabled, acquireMs: acq, txMs: tx });
      setFeedbackFor("wifi", "Comando enviado.", true);
    } catch (e) {
      setFeedbackFor("wifi", e.message, false);
    }
  };

  const FeedbackLine = ({ id }) => feedback[id]
    ? <div style={{ fontSize: 11, marginTop: 10, color: feedback[id].ok ? C.green : C.red }}>{feedback[id].text}</div>
    : null;

  return (
    <>
      {!isConnected && (
        <div style={{ background: `${C.amber}18`, border: `1px solid ${C.amber}55`, borderRadius: 8,
          color: C.amber, fontSize: 12, marginBottom: 20, padding: "10px 14px" }}>
          Conecte ao MQTT na aba <strong>Monitoramento</strong> para enviar comandos ao dispositivo.
        </div>
      )}

      <Card title="Tópico de comandos">
        <SettingsField
          label="Tópico MQTT de comandos"
          value={commandTopic}
          onChange={e => onCommandTopicChange(e.target.value)}
          placeholder={DEFAULT_COMMAND_TOPIC}
          help="Tópico que o ESP32 assina para receber comandos (configurado durante o provisioning)."
        />
      </Card>

      <Card title="Intervalos de telemetria">
        <div className="alert-settings-row">
          <SettingsField label="Medição (ms)" type="number" value={measurementMs}
            onChange={e => setMeasurementMs(e.target.value)} min="100" max="60000"
            help="100 – 60000 ms · cadência do PZEM" />
          <SettingsField label="Gravação no SD (ms)" type="number" value={sdLogMs}
            onChange={e => setSdLogMs(e.target.value)} min="100" max="60000"
            help="100 – 60000 ms · append no cartão SD" />
          <SettingsField label="Publicação MQTT (ms)" type="number" value={mqttPublishMs}
            onChange={e => setMqttPublishMs(e.target.value)} min="100" max="60000"
            help="100 – 60000 ms · envio de telemetria" />
          <div className="connection-actions">
            <button className="primary-button" onClick={applyIntervals} disabled={!isConnected}>Aplicar</button>
          </div>
        </div>
        <FeedbackLine id="intervals" />
      </Card>

      <Card title="Retenção no SD card">
        <div style={{ display: "grid", gap: 12, gridTemplateColumns: "minmax(0,1fr) auto", alignItems: "end" }}>
          <SettingsField label="Dias de retenção" type="number" value={sdRetentionDays}
            onChange={e => setSdRetentionDays(e.target.value)} min="1" max="365"
            help="1 – 365 dias · registros mais antigos são apagados automaticamente" />
          <div className="connection-actions">
            <button className="primary-button" onClick={applyStorage} disabled={!isConnected}>Aplicar</button>
          </div>
        </div>
        <FeedbackLine id="storage" />
      </Card>

      <Card title="Wi-Fi híbrido">
        <label style={{ display: "flex", alignItems: "center", gap: 8, cursor: "pointer",
          color: C.text, fontSize: 13, marginBottom: 14 }}>
          <input type="checkbox" style={{ accentColor: C.cyan }}
            checked={hybridEnabled} onChange={e => setHybridEnabled(e.target.checked)} />
          Habilitar modo híbrido
        </label>
        <div className="settings-pair" style={{
          display: "grid", gap: 12, alignItems: "end",
          opacity: hybridEnabled ? 1 : 0.4,
          pointerEvents: hybridEnabled ? "auto" : "none",
        }}>
          <SettingsField label="Slot de aquisição (ms)" type="number" value={hybridAcquireMs}
            onChange={e => setHybridAcquireMs(e.target.value)} min="0"
            help="Duração com Wi-Fi ativo para ler o PZEM" disabled={!hybridEnabled} />
          <SettingsField label="Slot de transmissão (ms)" type="number" value={hybridTxMs}
            onChange={e => setHybridTxMs(e.target.value)} min="0"
            help="Duração do burst MQTT antes de desligar o Wi-Fi" disabled={!hybridEnabled} />
        </div>
        <div className="connection-actions" style={{ marginTop: 14 }}>
          <button className="primary-button" onClick={applyHybridWifi} disabled={!isConnected}>Aplicar</button>
        </div>
        <FeedbackLine id="wifi" />
      </Card>
    </>
  );
}

// ─── App principal ────────────────────────────────────────────────────────────
export default function App() {
  const [data, setData] = useState(INITIAL_DATA);
  const [tab, setTab] = useState("monitor"); // monitor | dashboard | editor
  const [mqttConfig, setMqttConfig] = useState(() => loadSettings(MQTT_SETTINGS_KEY, DEFAULT_MQTT_CONFIG));
  const [alertSettings, setAlertSettings] = useState(() => loadSettings(ALERT_SETTINGS_KEY, DEFAULT_ALERT_SETTINGS));
  const [commandTopic, setCommandTopic] = useState(() => {
    try { return window.localStorage.getItem(COMMAND_TOPIC_KEY) || DEFAULT_COMMAND_TOPIC; } catch (_) { return DEFAULT_COMMAND_TOPIC; }
  });
  const [connection, setConnection] = useState({ phase: "disconnected", label: "MQTT desconectado", message: "Configure um endpoint WebSocket para iniciar." });
  const [telemetry, setTelemetry] = useState(null);
  const [liveHistory, setLiveHistory] = useState([]);
  const [alerts, setAlerts] = useState([]);
  const [clock, setClock] = useState(Date.now());
  const clientRef = useRef(null);
  const alertSettingsRef = useRef(alertSettings);
  const alertGateRef = useRef({ voltage: false, energy: false, offline: false });

  useEffect(() => {
    alertSettingsRef.current = alertSettings;
    window.localStorage.setItem(ALERT_SETTINGS_KEY, JSON.stringify(alertSettings));
  }, [alertSettings]);

  useEffect(() => {
    try { window.localStorage.setItem(COMMAND_TOPIC_KEY, commandTopic); } catch (_) {}
  }, [commandTopic]);

  function publishDeviceCommand(payload) {
    publishCommand(clientRef.current, commandTopic, payload);
  }

  useEffect(() => {
    const { password, ...safeConfig } = mqttConfig;
    window.localStorage.setItem(MQTT_SETTINGS_KEY, JSON.stringify(safeConfig));
  }, [mqttConfig]);

  useEffect(() => {
    const timer = window.setInterval(() => setClock(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => () => {
    clientRef.current?.end(true);
  }, []);

  const deviceOnline = useMemo(
    () => {
      const measurementTime = telemetry?.measuredAt ?? telemetry?.receivedAt;
      return Boolean(
        telemetry
        && connection.phase === "connected"
        && measurementTime
        && clock - measurementTime.getTime() <= DEVICE_TIMEOUT_MS,
      );
    },
    [clock, connection.phase, telemetry],
  );

  function clearHistory() {
    if (!window.confirm("Limpar histórico? Os valores e gráficos atuais serão apagados.")) return;
    setTelemetry(null);
    setLiveHistory([]);
    setAlerts([]);
    alertGateRef.current = { voltage: false, energy: false, offline: false };
  }

  function appendAlert({ key, title, message, severity }) {
    if (alertGateRef.current[key]) return;
    alertGateRef.current[key] = true;

    const alert = { id: `${key}-${Date.now()}`, title, message, severity, createdAt: new Date() };
    setAlerts(current => [alert, ...current].slice(0, 8));

    if ("Notification" in window && Notification.permission === "granted") {
      new Notification(title, { body: message });
    }
  }

  function clearAlertGate(key) {
    alertGateRef.current[key] = false;
  }

  function evaluateTelemetryAlerts(nextTelemetry) {
    const rules = alertSettingsRef.current;
    const voltageOutOfRange = nextTelemetry.voltage < rules.voltageMin || nextTelemetry.voltage > rules.voltageMax;
    if (voltageOutOfRange) {
      appendAlert({
        key: "voltage",
        title: "Tensão fora da faixa",
        message: `Valor: ${nextTelemetry.voltage.toFixed(2)} V · Faixa: ${rules.voltageMin}–${rules.voltageMax} V`,
        severity: "warning",
      });
    } else {
      clearAlertGate("voltage");
    }

    if (nextTelemetry.energy > rules.energyLimit) {
      appendAlert({
        key: "energy",
        title: "Consumo acima do limite",
        message: `Energia acumulada: ${nextTelemetry.energy.toFixed(3)} kWh · Limite: ${rules.energyLimit} kWh`,
        severity: "critical",
      });
    } else if (nextTelemetry.energy <= rules.energyLimit * 0.95) {
      clearAlertGate("energy");
    }
  }

  function connect() {
    clientRef.current?.removeAllListeners();
    clientRef.current?.end(true);
    setConnection({ phase: "connecting", label: "MQTT conectando", message: "Conectando ao broker e assinando o tópico…" });

    try {
      clientRef.current = connectMqtt(mqttConfig, {
        onConnected: () => setConnection({ phase: "connected", label: "MQTT conectado", message: `Assinando ${mqttConfig.topic.trim()}` }),
        onTelemetry: (nextTelemetry) => {
          setTelemetry(nextTelemetry);
          const measurementTime = nextTelemetry.measuredAt ?? nextTelemetry.receivedAt;
          setLiveHistory(current => [...current, {
            time: measurementTime.toLocaleTimeString("pt-BR"),
            power: nextTelemetry.power,
            apparentPower: nextTelemetry.apparentPower,
            reactivePower: nextTelemetry.reactivePower,
            voltage: nextTelemetry.voltage,
            current: nextTelemetry.current,
            frequency: nextTelemetry.frequency,
            pf: nextTelemetry.pf,
            phaseAngleDeg: nextTelemetry.phaseAngleDeg,
            currentAngleDeg: nextTelemetry.currentAngleDeg,
            loadType: nextTelemetry.loadType,
            reactivePowerSource: nextTelemetry.reactivePowerSource,
            energy: nextTelemetry.energy,
            temperature: nextTelemetry.temperature,
          }].slice(-300));
          clearAlertGate("offline");
          evaluateTelemetryAlerts(nextTelemetry);
        },
        onPayloadError: (error) => setConnection(current => ({ ...current, message: `Payload ignorado: ${error.message}` })),
        onReconnecting: () => setConnection({ phase: "connecting", label: "MQTT reconectando", message: "Tentando restabelecer a conexão…" }),
        onOffline: () => setConnection({ phase: "error", label: "MQTT offline", message: "O broker não está acessível no momento." }),
        onClosed: () => setConnection(current => current.phase === "disconnected" ? current : { phase: "disconnected", label: "MQTT desconectado", message: "Conexão MQTT encerrada." }),
        onError: (error) => setConnection({ phase: "error", label: "Erro MQTT", message: error.message || "Não foi possível conectar ao broker." }),
      });
    } catch (error) {
      setConnection({ phase: "error", label: "Configuração inválida", message: error.message });
    }
  }

  function disconnect() {
    clientRef.current?.removeAllListeners();
    clientRef.current?.end(true);
    clientRef.current = null;
    setConnection({ phase: "disconnected", label: "MQTT desconectado", message: "Monitoramento pausado." });
  }

  function requestNotifications() {
    if (!("Notification" in window)) {
      setConnection(current => ({ ...current, message: "Este navegador não oferece notificações do sistema." }));
      return;
    }

    Notification.requestPermission().then(permission => {
      setConnection(current => ({
        ...current,
        message: permission === "granted" ? "Notificações do sistema ativadas." : "Permissão de notificações não concedida.",
      }));
    });
  }

  useEffect(() => {
    if (!telemetry || connection.phase !== "connected") {
      clearAlertGate("offline");
      return;
    }

    if (!deviceOnline) {
      appendAlert({
        key: "offline",
        title: "ESP32 sem telemetria",
        message: "Nenhuma leitura foi recebida nos últimos 15 segundos.",
        severity: "critical",
      });
    }
  }, [clock, connection.phase, deviceOnline, telemetry]);

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
    { id: "monitor",   label: "Monitoramento" },
    { id: "dashboard", label: "Análise de validação" },
    { id: "editor",    label: "Editar Dados" },
    { id: "settings",  label: "Configurações" },
  ];

  const kpiColor = (v) => Math.abs(v) > 1.5 ? C.red : Math.abs(v) > 0.8 ? C.amber : C.green;

  return (
    <div style={{ background: C.bg, minHeight: "100vh", color: C.text,
      fontFamily: "'Inter', 'Segoe UI', sans-serif", padding: "32px 24px", maxWidth: 1160, margin: "0 auto" }}>

      {/* Header */}
      <div style={{ marginBottom: 24 }}>
        <div style={{ fontSize: 11, color: C.amber, letterSpacing: "0.16em",
          textTransform: "uppercase", fontWeight: 700, marginBottom: 6 }}>
          ESP32 + PZEM-004T
        </div>
        <h1 style={{ fontSize: 26, fontWeight: 800, margin: 0, color: C.text }}>
          {tab === "monitor" ? "Monitoramento de Energia" : tab === "settings" ? "Configurações do Dispositivo" : "Validação do Medidor de Energia"}
        </h1>
        <p style={{ color: C.muted, fontSize: 13, marginTop: 6 }}>
          {tab === "monitor"
            ? "Telemetria MQTT ao vivo · Status do ESP32 · Alertas operacionais"
            : tab === "settings"
            ? "Intervalos de telemetria · Retenção SD · Wi-Fi híbrido"
            : "Comparação com medidor comercial de referência · Análise de erro relativo"}
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
          <CsvImportButton onImport={setData} />
          <DataEditor data={data} onChange={setData} />
        </Card>
      )}

      {tab === "settings" && (
        <DeviceSettingsTab
          connectionPhase={connection.phase}
          commandTopic={commandTopic}
          onCommandTopicChange={setCommandTopic}
          onPublish={publishDeviceCommand}
          deviceConfig={telemetry?.config ?? null}
        />
      )}

      {tab === "monitor" && (
        <MonitorDashboard
          telemetry={telemetry}
          history={liveHistory}
          connection={connection}
          deviceOnline={deviceOnline}
          config={mqttConfig}
          alertSettings={alertSettings}
          alerts={alerts}
          onConfigChange={setMqttConfig}
          onAlertSettingsChange={setAlertSettings}
          onConnect={connect}
          onDisconnect={disconnect}
          onRequestNotifications={requestNotifications}
          onClearHistory={clearHistory}
        />
      )}

      {tab === "dashboard" && (<>

        {/* KPIs */}
        <div className="validation-kpis" style={{ display: "grid", gap: 12, marginBottom: 20 }}>
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
        <ChartCard title="Erro relativo (%) por grandeza e tipo de carga" fileName="erro_por_grandeza.png">
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={barData} margin={{ top: 20, right: 36, left: 16, bottom: 28 }}>
              <CartesianGrid strokeDasharray="3 3" stroke={C.border} />
              <XAxis
                dataKey="load"
                angle={-24}
                height={72}
                interval={0}
                padding={{ left: 12, right: 12 }}
                textAnchor="end"
                tickMargin={12}
                tick={{ fill: C.muted, fontSize: 10 }}
              />
              <YAxis
                width={60}
                tickFormatter={v => `${v}%`}
                tick={{ fill: C.muted, fontSize: 11 }}
              />
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
        </ChartCard>

        <div className="analysis-grid" style={{ display: "grid", gap: 16 }}>

          {/* Erro P vs FP */}
          <ChartCard title="Erro ΔP (%) × Fator de Potência" fileName="erro_potencia_por_fp.png">
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
          </ChartCard>

          {/* Erro P vs THD */}
          <ChartCard title="Erro ΔP (%) × Distorção Harmônica (THD%)" fileName="erro_potencia_por_thd.png">
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
          </ChartCard>

        </div>

        {/* Bland-Altman */}
        <ChartCard title="Gráfico Bland-Altman — Potência Ativa P (W)" fileName="bland_altman_potencia.png">
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
        </ChartCard>

        {/* Diagnóstico */}
        <Card title="Guia de diagnóstico — padrão de erro → causa provável" accent={`${C.amber}44`}>
          <div className="diagnosis-grid" style={{ display: "grid", gap: 10, fontSize: 13 }}>
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
