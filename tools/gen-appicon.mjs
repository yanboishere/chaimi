// gen-appicon.mjs — 柴米 App 图标(手绘风)
// 用法:node tools/gen-appicon.mjs [candidates]
//   candidates: 渲染 4 个候选到 /tmp/chaimi-icon-*.png 并输出对比表 /tmp/chaimi-icon-sheet.png
//   不带参数: 渲染选定方案(basket)写入 Assets.xcassets/AppIcon.appiconset/appicon.png
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import rough from "roughjs/bundled/rough.esm.js";
import { Resvg } from "@resvg/resvg-js";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "..");
const fontFile = path.join(root, "Chaimi/Fonts/ZCOOLKuaiLe-Regular.ttf");

const INK = "#4a3f35";
const CREAM = "#f8f1e0";
const RED = "#c94c3b";
const GREEN = "#6a994e";

// —— 画布:显式分层,背景永远在最底 ————————————————————————
class Icon {
  constructor(seed = 7) { this.g = rough.generator(); this.seed = seed; this.n = 0; this.layers = []; }
  opt(fill, extra = {}) {
    this.n += 1;
    return {
      stroke: INK, strokeWidth: 13, roughness: 2.0, bowing: 1.6,
      fill, fillStyle: "hachure", fillWeight: 8, hachureGap: 26,
      hachureAngle: -41 + (this.n * 23) % 50, seed: this.seed + this.n * 17,
      ...extra,
    };
  }
  draw(dr) { this.layers.push({ kind: "rough", dr }); return this; }
  path(d, fill, extra) { return this.draw(this.g.path(d, this.opt(fill, extra))); }
  circle(x, y, dia, fill, extra) { return this.draw(this.g.circle(x, y, dia, this.opt(fill, extra))); }
  ellipse(x, y, w, h, fill, extra) { return this.draw(this.g.ellipse(x, y, w, h, this.opt(fill, extra))); }
  line(x1, y1, x2, y2, extra) { return this.draw(this.g.line(x1, y1, x2, y2, this.opt(undefined, { strokeWidth: 11, ...extra }))); }
  arc(x, y, w, h, a1, a2, closed, fill, extra) { return this.draw(this.g.arc(x, y, w, h, a1, a2, closed, this.opt(fill, extra))); }
  raw(s) { this.layers.push({ kind: "raw", s }); return this; }
  text(str, x, y, size, color = INK, rotate = -2) {
    return this.raw(`<text x="${x}" y="${y}" font-family="ZCOOL KuaiLe" font-size="${size}" fill="${color}" text-anchor="middle" transform="rotate(${rotate} ${x} ${y})">${str}</text>`);
  }
  svg(bg = CREAM) {
    let speck = "";
    let s = 88172645463325252n;
    const rnd = () => { s ^= s << 13n; s ^= s >> 7n; s ^= s << 17n; return Number((s >> 8n) % 10000n) / 10000; };
    for (let i = 0; i < 90; i++) {
      const r = rnd() * 5 + 2;
      speck += `<circle cx="${(rnd() * 1024).toFixed(0)}" cy="${(rnd() * 1024).toFixed(0)}" r="${r.toFixed(1)}" fill="${INK}" opacity="0.045"/>`;
    }
    const body = this.layers.map((l) => {
      if (l.kind === "raw") return l.s;
      return this.g.toPaths(l.dr).map((p) =>
        `<path d="${p.d}" stroke="${p.stroke}" stroke-width="${p.strokeWidth}" fill="${p.fill || "none"}" stroke-linecap="round" stroke-linejoin="round"/>`
      ).join("");
    }).join("");
    return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="${bg}"/>${speck}${body}</svg>`;
  }
}

const leafD = (x, y, w, h, a) => {
  const r = (a * Math.PI) / 180, cos = Math.cos(r), sin = Math.sin(r);
  const P = (px, py) => `${(x + px * cos - py * sin).toFixed(1)} ${(y + px * sin + py * cos).toFixed(1)}`;
  return `M ${P(0, 0)} C ${P(w * 0.55, -h * 0.45)} ${P(w * 0.55, -h)} ${P(0, -h * 1.25)} C ${P(-w * 0.55, -h)} ${P(-w * 0.55, -h * 0.45)} ${P(0, 0)} Z`;
};

// —— 公共元素 ————————————————————————————————————————————————
function produceTrio(ic, { tomatoX = 350, tomatoY = 468 } = {}) {
  // 白菜(中)
  ic.path(leafD(500, 520, 70, 150, -14), GREEN, { hachureGap: 20 });
  ic.path(leafD(585, 520, 70, 140, 16), "#7fae5c", { hachureGap: 20 });
  ic.path(leafD(540, 505, 72, 170, 2), "#86b961", { hachureGap: 20 });
  // 胡萝卜(右,斜插)
  ic.path(`M 652 320 C 700 300 742 318 752 356 C 768 420 740 500 700 548 L 640 500 C 630 430 634 360 652 320 Z`, "#e0793f", { hachureGap: 20 });
  ic.line(668, 380, 724, 404, { strokeWidth: 8 });
  ic.line(658, 440, 716, 468, { strokeWidth: 8 });
  for (const a of [-30, 0, 28]) ic.path(leafD(690, 318, 26, 64, a), GREEN, { fillStyle: "solid", strokeWidth: 8 });
  // 番茄(左)
  ic.circle(tomatoX, tomatoY, 230, RED, { hachureGap: 20 });
  for (const a of [-40, 0, 40]) ic.path(leafD(tomatoX, tomatoY - 112, 22, 46, a + 180), GREEN, { fillStyle: "solid", strokeWidth: 8 });
  ic.arc(tomatoX - 52, tomatoY - 44, 120, 100, Math.PI, Math.PI * 1.45, false, undefined, { strokeWidth: 9 });
}

function basket(ic) {
  // 提手(最后面)
  ic.arc(512, 560, 560, 620, Math.PI, Math.PI * 2, false, undefined, { strokeWidth: 26 });
  ic.arc(512, 560, 470, 530, Math.PI, Math.PI * 2, false, undefined, { strokeWidth: 14 });
  produceTrio(ic);
  // 篮身(盖住果蔬下半)
  ic.path(`M 232 566 C 240 700 282 848 330 892 C 450 928 574 928 694 892 C 742 848 784 700 792 566 C 700 540 324 540 232 566 Z`, "#d9a35e", { hachureGap: 30, fillWeight: 9 });
  // 编织纹
  for (const y of [648, 732, 814]) ic.path(`M ${262 + (y - 648) * 0.3} ${y} C 420 ${y + 26} 604 ${y + 26} ${762 - (y - 648) * 0.3} ${y}`, undefined, { strokeWidth: 9, stroke: "#8a5a44" });
  for (const x of [340, 420, 500, 580, 660]) ic.line(x, 586, x + (x < 512 ? 14 : -14) * 0, 886, { strokeWidth: 8, stroke: "#8a5a44" });
  // 篮口
  ic.ellipse(512, 560, 584, 96, "#b9854a", { hachureGap: 14, fillWeight: 7 });
  ic.ellipse(512, 560, 584, 96, undefined, { fill: undefined, strokeWidth: 15 });
}

// —— 候选方案 ————————————————————————————————————————————————
const CANDIDATES = {
  // 最终方案:大果蔬 + 无提手菜篮 + 右下「柴米」红印
  final(ic) {
    // 白菜(中,探出更高)
    ic.path(leafD(492, 460, 92, 196, -16), GREEN, { hachureGap: 17 });
    ic.path(leafD(606, 462, 90, 184, 18), "#7fae5c", { hachureGap: 17 });
    ic.path(leafD(548, 442, 94, 220, 1), "#86b961", { hachureGap: 17 });
    // 胡萝卜(右,斜插)
    ic.path(`M 664 258 C 722 234 772 256 782 302 C 800 378 766 474 718 530 L 646 472 C 636 388 642 306 664 258 Z`, "#e0793f", { hachureGap: 17 });
    ic.line(684, 330, 750, 358, { strokeWidth: 9 });
    ic.line(672, 400, 742, 432, { strokeWidth: 9 });
    for (const a of [-32, 0, 30]) ic.path(leafD(706, 254, 30, 76, a), GREEN, { fillStyle: "solid", strokeWidth: 9 });
    // 番茄(左,更大)
    ic.circle(332, 420, 290, RED, { hachureGap: 17 });
    for (const a of [-40, 0, 40]) ic.path(leafD(332, 282, 27, 56, a + 180), GREEN, { fillStyle: "solid", strokeWidth: 9 });
    ic.arc(268, 368, 150, 124, Math.PI, Math.PI * 1.45, false, undefined, { strokeWidth: 10 });
    // 篮身(无提手,大且稳)
    ic.path(`M 172 540 C 182 702 236 864 296 916 C 436 958 588 958 728 916 C 788 864 842 702 852 540 C 736 506 288 506 172 540 Z`, "#dca75f", { hachureGap: 21, fillWeight: 10 });
    for (const y of [644, 744, 838]) {
      const inset = (y - 644) * 0.36;
      ic.path(`M ${212 + inset} ${y} C 400 ${y + 30} 624 ${y + 30} ${812 - inset} ${y}`, undefined, { strokeWidth: 10, stroke: "#8a5a44" });
    }
    for (const x of [320, 416, 512, 608, 704]) ic.line(x, 560, x, 924 - Math.abs(x - 512) * 0.12, { strokeWidth: 9, stroke: "#8a5a44" });
    // 篮口
    ic.ellipse(512, 536, 692, 104, "#b9854a", { hachureGap: 12, fillWeight: 8 });
    ic.ellipse(512, 536, 692, 104, undefined, { fill: undefined, strokeWidth: 16 });
    // 右下「柴米」朱文印
    const sx = 762, sy = 704, sw = 198, sh = 252;
    ic.raw(`<rect x="${sx}" y="${sy}" width="${sw}" height="${sh}" rx="26" fill="${RED}" opacity="0.94" transform="rotate(-4 ${sx + sw / 2} ${sy + sh / 2})"/>`);
    ic.raw(`<g transform="rotate(-4 ${sx + sw / 2} ${sy + sh / 2})">
      <text x="${sx + sw / 2}" y="${sy + 108}" font-family="ZCOOL KuaiLe" font-size="104" fill="${CREAM}" text-anchor="middle">柴</text>
      <text x="${sx + sw / 2}" y="${sy + 222}" font-family="ZCOOL KuaiLe" font-size="104" fill="${CREAM}" text-anchor="middle">米</text>
    </g>`);
  },

  // A. 菜篮子
  basket(ic) { basket(ic); },

  // B. 菜篮 + 市场遮阳棚
  awning(ic) {
    for (let i = 0; i < 7; i++) {
      const x = i * (1024 / 7);
      if (i % 2 === 0) ic.raw(`<rect x="${x}" y="0" width="${1024 / 7 + 2}" height="150" fill="${RED}" opacity="0.92"/>`);
    }
    ic.raw(`<rect x="0" y="0" width="1024" height="150" fill="none"/>`);
    for (let i = 0; i < 7; i++) {
      const cx = i * (1024 / 7) + 1024 / 14;
      ic.arc(cx, 150, 1024 / 7, 110, 0, Math.PI, true, i % 2 === 0 ? RED : CREAM, { fillStyle: "solid", strokeWidth: 10 });
    }
    ic.line(-10, 96, 1034, 96, { strokeWidth: 10 });
    basket(ic);
  },

  // C. 一碗米饭
  bowl(ic) {
    // 蒸汽
    for (const [x, d] of [[380, 0], [512, 24], [644, 8]]) {
      ic.path(`M ${x} ${300 - d} C ${x - 44} ${252 - d} ${x + 44} ${196 - d} ${x} ${140 - d}`, undefined, { strokeWidth: 13, stroke: "#b9ab8f" });
    }
    // 筷子
    ic.line(668, 150, 554, 468, { strokeWidth: 17, stroke: "#a9763f" });
    ic.line(764, 186, 630, 490, { strokeWidth: 17, stroke: "#a9763f" });
    // 米饭(三团)
    for (const [x, y, d] of [[400, 480, 190], [624, 480, 190], [512, 432, 230]]) {
      ic.circle(x, y, d, "#fffdf4", { fillStyle: "solid", strokeWidth: 12 });
    }
    for (const [x, y] of [[420, 440], [520, 392], [610, 444], [468, 478], [560, 470]]) {
      ic.line(x, y, x + 26, y + 10, { strokeWidth: 7 });
    }
    // 碗
    ic.path(`M 206 520 C 212 700 330 836 512 836 C 694 836 812 700 818 520 C 716 488 308 488 206 520 Z`, "#eef3f2", { fillStyle: "solid", strokeWidth: 14 });
    ic.path(`M 268 660 C 352 742 672 742 756 660`, undefined, { strokeWidth: 24, stroke: "#5a7d9a" });
    ic.path(`M 238 586 C 348 640 676 640 786 586`, undefined, { strokeWidth: 12, stroke: "#5a7d9a" });
    ic.ellipse(512, 518, 612, 86, "#dde7e6", { fillStyle: "solid", strokeWidth: 14 });
    ic.path(`M 430 870 L 438 920 C 486 934 538 934 586 920 L 594 870 Z`, "#eef3f2", { fillStyle: "solid", strokeWidth: 12 });
  },

  // D. 印章「柴米」
  seal(ic) {
    const rr = (x, y, w, h, r) => `M ${x + r} ${y} L ${x + w - r} ${y} Q ${x + w} ${y} ${x + w} ${y + r} L ${x + w} ${y + h - r} Q ${x + w} ${y + h} ${x + w - r} ${y + h} L ${x + r} ${y + h} Q ${x} ${y + h} ${x} ${y + h - r} L ${x} ${y + r} Q ${x} ${y} ${x + r} ${y} Z`;
    ic.path(rr(150, 150, 724, 724, 96), undefined, { fill: undefined, strokeWidth: 30, stroke: RED, roughness: 2.6 });
    ic.path(rr(196, 196, 632, 632, 70), undefined, { fill: undefined, strokeWidth: 12, stroke: RED, roughness: 2.2 });
    ic.text("柴", 512, 568, 320, RED, -2);
    ic.text("米", 512, 858, 320, RED, 2);
  },
};

// —— 渲染 ————————————————————————————————————————————————————
function renderPNG(svg, px = 1024) {
  return new Resvg(svg, {
    fitTo: { mode: "width", value: px },
    font: { fontFiles: [fontFile], loadSystemFonts: false, defaultFontFamily: "ZCOOL KuaiLe" },
    background: CREAM,
  }).render().asPng();
}

function build(name) {
  const ic = new Icon(hash(name));
  CANDIDATES[name](ic);
  return ic.svg();
}
function hash(s) { let h = 0; for (const c of s) h = (h * 31 + c.codePointAt(0)) | 0; return (h >>> 0) % 1000 + 3; }

const mode = process.argv[2];
if (mode === "candidates") {
  const names = Object.keys(CANDIDATES);
  const files = {};
  for (const n of names) {
    const png = renderPNG(build(n));
    const f = `/tmp/chaimi-icon-${n}.png`;
    fs.writeFileSync(f, png);
    files[n] = png.toString("base64");
    console.log("wrote", f);
  }
  // 对比表:每个方案 180px + 60px,iOS 圆角遮罩(22.37%)
  let cells = "", defs = "";
  names.forEach((n, i) => {
    const x = 40 + (i % 2) * 460, y = 50 + Math.floor(i / 2) * 330;
    const r180 = 180 * 0.2237, r60 = 60 * 0.2237;
    defs += `<clipPath id="c${i}a"><rect x="${x}" y="${y}" width="180" height="180" rx="${r180}"/></clipPath>`;
    defs += `<clipPath id="c${i}b"><rect x="${x + 210}" y="${y + 60}" width="60" height="60" rx="${r60}"/></clipPath>`;
    defs += `<clipPath id="c${i}c"><rect x="${x + 210}" y="${y + 130}" width="40" height="40" rx="${40 * 0.2237}"/></clipPath>`;
    cells += `<image x="${x}" y="${y}" width="180" height="180" href="data:image/png;base64,${files[n]}" clip-path="url(#c${i}a)"/>`;
    cells += `<image x="${x + 210}" y="${y + 60}" width="60" height="60" href="data:image/png;base64,${files[n]}" clip-path="url(#c${i}b)"/>`;
    cells += `<image x="${x + 210}" y="${y + 130}" width="40" height="40" href="data:image/png;base64,${files[n]}" clip-path="url(#c${i}c)"/>`;
    cells += `<text x="${x}" y="${y + 215}" font-size="24" font-family="ZCOOL KuaiLe" fill="#333">${i + 1}. ${n}</text>`;
  });
  const sheet = `<svg xmlns="http://www.w3.org/2000/svg" width="940" height="${50 + Math.ceil(names.length / 2) * 330}"><rect width="100%" height="100%" fill="#e7e2d5"/>${defs}${cells}</svg>`;
  fs.writeFileSync("/tmp/chaimi-icon-sheet.png", new Resvg(sheet, { font: { fontFiles: [fontFile], loadSystemFonts: false, defaultFontFamily: "ZCOOL KuaiLe" } }).render().asPng());
  console.log("wrote /tmp/chaimi-icon-sheet.png");
} else {
  const chosen = mode || "basket";
  const out = path.join(root, "Chaimi/Assets.xcassets/AppIcon.appiconset/appicon.png");
  fs.writeFileSync(out, renderPNG(build(chosen)));
  console.log("wrote", out, `(design: ${chosen}; 记得用 sips 去掉 alpha 通道)`);
}
