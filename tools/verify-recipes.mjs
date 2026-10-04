// verify-recipes.mjs — 全量联网取证:每道菜在下厨房检索「标题真正指向这道菜」的攻略数
// 关键教训:下厨房搜索会模糊降级,无结果时也渲染 15 条推荐(连"蒜蓉炒冰淇淋"都返回 15 条
// 冰淇淋菜谱),所以不能数链接,必须解析结果标题做相关性匹配。
// 判定:相关攻略 ≥10 pass;<10 fail(gen 将被 prune 脚本删除);网络连续失败标 error(不删,人工复核)
// 运行:node tools/verify-recipes.mjs            全量 → tools/verify-report.json
//       node tools/verify-recipes.mjs --test 名1 名2   抽查指定菜名(打印每条标题判定)
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "..");

const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const norm = (s) => s.replace(/[^一-鿿A-Za-z0-9]/g, "");

// 菜名拆词:在首个内部连接字处切开(两侧都 ≥2 字才切),否则整名一个词。
// 例:山药炒牛肉→[山药,牛肉](容忍"牛肉炒山药"写法);清蒸鲈鱼/番茄炒蛋→整名。
const CONNECTORS = ["炒", "烧", "炖", "蒸", "拌", "煮", "焖", "烤", "熘", "爆", "煎", "烩", "卤", "汆", "酿", "配"];
function tokens(name) {
  const n = norm(name);
  for (const c of CONNECTORS) {
    const i = n.indexOf(c);
    if (i >= 2 && n.length - i - 1 >= 2) return [n.slice(0, i), n.slice(i + 1)];
  }
  return [n];
}

function fetchPage(name, page) {
  const url = `https://www.xiachufang.com/search/?keyword=${encodeURIComponent(name)}${page > 1 ? `&page=${page}` : ""}`;
  const html = execFileSync("curl", ["-s", "-m", "25", "-A", UA, url], { maxBuffer: 10 * 1024 * 1024 }).toString();
  if (html.length < 2000) throw new Error(`short response ${html.length}`);
  const items = [];
  const re = /<p class="name">\s*<a href="\/recipe\/(\d+)\/"[^>]*>\s*([\s\S]*?)\s*<\/a>/g;
  let m;
  while ((m = re.exec(html))) items.push({ id: m[1], title: m[2] });
  return items;
}

function judge(name, items, seen, verbose = false) {
  const full = norm(name);
  const tks = tokens(name);
  let matched = 0;
  for (const { id, title } of items) {
    if (seen.has(id)) continue;
    seen.add(id);
    const t = norm(title);
    const ok = t.includes(full) || (tks.length >= 2 && tks.every((k) => t.includes(k)));
    if (ok) matched++;
    if (verbose) console.log(`   ${ok ? "✓" : "✗"} ${title.replace(/\s+/g, " ").slice(0, 40)}`);
  }
  return matched;
}

// 返回 { matched, raw }:raw = 首页原始条数(模糊降级页也有 15,仅用于决定是否翻页)
async function relevantCount(name, verbose = false) {
  const seen = new Set();
  const p1 = fetchPage(name, 1);
  let matched = judge(name, p1, seen, verbose);
  // 相关性排序下,真有 ≥10 攻略的菜第一页至少命中 1 条;
  // 0 命中 = 降级推荐页,翻页只会有更多垃圾,直接判负。
  if (matched >= 1 && matched < 10 && p1.length >= 15) {
    await sleep(900 + Math.random() * 500);
    matched += judge(name, fetchPage(name, 2), seen, verbose);
  }
  return { matched, raw: p1.length };
}

// --test 模式:抽查并打印逐条判定
if (process.argv[2] === "--test") {
  for (const name of process.argv.slice(3)) {
    console.log(`== ${name} (tokens: ${tokens(name).join("+")})`);
    const { matched, raw } = await relevantCount(name, true);
    console.log(`   → matched=${matched} raw=${raw} ${matched >= 10 ? "PASS" : "FAIL"}`);
    await sleep(1200);
  }
  process.exit(0);
}

const hand = JSON.parse(fs.readFileSync(path.join(root, "Chaimi/Resources/recipes.json"), "utf8")).recipes;
const gen = JSON.parse(fs.readFileSync(path.join(root, "Chaimi/Resources/recipes_gen.json"), "utf8")).recipes;
const all = [
  ...hand.map((r) => ({ id: r.id, name: r.name, src: "hand" })),
  ...gen.map((r) => ({ id: r.id, name: r.name, src: "gen" })),
];
const report = [];
let done = 0;
for (const r of all) {
  let matched = -1, raw = -1, error = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const res = await relevantCount(r.name);
      matched = res.matched; raw = res.raw; error = null;
      break;
    } catch (e) {
      error = String(e.message).slice(0, 60);
      await sleep(4000 + attempt * 3000);
    }
  }
  const status = error ? "error" : matched >= 10 ? "pass" : "fail";
  report.push({ id: r.id, name: r.name, src: r.src, matched, raw, status });
  done += 1;
  if (done % 20 === 0 || status !== "pass") {
    console.log(`[${done}/${all.length}] ${r.name} → ${status}${matched >= 0 ? ` (${matched}/${raw})` : ""}${error ? " " + error : ""}`);
  }
  fs.writeFileSync(path.join(here, "verify-report.json"), JSON.stringify(report, null, 1));
  await sleep(1100 + Math.random() * 700);
}
const stats = { pass: 0, fail: 0, error: 0 };
for (const r of report) stats[r.status]++;
console.log("DONE", JSON.stringify(stats));
console.log("FAILS:", report.filter((r) => r.status === "fail").map((r) => `${r.name}(${r.matched})`).join("、") || "无");
console.log("ERRORS:", report.filter((r) => r.status === "error").map((r) => r.name).join("、") || "无");
