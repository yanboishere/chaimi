// gen-icons.mjs — 柴米手绘图标生成器
// 读取 catalog.json / recipes.json,用 rough.js 生成手绘涂鸦 SVG,再用 resvg 渲染 PNG,
// 写入 Chaimi/Assets.xcassets 的 imageset。运行:node tools/gen-icons.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import rough from "roughjs/bundled/rough.esm.js";
import { Resvg } from "@resvg/resvg-js";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "..");
const catalog = JSON.parse(fs.readFileSync(path.join(root, "Chaimi/Resources/catalog.json"), "utf8"));
const recipes = JSON.parse(fs.readFileSync(path.join(root, "Chaimi/Resources/recipes.json"), "utf8"));
const xcassets = path.join(root, "Chaimi/Assets.xcassets");
const fontFile = path.join(root, "Chaimi/Fonts/ZCOOLKuaiLe-Regular.ttf");

const INK = "#4a3f35";
const CREAM = "#f6efdd";

function hashSeed(s) { let h = 2166136261; for (const ch of s) { h ^= ch.codePointAt(0); h = Math.imul(h, 16777619); } return (h >>> 0) % 2 ** 31 || 7; }

function makeGen(seed) {
  return { g: rough.generator(), seed, n: 0 };
}
function opt(G, fill, extra = {}) {
  G.n += 1;
  return {
    stroke: INK, strokeWidth: 3.4, roughness: 1.5, bowing: 1.2,
    fill, fillStyle: "hachure", fillWeight: 2.2, hachureGap: 7.5,
    hachureAngle: -41 + (G.n * 23) % 50, seed: G.seed + G.n * 17,
    ...extra,
  };
}
function solid(G, fill, extra = {}) { return opt(G, fill, { fillStyle: "solid", ...extra }); }

// —— 基础绘制积木 ————————————————————————————————————————————
class Pic {
  constructor(id) { this.G = makeGen(hashSeed(id)); this.parts = []; this.raw = []; }
  push(drawable) { this.parts.push(drawable); return this; }
  ellipse(x, y, w, h, fill, extra) { return this.push(this.G.g.ellipse(x, y, w, h, opt(this.G, fill, extra))); }
  circle(x, y, d, fill, extra) { return this.push(this.G.g.circle(x, y, d, opt(this.G, fill, extra))); }
  rect(x, y, w, h, fill, extra) { return this.push(this.G.g.rectangle(x, y, w, h, opt(this.G, fill, extra))); }
  poly(pts, fill, extra) { return this.push(this.G.g.polygon(pts, opt(this.G, fill, extra))); }
  path(d, fill, extra) { return this.push(this.G.g.path(d, opt(this.G, fill, extra))); }
  line(x1, y1, x2, y2, extra) { return this.push(this.G.g.line(x1, y1, x2, y2, opt(this.G, undefined, { strokeWidth: 3, ...extra }))); }
  curve(pts, extra) { return this.push(this.G.g.curve(pts, opt(this.G, undefined, { strokeWidth: 3, ...extra }))); }
  arc(x, y, w, h, start, stop, closed, fill, extra) { return this.push(this.G.g.arc(x, y, w, h, start, stop, closed, opt(this.G, fill, extra))); }
  dot(x, y, r, color) { return this.push(this.G.g.circle(x, y, r * 2, solid(this.G, color || INK, { strokeWidth: 1.6 }))); }
  text(str, x, y, size, { color = INK, rotate = -3, anchor = "middle" } = {}) {
    this.raw.push(`<text x="${x}" y="${y}" font-family="ZCOOL KuaiLe" font-size="${size}" fill="${color}" text-anchor="${anchor}" transform="rotate(${rotate} ${x} ${y})">${str}</text>`);
    return this;
  }
  svg(size = 256) {
    const body = this.parts.map((dr) => this.G.g.toPaths(dr).map((p) =>
      `<path d="${p.d}" stroke="${p.stroke}" stroke-width="${p.strokeWidth}" fill="${p.fill || "none"}" stroke-linecap="round" stroke-linejoin="round"/>`
    ).join("")).join("");
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 256 256">${body}${this.raw.join("")}</svg>`;
  }
}

const leafD = (x, y, w, h, a) => { // 一片叶子的贝塞尔轮廓,a=旋转角度
  const r = (a * Math.PI) / 180, cos = Math.cos(r), sin = Math.sin(r);
  const P = (px, py) => `${(x + px * cos - py * sin).toFixed(1)} ${(y + px * sin + py * cos).toFixed(1)}`;
  return `M ${P(0, 0)} C ${P(w * 0.55, -h * 0.45)} ${P(w * 0.55, -h)} ${P(0, -h * 1.25)} C ${P(-w * 0.55, -h)} ${P(-w * 0.55, -h * 0.45)} ${P(0, 0)} Z`;
};

function glyphSize(g) { return Math.max(22, Math.min(46, Math.floor(132 / g.length))); }

