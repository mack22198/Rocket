// Draws the GUI tree written by ui-export.luau roughly the way Roblox lays it out (UDim2 positions, anchor
// points, UIScale, UIPadding, list/grid layouts, TextScaled, corners, strokes and gradients).
const params = new URLSearchParams(location.search);
const scenario = params.get("scenario") || "lobby";
const W = 1280, H = 720, INSET = 58;
const root = document.getElementById("root");
if (params.get("bg")) root.style.backgroundImage = `url(${params.get("bg")})`;

const FONTS = {
  FredokaOne: "'DejaVu Sans', sans-serif",
  GothamBlack: "'Liberation Sans', sans-serif",
  GothamBold: "'Liberation Sans', sans-serif",
  GothamMedium: "'Liberation Sans', sans-serif",
  Gotham: "'Liberation Sans', sans-serif",
};
const family = (f) => FONTS[f] || "'Liberation Sans', sans-serif";
const rgba = (c, a = 1) => `rgba(${c.map((v) => Math.round(v * 255)).join(",")},${a})`;

const ctx = document.createElement("canvas").getContext("2d");
function measure(text, size, fam) { ctx.font = `bold ${size}px ${fam}`; return ctx.measureText(text).width; }
function wrap(text, size, fam, maxW) {
  const lines = [];
  for (const para of String(text).split("\n")) {
    let line = "";
    for (const word of para.split(" ")) {
      const test = line ? line + " " + word : word;
      if (!line || measure(test, size, fam) <= maxW) line = test; else { lines.push(line); line = word; }
    }
    lines.push(line);
  }
  return lines;
}
function fit(text, fam, w, h, max) {
  let lo = 1, hi = Math.max(1, Math.floor(max));
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    const lines = wrap(text, mid, fam, w);
    const ok = lines.length * mid <= h + 0.5 && lines.every((l) => measure(l, mid, fam) <= w + 0.5);
    if (ok) lo = mid; else hi = mid - 1;
  }
  return lo;
}

function mods(node) {
  const m = { strokes: [] };
  for (const c of arr(node.children)) {
    switch (c.class) {
      case "UICorner": m.corner = c.radius; break;
      case "UIStroke": if (c.enabled) m.strokes.push(c); break;
      case "UIGradient": if (c.enabled) m.gradient = c; break;
      case "UIPadding": m.padding = c.pad; break;
      case "UIScale": m.scale = c.scale; break;
      case "UIListLayout": m.list = c; break;
      case "UIGridLayout": m.grid = c; break;
      case "UIAspectRatioConstraint": m.aspect = c.ratio; break;
      case "UITextSizeConstraint": m.textMax = c.maxText; break;
    }
  }
  return m;
}
const isGui = (n) => n.pos !== undefined;
// Empty Luau tables arrive as {} rather than [].
const arr = (x) => (Array.isArray(x) ? x : []);

function sizeOf(node, content) {
  let w = node.size[0] * content.w + node.size[1] * content.acc;
  let h = node.size[2] * content.h + node.size[3] * content.acc;
  const m = mods(node);
  if (m.aspect) { if (w / h > m.aspect) w = h * m.aspect; else h = w / m.aspect; }
  const s = m.scale ?? 1;
  return { w: w * s, h: h * s };
}

