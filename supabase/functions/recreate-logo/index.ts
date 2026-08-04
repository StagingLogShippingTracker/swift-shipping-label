/// <reference lib="deno.ns" />
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Vectorizer (WASM build of vtracer, no native deps).
// Docs: https://www.npmjs.com/package/@visioncortex/vtracer
import vtracer from "npm:@visioncortex/vtracer@1.0.0-alpha.3";

// SVG rasterizer (pure WASM resvg build).
// Docs: https://www.npmjs.com/package/@resvg/resvg-wasm
import * as resvg from "npm:@resvg/resvg-wasm@2.6.2";

// Deno-friendly PNG codec — @jsquash/png ships a WASM build.
// (JPEG is optional: most logos are PNG; if a JPEG shows up we still handle
// it via vtracer.convertBuffer as a fallback that skips our bg-strip.)
import * as pngCodec from "npm:@jsquash/png@3.1.1";
import * as jpegCodec from "npm:@jsquash/jpeg@1.6.0";

/* ------------------------------------------------------------------ */
/* Types & helpers                                                    */
/* ------------------------------------------------------------------ */

type ImageBuf = {
  data: Uint8Array; // RGBA8, length = w*h*4
  width: number;
  height: number;
};

interface RecreatePayload {
  svg: string;
  png_base64: string;
  palette_hex: string[];
  section_count: number;
  bg_stripped: boolean;
  source_width: number;
  source_height: number;
  render_width: number;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-swift-recreate",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function base64FromBytes(bytes: Uint8Array): string {
  // btoa can't handle Uint8Array directly; build binary string in chunks.
  let out = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    out += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk) as unknown as number[]);
  }
  return btoa(out);
}

/* ------------------------------------------------------------------ */
/* WASM init                                                           */
/* ------------------------------------------------------------------ */

let resvgReady = false;
async function ensureResvg(): Promise<void> {
  if (resvgReady) return;
  // resvg-wasm exports `initWasm(input)` which accepts either a Response,
  // a Promise<Response>, WebAssembly.Module, or an ArrayBuffer / Uint8Array.
  const wasmUrl = "https://unpkg.com/@resvg/resvg-wasm@2.6.2/index_bg.wasm";
  const res = await fetch(wasmUrl);
  if (!res.ok) throw new Error(`resvg wasm fetch failed: ${res.status}`);
  const buf = new Uint8Array(await res.arrayBuffer());
  await (resvg as unknown as {
    initWasm: (b: BufferSource) => Promise<unknown>;
  }).initWasm(buf);
  resvgReady = true;
}

/* ------------------------------------------------------------------ */
/* Decode input                                                        */
/* ------------------------------------------------------------------ */

async function decodeToRgba(
  bytes: Uint8Array,
  contentType: string,
): Promise<ImageBuf> {
  const ct = contentType.toLowerCase();
  if (ct.includes("image/jpeg") || ct.includes("image/jpg")) {
    const img = await (jpegCodec as unknown as {
      decode: (b: BufferSource) => Promise<ImageData>;
    }).decode(bytes);
    return { data: new Uint8Array(img.data.buffer, img.data.byteOffset, img.data.byteLength), width: img.width, height: img.height };
  }
  // Default: try PNG.
  try {
    const img = await (pngCodec as unknown as {
      decode: (b: BufferSource) => Promise<ImageData>;
    }).decode(bytes);
    return { data: new Uint8Array(img.data.buffer, img.data.byteOffset, img.data.byteLength), width: img.width, height: img.height };
  } catch (_) {
    const img = await (jpegCodec as unknown as {
      decode: (b: BufferSource) => Promise<ImageData>;
    }).decode(bytes);
    return { data: new Uint8Array(img.data.buffer, img.data.byteOffset, img.data.byteLength), width: img.width, height: img.height };
  }
}

/* ------------------------------------------------------------------ */
/* Background strip (ported from tools/logo_vectorizer/customer_recreate.py) */
/* ------------------------------------------------------------------ */

const ALPHA_HAS_HOLES = 32;
const FLOOD_TOLERANCE = 26;

