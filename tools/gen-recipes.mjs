// gen-recipes.mjs — 组合式菜谱生成器:做法模板 × 食材类别兼容矩阵 → 一万道可做的菜
// 读 catalog.json,写 Chaimi/Resources/recipes_gen.json(52 道手写精选在 recipes.json 里保持不变)
// 运行:node tools/gen-recipes.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "..");
const catalog = JSON.parse(fs.readFileSync(path.join(root, "Chaimi/Resources/catalog.json"), "utf8"));
const hand = JSON.parse(fs.readFileSync(path.join(root, "Chaimi/Resources/recipes.json"), "utf8"));
const byId = Object.fromEntries(catalog.items.map((i) => [i.id, i]));
const kcalOf = (id) => byId[id]?.kcal ?? 50;
const nameOf = (id) => byId[id]?.name ?? id;
for (const id of Object.keys(byId)) if (!byId[id]) throw new Error("bad id " + id);

// ———— 食材分类(全部用目录 id,生成前校验)————————————————————————
const C = {
  leafy: ["bocai", "youmaicai", "xiaobaicai", "jiucai", "qincai", "shengcai", "dabaicai", "yuanbaicai", "suantai"],
  crisp: ["xilanhua", "huacai", "qingjiao", "xianjiao", "huanggua", "xihulu", "sigua", "kugua", "douya", "helandou",
          "doujiao", "jiangdou", "lianou", "shanyao", "huluobo", "bailuobo", "yangcong", "donggua", "yumi", "nangua"],
  stewVeg: ["tudou", "bailuobo", "huluobo", "lianou", "shanyao", "yutou", "donggua", "nangua", "hongshu", "dabaicai", "fentiao", "dongdoufu", "haidai"],
  mushroom: ["xianggu", "jinzhengu", "xingbaogu", "pinggu", "koumo", "muer"],
  meatSlice: [
    { id: "wuhuarou", noun: "五花肉", cut: "切薄片" },
    { id: "zhuliji", noun: "肉丝", cut: "切丝,加料酒淀粉抓匀" },
    { id: "niuliji", noun: "牛柳", cut: "逆纹切片,上浆" },
    { id: "feiniujuan", noun: "肥牛", cut: "散开备用" },
    { id: "yangroujuan", noun: "羊肉", cut: "散开备用" },
    { id: "jixiongrou", noun: "鸡丁", cut: "切丁,腌10分钟" },
    { id: "jitui", noun: "鸡腿肉", cut: "去骨切块" },
    { id: "peigen", noun: "培根", cut: "切段" },
    { id: "xiangchang", noun: "腊肠", cut: "斜切薄片" },
    { id: "huotui", noun: "火腿", cut: "切条" },
    { id: "dougan", noun: "香干", cut: "切条" },
    { id: "zhuroumo", noun: "肉末", cut: "备用" },
  ],
  stewMeat: [
    { id: "zhupaigu", noun: "排骨", prep: "冷水下锅焯净浮沫" },
    { id: "niunan", noun: "牛腩", prep: "切块焯水" },
    { id: "yangpai", noun: "羊排", prep: "焯水去膻" },
    { id: "jitui", noun: "鸡腿", prep: "剁块焯水" },
    { id: "sanhuangji", noun: "鸡", prep: "剁块焯水" },
    { id: "yatui", noun: "鸭腿", prep: "剁块焯水" },
    { id: "jizhua", noun: "鸡爪", prep: "剪指焯水" },
    { id: "wuhuarou", noun: "五花肉", prep: "切块焯水" },
  ],
  fish: ["luyu", "huanghuayu", "caoyu", "daiyu", "xueyu"],
  shellfresh: ["jiweixia", "xiaren", "youyu", "hage", "shanbei"],
  tofu: ["nendoufu", "laodoufu", "doupi", "fuzhu"],
  eggMate: ["jiucai", "huanggua", "kugua", "yangcong", "sigua", "qingjiao", "xihulu", "muer", "fanqie", "douya", "suantai", "xiaocong"],
  soupVeg: ["donggua", "bailuobo", "haidai", "yuanbaicai", "fanqie", "zicai", "jinzhengu", "koumo", "shanyao", "lianou", "dabaicai", "doupi"],
  congee: ["nangua", "hongshu", "yumi", "shanyao", "xiaomi", "lvdou", "hongdou", "yiner"],
};
for (const [k, arr] of Object.entries(C)) {
  for (const it of arr) { const id = typeof it === "string" ? it : it.id; if (!byId[id]) throw new Error(`类别 ${k} 引用了不存在的 id: ${id}`); }
}