// —— 模板 ————————————————————————————————————————————————————
const T = {
  cabbage(p, ic) {
    p.ellipse(128, 142, 158, 136, ic.c);
    p.path(`M 60 150 C 78 96 118 76 128 70 C 100 96 92 128 94 166`, undefined, { fill: undefined, strokeWidth: 3 });
    p.path(`M 196 150 C 182 100 150 80 128 70 C 158 98 164 130 160 168`, undefined, { fill: undefined, strokeWidth: 3 });
    p.path(leafD(128, 212, 36, 60, 180), ic.c2, { hachureGap: 6 });
  },
  bokchoy(p, ic) {
    p.path(`M 100 210 C 86 170 88 130 96 96 C 104 126 104 140 112 170 L 128 208 Z`, ic.c2);
    p.path(`M 156 210 C 170 170 168 130 160 96 C 152 126 152 140 144 170 L 128 208 Z`, ic.c2);
    p.path(leafD(100, 104, 30, 42, -18), ic.c);
    p.path(leafD(156, 104, 30, 42, 18), ic.c);
    p.path(leafD(128, 96, 34, 48, 0), ic.c);
    p.path(`M 104 210 C 112 222 144 222 152 210 C 144 200 112 200 104 210 Z`, ic.c2);
  },
  leafy(p, ic) {
    for (const [dx, a, h, c] of [[-34, -26, 58, ic.c2], [34, 26, 58, ic.c2], [-16, -12, 70, ic.c], [16, 12, 70, ic.c], [0, 0, 78, ic.c]]) {
      p.path(leafD(128 + dx, 190, 24, h, a), c, { hachureGap: 6 });
    }
    p.rect(108, 190, 40, 22, "#e0b35a", { fillStyle: "hachure", hachureGap: 5 });
    p.line(104, 224, 118, 242); p.line(128, 226, 128, 246); p.line(152, 224, 138, 242);
  },
  scallion(p, ic) {
    for (const [x0, lean] of [[104, -8], [128, 0], [152, 8]]) {
      p.path(`M ${x0 - 8} 150 L ${x0 - 5 + lean} 52 L ${x0 + 5 + lean} 52 L ${x0 + 8} 150 Z`, ic.c, { hachureGap: 5.5 });
      p.path(`M ${x0 - 8} 150 L ${x0 - 7} 218 L ${x0 + 7} 218 L ${x0 + 8} 150 Z`, ic.c2, { fillStyle: "solid" });
      for (const r of [-6, 0, 6]) p.line(x0 + r * 0.7, 222, x0 + r, 238, { strokeWidth: 2.2 });
    }
  },
  root(p, ic) {
    const straight = ic.straight;
    const d = straight
      ? `M 112 70 C 100 120 102 180 120 226 C 128 238 132 238 138 226 C 152 178 150 118 142 70 Z`
      : `M 100 78 C 86 120 96 178 122 222 C 128 232 132 230 136 220 C 158 170 162 112 152 76 Z`;
    p.path(d, ic.c, { hachureGap: 6.5 });
    for (const y of [110, 142, 174]) p.line(straight ? 112 : 106, y, straight ? 142 : 150, y + 6, { strokeWidth: 2.4 });
    if (ic.straight) { for (let i = 0; i < 7; i++) p.dot(114 + (i * 37) % 26, 96 + i * 19, 2.2, ic.c2); }
    else { p.path(leafD(114, 70, 16, 34, -24), ic.c2); p.path(leafD(136, 68, 16, 38, 14), ic.c2); p.path(leafD(125, 66, 14, 30, -4), ic.c2); }
  },
  tuber(p, ic) {
    const d = ic.taper
      ? `M 70 148 C 76 108 112 92 150 102 C 186 112 196 140 186 158 C 172 182 118 190 92 176 C 74 166 66 160 70 148 Z`
      : `M 72 140 C 72 104 110 86 146 94 C 184 102 196 130 188 158 C 178 188 124 196 94 180 C 76 170 72 158 72 140 Z`;
    p.path(d, ic.c, { hachureGap: 7 });
    if (ic.rings) { p.arc(130, 142, 150, 110, Math.PI * 1.15, Math.PI * 1.85, false); p.arc(130, 150, 110, 80, Math.PI * 1.15, Math.PI * 1.8, false); }
    else for (let i = 0; i < 6; i++) p.dot(96 + (i * 53) % 110, 118 + (i * 31) % 52, 2.4);
  },
  bulb(p, ic) {
    p.path(`M 128 60 C 118 78 92 86 84 118 C 76 152 96 186 128 188 C 160 186 180 152 172 118 C 164 86 138 78 128 60 Z`, ic.c);
    p.path(`M 104 92 C 96 120 98 156 112 182`, undefined, { strokeWidth: 2.6 });
    p.path(`M 152 92 C 160 120 158 156 144 182`, undefined, { strokeWidth: 2.6 });
    p.line(128, 66, 128, 184, { strokeWidth: 2.6 });
    p.path(`M 120 60 C 122 46 134 44 136 58 C 132 54 124 54 120 60 Z`, ic.c2);
    p.line(112, 196, 120, 210, { strokeWidth: 2.2 }); p.line(128, 198, 128, 214, { strokeWidth: 2.2 }); p.line(144, 196, 136, 210, { strokeWidth: 2.2 });
  },
  ginger(p, ic) {
    p.path(`M 70 150 C 60 128 78 112 98 120 C 102 100 128 94 140 108 C 150 92 176 96 180 114 C 198 118 200 142 186 152 C 192 170 174 184 158 176 C 150 190 126 190 118 176 C 96 186 76 172 70 150 Z`, ic.c, { hachureGap: 6.5 });
    p.dot(104, 140, 2.6, ic.c2); p.dot(140, 128, 2.6, ic.c2); p.dot(162, 150, 2.6, ic.c2); p.dot(126, 160, 2.6, ic.c2);
  },
  tomato(p, ic) {
    p.circle(128, 144, 148, ic.c, { hachureGap: 6.5 });
    for (const a of [-50, -10, 30, 70, 110]) p.path(leafD(128, 78, 11, 24, a + 90), ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
    p.line(128, 80, 128, 60, { strokeWidth: 3.4 });
    p.arc(100, 120, 60, 50, Math.PI, Math.PI * 1.5, false, undefined, { strokeWidth: 2.4 });
  },
  pepperbell(p, ic) {
    p.path(`M 92 92 C 72 108 70 160 86 184 C 96 200 116 204 128 198 C 140 204 160 200 170 184 C 186 160 184 108 164 92 C 152 82 104 82 92 92 Z`, ic.c, { hachureGap: 6 });
    p.line(108, 196, 108, 170, { strokeWidth: 2.4 }); p.line(148, 196, 148, 170, { strokeWidth: 2.4 });
    p.path(`M 118 86 C 118 70 138 70 138 86`, ic.c2, { fill: undefined, strokeWidth: 4 });
  },
  pepperlong(p, ic) {
    if (ic.small) {
      p.path(`M 92 110 C 120 104 158 118 176 146 C 182 156 174 164 164 158 C 138 144 108 128 90 120 Z`, ic.c);
      p.path(`M 74 170 C 104 162 144 172 164 198 C 170 208 162 216 152 210 C 128 198 96 184 72 180 Z`, ic.c2 || ic.c);
      p.path(`M 92 110 C 84 100 72 102 70 112`, undefined, { strokeWidth: 3 });
      p.path(`M 74 170 C 64 162 54 166 52 176`, undefined, { strokeWidth: 3 });
    } else {
      p.path(`M 96 74 C 86 120 92 176 122 208 C 132 218 142 212 138 198 C 122 158 116 112 120 76 Z`, ic.c, { hachureGap: 5.5 });
      p.path(`M 98 72 C 92 58 108 50 116 62 C 118 68 116 72 118 76`, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
    }
  },
  gourd(p, ic) {
    const L = ic.len || 1;
    const top = 128 - 86 * L, bot = 128 + 86 * L;
    p.path(`M 112 ${top + 14} C 96 ${top + 50} 98 ${bot - 60} 114 ${bot - 12} C 122 ${bot + 2} 136 ${bot + 2} 142 ${bot - 14} C 156 ${bot - 64} 156 ${top + 54} 142 ${top + 12} C 134 ${top - 2} 118 ${top} 112 ${top + 14} Z`, ic.c, { hachureGap: 6 });
    p.path(`M 124 ${top + 8} C 124 ${top - 8} 136 ${top - 10} 138 ${top + 2}`, ic.c2, { fill: undefined, strokeWidth: 3.6 });
    if (ic.bumps) for (let i = 0; i < 9; i++) p.dot(114 + (i * 29) % 30, top + 36 + i * (150 * L / 9), 1.9);
    else { p.line(120, top + 34, 118, bot - 34, { strokeWidth: 2 }); p.line(138, top + 34, 140, bot - 34, { strokeWidth: 2 }); }
  },
  melon(p, ic) {
    p.circle(128, 136, 164, ic.c, { hachureGap: 6.5 });
    if (ic.stripes) for (const dx of [-52, -18, 16, 50]) p.path(`M ${128 + dx} 58 C ${120 + dx} 100 ${120 + dx} 172 ${128 + dx} 214`, undefined, { strokeWidth: 7, stroke: ic.c2, roughness: 2.2 });
    if (ic.net) for (let i = 0; i < 5; i++) { p.arc(128, 136, 164 - i * 8, 164 - i * 8, Math.PI * (0.1 + i * 0.4), Math.PI * (0.6 + i * 0.4), false, undefined, { strokeWidth: 1.8, stroke: ic.c2 }); }
    if (ic.frost) for (let i = 0; i < 7; i++) p.line(92 + (i * 37) % 80, 100 + (i * 23) % 80, 102 + (i * 37) % 80, 104 + (i * 23) % 80, { strokeWidth: 2, stroke: "#f7f3e9" });
    p.path(`M 124 56 C 122 42 136 38 142 50`, undefined, { strokeWidth: 3.6 });
  },
  pumpkin(p, ic) {
    p.ellipse(128, 148, 160, 112, ic.c, { hachureGap: 6.5 });
    p.ellipse(88, 148, 62, 104, undefined, { fill: undefined, strokeWidth: 2.6 });
    p.ellipse(168, 148, 62, 104, undefined, { fill: undefined, strokeWidth: 2.6 });
    p.path(`M 120 94 C 118 76 128 68 136 66 C 132 78 136 86 136 94`, ic.c2, { fillStyle: "solid", strokeWidth: 3 });
    p.path(`M 142 78 C 156 70 166 76 164 88`, undefined, { strokeWidth: 2.4 });
  },
  eggplant(p, ic) {
    p.path(`M 150 70 C 184 92 192 150 168 186 C 148 214 108 214 92 190 C 80 170 92 158 110 148 C 136 134 142 104 150 70 Z`, ic.c, { hachureGap: 6 });
    for (const a of [-40, 0, 40]) p.path(leafD(150, 72, 12, 26, a + 180), ic.c2, { fillStyle: "solid", strokeWidth: 2.2 });
    p.path(`M 148 68 C 146 52 158 46 164 54`, undefined, { strokeWidth: 3.6 });
  },
  broccoli(p, ic) {
    p.path(`M 116 150 L 112 206 C 120 214 136 214 144 206 L 140 150 Z`, ic.c2 || "#cfe1a2", { hachureGap: 5.5 });
    for (const [x, y, d] of [[90, 120, 56], [128, 100, 64], [166, 120, 56], [106, 146, 48], [150, 146, 48]]) p.circle(x, y, d, ic.c, { hachureGap: 5 });
    for (let i = 0; i < 8; i++) p.dot(92 + (i * 41) % 76, 102 + (i * 29) % 52, 1.8);
  },
  corn(p, ic) {
    p.path(`M 108 70 C 92 110 94 170 118 212 C 124 222 132 222 138 212 C 162 170 164 110 148 70 C 136 60 120 60 108 70 Z`, ic.c, { hachureGap: 5 });
    for (const y of [96, 124, 152, 180]) p.arc(128, y, 52, 24, Math.PI * 0.05, Math.PI * 0.95, false, undefined, { strokeWidth: 2 });
    p.line(118, 80, 118, 200, { strokeWidth: 2 }); p.line(138, 80, 138, 200, { strokeWidth: 2 });
    p.path(`M 104 84 C 80 108 76 160 94 196 C 84 150 88 110 104 84 Z`, ic.c2, { fillStyle: "solid" });
    p.path(`M 152 84 C 176 108 180 160 162 196 C 172 150 168 110 152 84 Z`, ic.c2, { fillStyle: "solid" });
  },
  beanpod(p, ic) {
    const pods = ic.long ? [[70, 70, 180, 196], [100, 60, 206, 176]] : [[76, 86, 188, 170], [86, 118, 196, 200]];
    for (const [x1, y1, x2, y2] of pods) {
      p.path(`M ${x1} ${y1} C ${x1 + 30} ${y1 + 50} ${x2 - 60} ${y2 - 40} ${x2} ${y2} C ${x2 - 16} ${y2 + 10} ${x2 - 36} ${y2} ${x2 - 44} ${y2 - 12} C ${x1 + 20} ${y1 + 66} ${x1 - 10} ${y1 + 28} ${x1} ${y1} Z`, ic.c, { hachureGap: 5.5 });
    }
    if (!ic.flat) for (let i = 0; i < 4; i++) p.dot(104 + i * 26, 118 + i * 18, 2.4);
    else for (let i = 0; i < 4; i++) p.circle(100 + i * 28, 122 + i * 16, 16, ic.c2, { fillStyle: "solid", strokeWidth: 2 });
  },
  sprout(p, ic) {
    for (let i = 0; i < 6; i++) {
      const x = 84 + i * 18, bend = (i % 2 ? 22 : -18);
      p.path(`M ${x} 200 C ${x + bend} 160 ${x - bend} 120 ${x + bend / 2} 92`, undefined, { strokeWidth: 3, stroke: "#d9cfae" });
      p.ellipse(x + bend / 2, 86, 18, 24, ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
    }
    p.path(`M 70 200 C 100 216 156 216 186 200`, undefined, { strokeWidth: 3 });
  },
  lotus(p, ic) {
    p.ellipse(150, 140, 136, 148, ic.c, { hachureGap: 7 });
    for (const [x, y] of [[150, 92], [118, 116], [182, 116], [108, 152], [192, 152], [124, 186], [176, 186], [150, 150]]) p.ellipse(x, y, 26, 30, "#fffdf4", { fillStyle: "solid", strokeWidth: 2.2 });
    p.ellipse(66, 150, 56, 96, ic.c2, { hachureGap: 5 });
  },
  fruit(p, ic) {
    if (ic.pear) p.path(`M 128 74 C 142 96 170 112 172 152 C 174 186 152 206 128 206 C 104 206 82 186 84 152 C 86 112 114 96 128 74 Z`, ic.c, { hachureGap: 6 });
    else if (ic.lemon) { p.ellipse(128, 142, 160, 120, ic.c, { hachureGap: 6 }); p.path(`M 46 136 C 38 128 44 118 54 122 Z`, ic.c, { fillStyle: "solid" }); p.path(`M 210 148 C 220 154 216 166 206 162 Z`, ic.c, { fillStyle: "solid" }); }
    else if (ic.mango) p.path(`M 84 100 C 110 70 160 76 182 108 C 202 138 192 180 158 192 C 118 206 70 178 72 140 C 72 122 76 110 84 100 Z`, ic.c, { hachureGap: 6 });
    else if (ic.flat) p.ellipse(128, 150, 156, 120, ic.c, { hachureGap: 6 });
    else p.circle(128, 146, 142, ic.c, { hachureGap: 6 });
    if (ic.cleft) p.path(`M 128 78 C 120 108 120 130 128 150`, undefined, { strokeWidth: 2.6 });
    if (ic.fuzz) for (let i = 0; i < 10; i++) { const a = i * 0.63; const r = 74; p.line(128 + Math.cos(a) * r, 146 + Math.sin(a) * r, 128 + Math.cos(a) * (r + 9), 146 + Math.sin(a) * (r + 9), { strokeWidth: 1.8 }); }
    if (ic.dots) for (let i = 0; i < 8; i++) p.dot(96 + (i * 37) % 70, 118 + (i * 53) % 60, 1.8);
    if (ic.spikes) for (const [x, y, a] of [[70, 110, -160], [60, 150, 180], [72, 188, 150], [186, 110, -20], [196, 150, 0], [184, 188, 30]]) p.path(leafD(x, y, 10, 26, a + 90), ic.c2, { fillStyle: "solid", strokeWidth: 2 });
    if (ic.leaf !== false && !ic.lemon && !ic.spikes) { p.line(128, ic.pear ? 74 : 78, 126, 56, { strokeWidth: 3.4 }); p.path(leafD(142, 62, 14, 26, 64), ic.c2, { fillStyle: "solid", strokeWidth: 2.4 }); }
  },
  grapes(p, ic) {
    if (ic.loose) {
      for (const [x, y] of [[96, 110], [150, 96], [182, 140], [112, 160], [156, 170], [86, 190], [196, 192]]) { p.circle(x, y, 40, ic.c, { hachureGap: 4.5 }); p.dot(x, y - 12, 1.6, ic.c2); }
    } else {
      const rows = [[128], [106, 150], [86, 128, 170], [106, 150], [128]];
      rows.forEach((xs, r) => xs.forEach((x) => p.circle(x, 96 + r * 28, 34, ic.c, { hachureGap: 4.5 })));
      p.line(128, 78, 128, 58, { strokeWidth: 3.2 });
      p.path(leafD(146, 64, 16, 28, 70), ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
    }
  },
  strawberry(p, ic) {
    p.path(`M 128 206 C 96 186 70 150 76 116 C 80 92 102 84 128 88 C 154 84 176 92 180 116 C 186 150 160 186 128 206 Z`, ic.c, { hachureGap: 5.5 });
    for (const a of [-70, -25, 25, 70]) p.path(leafD(128, 86, 12, 24, a + 180), ic.c2, { fillStyle: "solid", strokeWidth: 2.2 });
    p.line(128, 84, 128, 64, { strokeWidth: 3.2 });
    for (let i = 0; i < 9; i++) p.line(98 + (i * 31) % 62, 112 + (i * 23) % 70, 101 + (i * 31) % 62, 117 + (i * 23) % 70, { strokeWidth: 2 });
  },
  banana(p, ic) {
    for (const off of [0, 22, 44]) {
      p.path(`M ${66 + off} 92 C ${54 + off} 140 ${84 + off} 184 ${140 + off} 192 C ${150 + off} 193 ${152 + off} 182 ${142 + off} 176 C ${100 + off} 164 ${80 + off} 130 ${84 + off} 94 C ${82 + off} 84 ${70 + off} 84 ${66 + off} 92 Z`, ic.c, { hachureGap: 5.5 });
    }
    p.rect(60, 80, 26, 18, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
  },
  cherry(p, ic) {
    p.circle(96, 170, 64, ic.c, { hachureGap: 5 });
    p.circle(162, 158, 64, ic.c, { hachureGap: 5 });
    p.path(`M 96 138 C 108 100 128 78 150 66`, undefined, { strokeWidth: 3.2 });
    p.path(`M 162 126 C 158 102 152 82 150 66`, undefined, { strokeWidth: 3.2 });
    p.path(leafD(150, 66, 16, 30, 70), ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
  },
  meat(p, ic) {
    const layers = ic.layers || 2;
    if (ic.thin) {
      p.path(`M 60 120 C 90 96 170 96 198 118 C 204 128 198 136 188 136 C 150 128 100 130 70 138 C 58 138 54 128 60 120 Z`, ic.c, { hachureGap: 5 });
      p.path(`M 64 158 C 94 136 174 138 198 158 C 204 168 198 176 188 176 C 150 166 104 168 74 176 C 62 176 58 166 64 158 Z`, ic.c2, { hachureGap: 5 });
      if (layers > 2) p.path(`M 68 196 C 98 176 170 178 192 196 C 198 206 192 212 184 212 C 148 204 108 206 80 212 C 70 212 64 204 68 196 Z`, ic.c, { hachureGap: 5 });
    } else {
      p.path(`M 64 96 C 110 78 170 82 192 102 C 204 116 204 170 190 186 C 150 204 96 200 70 184 C 54 168 52 114 64 96 Z`, ic.c, { hachureGap: 5.5 });
      for (let i = 1; i < layers + 1; i++) {
        const y = 96 + (i * 90) / (layers + 1);
        p.path(`M 68 ${y} C 110 ${y - 14} 160 ${y - 10} 192 ${y + 4}`, undefined, { strokeWidth: 4.5, stroke: ic.c2, roughness: 2 });
      }
    }
  },
  steak(p, ic) {
    p.path(`M 60 118 C 70 88 130 76 172 92 C 204 104 206 148 188 172 C 164 200 104 202 76 182 C 52 164 52 136 60 118 Z`, ic.c, { hachureGap: 5 });
    p.path(`M 60 118 C 70 88 130 76 172 92 C 186 98 194 108 197 120 C 170 108 120 104 84 116 C 70 120 62 122 60 118 Z`, ic.c2 || CREAM, { fillStyle: "solid", strokeWidth: 2.4 });
    p.line(92, 134, 122, 180, { strokeWidth: 3.4 }); p.line(124, 126, 154, 172, { strokeWidth: 3.4 }); p.line(156, 122, 178, 158, { strokeWidth: 3.4 });
  },
  ribs(p, ic) {
    p.path(`M 56 108 C 100 88 160 88 200 110 L 192 180 C 152 198 104 198 64 180 Z`, ic.c, { hachureGap: 5.5 });
    for (const x of [88, 122, 156] ) {
      p.path(`M ${x - 9} 104 L ${x - 11} 186`, undefined, { strokeWidth: 9, stroke: ic.c2, roughness: 1.8 });
      p.circle(x - 10, 98, 20, ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
    }
  },
  mince(p, ic) {
    p.path(`M 64 170 C 60 130 94 104 130 106 C 170 108 196 136 192 170 C 180 192 76 192 64 170 Z`, ic.c, { hachureGap: 4.5 });
    for (let i = 0; i < 12; i++) p.dot(84 + (i * 37) % 96, 126 + (i * 23) % 50, 2.2, ic.c2);
    p.ellipse(128, 186, 150, 26, undefined, { fill: undefined, strokeWidth: 3 });
  },
  roll(p, ic) {
    for (const [x, y] of [[88, 140], [148, 120], [172, 178]]) {
      p.circle(x, y, 62, ic.c, { hachureGap: 5 });
      p.path(`M ${x} ${y} m -18 0 a 18 18 0 1 1 36 0 a 12 12 0 1 0 -24 2`, undefined, { strokeWidth: 2.6, stroke: ic.c2 });
    }
  },
  chicken(p, ic) {
    p.ellipse(128, 136, 150, 116, ic.c, { hachureGap: 6 });
    p.path(`M 70 122 C 56 112 56 94 72 92 C 80 92 86 100 86 108`, ic.c, { hachureGap: 5 });
    p.path(`M 96 188 C 86 206 98 216 110 208 L 118 196`, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
    p.path(`M 160 188 C 170 206 158 216 146 208 L 138 196`, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
    p.arc(128, 128, 96, 70, Math.PI * 1.1, Math.PI * 1.9, false, undefined, { strokeWidth: 2.6 });
  },
  drumstick(p, ic) {
    p.path(`M 86 86 C 120 60 176 76 184 124 C 190 162 160 190 124 182 C 108 178 96 168 90 154 C 74 146 68 112 86 86 Z`, ic.c, { hachureGap: 5.5 });
    p.path(`M 96 164 C 76 186 62 198 52 206`, undefined, { strokeWidth: 7, stroke: ic.c2 || CREAM });
    p.circle(48, 212, 24, ic.c2 || CREAM, { fillStyle: "solid", strokeWidth: 2.6 });
    p.circle(66, 224, 24, ic.c2 || CREAM, { fillStyle: "solid", strokeWidth: 2.6 });
  },
  wing(p, ic) {
    p.path(`M 60 150 C 70 116 110 100 146 110 C 150 96 170 92 180 104 C 192 118 184 134 170 136 C 174 160 150 182 118 180 C 90 178 66 168 60 150 Z`, ic.c, { hachureGap: 5.5 });
    p.path(`M 84 142 C 104 132 134 130 154 136`, undefined, { strokeWidth: 2.6 });
    p.path(`M 92 160 C 112 152 136 150 154 154`, undefined, { strokeWidth: 2.6 });
  },
  claw(p, ic) {
    p.path(`M 128 214 C 104 206 92 184 96 160 L 88 110 C 86 98 100 94 104 106 L 110 142 L 112 96 C 112 84 128 84 128 96 L 130 142 L 140 100 C 143 88 158 92 155 104 L 146 148 C 158 142 170 150 162 162 C 150 178 146 196 142 210 Z`, ic.c, { hachureGap: 5 });
  },
  sausage(p, ic) {
    p.path(`M 70 96 C 60 86 70 72 82 78 C 130 56 196 92 198 142 C 210 146 206 162 194 160 C 150 186 80 160 70 108 Z`, ic.c, { hachureGap: 5 });
    p.path(`M 96 86 C 86 118 94 142 116 158`, undefined, { strokeWidth: 2.4, stroke: ic.c2 });
    p.line(70, 90, 56, 80, { strokeWidth: 2.6 }); p.line(200, 150, 214, 158, { strokeWidth: 2.6 });
  },
  egg(p, ic) {
    const two = ic.small;
    const draw = (x, y, s) => {
      p.path(`M ${x} ${y - 66 * s} C ${x + 44 * s} ${y - 60 * s} ${x + 54 * s} ${y + 8 * s} ${x + 40 * s} ${y + 42 * s} C ${x + 24 * s} ${y + 70 * s} ${x - 24 * s} ${y + 70 * s} ${x - 40 * s} ${y + 42 * s} C ${x - 54 * s} ${y + 8 * s} ${x - 44 * s} ${y - 60 * s} ${x} ${y - 66 * s} Z`, ic.c, { hachureGap: 6 });
      if (ic.spots) for (let i = 0; i < 6; i++) p.dot(x - 26 * s + (i * 29) % (52 * s), y - 30 * s + (i * 37) % (60 * s), 2.6, ic.c2);
    };
    if (two) { draw(96, 126, 0.72); draw(166, 158, 0.72); } else draw(128, 140, 1);
  },
  fish(p, ic) {
    if (ic.long) {
      p.path(`M 48 96 C 96 76 176 84 208 120 C 180 128 150 124 120 136 C 96 146 70 170 48 196 C 56 164 60 124 48 96 Z`, ic.c, { hachureGap: 5 });
      p.dot(188, 106, 2.6);
      p.path(`M 60 108 C 90 96 150 94 190 108`, undefined, { strokeWidth: 2, stroke: ic.c2 });
    } else {
      p.path(`M 52 140 C 80 100 140 88 176 112 C 190 122 196 136 196 140 C 196 146 190 158 176 168 C 140 192 80 180 52 140 Z`, ic.c, { hachureGap: 5.5 });
      p.poly([[196, 140], [232, 108], [224, 140], [232, 172]], ic.c, { hachureGap: 4.5 });
      p.dot(84, 130, 3);
      p.arc(104, 140, 40, 52, -Math.PI / 2.5, Math.PI / 2.5, false, undefined, { strokeWidth: 2.4 });
      p.poly([[128, 102], [148, 84], [152, 106]], ic.c2, { fillStyle: "solid", strokeWidth: 2.2 });
    }
  },
  shrimp(p, ic) {
    p.path(`M 84 92 C 132 70 186 102 184 148 C 182 190 140 210 106 196 C 98 192 102 182 110 184 C 140 192 168 176 170 148 C 172 114 132 88 92 104 Z`, ic.c, { hachureGap: 5 });
    for (const a of [0.15, 0.4, 0.65]) { const x = 110 + a * 80, y = 88 + a * 24; p.path(`M ${x} ${y} C ${x + 10} ${y + 20} ${x + 14} ${y + 28} ${x + 10} ${y + 40}`, undefined, { strokeWidth: 2.2 }); }
    p.poly([[100, 190], [78, 212], [104, 212]], ic.c, { hachureGap: 4 });
    if (!ic.small) { p.dot(86, 100, 2.6); p.path(`M 80 92 C 64 84 52 86 44 96`, undefined, { strokeWidth: 2 }); p.path(`M 82 100 C 64 100 52 108 48 118`, undefined, { strokeWidth: 2 }); }
  },
  crab(p, ic) {
    p.ellipse(128, 150, 128, 92, ic.c, { hachureGap: 5.5 });
    for (const s of [-1, 1]) {
      p.path(`M ${128 + s * 56} 120 C ${128 + s * 84} 96 ${128 + s * 96} 80 ${128 + s * 88} 64`, undefined, { strokeWidth: 3.2 });
      p.circle(128 + s * 92, 58, 34, ic.c, { hachureGap: 4.5 });
      p.path(`M ${128 + s * 104} 46 L ${128 + s * 112} 58 L ${128 + s * 100} 62`, undefined, { strokeWidth: 2.6 });
      for (const dy of [0, 20, 40]) p.path(`M ${128 + s * 60} ${150 + dy * 0.6} C ${128 + s * 92} ${156 + dy} ${128 + s * 102} ${164 + dy} ${128 + s * 108} ${176 + dy * 0.8}`, undefined, { strokeWidth: 2.8 });
    }
    p.dot(112, 128, 2.8); p.dot(144, 128, 2.8);
  },
  shell(p, ic) {
    if (ic.rough) {
      p.path(`M 64 150 C 60 110 96 84 140 90 C 186 96 204 134 192 168 C 178 198 100 202 76 180 C 66 170 66 160 64 150 Z`, ic.c, { hachureGap: 5 });
      p.path(`M 76 146 C 100 130 160 128 184 146`, undefined, { strokeWidth: 2.4, stroke: ic.c2 });
      p.path(`M 82 166 C 108 152 152 152 178 164`, undefined, { strokeWidth: 2.4, stroke: ic.c2 });
    } else {
      p.path(`M 128 200 C 84 180 62 140 70 104 C 72 92 84 90 90 100 L 128 160 L 166 100 C 172 90 184 92 186 104 C 194 140 172 180 128 200 Z`, ic.c, { hachureGap: 5 });
      for (const a of [-32, 0, 32]) p.line(128, 196, 128 + a, 112, { strokeWidth: 2.4 });
      p.ellipse(128, 206, 44, 18, ic.c2, { fillStyle: "solid", strokeWidth: 2.2 });
    }
  },
  squid(p, ic) {
    p.poly([[128, 44], [172, 118], [84, 118]], ic.c, { hachureGap: 5.5 });
    p.path(`M 96 118 C 92 150 96 168 108 180 L 148 180 C 160 168 164 150 160 118 Z`, ic.c, { hachureGap: 5.5 });
    p.dot(114, 142, 3); p.dot(142, 142, 3);
    for (let i = 0; i < 5; i++) { const x = 102 + i * 13; p.path(`M ${x} 180 C ${x - 6} 198 ${x + 6} 210 ${x} 224`, undefined, { strokeWidth: 2.6 }); }
  },
  seaweed(p, ic) {
    for (const [x0, w] of [[84, 1], [128, 1.2], [172, 1]]) {
      p.path(`M ${x0} 52 C ${x0 - 22 * w} 92 ${x0 + 22 * w} 128 ${x0 - 18 * w} 168 C ${x0 - 30 * w} 192 ${x0 + 8 * w} 210 ${x0 + 4 * w} 218`, undefined, { strokeWidth: 10, stroke: ic.c, roughness: 1.8 });
    }
    p.rect(108, 120, 40, 18, ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
  },
  balls(p, ic) {
    for (const [x, y] of [[100, 112], [156, 112], [128, 162]]) {
      p.circle(x, y, 58, ic.c, { hachureGap: 6 });
      if (ic.snow) for (let i = 0; i < 4; i++) p.dot(x - 14 + i * 9, y - 10 + (i % 2) * 10, 1.4, ic.c2);
    }
    p.ellipse(128, 206, 140, 26, undefined, { fill: undefined, strokeWidth: 3 });
  },
  bag(p, ic) {
    const w = ic.small ? 112 : 136, x = 128 - w / 2, y = ic.puffy ? 70 : 62, h = ic.puffy ? 140 : 152;
    if (ic.puffy) {
      p.path(`M ${x} ${y + 12} C ${x - 10} ${y + h / 2} ${x - 6} ${y + h - 16} ${x + 10} ${y + h} L ${x + w - 10} ${y + h} C ${x + w + 6} ${y + h - 16} ${x + w + 10} ${y + h / 2} ${x + w} ${y + 12} C ${x + w - 18} ${y - 6} ${x + 18} ${y - 6} ${x} ${y + 12} Z`, ic.c, { hachureGap: 6.5 });
      p.line(x + 4, y + 8, x + w - 4, y + 8, { strokeWidth: 2.6 });
    } else {
      p.path(`M ${x} ${y + 14} L ${x + 6} ${y + h} C ${x + 50} ${y + h + 10} ${x + w - 50} ${y + h + 10} ${x + w - 6} ${y + h} L ${x + w} ${y + 14} Z`, ic.c, { hachureGap: 6.5 });
      p.path(`M ${x - 4} ${y + 14} L ${x} ${y} L ${x + w} ${y} L ${x + w + 4} ${y + 14} Z`, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
    }
    p.ellipse(128, y + h / 2 + 8, w - 34, 62, "#fffdf4", { fillStyle: "solid", strokeWidth: 2.4 });
    if (ic.g) p.text(ic.g, 128, y + h / 2 + 8 + glyphSize(ic.g) / 2.8, glyphSize(ic.g));
    if (ic.grains) for (let i = 0; i < 5; i++) p.dot(104 + i * 12, y + h - 14, 1.8, ic.c2);
  },
  noodles(p, ic) {
    const n = ic.bundle ? 7 : 9;
    for (let i = 0; i < n; i++) {
      const x = 88 + (i * 80) / (n - 1);
      if (ic.wavy) p.path(`M ${x} 60 C ${x - 8} 100 ${x + 8} 150 ${x} 200`, undefined, { strokeWidth: 3.2, stroke: i % 2 ? ic.c : ic.c2 });
      else p.line(x, 60, x + (ic.bundle ? 6 : 0), 200, { strokeWidth: 3.2, stroke: i % 2 ? ic.c : ic.c2 });
    }
    p.path(`M 84 118 C 100 108 156 108 172 118 L 172 148 C 156 158 100 158 84 148 Z`, ic.c, { hachureGap: 5 });
  },
  bottle(p, ic) {
    const w = ic.slim ? 56 : 84;
    p.rect(128 - 14, 48, 28, 20, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
    p.path(`M ${128 - 11} 68 L ${128 - w / 2} 96 L ${128 - w / 2} 196 C ${128 - w / 2} 208 ${128 + w / 2} 208 ${128 + w / 2} 196 L ${128 + w / 2} 96 L ${128 + 11} 68 Z`, ic.c, { hachureGap: 6 });
    p.ellipse(128, 148, w - 22, 58, "#fffdf4", { fillStyle: "solid", strokeWidth: 2.2 });
    if (ic.g) p.text(ic.g, 128, 148 + glyphSize(ic.g) / 2.8, Math.min(glyphSize(ic.g), ic.slim ? 30 : 40));
  },
  saucebottle(p, ic) {
    const w = ic.fat ? 96 : 76;
    p.rect(114, 44, 28, 18, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
    p.path(`M 117 62 L 117 84 C ${128 - w / 2} 92 ${128 - w / 2} 100 ${128 - w / 2} 116 L ${128 - w / 2} 192 C ${128 - w / 2} 206 ${128 + w / 2} 206 ${128 + w / 2} 192 L ${128 + w / 2} 116 C ${128 + w / 2} 100 ${128 + w / 2} 92 139 84 L 139 62 Z`, ic.c, { hachureGap: 5.5 });
    p.rect(128 - (w - 26) / 2, 126, w - 26, 56, "#fffdf4", { fillStyle: "solid", strokeWidth: 2.2 });
    if (ic.g) p.text(ic.g, 128, 154 + glyphSize(ic.g) / 2.8, Math.min(34, glyphSize(ic.g)));
  },
  jar(p, ic) {
    p.ellipse(128, 70, 96, 30, ic.c2, { fillStyle: "solid", strokeWidth: 2.8 });
    p.rect(84, 70, 88, 16, ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
    p.path(`M 80 92 C 72 120 72 170 82 192 C 94 208 162 208 174 192 C 184 170 184 120 176 92 Z`, ic.c, { hachureGap: 5.5 });
    p.rect(96, 122, 64, 52, "#fffdf4", { fillStyle: "solid", strokeWidth: 2.2 });
    if (ic.g) p.text(ic.g, 128, 148 + glyphSize(ic.g) / 2.8, Math.min(36, glyphSize(ic.g)));
  },
  shaker(p, ic) {
    p.path(`M 98 76 C 98 56 158 56 158 76 L 158 92 L 98 92 Z`, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
    p.dot(112, 72, 2.2); p.dot(128, 68, 2.2); p.dot(144, 72, 2.2);
    p.path(`M 94 92 L 90 188 C 90 204 166 204 166 188 L 162 92 Z`, ic.c, { hachureGap: 5.5 });
    p.ellipse(128, 146, 56, 48, "#fffdf4", { fillStyle: "solid", strokeWidth: 2.2 });
    if (ic.g) p.text(ic.g, 128, 146 + glyphSize(ic.g) / 2.8, Math.min(34, glyphSize(ic.g)));
  },
  spicebag(p, ic) {
    p.path(`M 76 112 C 70 150 74 184 90 200 C 118 212 150 210 168 198 C 182 180 184 146 178 112 C 160 100 146 104 128 110 C 110 104 94 100 76 112 Z`, ic.c, { hachureGap: 6 });
    p.path(`M 74 112 C 94 96 160 96 180 112 C 160 122 96 122 74 112 Z`, ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
    if (ic.dots) for (let i = 0; i < 7; i++) p.dot(98 + (i * 31) % 62, 142 + (i * 19) % 42, 2.2, "#fffdf4");
    if (ic.g) { p.ellipse(128, 160, 72, 44, "#fffdf4", { fillStyle: "solid", strokeWidth: 2 }); p.text(ic.g, 128, 160 + glyphSize(ic.g) / 2.8, Math.min(32, glyphSize(ic.g))); }
  },
  star(p, ic) {
    const pts = [];
    for (let i = 0; i < 16; i++) { const a = (Math.PI * i) / 8 - Math.PI / 2; const r = i % 2 ? 36 : 84; pts.push([128 + Math.cos(a) * r, 136 + Math.sin(a) * r]); }
    p.poly(pts, ic.c, { hachureGap: 5 });
    p.circle(128, 136, 30, ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
  },
  milkbox(p, ic) {
    p.poly([[86, 104], [128, 84], [170, 104], [170, 206], [86, 206]], ic.c, { hachureGap: 6.5 });
    p.poly([[86, 104], [128, 84], [170, 104], [128, 122]], ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
    p.line(128, 122, 128, 206, { strokeWidth: 2 });
    p.ellipse(128, 164, 64, 52, "#fffdf4", { fillStyle: "solid", strokeWidth: 2.2 });
    if (ic.g) p.text(ic.g, 128, 164 + glyphSize(ic.g) / 2.8, Math.min(34, glyphSize(ic.g)));
  },
  cup(p, ic) {
    p.ellipse(128, 80, 104, 28, ic.c2, { fillStyle: "solid", strokeWidth: 2.8 });
    p.path(`M 78 84 L 92 196 C 94 210 162 210 164 196 L 178 84 Z`, ic.c, { hachureGap: 6 });
    p.ellipse(128, 142, 64, 46, "#fffdf4", { fillStyle: "solid", strokeWidth: 2.2 });
    if (ic.g) p.text(ic.g, 128, 142 + glyphSize(ic.g) / 2.8, Math.min(30, glyphSize(ic.g)));
    p.path(`M 182 76 C 196 68 204 76 198 86`, undefined, { strokeWidth: 2.6 });
  },
  butter(p, ic) {
    p.poly([[64, 130], [150, 118], [196, 134], [196, 176], [108, 190], [64, 172]], ic.c, { hachureGap: 5 });
    p.poly([[64, 130], [150, 118], [196, 134], [110, 148]], ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
    p.path(`M 96 96 C 112 84 136 86 142 100 C 132 96 112 96 104 104 Z`, ic.c, { fillStyle: "solid", strokeWidth: 2.2 });
  },
  cheese(p, ic) {
    p.poly([[56, 170], [196, 110], [200, 182], [60, 196]], ic.c, { hachureGap: 5 });
    p.poly([[56, 170], [196, 110], [160, 102], [52, 152]], ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
    for (const [x, y, d] of [[110, 162, 22], [152, 148, 16], [92, 180, 12], [172, 168, 13]]) p.circle(x, y, d, "#fffdf4", { fillStyle: "solid", strokeWidth: 2 });
  },
  bread(p, ic) {
    p.path(`M 70 120 C 60 92 100 78 118 94 C 136 78 176 92 166 120 L 166 196 L 70 196 Z`, ic.c, { hachureGap: 6 });
    p.path(`M 92 134 C 86 116 112 106 124 118 C 136 106 160 116 154 134 L 154 196 L 92 196 Z`, CREAM, { fillStyle: "solid", strokeWidth: 2.4 });
    p.line(104, 150, 142, 150, { strokeWidth: 2 }); p.line(104, 168, 142, 168, { strokeWidth: 2 });
  },
  tofu(p, ic) {
    if (ic.small) {
      for (const [x, y] of [[92, 112], [164, 112], [128, 172]]) { p.poly([[x - 34, y - 12], [x + 20, y - 26], [x + 34, y + 2], [x - 20, y + 16]], ic.c, { hachureGap: 4.5 }); p.poly([[x - 20, y + 16], [x + 34, y + 2], [x + 34, y + 20], [x - 20, y + 34]], ic.c2, { fillStyle: "solid", strokeWidth: 2 }); }
    } else if (ic.thin) {
      for (let i = 0; i < 4; i++) p.poly([[70, 110 + i * 24], [186, 96 + i * 24], [196, 112 + i * 24], [80, 126 + i * 24]], i % 2 ? ic.c : ic.c2, { hachureGap: 5 });
    } else {
      p.poly([[66, 118], [172, 96], [198, 128], [92, 150]], ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
      p.poly([[92, 150], [198, 128], [198, 176], [92, 198]], ic.c, { hachureGap: 5.5 });
      p.poly([[66, 118], [92, 150], [92, 198], [66, 166]], ic.c, { hachureGap: 5.5 });
      if (ic.holes) for (let i = 0; i < 6; i++) p.dot(108 + (i * 29) % 76, 158 + (i * 17) % 28, 2.6, "#fffdf4");
    }
  },
  mushroom(p, ic) {
    if (ic.cluster) {
      for (const [x, y, w, a] of [[92, 120, 88, -14], [152, 104, 96, 4], [128, 160, 80, 20]]) { p.path(`M ${x - w / 2} ${y} C ${x - w / 2} ${y - 36} ${x + w / 2} ${y - 36} ${x + w / 2} ${y} Z`, ic.c, { hachureGap: 5 }); p.line(x, y, x - 8, y + 42, { strokeWidth: 7, stroke: ic.c2 }); }
    } else if (ic.round) {
      for (const [x, y, d] of [[96, 120, 70], [162, 110, 62], [132, 176, 66]]) { p.circle(x, y, d, ic.c, { hachureGap: 5 }); p.rect(x - 9, y + d / 2 - 4, 18, 22, ic.c2, { fillStyle: "solid", strokeWidth: 2 }); }
    } else if (ic.tall) {
      p.path(`M 104 92 C 104 70 152 70 152 92 C 160 96 160 108 150 110 L 106 110 C 96 108 96 96 104 92 Z`, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
      p.path(`M 110 110 C 104 150 106 184 114 206 C 126 216 132 216 142 206 C 150 184 152 150 146 110 Z`, ic.c, { hachureGap: 6 });
    } else {
      p.path(`M 60 128 C 64 84 192 84 196 128 C 198 140 186 146 172 144 L 84 144 C 70 146 58 140 60 128 Z`, ic.c, { hachureGap: 5.5 });
      p.path(`M 108 146 C 104 170 106 188 112 202 C 124 212 132 212 144 202 C 150 188 152 170 148 146 Z`, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
      for (const x of [88, 128, 168]) p.line(x, 96, x, 136, { strokeWidth: 2 });
    }
  },
  enoki(p, ic) {
    for (let i = 0; i < 9; i++) {
      const x = 86 + i * 10.5, top = 72 + (i * 13) % 26;
      p.line(x, 196, x + ((i % 3) - 1) * 10, top, { strokeWidth: 2.6, stroke: "#e3d7b4" });
      p.circle(x + ((i % 3) - 1) * 10, top - 7, 15, ic.c2, { fillStyle: "solid", strokeWidth: 2 });
    }
    p.path(`M 74 196 C 100 186 156 186 182 196 L 182 212 C 156 222 100 222 74 212 Z`, ic.c, { hachureGap: 5 });
  },
  fungus(p, ic) {
    p.path(`M 70 150 C 48 128 66 94 96 102 C 100 76 140 68 156 90 C 186 76 212 108 196 132 C 212 150 196 180 170 176 C 166 196 130 204 114 188 C 90 198 66 176 70 150 Z`, ic.c, { hachureGap: ic.light ? 7.5 : 4.5 });
    p.path(`M 96 136 C 112 120 148 118 166 134`, undefined, { strokeWidth: 2.4, stroke: ic.c2 });
    p.path(`M 104 158 C 120 146 144 146 158 156`, undefined, { strokeWidth: 2.4, stroke: ic.c2 });
  },
  dumpling(p, ic) {
    const one = (x, y, s, a) => {
      const r = (a * Math.PI) / 180, cos = Math.cos(r), sin = Math.sin(r);
      const P = (px, py) => `${(x + (px * cos - py * sin) * s).toFixed(1)} ${(y + (px * sin + py * cos) * s).toFixed(1)}`;
      p.path(`M ${P(-52, 18)} C ${P(-56, -14)} ${P(-24, -38)} ${P(0, -38)} C ${P(24, -38)} ${P(56, -14)} ${P(52, 18)} C ${P(20, 30)} ${P(-20, 30)} ${P(-52, 18)} Z`, ic.c, { hachureGap: 5.5 });
      for (const t of [-30, -10, 10, 30]) p.line(x + t * cos * s, y - 26 * s + Math.abs(t) * 0.26 * s, x + t * cos * s * 1.15, y - 38 * s + Math.abs(t) * 0.3 * s, { strokeWidth: 2.2 });
    };
    if (ic.wonton) { one(100, 120, 0.8, -10); one(168, 140, 0.8, 8); one(120, 188, 0.8, 3); }
    else { one(128, 110, 0.95, 0); one(90, 174, 0.85, -8); one(170, 174, 0.85, 8); }
  },
  bun(p, ic) {
    if (ic.open) {
      p.path(`M 92 120 C 84 94 172 94 164 120 C 176 116 182 128 172 134 L 168 196 C 150 208 106 208 88 196 L 84 134 C 74 128 80 116 92 120 Z`, ic.c2, { hachureGap: 5.5 });
      for (let i = 0; i < 5; i++) p.dot(104 + i * 12, 112, 3, ic.c);
    } else {
      p.path(`M 64 168 C 64 110 192 110 192 168 C 192 186 64 186 64 168 Z`, ic.c, { hachureGap: 6 });
      for (const a of [-44, -15, 15, 44]) p.path(`M 128 128 C ${128 + a} 136 ${128 + a * 1.4} 150 ${128 + a * 1.5} 164`, undefined, { strokeWidth: 2.2 });
      p.dot(128, 126, 3, ic.c2);
    }
    p.ellipse(128, 196, 120, 22, undefined, { fill: undefined, strokeWidth: 2.8 });
  },
  pancake(p, ic) {
    p.ellipse(128, 120, 156, 64, ic.c, { hachureGap: 6 });
    p.ellipse(128, 160, 156, 64, ic.c2 || ic.c, { hachureGap: 6 });
    p.path(`M 84 110 C 104 100 152 100 172 110`, undefined, { strokeWidth: 2.2 });
    p.path(`M 96 152 C 116 144 148 146 164 154`, undefined, { strokeWidth: 2.2 });
  },
  can(p, ic) {
    p.ellipse(128, 76, 100, 30, ic.c2, { fillStyle: "solid", strokeWidth: 2.8 });
    p.path(`M 78 78 L 80 192 C 80 208 176 208 176 192 L 178 78 Z`, ic.c, { hachureGap: 5.5 });
    p.ellipse(128, 142, 70, 50, "#fffdf4", { fillStyle: "solid", strokeWidth: 2.2 });
    if (ic.g) p.text(ic.g, 128, 142 + glyphSize(ic.g) / 2.8, Math.min(32, glyphSize(ic.g)));
    p.line(112, 70, 144, 76, { strokeWidth: 3 });
  },
  drinkbottle(p, ic) {
    p.rect(116, 42, 24, 16, ic.c2, { fillStyle: "solid", strokeWidth: 2.6 });
    p.path(`M 118 58 C 112 76 104 84 104 100 L 104 194 C 104 208 152 208 152 194 L 152 100 C 152 84 144 76 138 58 Z`, ic.c, { hachureGap: 6 });
    for (let i = 0; i < 5; i++) p.dot(118 + (i * 17) % 24, 120 + i * 16, 2.4, "#fffdf4");
  },
  icecream(p, ic) {
    p.path(`M 96 60 C 96 40 160 40 160 60 L 158 150 C 158 164 98 164 98 150 Z`, ic.c, { hachureGap: 5.5 });
    p.path(`M 100 96 C 108 108 120 104 124 96 C 130 108 142 106 146 96 C 150 104 156 106 158 102 L 158 150 C 158 164 98 164 98 150 Z`, ic.c2, { fillStyle: "solid", strokeWidth: 2.2 });
    p.rect(120, 164, 16, 48, "#d9b98c", { fillStyle: "solid", strokeWidth: 2.4 });
  },
  chocolate(p, ic) {
    p.rect(68, 84, 120, 108, ic.c, { hachureGap: 4.5 });
    p.line(128, 86, 128, 190, { strokeWidth: 2.6 }); p.line(70, 120, 186, 120, { strokeWidth: 2.6 }); p.line(70, 156, 186, 156, { strokeWidth: 2.6 });
    p.poly([[160, 70], [206, 70], [206, 116], [188, 98]], ic.c2, { fillStyle: "solid", strokeWidth: 2.4 });
    if (ic.g) p.text(ic.g, 128, 226, 30);
  },
  cookie(p, ic) {
    p.circle(118, 134, 140, ic.c, { hachureGap: 5.5 });
    p.path(`M 182 90 A 70 70 0 0 0 176 182 A 46 46 0 0 1 182 90 Z`, "#fffdf4", { fillStyle: "solid", strokeWidth: 2 });
    for (const [x, y] of [[92, 110], [134, 96], [84, 158], [126, 164], [108, 134]]) p.dot(x, y, 4.2, ic.c2);
  },
  peanut(p, ic) {
    const one = (x, y, a) => {
      const r = (a * Math.PI) / 180, cos = Math.cos(r), sin = Math.sin(r);
      const P = (px, py) => `${(x + px * cos - py * sin).toFixed(1)} ${(y + px * sin + py * cos).toFixed(1)}`;
      p.path(`M ${P(0, -46)} C ${P(26, -44)} ${P(30, -16)} ${P(16, -2)} C ${P(32, 10)} ${P(28, 42)} ${P(0, 46)} C ${P(-28, 42)} ${P(-32, 10)} ${P(-16, -2)} C ${P(-30, -16)} ${P(-26, -44)} ${P(0, -46)} Z`, ic.c, { hachureGap: 5 });
      for (const t of [-24, 0, 24]) p.line(x - 10 * cos + t * sin * 0.4, y + t * 0.8, x + 10 * cos + t * sin * 0.4, y + t * 0.84, { strokeWidth: 1.8 });
    };
    one(96, 120, -18); one(164, 158, 14);
  },
  lemonade() {},
};

// —— 菜谱(菜系)图标模板 ————————————————————————————————————
const DISH = {
  steamLines(p, x, y) {
    for (const dx of [-26, 0, 26]) p.path(`M ${x + dx} ${y} C ${x + dx - 10} ${y - 18} ${x + dx + 10} ${y - 34} ${x + dx} ${y - 50}`, undefined, { strokeWidth: 3, stroke: "#b9ab8f" });
  },
  wok(p, c) {
    DISH.steamLines(p, 128, 92);
    p.ellipse(128, 150, 180, 56, "#fffdf4", { fillStyle: "solid", strokeWidth: 3.2 });
    p.path(`M 70 142 C 86 112 170 112 186 142 C 160 132 96 132 70 142 Z`, c, { hachureGap: 5 });
    for (let i = 0; i < 5; i++) p.dot(100 + i * 14, 128 + (i % 2) * 8, 2.6, "#4a3f35");
    p.ellipse(128, 176, 120, 22, undefined, { fill: undefined, strokeWidth: 2.6 });
  },
  soup(p, c) {
    DISH.steamLines(p, 128, 86);
    p.path(`M 56 118 C 56 182 200 182 200 118 Z`, c, { hachureGap: 6 });
    p.ellipse(128, 118, 144, 34, "#fffdf4", { fillStyle: "solid", strokeWidth: 3 });
    p.ellipse(128, 118, 110, 22, c, { hachureGap: 4.5 });
    p.rect(108, 184, 40, 14, "#e8dfc6", { fillStyle: "solid", strokeWidth: 2.6 });
  },
  pot(p, c) {
    DISH.steamLines(p, 128, 74);
    p.ellipse(128, 96, 150, 30, "#8a5a44", { hachureGap: 5 });
    p.circle(128, 84, 22, "#8a5a44", { hachureGap: 4 });
    p.path(`M 56 104 C 52 160 80 190 128 190 C 176 190 204 160 200 104 Z`, c, { hachureGap: 5.5 });
    p.line(42, 116, 60, 112, { strokeWidth: 6 }); p.line(214, 116, 196, 112, { strokeWidth: 6 });
  },
  steam(p, c) {
    DISH.steamLines(p, 128, 70);
    p.ellipse(128, 100, 170, 40, "#d9b98c", { hachureGap: 5.5 });
    p.path(`M 44 102 L 46 150 C 46 170 210 170 210 150 L 212 102 C 170 122 86 122 44 102 Z`, "#e3c9a0", { hachureGap: 6 });
    for (const x of [86, 128, 170]) p.circle(x, 96, 40, c, { hachureGap: 4.5 });
    p.line(60, 142, 196, 142, { strokeWidth: 2.4 });
  },
  rice(p, c) {
    p.path(`M 56 128 C 56 188 200 188 200 128 Z`, "#9bb7c9", { hachureGap: 6 });
    p.path(`M 64 128 C 86 96 170 96 192 128 Z`, "#fffdf4", { fillStyle: "solid", strokeWidth: 3 });
    for (let i = 0; i < 8; i++) p.line(84 + (i * 29) % 90, 106 + (i * 11) % 18, 90 + (i * 29) % 90, 108 + (i * 11) % 18, { strokeWidth: 2.2 });
    p.ellipse(128, 102, 74, 30, c, { hachureGap: 4.5 });
    p.line(150, 58, 206, 96, { strokeWidth: 4 }); p.line(166, 50, 214, 86, { strokeWidth: 4 });
  },
  noodle(p, c) {
    p.line(96, 44, 186, 64, { strokeWidth: 4.5 });
    for (let i = 0; i < 5; i++) p.path(`M ${106 + i * 12} ${50 + i * 2} C ${100 + i * 12} 92 ${112 + i * 12} 112 ${104 + i * 12} 136`, undefined, { strokeWidth: 3, stroke: "#e8d5a3" });
    p.path(`M 52 130 C 52 190 204 190 204 130 Z`, c, { hachureGap: 6 });
    p.ellipse(128, 130, 152, 36, "#fffdf4", { fillStyle: "solid", strokeWidth: 3 });
    p.ellipse(128, 130, 118, 24, "#e8d5a3", { fillStyle: "solid", strokeWidth: 2 });
  },
  cold(p, c) {
    p.ellipse(128, 152, 188, 72, "#fffdf4", { fillStyle: "solid", strokeWidth: 3.2 });
    p.ellipse(128, 152, 150, 52, undefined, { fill: undefined, strokeWidth: 2 });
    p.path(`M 78 148 C 94 122 162 122 178 148 C 156 160 100 160 78 148 Z`, c, { hachureGap: 5 });
    for (let i = 0; i < 4; i++) p.dot(104 + i * 16, 136, 2.4, "#4a3f35");
  },
};

// —— 渲染与写盘 ————————————————————————————————————————————
const fontOpts = { fontFiles: [fontFile], loadSystemFonts: false, defaultFontFamily: "ZCOOL KuaiLe" };
function renderPNG(svg, px) {
  const r = new Resvg(svg, { fitTo: { mode: "width", value: px }, font: fontOpts, background: "rgba(0,0,0,0)" });
  return r.render().asPng();
}
function writeImageset(dir, name, png) {
  const d = path.join(dir, `${name}.imageset`);
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, `${name}.png`), png);
  fs.writeFileSync(path.join(d, "Contents.json"), JSON.stringify({
    images: [{ idiom: "universal", filename: `${name}.png`, scale: "2x" }],
    info: { author: "xcode", version: 1 },
  }, null, 2));
}

fs.mkdirSync(xcassets, { recursive: true });
fs.writeFileSync(path.join(xcassets, "Contents.json"), JSON.stringify({ info: { author: "xcode", version: 1 } }, null, 2));

let made = 0; const missing = [];
for (const item of catalog.items) {
  const t = T[item.icon.t];
  if (!t) { missing.push(`${item.id}:${item.icon.t}`); continue; }
  const p = new Pic(item.id);
  t(p, item.icon);
  writeImageset(xcassets, `food_${item.id}`, renderPNG(p.svg(), 256));
  made++;
}
for (const r of recipes.recipes) {
  const fn = DISH[r.icon.t];
  if (!fn) { missing.push(`${r.id}:${r.icon.t}`); continue; }
  const p = new Pic(r.id);
  fn(p, r.icon.c);
  writeImageset(xcassets, `recipe_${r.id}`, renderPNG(p.svg(), 256));
  made++;
}

// AppIcon:纸底 + 手绘菜篮 + 柴米
{
  const p = new Pic("appicon");
  p.raw.push(`<rect x="0" y="0" width="256" height="256" fill="#faf4e6"/>`);
  p.path(`M 52 128 C 48 180 90 212 128 212 C 166 212 208 180 204 128 Z`, "#d9b98c", { hachureGap: 6 });
  p.arc(128, 128, 150, 120, Math.PI, Math.PI * 2, false, undefined, { strokeWidth: 5 });
  for (let i = 0; i < 4; i++) p.line(70 + i * 40, 132, 78 + i * 40, 204, { strokeWidth: 2.4 });
  p.path(leafD(88, 126, 22, 46, -28), "#6a994e");
  p.circle(126, 106, 54, "#e5533d", { hachureGap: 5 });
  p.path(leafD(126, 80, 9, 18, 180), "#6a994e", { fillStyle: "solid", strokeWidth: 2 });
  p.path(`M 156 128 C 150 96 164 72 184 64 C 180 88 182 110 174 130 Z`, "#e9c46a", { hachureGap: 5 });
  p.text("柴米", 128, 246, 42, { rotate: -2 });
  const png = renderPNG(p.svg(), 1024);
  const d = path.join(xcassets, "AppIcon.appiconset");
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, "appicon.png"), png);
  fs.writeFileSync(path.join(d, "Contents.json"), JSON.stringify({
    images: [{ filename: "appicon.png", idiom: "universal", platform: "ios", size: "1024x1024" }],
    info: { author: "xcode", version: 1 },
  }, null, 2));
  made++;
}

// AccentColor + PaperBackground 色板
function colorset(name, hex, darkHex) {
  const toC = (h) => ({ "color-space": "srgb", components: { red: (parseInt(h.slice(1, 3), 16) / 255).toFixed(3), green: (parseInt(h.slice(3, 5), 16) / 255).toFixed(3), blue: (parseInt(h.slice(5, 7), 16) / 255).toFixed(3), alpha: "1.000" } });
  const d = path.join(xcassets, `${name}.colorset`);
  fs.mkdirSync(d, { recursive: true });
  const images = [{ idiom: "universal", color: toC(hex) }];
  if (darkHex) images.push({ idiom: "universal", appearances: [{ appearance: "luminosity", value: "dark" }], color: toC(darkHex) });
  fs.writeFileSync(path.join(d, "Contents.json"), JSON.stringify({ colors: images, info: { author: "xcode", version: 1 } }, null, 2));
}
colorset("AccentColor", "#bc4749");
colorset("PaperBackground", "#faf4e6", "#201b14");
colorset("PaperCard", "#fffdf4", "#2a241b");
colorset("InkPrimary", "#4a3f35", "#e8dfc9");

console.log(`generated ${made} images into ${xcassets}`);
if (missing.length) { console.error("MISSING TEMPLATES:", missing.join(", ")); process.exit(1); }