function borderMostlyTransparent(buf: ImageBuf): boolean {
  const { data, width: w, height: h } = buf;
  if (w < 4 || h < 4) return false;
  let count = 0;
  let holes = 0;
  const inc = (a: number) => {
    count++;
    if (a < ALPHA_HAS_HOLES) holes++;
  };
  for (let x = 0; x < w; x++) {
    inc(data[(x) * 4 + 3]);
    inc(data[((h - 1) * w + x) * 4 + 3]);
  }
  for (let y = 1; y < h - 1; y++) {
    inc(data[(y * w) * 4 + 3]);
    inc(data[(y * w + (w - 1)) * 4 + 3]);
  }
  return count > 0 && holes / count >= 0.35;
}

function medianCornerColor(buf: ImageBuf): [number, number, number] | null {
  const { data, width: w, height: h } = buf;
  const corners: Array<[number, number]> = [
    [0, 0],
    [w - 1, 0],
    [0, h - 1],
    [w - 1, h - 1],
  ];
  const rs: number[] = [], gs: number[] = [], bs: number[] = [];
  for (const [x, y] of corners) {
    const i = (y * w + x) * 4;
    rs.push(data[i]);
    gs.push(data[i + 1]);
    bs.push(data[i + 2]);
  }
  rs.sort((a, b) => a - b);
  gs.sort((a, b) => a - b);
  bs.sort((a, b) => a - b);
  const m = 2; // median of 4
  const median: [number, number, number] = [
    Math.round((rs[m - 1] + rs[m]) / 2),
    Math.round((gs[m - 1] + gs[m]) / 2),
    Math.round((bs[m - 1] + bs[m]) / 2),
  ];
  let agree = 0;
  for (let i = 0; i < 4; i++) {
    const dr = Math.abs(rs[i] - median[0]);
    const dg = Math.abs(gs[i] - median[1]);
    const db = Math.abs(bs[i] - median[2]);
    if (Math.max(dr, dg, db) <= FLOOD_TOLERANCE) agree++;
  }
  if (agree < 3) return null;
  return median;
}

function floodFillTransparent(
  buf: ImageBuf,
  target: [number, number, number],
  tol: number,
): number {
  const { data, width: w, height: h } = buf;
  const visited = new Uint8Array(w * h);
  const stack: number[] = [];
  const trySeed = (x: number, y: number): void => {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    const idx = y * w + x;
    if (visited[idx]) return;
    const i = idx * 4;
    if (
      Math.abs(data[i] - target[0]) > tol ||
      Math.abs(data[i + 1] - target[1]) > tol ||
      Math.abs(data[i + 2] - target[2]) > tol
    ) return;
    visited[idx] = 1;
    stack.push(idx);
  };
  trySeed(0, 0);
  trySeed(w - 1, 0);
  trySeed(0, h - 1);
  trySeed(w - 1, h - 1);
  let stripped = 0;
  while (stack.length > 0) {
    const idx = stack.pop()!;
    data[idx * 4 + 3] = 0;
    stripped++;
    const x = idx % w;
    const y = (idx / w) | 0;
    trySeed(x + 1, y);
    trySeed(x - 1, y);
    trySeed(x, y + 1);
    trySeed(x, y - 1);
  }
  // Feather fringe: pixels adjacent to stripped region get alpha *= 3/4.
  if (stripped > 0) {
    const fringe = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const idx = y * w + x;
        if (visited[idx]) continue;
        for (const [dx, dy] of [
          [1, 0], [-1, 0], [0, 1], [0, -1],
        ] as Array<[number, number]>) {
          const nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          if (visited[ny * w + nx]) { fringe[idx] = 1; break; }
        }
      }
    }
    for (let i = 0; i < w * h; i++) {
      if (fringe[i]) data[i * 4 + 3] = Math.floor(data[i * 4 + 3] * 3 / 4);
    }
  }
  return stripped;
}