// ———— 菜系风味(调料组,全部为目录 id)—————————————————————————
const FLAVORS = {
  jiachang: { pre: "", sea: ["dasuan", "shengchou", "yan", "shiyongyou"], extra: "生抽和盐调味", kick: 0 },
  chuan: { pre: "川味", sea: ["doubanjiang", "huajiao", "ganlajiao", "jiang", "dasuan", "shiyongyou"], extra: "豆瓣酱炒出红油,花椒干辣椒增香", kick: 40 },
  xiang: { pre: "湘味", sea: ["xiaomila", "dasuan", "shengchou", "haoyou", "shiyongyou"], extra: "小米辣爆香,出锅前淋少许蚝油", kick: 30 },
  yue: { pre: "粤式", sea: ["haoyou", "jiang", "xiaocong", "shengchou", "shiyongyou", "baitang"], extra: "蚝油提鲜,少糖吊味", kick: 10 },
  lu: { pre: "葱香", sea: ["dacong", "jiang", "shengchou", "xiangcu", "shiyongyou"], extra: "葱姜爆锅,锅边烹醋", kick: 10 },
  dongbei: { pre: "东北", sea: ["dacong", "jiang", "tianmianjiang", "shengchou", "laochou", "yan"], extra: "一勺大酱炝锅,酱香打底", kick: 20 },
  xibei: { pre: "孜然", sea: ["ziranfen", "ganlajiao", "yangcong", "yan", "shiyongyou"], extra: "孜然辣椒面出锅前撒", kick: 30 },
  jiangzhe: { pre: "本帮", sea: ["bingtang", "shengchou", "laochou", "jiang", "liaojiu"], extra: "冰糖收出亮汁,咸中带甜", kick: 15 },
};

const prepOf = (id) => {
  if (C.leafy.includes(id)) return "洗净切段";
  if (C.mushroom.includes(id)) return id === "muer" ? "提前泡发撕小朵" : "切片";
  if (["tudou", "shanyao", "lianou", "huluobo", "bailuobo", "yutou", "hongshu"].includes(id)) return "去皮切片";
  if (["donggua", "nangua", "xihulu", "sigua", "kugua", "huanggua"].includes(id)) return "去瓤切块";
  if (["qingjiao", "xianjiao", "yangcong"].includes(id)) return "切块";
  if (["doujiao", "jiangdou", "helandou", "suantai"].includes(id)) return "撕筋掰段";
  if (id === "fentiao" || id === "fuzhu") return "温水泡软";
  if (C.tofu.includes(id)) return "切块";
  return "处理干净切好";
};

// ———— 生成器基建 ————————————————————————————————————————————
const used = new Set(hand.recipes.map((r) => r.name));
const out = [];
let serial = 0;
const PALETTE = 8;
function push({ name, cui, iconT, time, serves, kcal, tags, ing, sea, steps }) {
  if (used.has(name)) return false;
  used.add(name);
  serial += 1;
  const color = (name.length * 31 + serial * 7) % PALETTE;
  out.push({
    id: `gen_${serial.toString(36)}`,
    name, cui,
    icon: { t: iconT, c: "#000000" },
    img: `dish_${iconT}_${color}`,
    time, serves,
    kcal: Math.round(Math.max(90, Math.min(1400, kcal))),
    tags: ["组合", ...tags],
    ing, sea, steps,
  });
  return true;
}
const kc = (id, g) => (kcalOf(id) * g) / 100;
// 干货(泡发类)按干重计,一餐用量远小于鲜货
const DRY = new Set(["fentiao", "fuzhu", "muer", "yiner", "haidai", "zicai"]);
const kcD = (id, g) => kc(id, DRY.has(id) ? Math.min(g, 80) : g);