// Positions for children managed by a UIListLayout / UIGridLayout (relative to the content box).
function layoutChildren(node, content) {
  const m = mods(node);
  const kids = arr(node.children).filter((c) => isGui(c) && c.visible);
  const byOrder = (a, b) => (m.list || m.grid).sort === "LayoutOrder" ? a.order - b.order : a.name.localeCompare(b.name);
  const placed = new Map();
  if (m.list) {
    kids.sort(byOrder);
    const vertical = m.list.fill === "Vertical";
    const pad = m.list.padding[0] * (vertical ? content.h : content.w) + m.list.padding[1] * content.acc;
    const sizes = kids.map((k) => sizeOf(k, content));
    const total = sizes.reduce((t, s) => t + (vertical ? s.h : s.w), 0) + pad * Math.max(0, kids.length - 1);
    let cursor = 0;
    const along = vertical ? m.list.vAlign : m.list.hAlign;
    if (along === "Center") cursor = ((vertical ? content.h : content.w) - total) / 2;
    else if (along === "Bottom" || along === "Right") cursor = (vertical ? content.h : content.w) - total;
    kids.forEach((k, i) => {
      const s = sizes[i];
      let cross = 0;
      const across = vertical ? m.list.hAlign : m.list.vAlign;
      const room = vertical ? content.w - s.w : content.h - s.h;
      if (across === "Center") cross = room / 2; else if (across === "Right" || across === "Bottom") cross = room;
      placed.set(k, vertical ? { x: cross, y: cursor, ...s } : { x: cursor, y: cross, ...s });
      cursor += (vertical ? s.h : s.w) + pad;
    });
  } else if (m.grid) {
    kids.sort(byOrder);
    const cw = m.grid.cellSize[0] * content.w + m.grid.cellSize[1] * content.acc;
    const ch = m.grid.cellSize[2] * content.h + m.grid.cellSize[3] * content.acc;
    const px = m.grid.cellPadding[0] * content.w + m.grid.cellPadding[1] * content.acc;
    const py = m.grid.cellPadding[2] * content.h + m.grid.cellPadding[3] * content.acc;
    const cols = Math.max(1, Math.floor((content.w + px) / (cw + px)));
    const used = Math.min(cols, kids.length) * (cw + px) - px;
    const offsetX = m.grid.hAlign === "Center" ? (content.w - used) / 2 : m.grid.hAlign === "Right" ? content.w - used : 0;
    kids.forEach((k, i) => placed.set(k, { x: offsetX + (i % cols) * (cw + px), y: Math.floor(i / cols) * (ch + py), w: cw, h: ch }));
  }
  return placed;
}