function luminanceStrip(buf: ImageBuf): number {
  const { data, width: w, height: h } = buf;
  // Only strip when border is dominated by very white OR very black.
  const isWhite = (i: number) =>
    data[i] > 232 && data[i + 1] > 232 && data[i + 2] > 232;
  const isBlack = (i: number) =>
    data[i] < 20 && data[i + 1] < 20 && data[i + 2] < 20;
  let ringN = 0, whiteN = 0, blackN = 0;
  const sample = (i: number) => {
    ringN++;
    if (isWhite(i)) whiteN++;
    if (isBlack(i)) blackN++;
  };
  for (let x = 0; x < w; x++) {
    sample((x) * 4);
    sample(((h - 1) * w + x) * 4);
  }
  for (let y = 1; y < h - 1; y++) {
    sample((y * w) * 4);
    sample((y * w + (w - 1)) * 4);
  }
  const useWhite = whiteN / ringN >= 0.6;
  const useBlack = blackN / ringN >= 0.6;
  if (!useWhite && !useBlack) return 0;
  let stripped = 0;
  for (let i = 0; i < w * h; i++) {
    const off = i * 4;
    if ((useWhite && isWhite(off)) || (useBlack && isBlack(off))) {
      data[off + 3] = 0;
      stripped++;
    }
  }
  return stripped;
}

function stripBackground(buf: ImageBuf): boolean {
  if (borderMostlyTransparent(buf)) return false;
  const total = buf.width * buf.height;
  let stripped = 0;
  const target = medianCornerColor(buf);
  if (target !== null) {
    stripped = floodFillTransparent(buf, target, FLOOD_TOLERANCE);
  }
  // If flood only nibbled at the border, try luminance-based fallback.
  if (stripped / total < 0.05) {
    const lum = luminanceStrip(buf);
    if (lum > stripped) return lum > 0;
  }
  return stripped > 0;
}

/* ------------------------------------------------------------------ */
/* Vector trace + rasterize                                            */
/* ------------------------------------------------------------------ */

interface RecreateOptions {
  maxColors: number;
  renderWidth: number;
  filterSpeckle: number;
  colorPrecision: number;
  pathPrecision: number;
  cornerThreshold: number;
  hierarchical: "stacked" | "cutout";
  mode: "spline" | "polygon" | "pixel";
}

const DEFAULT_OPTS: RecreateOptions = {
  maxColors: 6,
  renderWidth: 3000,
  filterSpeckle: 4,
  colorPrecision: 6,
  pathPrecision: 5,
  cornerThreshold: 60,
  hierarchical: "stacked",
  mode: "spline",
};

function traceSvg(buf: ImageBuf, opts: RecreateOptions): {
  svg: string;
  palette: string[];
  sections: number;
} {
  const convertPixels = (vtracer as unknown as {
    convertPixels: (
      rgba: Uint8Array,
      width: number,
      height: number,
      opts?: Record<string, unknown>,
    ) => string;
  }).convertPixels;

  const svg = convertPixels(buf.data, buf.width, buf.height, {
    mode: opts.mode,
    clustering: "color-cluster",
    hierarchical: opts.hierarchical,
    filterSpeckle: opts.filterSpeckle,
    colorPrecision: opts.colorPrecision,
    pathPrecision: opts.pathPrecision,
    cornerThreshold: opts.cornerThreshold,
    maxColors: opts.maxColors,
  });

  // Parse palette hex + count sections from generated SVG.
  const palette: string[] = [];
  const sectionRe = /fill="(#[0-9a-fA-F]{6})"/g;
  let match: RegExpExecArray | null;
  while ((match = sectionRe.exec(svg)) !== null) {
    const hex = match[1].toUpperCase();
    if (!palette.includes(hex)) palette.push(hex);
  }
  const pathRe = /<path/g;
  let sections = 0;
  while ((pathRe.exec(svg)) !== null) sections++;
  return { svg, palette, sections };
}

async function rasterize(svg: string, renderWidth: number): Promise<Uint8Array> {
  await ensureResvg();
  const R = (resvg as unknown as {
    Resvg: new (
      svgString: string,
      opts?: unknown,
    ) => {
      render(): { asPng(): Uint8Array };
      width: number;
      height: number;
    };
  }).Resvg;
  const inst = new R(svg, {
    fitTo: { mode: "width", value: renderWidth },
    background: "rgba(0,0,0,0)",
    font: { loadSystemFonts: false },
  });
  return inst.render().asPng();
}

/* ------------------------------------------------------------------ */
/* Handler                                                             */
/* ------------------------------------------------------------------ */