// ———— 1. 单主料小品 ———————————————————————————————————————————
const SINGLE_METHODS = [
  { n: (x) => `蒜蓉${x}`, pool: [...C.leafy, "xilanhua", "huacai", "sigua", "jinzhengu", "jiweixia"], cui: "yue", icon: "wok", t: 12, sea: ["dasuan", "haoyou", "yan", "shiyongyou"], tag: ["素菜", "快手"],
    steps: (x, p) => [`${x}${p},焯水半分钟捞出`, "多切点蒜末,小火煸到微黄出香", `下${x}转大火快炒`, "蚝油和盐调味,淋一点热油出锅"] },
  { n: (x) => `清炒${x}`, pool: [...C.leafy, "douya", "helandou", "xihulu", "sigua", "shanyao", "lianou"], cui: "jiachang", icon: "wok", t: 10, sea: ["dasuan", "yan", "shiyongyou"], tag: ["素菜", "快手", "低脂"],
    steps: (x, p) => [`${x}${p}`, "热锅凉油,蒜片爆香", `下${x}大火快炒断生`, "少许盐调味,脆嫩即出"] },
  { n: (x) => `凉拌${x}`, pool: ["huanggua", "muer", "doupi", "fuzhu", "jinzhengu", "bailuobo", "bocai", "qincai", "douya", "haidai", "shengcai", "youmaicai", "xilanhua", "lianou", "dougan", "fentiao", "helandou", "xihulu"], cui: "jiachang", icon: "cold", t: 12, sea: ["dasuan", "xiangcu", "shengchou", "baitang", "xiangyou", "lajiangjiang"], tag: ["凉菜", "开胃"],
    steps: (x, p) => [`${x}${p},焯熟过凉水攥干`, "蒜末、醋、生抽、糖、香油调成料汁,嗜辣加一勺辣酱", `浇在${x}上拌匀`, "冷藏10分钟更入味"] },
  { n: (x) => `干煸${x}`, pool: ["doujiao", "huacai", "xingbaogu", "lianou", "kugua"], cui: "chuan", icon: "wok", t: 20, sea: ["ganlajiao", "huajiao", "dasuan", "shengchou", "yan", "shiyongyou"], tag: ["素菜", "下饭"],
    steps: (x, p) => [`${x}${p},擦干水分`, "中火多油煸到表面起皱微焦,盛出", "底油下干辣椒花椒蒜末炝锅", `回${x},生抽和盐调味,大火翻匀`] },
  { n: (x) => `红烧${x}`, pool: ["qiezi", "tudou", "laodoufu", "donggua", "xianggu", "dongdoufu", ...C.fish], cui: "jiachang", icon: "wok", t: 25, sea: ["dasuan", "jiang", "shengchou", "laochou", "baitang", "dianfen", "shiyongyou"], tag: ["下饭"],
    steps: (x, p) => [`${x}${C.fish.includes(idByName(x)) ? "两面煎至金黄" : p + ",过油煎香"}`, "爆香蒜姜,调入生抽老抽和一勺糖", "加小半碗水烧开,下主料焖3-5分钟", "大火收汁,淀粉水勾薄芡"] },
  { n: (x) => `清蒸${x}`, pool: [...C.fish, "shanbei", "jiweixia"], cui: "yue", icon: "steam", t: 18, sea: ["zhengyuchiyou", "jiang", "xiaocong", "liaojiu", "shiyongyou"], tag: ["清淡", "快手"],
    steps: (x) => [`${x}收拾干净,抹料酒铺姜片腌10分钟`, "水开上锅,大火蒸8-10分钟", "倒掉腥水,铺姜丝葱丝,淋蒸鱼豉油", "烧一勺热油浇在葱丝上激香"] },
  { n: (x) => `椒盐${x}`, pool: ["xiaren", "youyu", "xueyu", "jichi", "laodoufu", "xingbaogu"], cui: "yue", icon: "wok", t: 22, sea: ["yan", "baihujiao", "dasuan", "dianfen", "shiyongyou", "xianjiao"], tag: ["下酒", "香酥"],
    steps: (x, p) => [`${x}${p},拍薄淀粉`, "六成油温炸到金黄捞出,升温复炸30秒", "底油爆香蒜末和青椒碎", `回${x},撒椒盐(盐+白胡椒)颠匀`] },
  { n: (x) => `孜然${x}`, pool: ["yangroujuan", "niuliji", "jitui", "tudou", "xingbaogu", "huacai"], cui: "xibei", icon: "wok", t: 15, sea: ["ziranfen", "ganlajiao", "yan", "shengchou", "shiyongyou", "yangcong"], tag: ["重口", "下饭"],
    steps: (x, p) => [`${x}${p}`, "大火热油快炒到边缘微焦", "下洋葱丝炒透明", "撒孜然粉辣椒碎,生抽调味,拌匀出锅"] },
  { n: (x) => `糖醋${x}`, pool: ["lianou", "bailuobo", "daiyu", "xiaren", "laodoufu"], cui: "lu", icon: "wok", t: 22, sea: ["baitang", "xiangcu", "shengchou", "fanqiejiang", "dianfen", "shiyongyou"], tag: ["酸甜", "开胃"],
    steps: (x, p) => [`${x}${p},拍淀粉煎到两面金黄`, "糖醋汁:2勺糖3勺醋2勺生抽1勺番茄酱半碗水", "倒入汁小火熬到冒大泡", `回${x}快速裹匀亮汁`] },
  { n: (x) => `剁椒蒸${x}`, pool: [...C.fish, "laodoufu", "jinzhengu", "shanbei"], cui: "xiang", icon: "steam", t: 20, sea: ["lajiangjiang", "dasuan", "jiang", "zhengyuchiyou", "shiyongyou"], tag: ["下饭", "湘味"],
    steps: (x, p) => [`${x}${p},铺盘底`, "蒜末与剁椒酱拌匀,厚厚铺满表面", "水开大火蒸10分钟", "撒葱花,浇热油激香,淋豉油"] },
  { n: (x) => `白灼${x}`, pool: ["jiweixia", "shengcai", "youmaicai", "shanbei"], cui: "yue", icon: "cold", t: 10, sea: ["shengchou", "jiang", "xiaocong", "shiyongyou", "baitang"], tag: ["清淡", "快手"],
    steps: (x) => [`${x}洗净,水开下锅烫熟即捞`, "姜丝葱丝铺面", "生抽加一点糖和两勺热水调成豉汁淋上", "热油一浇即可"] },
  { n: (x) => `香煎${x}`, pool: ["sanwenyu", "xueyu", "niupai", "jixiongrou", "laodoufu", "nendoufu"], cui: "jiachang", icon: "wok", t: 15, sea: ["yan", "heihujiao", "dasuan", "shiyongyou"], tag: ["低脂", "快手"],
    steps: (x) => [`${x}擦干,两面抹盐和黑胡椒腌10分钟`, "平底锅少油烧热,下锅后别急着翻", "一面定型金黄再翻面,各煎2-3分钟", "出锅静置1分钟再切"] },
  { n: (x) => `上汤${x}`, pool: [...C.leafy], cui: "yue", icon: "soup", t: 15, sea: ["dasuan", "pidan", "huotui", "yan", "shiyongyou"], tag: ["汤菜", "清淡"],
    steps: (x, p) => [`${x}${p}`, "蒜瓣煎金黄,加开水煮出奶白", "下皮蛋丁火腿丁滚1分钟", `下${x}煮软,盐调味连汤上桌`] },
  { n: (x) => `油焖${x}`, pool: ["jiweixia", "xianjiao", "sigua", "xingbaogu", "doujiao"], cui: "jiangzhe", icon: "wok", t: 18, sea: ["jiang", "baitang", "shengchou", "liaojiu", "shiyongyou"], tag: ["下饭"],
    steps: (x, p) => [`${x}${p}`, "多油烧热,下主料煎炒出香", "烹料酒,加糖和生抽小半碗水", "盖盖焖3分钟,大火收浓"] },
  { n: (x) => `酱爆${x}`, pool: ["jixiongrou", "youyu", "xiaren", "dougan", "xihulu"], cui: "lu", icon: "wok", t: 15, sea: ["tianmianjiang", "jiang", "dacong", "baitang", "liaojiu", "shiyongyou"], tag: ["下饭", "酱香"],
    steps: (x, p) => [`${x}${p}`, "甜面酱加一点糖和料酒调开", "热油爆香葱姜,下主料炒到八成熟", "倒入酱汁裹匀,酱香浓郁即出"] },
];
function idByName(n) { return catalog.items.find((i) => i.name === n)?.id ?? ""; }

