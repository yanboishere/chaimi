// gen-receipt.mjs — 生成一张模拟超市小票 PNG,打包进 App 供模拟器演示 OCR 识别。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "..");

const lines = [
  ["header", "盒马鲜生 望京店"],
  ["sub", "欢迎光临  WELCOME"],
  ["sub", "2026-10-03 18:42  收银:0038"],
  ["rule"],
  ["item", "普罗旺斯番茄 450g", "8.90"],
  ["item", "黄瓜 3根装", "6.50"],
  ["item", "精品五花肉 500g", "29.80"],
  ["item", "三黄鸡 1只", "25.90"],
  ["item", "内酯豆腐 350g", "3.50"],
  ["item", "鲜香菇 250g", "7.90"],
  ["item", "小葱 1把", "2.00"],
  ["item", "可生食鸡蛋 10枚", "15.90"],
  ["item", "郫县豆瓣 500g", "12.80"],
  ["item", "金龙鱼玉米油 1.8L", "35.90"],
  ["item", "青线椒 250g", "5.80"],
  ["item", "帝王蕉 5根", "9.90"],
  ["item", "环保购物袋", "1.00"],
  ["rule"],
  ["total", "合计 13 件", "165.80"],
  ["sub", "微信支付: ¥165.80"],
  ["sub", "会员号: 139****2688  积分+165"],
  ["rule"],
  ["sub", "退换货请保留小票"],
];

const W = 760;
let y = 90;
let body = "";
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
for (const row of lines) {
  const [kind, text, price] = row;
  if (kind === "rule") {
    body += `<text x="40" y="${y}" font-size="26" fill="#333" font-family="PingFang SC">--------------------------------------------</text>`;
    y += 44;
  } else if (kind === "header") {
    body += `<text x="${W / 2}" y="${y}" font-size="44" fill="#111" text-anchor="middle" font-family="PingFang SC" font-weight="600">${esc(text)}</text>`;
    y += 62;
  } else if (kind === "item") {
    body += `<text x="48" y="${y}" font-size="30" fill="#111" font-family="PingFang SC">${esc(text)}</text>`;
    body += `<text x="${W - 48}" y="${y}" font-size="30" fill="#111" text-anchor="end" font-family="PingFang SC">${price}</text>`;
    y += 50;
  } else if (kind === "total") {
    body += `<text x="48" y="${y}" font-size="34" fill="#111" font-family="PingFang SC" font-weight="600">${esc(text)}</text>`;
    body += `<text x="${W - 48}" y="${y}" font-size="34" fill="#111" text-anchor="end" font-family="PingFang SC" font-weight="600">¥${price}</text>`;
    y += 56;
  } else {
    body += `<text x="${W / 2}" y="${y}" font-size="26" fill="#444" text-anchor="middle" font-family="PingFang SC">${esc(text)}</text>`;
    y += 42;
  }
}
// 底部条码
let bars = "";
let bx = 150;
const seed = [3, 1, 2, 1, 4, 1, 1, 2, 3, 1, 2, 2, 1, 3, 1, 1, 2, 1, 4, 2, 1, 1, 3, 2, 1, 2, 1, 1, 2, 3];
for (let i = 0; i < seed.length; i++) { const w = seed[i] * 3; if (i % 2 === 0) bars += `<rect x="${bx}" y="${y}" width="${w}" height="70" fill="#111"/>`; bx += w + 3; }
y += 110;

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${y}"><rect width="100%" height="100%" fill="#fdfdfb"/>${body}${bars}</svg>`;
const png = new Resvg(svg, { font: { loadSystemFonts: true, defaultFontFamily: "PingFang SC" } }).render().asPng();
fs.writeFileSync(path.join(root, "Chaimi/Resources/SampleReceipt.png"), png);
console.log("SampleReceipt.png", y, "px tall");