async function handleRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  const url = new URL(req.url);
  const q = url.searchParams;
  const opts: RecreateOptions = { ...DEFAULT_OPTS };
  const maxColors = Number(q.get("max_colors") ?? "");
  const renderWidth = Number(q.get("render_width") ?? "");
  if (Number.isFinite(maxColors) && maxColors > 0) opts.maxColors = maxColors;
  if (Number.isFinite(renderWidth) && renderWidth > 100) opts.renderWidth = renderWidth;

  const contentType = req.headers.get("content-type") ?? "application/octet-stream";
  const raw = new Uint8Array(await req.arrayBuffer());
  if (raw.length === 0) {
    return jsonResponse(400, { error: "Empty request body" });
  }
  // Hard cap so we don't burn CPU on huge photos.
  const MAX_BYTES = 6 * 1024 * 1024;
  if (raw.length > MAX_BYTES) {
    return jsonResponse(413, {
      error: `Image too large: ${raw.length} bytes (max ${MAX_BYTES})`,
    });
  }

  let buf: ImageBuf;
  try {
    buf = await decodeToRgba(raw, contentType);
  } catch (e) {
    return jsonResponse(400, {
      error: `Could not decode image (${(e as Error).message})`,
    });
  }

  // Cap tracing resolution — vtracer time scales O(w*h). If input is very
  // large, downscale (with area sampling) before tracing. Output raster is
  // still rendered at opts.renderWidth so print quality stays crisp.
  const TRACE_MAX_SIDE = 1600;
  if (Math.max(buf.width, buf.height) > TRACE_MAX_SIDE) {
    buf = downscaleRgba(buf, TRACE_MAX_SIDE);
  }

  const bgStripped = stripBackground(buf);
  let traced: ReturnType<typeof traceSvg>;
  try {
    traced = traceSvg(buf, opts);
  } catch (e) {
    return jsonResponse(500, {
      error: `Vector trace failed: ${(e as Error).message}`,
    });
  }

  let pngBytes: Uint8Array;
  try {
    pngBytes = await rasterize(traced.svg, opts.renderWidth);
  } catch (e) {
    return jsonResponse(500, {
      error: `SVG rasterize failed: ${(e as Error).message}`,
    });
  }

  const payload: RecreatePayload = {
    svg: traced.svg,
    png_base64: base64FromBytes(pngBytes),
    palette_hex: traced.palette,
    section_count: traced.sections,
    bg_stripped: bgStripped,
    source_width: buf.width,
    source_height: buf.height,
    render_width: opts.renderWidth,
  };
  return jsonResponse(200, payload);
}

/* Area-averaged downscale of an RGBA buffer (max side <= target). */
function downscaleRgba(src: ImageBuf, targetMax: number): ImageBuf {
  const scale = targetMax / Math.max(src.width, src.height);
  const nw = Math.max(1, Math.round(src.width * scale));
  const nh = Math.max(1, Math.round(src.height * scale));
  const out = new Uint8Array(nw * nh * 4);
  const sxRatio = src.width / nw;
  const syRatio = src.height / nh;
  for (let y = 0; y < nh; y++) {
    const y0 = Math.floor(y * syRatio);
    const y1 = Math.max(y0 + 1, Math.floor((y + 1) * syRatio));
    for (let x = 0; x < nw; x++) {
      const x0 = Math.floor(x * sxRatio);
      const x1 = Math.max(x0 + 1, Math.floor((x + 1) * sxRatio));
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      for (let sy = y0; sy < y1 && sy < src.height; sy++) {
        for (let sx = x0; sx < x1 && sx < src.width; sx++) {
          const i = (sy * src.width + sx) * 4;
          r += src.data[i];
          g += src.data[i + 1];
          b += src.data[i + 2];
          a += src.data[i + 3];
          n++;
        }
      }
      const oi = (y * nw + x) * 4;
      out[oi] = Math.round(r / n);
      out[oi + 1] = Math.round(g / n);
      out[oi + 2] = Math.round(b / n);
      out[oi + 3] = Math.round(a / n);
    }
  }
  return { data: out, width: nw, height: nh };
}

Deno.serve(async (req: Request) => {
  try {
    return await handleRequest(req);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[recreate-logo] unhandled:", msg);
    return jsonResponse(500, { error: msg });
  }
});