for (const m of SINGLE_METHODS) {
  for (const id of m.pool) {
    const x = nameOf(id);
    const kcal = (kc(id, 300) + 120) / 2;
    push({ name: m.n(x), cui: m.cui, iconT: m.icon, time: m.t, serves: 2, kcal,
      tags: m.tag, ing: [{ id, q: id === "jiweixia" ? "400克" : "300克" }],
      sea: m.sea.filter((s) => s !== id), steps: m.steps(x, prepOf(id)) });
  }
}

// ———— 2. 荤素双拼:X炒/烧/焖/干锅 ————————————————————————————————
const PAIR_VEG = [...new Set([...C.crisp, ...C.leafy.filter((i) => !["shengcai", "dabaicai"].includes(i)), ...C.mushroom])];
const BAD_PAIR = new Set(["kugua|niunan", "huanggua|xiangchang", "nangua|peigen"]); // 口味黑名单(示例,可持续补充)
const PAIR_METHODS = [
  { key: "chao", name: (v, m) => `${v}炒${m.noun}`, icon: "wok", t: 15, tag: ["下饭", "快手"], cuis: ["jiachang", "chuan", "xiang", "yue", "dongbei"],
    steps: (v, m, f) => [`${m.noun}${m.cut};${v}${prepOf(v.id ?? "")}`, `热油先滑炒${m.noun}至变色盛出`, f.extra, `下${v}大火炒断生,回${m.noun}翻匀,调味出锅`] },
  { key: "shao", name: (v, m) => `${m.noun}烧${v}`, icon: "wok", t: 30, tag: ["下饭"], cuis: ["jiachang", "jiangzhe", "dongbei"],
    steps: (v, m, f) => [`${m.noun}${m.cut};${v}${prepOf(v.id ?? "")}`, `煸${m.noun}出油出香`, f.extra + ",加开水没过食材", `下${v}中火烧8-10分钟,收浓汤汁`] },
  { key: "ganguo", name: (v, m) => `干锅${v}${m.noun}`, icon: "pot", t: 25, tag: ["重口", "下饭"], cuis: ["chuan", "xiang"],
    steps: (v, m, f) => [`${v}过油断生;${m.noun}${m.cut}`, `煸${m.noun}到微焦`, f.extra, "合炒后转小锅,小火咕嘟着吃"] },
];
const pairVegOK = (vid, mid, key) => {
  if (BAD_PAIR.has(`${vid}|${mid}`)) return false;
  if (key === "shao" && !["tudou", "qiezi", "donggua", "bailuobo", "lianou", "xianggu", "dabaicai", "nangua", "doujiao", "jiangdou", "fentiao"].includes(vid) && !C.mushroom.includes(vid)) return false;
  if (key === "ganguo" && !["huacai", "xilanhua", "lianou", "tudou", "doujiao", "xingbaogu", "pinggu", "bailuobo"].includes(vid)) return false;
  if (key === "chao" && ["donggua", "nangua", "yumi"].includes(vid)) return false;
  return true;
};

for (const method of PAIR_METHODS) {
  for (const meat of C.meatSlice) {
    if (method.key !== "chao" && ["peigen", "huotui", "dougan", "zhuroumo", "feiniujuan"].includes(meat.id)) continue;
    for (const vid of PAIR_VEG) {
      if (!pairVegOK(vid, meat.id, method.key)) continue;
      for (const cui of method.cuis) {
        const f = FLAVORS[cui];
        const base = method.name(nameOf(vid), meat);
        const name = cui === method.cuis[0] ? base : `${f.pre}${base}`;
        const kcal = (kc(meat.id, 200) + kcD(vid, 200) + 130) / 2 + f.kick;
        push({ name, cui, iconT: method.icon, time: method.t, serves: 2, kcal, tags: method.tag,
          ing: [{ id: vid, q: "300克" }, { id: meat.id, q: "200克" }],
          sea: [...new Set(f.sea)], steps: method.steps({ id: vid, toString: () => nameOf(vid) }, meat, f) });
      }
    }
  }
}