function render(node, parentEl, content, forced) {
  if (!node.visible) return;
  const m = mods(node);
  let x, y, w, h;
  if (forced) ({ x, y, w, h } = forced);
  else {
    ({ w, h } = sizeOf(node, content));
    const px = content.x0 + node.pos[0] * content.w + node.pos[1] * content.acc;
    const py = content.y0 + node.pos[2] * content.h + node.pos[3] * content.acc;
    x = px - node.anchor[0] * w;
    y = py - node.anchor[1] * h;
  }
  const acc = content.acc * (m.scale ?? 1);
  const el = document.createElement("div");
  el.dataset.name = node.name;
  el.style.cssText = `position:absolute;left:${x}px;top:${y}px;width:${w}px;height:${h}px;z-index:${node.z};`;
  if (node.rot) el.style.transform = `rotate(${node.rot}deg)`;
  if (node.clip || node.class === "ScrollingFrame") el.style.overflow = "hidden";
  if (m.corner) el.style.borderRadius = `${m.corner[0] * Math.min(w, h) + m.corner[1] * acc}px`;
  const alpha = 1 - node.bgT;
  if (alpha > 0.001 && node.class !== "TextLabel" || (node.class === "TextLabel" && alpha > 0.001)) {
    if (m.gradient) {
      const alphas = arr(m.gradient.alphas);
      const stops = arr(m.gradient.colors).map((k) => {
        const c = [node.bg[0] * k[1], node.bg[1] * k[2], node.bg[2] * k[3]];
        const t = alphas.length ? alphas.reduce((a, p) => (p[0] <= k[0] ? p[1] : a), alphas[0][1]) : 0;
        return `${rgba(c, alpha * (1 - t))} ${k[0] * 100}%`;
      });
      el.style.background = `linear-gradient(${90 + m.gradient.rotation}deg, ${stops.join(",")})`;
    } else el.style.background = rgba(node.bg, alpha);
  }
  if (node.class === "ViewportFrame") {
    el.style.background = rgba(node.bg, Math.max(alpha, 0.001) === 0.001 ? 0 : alpha);
    const hint = arr(node.children).find((c) => c.class === "Model");
    if (hint) {
      const t = document.createElement("div");
      t.textContent = `[3D: ${hint.name}]`;
      t.style.cssText = "position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:rgba(255,255,255,0.5);font:bold 12px sans-serif;";
      el.appendChild(t);
    }
  }
  const textual = node.text !== undefined;
  for (const s of m.strokes) {
    const color = rgba(s.color, 1 - s.t);
    if (textual && s.mode === "Contextual") el.dataset.textStroke = `${s.thickness * acc}px ${color}`;
    else el.style.boxShadow = `0 0 0 ${s.thickness * acc}px ${color}`;
  }
  const pad = m.padding || [[0, 0], [0, 0], [0, 0], [0, 0]];
  const padT = pad[0][0] * h + pad[0][1] * acc, padB = pad[1][0] * h + pad[1][1] * acc;
  const padL = pad[2][0] * w + pad[2][1] * acc, padR = pad[3][0] * w + pad[3][1] * acc;
  const inner = { x0: padL, y0: padT, w: w - padL - padR, h: h - padT - padB, acc };
  if (textual && node.text !== "") {
    const t = document.createElement("div");
    const fam = family(node.font);
    const max = Math.min(100 * acc, m.textMax ? m.textMax * acc : Infinity);
    const size = node.scaled ? fit(node.text, fam, inner.w, inner.h, max) : node.textSize * acc;
    const justify = { Left: "flex-start", Center: "center", Right: "flex-end" }[node.xAlign] || "center";
    const alignY = { Top: "flex-start", Center: "center", Bottom: "flex-end" }[node.yAlign] || "center";
    t.style.cssText = `position:absolute;left:${padL}px;top:${padT}px;width:${inner.w}px;height:${inner.h}px;display:flex;` +
      `justify-content:${justify};align-items:${alignY};text-align:${node.xAlign.toLowerCase()};font:bold ${size}px ${fam};` +
      `line-height:1;color:${rgba(node.textColor, 1 - node.textT)};white-space:${node.scaled || node.wrapped ? "normal" : "nowrap"};`;
    const strokes = [];
    if (node.strokeT < 1) {
      const c = rgba(node.strokeColor, (1 - node.strokeT) * (1 - node.textT));
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]) strokes.push(`${dx}px ${dy}px 0 ${c}`);
      t.style.textShadow = strokes.join(",");
    }
    if (el.dataset.textStroke) { t.style.webkitTextStroke = el.dataset.textStroke; t.style.paintOrder = "stroke fill"; }
    t.textContent = node.text;
    el.appendChild(t);
  }
  parentEl.appendChild(el);
  const placed = layoutChildren(node, inner);
  for (const child of arr(node.children)) {
    if (!isGui(child)) continue;
    const spot = placed.get(child);
    render(child, el, inner, spot ? { x: inner.x0 + spot.x, y: inner.y0 + spot.y, w: spot.w, h: spot.h } : null);
  }
}

// A stand-in for Roblox's top bar, so we can see what the UI has to stay clear of.
function topBar() {
  for (const [x, label] of [[12, "≡"], [64, "💬"]]) {
    const b = document.createElement("div");
    b.style.cssText = `position:absolute;left:${x}px;top:8px;width:44px;height:44px;border-radius:22px;background:rgba(18,18,21,0.7);color:#fff;font:bold 20px sans-serif;display:flex;align-items:center;justify-content:center;z-index:10000;`;
    b.textContent = label;
    root.appendChild(b);
  }
}

const res = await fetch(params.get("ui") || `ui-${scenario}.json`);
const data = await res.json();
for (const screen of arr(data.screens)) {
  if (!screen.enabled) continue;
  const layer = document.createElement("div");
  const top = screen.ignoreInset ? 0 : INSET;
  layer.style.cssText = `position:absolute;left:0;top:${top}px;width:${W}px;height:${H - top}px;z-index:${screen.displayOrder};`;
  root.appendChild(layer);
  const content = { x0: 0, y0: 0, w: W, h: H - top, acc: 1 };
  for (const child of arr(screen.children)) if (isGui(child)) render(child, layer, content, null);
}
topBar();
await document.fonts.ready;
window.__ready = true;