// ———— 3. 炖菜/汤煲 ————————————————————————————————————————————
for (const meat of C.stewMeat) {
  for (const vid of C.stewVeg) {
    if (BAD_PAIR.has(`${vid}|${meat.id}`)) continue;
    for (const cui of ["jiachang", "dongbei", "chuan"]) {
      const f = FLAVORS[cui];
      const name = `${cui === "dongbei" ? "东北" : cui === "chuan" ? "麻辣" : ""}${meat.noun}炖${nameOf(vid)}`;
      push({ name, cui, iconT: "pot", time: 70, serves: 3,
        kcal: (kc(meat.id, 450) + kcD(vid, 350) + 120) / 3 * 1.6,
        tags: ["炖菜", "硬菜"],
        ing: [{ id: meat.id, q: "500克" }, { id: vid, q: "400克" }],
        sea: [...new Set(["dacong", "jiang", "bajiao", ...f.sea])].slice(0, 8),
        steps: [`${meat.noun}${meat.prep}`, "热油煸香葱姜八角,下肉炒上色,烹料酒", "加开水没过,小火炖40分钟", `下${nameOf(vid)}再炖15-20分钟,盐调味`] });
    }
  }
  // 清汤系
  for (const vid of C.soupVeg) {
    if (["fanqie", "zicai"].includes(vid) && !["zhupaigu", "niunan"].includes(meat.id)) continue;
    const name = `${nameOf(vid)}${meat.noun}汤`;
    push({ name, cui: "yue", iconT: "soup", time: 60, serves: 3,
      kcal: (kc(meat.id, 400) + kcD(vid, 300)) / 3 + 60,
      tags: ["汤", "清淡"],
      ing: [{ id: meat.id, q: "400克" }, { id: vid, q: "300克" }],
      sea: ["jiang", "yan", "baihujiao", "xiaocong", "liaojiu"],
      steps: [`${meat.noun}${meat.prep}`, "换砂锅加足量开水和姜片,小火煲40分钟", `下${nameOf(vid)}再煲15分钟`, "盐和白胡椒调味,撒葱花"] });
  }
}

// ———— 4. 海鲜小炒 ————————————————————————————————————————————
const SEA_VEG = ["qingjiao", "xianjiao", "huanggua", "xilanhua", "yangcong", "qincai", "douya", "suantai", "jiucai", "xihulu", "helandou", "jinzhengu", "muer", "huacai", "sigua"];
for (const sid of C.shellfresh) {
  for (const vid of SEA_VEG) {
    for (const cui of ["jiachang", "yue", "xiang", "chuan"]) {
      const f = FLAVORS[cui];
      const base = `${nameOf(vid)}炒${nameOf(sid)}`;
      const name = cui === "jiachang" ? base : `${f.pre}${base}`;
      push({ name, cui, iconT: "wok", time: 14, serves: 2,
        kcal: (kc(sid, 250) + kc(vid, 200) + 110) / 2 + f.kick,
        tags: ["快手", "鲜"],
        ing: [{ id: sid, q: "250克" }, { id: vid, q: "200克" }],
        sea: [...new Set(["jiang", "liaojiu", ...f.sea])].slice(0, 8),
        steps: [`${nameOf(sid)}处理干净,料酒姜丝腌5分钟`, `${nameOf(vid)}${prepOf(vid)}`, `热油先下${nameOf(sid)}大火快炒至变色盛出`, `${f.extra};下${nameOf(vid)}炒断生,回锅合炒调味`] });
    }
  }
}

// ———— 5. 蛋与豆腐 ————————————————————————————————————————————
for (const vid of C.eggMate) {
  push({ name: `${nameOf(vid)}炒蛋`, cui: "jiachang", iconT: "wok", time: 10, serves: 2,
    kcal: (kc("jidan", 150) + kc(vid, 180) + 110) / 2,
    tags: ["快手", "家常"],
    ing: [{ id: vid, q: "200克" }, { id: "jidan", q: "3个" }],
    sea: ["yan", "xiaocong", "shiyongyou"],
    steps: ["鸡蛋加盐打散,热油炒成大块盛出", `${nameOf(vid)}${prepOf(vid)},下锅炒断生`, "回鸡蛋合炒", "盐调味,撒葱花"] });
}
const TOFU_MATE = [
  ["zhuroumo", "肉末"], ["xiaren", "虾仁"], ["xianggu", "香菇"], ["pidan", "皮蛋"], ["jinzhengu", "金针菇"], ["xianyadan", "咸蛋"],
];
for (const t of C.tofu) {
  for (const [mid, mn] of TOFU_MATE) {
    if (BAD_PAIR.has(`${t}|${mid}`)) continue;
    for (const cui of ["jiachang", "chuan"]) {
      const f = FLAVORS[cui];
      const name = `${f.pre}${mn}${nameOf(t)}`;
      push({ name, cui, iconT: "wok", time: 18, serves: 2,
        kcal: (kc(t, 300) + kc(mid, 120) + 120) / 2 + f.kick,
        tags: ["下饭", "豆香"],
        ing: [{ id: t, q: "1盒" }, { id: mid, q: "100克" }],
        sea: [...new Set(["dianfen", ...f.sea])].slice(0, 8),
        steps: [`${nameOf(t)}切块,盐水焯1分钟`, `${mn}煸炒出香`, f.extra + ",加小半碗水", "下豆腐轻推焖2分钟,淀粉水勾芡"] });
    }
  }
}

// ———— 6. 主食:面/粉/饭/粥 ————————————————————————————————————————
const TOPPING_MEAT = C.meatSlice.filter((m) => !["dougan"].includes(m.id));
const TOPPING_VEG = ["qingjiao", "xianggu", "douya", "dabaicai", "jiucai", "suantai", "yangcong", "xilanhua", "fanqie", "huanggua", "muer", "jinzhengu", "bocai", "xiaobaicai", "qincai", "doujiao"];
const NOODLES = [["xianmian", "面"], ["guamian", "挂面"], ["mifen", "米粉"], ["fentiao", "粉"], ["yidalimian", "意面"]];
const NOODLE_STYLES = [
  { n: (tv, tm, nn) => `${tv}${tm.noun}炒${nn}`, icon: "noodle", t: 18, tag: ["主食", "快手"],
    steps: (tv, tm, nn) => [`${nn}煮到八成熟,过凉沥干拌点油`, `${tm.noun}${tm.cut},滑炒变色`, `下${tv}炒断生`, `下${nn}大火颠炒,生抽老抽调色调味`],
    sea: ["shengchou", "laochou", "dasuan", "shiyongyou", "yan"] },
  { n: (tv, tm, nn) => `${tv}${tm.noun}汤${nn}`, icon: "noodle", t: 16, tag: ["主食", "热汤"],
    steps: (tv, tm, nn) => [`${tm.noun}${tm.cut};${tv}洗净切好`, "爆香葱姜,炒料后加开水烧出汤底", `下${nn}煮熟`, `码上炒好的${tv}和${tm.noun},撒葱花`],
    sea: ["jiang", "xiaocong", "shengchou", "yan", "baihujiao", "xiangyou"] },
  { n: (tv, tm, nn) => `${tv}${tm.noun}拌${nn}`, icon: "noodle", t: 14, tag: ["主食", "快手"],
    steps: (tv, tm, nn) => [`${nn}煮熟过凉`, `${tm.noun}与${tv}炒成浇头`, "生抽香醋辣酱调一勺灵魂酱汁", "浇头+酱汁拌匀开吃"],
    sea: ["shengchou", "xiangcu", "lajiangjiang", "dasuan", "xiangyou"] },
];
const NOODLE_FLAVORS = ["jiachang", "chuan", "xiang"];
for (const [nid, nn] of NOODLES) {
  for (const style of NOODLE_STYLES) {
    for (const flavorKey of NOODLE_FLAVORS) {
      const f = FLAVORS[flavorKey];
      // 意面只做家常炒/拌,避免「川味意面」泛滥
      if (nid === "yidalimian" && flavorKey !== "jiachang") continue;
      for (const tm of TOPPING_MEAT) {
        for (const tv of TOPPING_VEG) {
          if (BAD_PAIR.has(`${tv}|${tm.id}`)) continue;
          const name = `${f.pre}${style.n(nameOf(tv), tm, nn)}`;
          const sea = [...new Set([...style.sea, ...(flavorKey === "jiachang" ? [] : f.sea)])].slice(0, 8);
          const steps = style.steps(nameOf(tv), tm, nn);
          if (flavorKey !== "jiachang") steps[2] = f.extra + ";" + steps[2];
          push({ name, cui: flavorKey, iconT: style.icon, time: style.t, serves: 1,
            kcal: kc(nid, 110) + kc(tm.id, 80) + kcD(tv, 80) + 90 + f.kick,
            tags: style.tag,
            ing: [{ id: nid, q: "1人份" }, { id: tm.id, q: "80克" }, { id: tv, q: "80克" }],
            sea, steps });
        }
      }
    }
  }
}
// 盖饭 & 炒饭
const RICE_FLAVORS = { gaifan: ["jiachang", "chuan", "yue"], chaofan: ["jiachang", "xiang"] };
for (const tm of TOPPING_MEAT) {
  for (const tv of TOPPING_VEG) {
    if (BAD_PAIR.has(`${tv}|${tm.id}`)) continue;
    for (const fk of RICE_FLAVORS.gaifan.slice(1)) {
      const f = FLAVORS[fk];
      push({ name: `${f.pre}${nameOf(tv)}${tm.noun}盖饭`, cui: fk, iconT: "rice", time: 20, serves: 1,
        kcal: kc("dami", 120) + kc(tm.id, 120) + kc(tv, 100) + 100 + f.kick,
        tags: ["主食", "一碗端"],
        ing: [{ id: "dami", q: "1碗" }, { id: tm.id, q: "120克" }, { id: tv, q: "120克" }],
        sea: [...new Set(["dianfen", ...f.sea])].slice(0, 8),
        steps: [`${tm.noun}${tm.cut};${nameOf(tv)}${prepOf(tv)}`, f.extra, "合炒后淀粉水收成有汁的浇头", "连汁浇在热米饭上"] });
    }
    for (const fk of RICE_FLAVORS.chaofan.slice(1)) {
      const f = FLAVORS[fk];
      push({ name: `${f.pre}${nameOf(tv)}${tm.noun}炒饭`, cui: fk, iconT: "rice", time: 12, serves: 1,
        kcal: kc("dami", 150) + kc(tm.id, 80) + kc(tv, 60) + 130 + f.kick,
        tags: ["主食", "快手"],
        ing: [{ id: "dami", q: "隔夜饭1碗" }, { id: tm.id, q: "80克" }, { id: tv, q: "80克" }],
        sea: [...new Set(f.sea)].slice(0, 8),
        steps: [`${tm.noun}和${nameOf(tv)}切小丁炒香`, f.extra, "下隔夜饭大火炒散炒粒", "调味出锅"] });
    }
    push({ name: `${nameOf(tv)}${tm.noun}盖饭`, cui: "jiachang", iconT: "rice", time: 20, serves: 1,
      kcal: kc("dami", 120) + kc(tm.id, 120) + kc(tv, 100) + 100,
      tags: ["主食", "一碗端"],
      ing: [{ id: "dami", q: "1碗" }, { id: tm.id, q: "120克" }, { id: tv, q: "120克" }],
      sea: ["shengchou", "haoyou", "dianfen", "dasuan", "shiyongyou"],
      steps: [`${tm.noun}${tm.cut};${nameOf(tv)}${prepOf(tv)}`, "滑炒肉后下菜合炒", "生抽蚝油调味,淀粉水收成有汁的浇头", "连汁浇在热米饭上"] });
    push({ name: `${nameOf(tv)}${tm.noun}炒饭`, cui: "jiachang", iconT: "rice", time: 12, serves: 1,
      kcal: kc("dami", 150) + kc(tm.id, 80) + kc(tv, 60) + 130,
      tags: ["主食", "快手", "剩饭救星"],
      ing: [{ id: "dami", q: "隔夜饭1碗" }, { id: tm.id, q: "80克" }, { id: tv, q: "80克" }, { id: "jidan", q: "1个", opt: true }],
      sea: ["yan", "shengchou", "xiaocong", "shiyongyou"],
      steps: [`${tm.noun}和${nameOf(tv)}切小丁`, "热油把配料炒香", "下隔夜饭大火炒散炒粒", "锅边淋生抽,盐调味,撒葱花"] });
  }
}
// 粥
for (const vid of C.congee) {
  push({ name: `${nameOf(vid)}粥`, cui: "jiachang", iconT: "rice", time: 45, serves: 2,
    kcal: (kc("dami", 100) + kc(vid, 150)) / 2 + 30,
    tags: ["主食", "早餐", "养胃"],
    ing: [{ id: "dami", q: "1杯" }, { id: vid, q: "适量" }],
    sea: ["bingtang"],
    steps: ["米淘净,加8倍水大火烧开", `${nameOf(vid)}${prepOf(vid)}下锅`, "转小火熬30分钟到开花黏稠", "按口味加一点冰糖"] });
}

// ———— 7. 砂锅煲 / 双素合炒 / 烤箱 / 卤味 / 蒸蛋 ————————————————————
for (const meat of C.stewMeat) {
  for (const vid of C.stewVeg) {
    if (BAD_PAIR.has(`${vid}|${meat.id}`)) continue;
    push({ name: `${nameOf(vid)}${meat.noun}煲`, cui: "yue", iconT: "pot", time: 55, serves: 3,
      kcal: (kc(meat.id, 450) + kcD(vid, 350) + 130) / 3 * 1.6,
      tags: ["砂锅", "硬菜"],
      ing: [{ id: meat.id, q: "450克" }, { id: vid, q: "350克" }],
      sea: ["jiang", "dasuan", "haoyou", "shengchou", "baihujiao", "shiyongyou"],
      steps: [`${meat.noun}${meat.prep}`, "砂锅爆香姜蒜,下肉煸出香", `码入${nameOf(vid)},蚝油生抽加热水至没过一半`, "盖盖小火煲25分钟,开盖撒葱"] });
  }
}
const DUO_VEG = ["tudou", "qingjiao", "huluobo", "muer", "shanyao", "xilanhua", "huacai", "lianou", "xihulu", "douya", "qincai", "xianggu", "jinzhengu", "yangcong", "huanggua", "doujiao"];
for (let i = 0; i < DUO_VEG.length; i++) {
  for (let j = i + 1; j < DUO_VEG.length; j++) {
    const a = DUO_VEG[i], b = DUO_VEG[j];
    if (BAD_PAIR.has(`${a}|${b}`)) continue;
    for (const fk of ["jiachang", "chuan"]) {
      const f = FLAVORS[fk];
      push({ name: `${f.pre}${nameOf(a)}炒${nameOf(b)}`, cui: fk, iconT: "wok", time: 12, serves: 2,
        kcal: (kcD(a, 200) + kcD(b, 200) + 110) / 2 + f.kick,
        tags: ["素菜", "快手"],
        ing: [{ id: a, q: "200克" }, { id: b, q: "200克" }],
        sea: [...new Set(f.sea)].slice(0, 7),
        steps: [`${nameOf(a)}${prepOf(a)};${nameOf(b)}${prepOf(b)}`, "热锅凉油,蒜片炝锅", f.extra, "先下难熟的翻炒,再下易熟的,断生调味"] });
    }
  }
}
const ROAST = ["jichi", "jitui", "yangpai", "sanwenyu", "jiweixia", "tudou", "yumi", "qiezi", "jinzhengu", "xingbaogu", "huacai", "nangua"];
for (const rid of ROAST) {
  push({ name: `孜然烤${nameOf(rid)}`, cui: "xibei", iconT: "wok", time: 35, serves: 2,
    kcal: (kc(rid, 300) + 90) / 2,
    tags: ["烤箱", "解馋"],
    ing: [{ id: rid, q: "300克" }],
    sea: ["ziranfen", "ganlajiao", "yan", "shiyongyou", "dasuan"],
    steps: [`${nameOf(rid)}${prepOf(rid)},用油盐蒜末抓匀腌20分钟`, "烤箱200度预热", "平铺烤盘烤15-20分钟,中途翻面", "出炉趁热撒孜然和辣椒面"] });
  push({ name: `蜜汁烤${nameOf(rid)}`, cui: "yue", iconT: "wok", time: 35, serves: 2,
    kcal: (kc(rid, 300) + 140) / 2,
    tags: ["烤箱", "甜口"],
    ing: [{ id: rid, q: "300克" }],
    sea: ["fengmi", "shengchou", "liaojiu", "jiang", "dasuan"],
    steps: [`${nameOf(rid)}${prepOf(rid)},生抽料酒姜蒜腌30分钟`, "烤箱190度预热,烤15分钟", "刷一层蜂蜜再烤5分钟上色", "出炉再刷一次蜜,亮晶晶开吃"] });
}
for (const lid of ["jidan", "dougan", "jizhua", "yatui", "niunan", "haidai", "doupi", "anchundan", "huasheng"].filter((x) => byId[x])) {
  push({ name: `卤${nameOf(lid)}`, cui: "lu", iconT: "pot", time: 60, serves: 3,
    kcal: kc(lid, 250) / 1.5 + 60,
    tags: ["卤味", "下酒"],
    ing: [{ id: lid, q: "400克" }],
    sea: ["bajiao", "jiang", "dacong", "shengchou", "laochou", "bingtang", "liaojiu", "yan"],
    steps: [`${nameOf(lid)}处理干净,需要焯水的先焯水`, "糖色炒到琥珀,加开水、八角葱姜和生抽老抽成卤水", "下主料小火卤30-40分钟", "关火再浸泡1小时更入味"] });
}
for (const sid of ["xiaren", "hage", "shanbei", "zhuroumo", "xianggu"]) {
  push({ name: `${nameOf(sid)}蒸蛋`, cui: "jiachang", iconT: "steam", time: 18, serves: 2,
    kcal: (kc("jidan", 150) + kc(sid, 80) + 40) / 2,
    tags: ["清淡", "嫩滑"],
    ing: [{ id: "jidan", q: "3个" }, { id: sid, q: "80克" }],
    sea: ["yan", "xiangyou", "shengchou", "xiaocong"],
    steps: ["鸡蛋加1.5倍温水和盐打匀过筛", "盖保鲜膜扎孔,水开中火蒸8分钟", `铺${nameOf(sid)}再蒸3-4分钟`, "淋生抽香油,撒葱花"] });
}

// ———— 8. 凉菜双拼 / 老醋系 ————————————————————————————————————
const COLD_BASE = ["huanggua", "muer", "fentiao", "doupi", "jinzhengu", "bocai", "douya", "bailuobo", "qincai", "lianou", "haidai", "youmaicai"];
const COLD_MATE = [["dougan", "豆干"], ["huashengmi", "花生"], ["pidan", "皮蛋"], ["jidan", "鸡蛋丝"], ["xiaren", "虾仁"], ["yangcong", "洋葱"]];
for (const base of COLD_BASE) {
  for (const [mid, mn] of COLD_MATE) {
    if (base === mid || BAD_PAIR.has(`${base}|${mid}`)) continue;
    push({ name: `${nameOf(base)}拌${mn}`, cui: "jiachang", iconT: "cold", time: 14, serves: 2,
      kcal: (kcD(base, 200) + kc(mid, 100) + 90) / 2,
      tags: ["凉菜", "开胃"],
      ing: [{ id: base, q: "200克" }, { id: mid, q: "100克" }],
      sea: ["dasuan", "xiangcu", "shengchou", "baitang", "xiangyou", "lajiangjiang"],
      steps: [`${nameOf(base)}${prepOf(base)},焯熟过凉攥干`, `${mn}处理好切条/切块`, "蒜末+醋+生抽+糖+香油调汁,嗜辣加辣酱", "全部拌匀,冷藏10分钟更爽口"] });
  }
}
for (const vid of ["huashengmi", "muer", "lianou", "bocai", "haidai", "jinzhengu", "doupi", "bailuobo"]) {
  push({ name: `老醋${nameOf(vid)}`, cui: "lu", iconT: "cold", time: 12, serves: 2,
    kcal: (kcD(vid, 220) + 100) / 2,
    tags: ["凉菜", "下酒"],
    ing: [{ id: vid, q: "220克" }],
    sea: ["xiangcu", "shengchou", "baitang", "dasuan", "xiangyou", "xiangcai"],
    steps: [`${nameOf(vid)}${prepOf(vid)},需要焯水的焯熟过凉`, "三勺陈醋一勺生抽半勺糖,蒜末香菜调成老醋汁", "食材入汁抓匀", "腌5分钟,酸香开胃"] });
}

// ———— 校验 & 落盘 ————————————————————————————————————————————
const ids = new Set();
for (const r of out) {
  if (ids.has(r.id)) throw new Error("dup id " + r.id);
  ids.add(r.id);
  for (const i of r.ing) if (!byId[i.id]) throw new Error(`${r.name} 主料不存在 ${i.id}`);
  for (const s of r.sea) if (!byId[s]) throw new Error(`${r.name} 调料不存在 ${s}`);
  if (r.steps.length < 3) throw new Error(`${r.name} 步骤过少`);
}
const total = out.length + hand.recipes.length;
console.log(`generated: ${out.length}, handcrafted: ${hand.recipes.length}, total: ${total}`);
const dist = {};
for (const r of out) dist[r.cui] = (dist[r.cui] ?? 0) + 1;
console.log(dist);
if (total < 10000) throw new Error(`总数 ${total} < 10000,扩充类别或方法`);
fs.writeFileSync(path.join(root, "Chaimi/Resources/recipes_gen.json"), JSON.stringify({ recipes: out }));
console.log("wrote recipes_gen.json", (fs.statSync(path.join(root, "Chaimi/Resources/recipes_gen.json")).size / 1048576).toFixed(2) + "MB");
