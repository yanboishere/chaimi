// gen-recipes.mjs — 组合菜谱生成器(真实性优先版)
// 原则:
//  1. 不造菜系前缀伪名(没有「川味XX面」):菜系只写进 cui 字段,不进菜名
//  2. 组合命名只用中餐通用句式(A炒B/A炖B/蒜蓉X/X汤…),搭配矩阵按现实收紧
//  3. 面/饭类不做叉乘,使用逐条核对的真实菜单
//  4. 每个模式桶均经网络抽样验证(见 README);搜不到攻略的桶不会出现在这里
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

const kc = (id, g) => (kcalOf(id) * g) / 100;
const DRY = new Set(["fentiao", "fuzhu", "muer", "yiner", "haidai", "zicai"]);
const kcD = (id, g) => kc(id, DRY.has(id) ? Math.min(g, 80) : g);

const prepOf = (id) => {
  if (["bocai", "youmaicai", "xiaobaicai", "jiucai", "qincai", "xiangcai", "shengcai", "dabaicai", "yuanbaicai", "suantai"].includes(id)) return "洗净切段";
  if (["xianggu", "xingbaogu", "pinggu", "koumo"].includes(id)) return "切片";
  if (id === "muer" || id === "yiner") return "提前泡发撕小朵";
  if (["tudou", "shanyao", "lianou", "huluobo", "bailuobo", "yutou", "hongshu"].includes(id)) return "去皮切片";
  if (["donggua", "nangua", "xihulu", "sigua", "kugua", "huanggua"].includes(id)) return "去瓤切块";
  if (["qingjiao", "xianjiao", "yangcong"].includes(id)) return "切块";
  if (["doujiao", "jiangdou", "helandou"].includes(id)) return "撕筋掰段";
  if (id === "fentiao" || id === "fuzhu") return "温水泡软";
  if (["nendoufu", "laodoufu", "doupi", "dougan"].includes(id)) return "切块";
  return "处理干净切好";
};

// 全量取证处置单(见 tools/rename-map.json 与 README):
//  renames — 在线验证 ≥10 攻略的规范名;blocked — 无可救名的淘汰菜,落盘前过滤(不动 serial);
//  removedHand — 取证未过线而从 recipes.json 删除的手写菜,继续占位防同名生成菜顶替复活
const MAP = JSON.parse(fs.readFileSync(path.join(here, "rename-map.json"), "utf8"));
const used = new Set([...hand.recipes.map((r) => r.name), ...MAP.removedHand]);
const out = [];
let serial = 0;
const PALETTE = 8;
function push({ name, cui, iconT, time, serves, kcal, tags, ing, sea, steps }) {
  name = MAP.renames[name]?.to ?? name;
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

// ———— 1. 单主料经典做法 ————————————————————————————————————————
const SINGLES = [
  { n: (x) => `蒜蓉${x}`, pool: ["bocai", "youmaicai", "xiaobaicai", "dabaicai", "sigua", "xilanhua", "jinzhengu", "huacai"], cui: "yue", icon: "wok", t: 12, sea: ["dasuan", "haoyou", "yan", "shiyongyou"], tag: ["素菜", "快手"],
    steps: (x, p) => [`${x}${p},焯水半分钟捞出`, "多切点蒜末,小火煸到微黄出香", `下${x}转大火快炒`, "蚝油和盐调味,淋一点热油出锅"] },
  { n: (x) => `清炒${x}`, pool: ["bocai", "youmaicai", "xiaobaicai", "douya", "helandou", "xihulu", "sigua", "shanyao", "lianou", "shengcai"], cui: "jiachang", icon: "wok", t: 10, sea: ["dasuan", "yan", "shiyongyou"], tag: ["素菜", "快手", "低脂"],
    steps: (x, p) => [`${x}${p}`, "热锅凉油,蒜片爆香", `下${x}大火快炒断生`, "少许盐调味,脆嫩即出"] },
  { n: (x) => `凉拌${x}`, pool: ["huanggua", "muer", "doupi", "fuzhu", "jinzhengu", "bocai", "qincai", "douya", "haidai", "fentiao", "lianou", "xilanhua"], cui: "jiachang", icon: "cold", t: 12, sea: ["dasuan", "xiangcu", "shengchou", "baitang", "xiangyou", "lajiangjiang"], tag: ["凉菜", "开胃"],
    steps: (x, p) => [`${x}${p},焯熟过凉水攥干`, "蒜末、醋、生抽、糖、香油调成料汁,嗜辣加一勺辣酱", `浇在${x}上拌匀`, "冷藏10分钟更入味"] },
  { n: (x) => `干煸${x}`, pool: ["doujiao", "huacai", "xingbaogu", "kugua"], cui: "chuan", icon: "wok", t: 20, sea: ["ganlajiao", "huajiao", "dasuan", "shengchou", "yan", "shiyongyou"], tag: ["素菜", "下饭"],
    steps: (x, p) => [`${x}${p},擦干水分`, "中火多油煸到表面起皱微焦,盛出", "底油下干辣椒花椒蒜末炝锅", `回${x},生抽和盐调味,大火翻匀`] },
  { n: (x) => `红烧${x}`, pool: ["qiezi", "tudou", "laodoufu", "donggua", "xianggu", "daiyu", "huanghuayu", "caoyu"], cui: "jiachang", icon: "wok", t: 25, sea: ["dasuan", "jiang", "shengchou", "laochou", "baitang", "dianfen", "shiyongyou"], tag: ["下饭"],
    steps: (x, p, isFish) => [isFish ? `${x}收拾干净,两面煎至金黄` : `${x}${p},过油煎香`, "爆香蒜姜,调入生抽老抽和一勺糖", "加小半碗水烧开,焖3-5分钟", "大火收汁,淀粉水勾薄芡"] },
  { n: (x) => `清蒸${x}`, pool: ["huanghuayu", "caoyu", "xueyu", "shanbei", "jiweixia"], cui: "yue", icon: "steam", t: 18, sea: ["zhengyuchiyou", "jiang", "xiaocong", "liaojiu", "shiyongyou"], tag: ["清淡", "快手"],
    steps: (x) => [`${x}收拾干净,抹料酒铺姜片腌10分钟`, "水开上锅,大火蒸8-10分钟", "倒掉腥水,铺姜丝葱丝,淋蒸鱼豉油", "烧一勺热油浇在葱丝上激香"] },
  { n: (x) => `椒盐${x}`, pool: ["xiaren", "youyu", "xingbaogu", "laodoufu"], cui: "yue", icon: "wok", t: 22, sea: ["yan", "baihujiao", "dasuan", "dianfen", "shiyongyou", "xianjiao"], tag: ["下酒", "香酥"],
    steps: (x, p) => [`${x}${p},拍薄淀粉`, "六成油温炸到金黄捞出,升温复炸30秒", "底油爆香蒜末和青椒碎", `回${x},撒椒盐(盐+白胡椒)颠匀`] },
  { n: (x) => `糖醋${x}`, pool: ["lianou", "daiyu"], cui: "lu", icon: "wok", t: 22, sea: ["baitang", "xiangcu", "shengchou", "fanqiejiang", "dianfen", "shiyongyou"], tag: ["酸甜", "开胃"],
    steps: (x, p) => [`${x}${p},拍淀粉煎到两面金黄`, "糖醋汁:2勺糖3勺醋2勺生抽1勺番茄酱半碗水", "倒入汁小火熬到冒大泡", `回${x}快速裹匀亮汁`] },
  { n: (x) => `剁椒蒸${x}`, pool: ["huanghuayu", "caoyu", "jinzhengu", "laodoufu"], cui: "xiang", icon: "steam", t: 20, sea: ["lajiangjiang", "dasuan", "jiang", "zhengyuchiyou", "shiyongyou"], tag: ["下饭", "湘味"],
    steps: (x, p) => [`${x}${p},铺盘底`, "蒜末与剁椒酱拌匀,厚厚铺满表面", "水开大火蒸10分钟", "撒葱花,浇热油激香,淋豉油"] },
  { n: (x) => `白灼${x}`, pool: ["jiweixia", "shengcai", "youmaicai"], cui: "yue", icon: "cold", t: 10, sea: ["shengchou", "jiang", "xiaocong", "shiyongyou", "baitang"], tag: ["清淡", "快手"],
    steps: (x) => [`${x}洗净,水开下锅烫熟即捞`, "姜丝葱丝铺面", "生抽加一点糖和两勺热水调成豉汁淋上", "热油一浇即可"] },
  { n: (x) => `香煎${x}`, pool: ["sanwenyu", "xueyu", "niupai", "jixiongrou", "laodoufu"], cui: "jiachang", icon: "wok", t: 15, sea: ["yan", "heihujiao", "dasuan", "shiyongyou"], tag: ["低脂", "快手"],
    steps: (x) => [`${x}擦干,两面抹盐和黑胡椒腌10分钟`, "平底锅少油烧热,下锅后别急着翻", "一面定型金黄再翻面,各煎2-3分钟", "出锅静置1分钟再切"] },
  { n: (x) => `上汤${x}`, pool: ["bocai", "xiaobaicai", "youmaicai"], cui: "yue", icon: "soup", t: 15, sea: ["dasuan", "pidan", "huotui", "yan", "shiyongyou"], tag: ["汤菜", "清淡"],
    steps: (x, p) => [`${x}${p}`, "蒜瓣煎金黄,加开水煮出奶白", "下皮蛋丁火腿丁滚1分钟", `下${x}煮软,盐调味连汤上桌`] },
  { n: (x) => `酱爆${x}`, pool: ["jixiongrou", "youyu", "dougan"], cui: "lu", icon: "wok", t: 15, sea: ["tianmianjiang", "jiang", "dacong", "baitang", "liaojiu", "shiyongyou"], tag: ["下饭", "酱香"],
    steps: (x, p) => [`${x}${p}`, "甜面酱加一点糖和料酒调开", "热油爆香葱姜,下主料炒到八成熟", "倒入酱汁裹匀,酱香浓郁即出"] },
  { n: (x) => `孜然${x}`, pool: ["yangroujuan", "niuliji", "tudou", "xingbaogu"], cui: "xibei", icon: "wok", t: 15, sea: ["ziranfen", "ganlajiao", "yan", "shengchou", "shiyongyou", "yangcong"], tag: ["重口", "下饭"],
    steps: (x, p) => [`${x}${p}`, "大火热油快炒到边缘微焦", "下洋葱丝炒透明", "撒孜然粉辣椒碎,生抽调味,拌匀出锅"] },
];
const FISH_IDS = new Set(["daiyu", "huanghuayu", "caoyu", "luyu", "xueyu"]);
for (const m of SINGLES) {
  for (const id of m.pool) {
    if (!byId[id]) continue;
    const x = nameOf(id);
    push({ name: m.n(x), cui: m.cui, iconT: m.icon, time: m.t, serves: 2, kcal: (kc(id, 300) + 120) / 2,
      tags: m.tag, ing: [{ id, q: id === "jiweixia" ? "400克" : "300克" }],
      sea: m.sea.filter((s) => s !== id), steps: m.steps(x, prepOf(id), FISH_IDS.has(id)) });
  }
}

// ———— 2. 家常小炒:肉 × 真实搭配蔬菜 ————————————————————————————
const CHAO = [
  ["wuhuarou", "五花肉", "切薄片", ["qingjiao", "xianjiao", "suantai", "yuanbaicai", "lianou", "doujiao", "xingbaogu", "huacai", "kugua"]],
  ["zhuliji", "肉丝", "切丝,料酒淀粉抓匀", ["qingjiao", "suantai", "qincai", "douya", "muer", "huluobo", "jiangdou", "xianjiao", "yangcong", "doujiao", "jiucai", "dougan"]],
  ["niuliji", "牛肉", "逆纹切片,上浆", ["qingjiao", "qincai", "yangcong", "kugua", "xianjiao", "xilanhua", "xingbaogu", "suantai", "shanyao"]],
  ["feiniujuan", "肥牛", "散开备用", ["jinzhengu", "yangcong", "xianjiao"]],
  ["yangroujuan", "羊肉", "散开备用", ["yangcong", "xiangcai"]],
  ["jixiongrou", "鸡丁", "切丁腌10分钟", ["qingjiao", "huanggua", "xilanhua", "xingbaogu", "yumi", "xianjiao"]],
  ["jitui", "鸡腿肉", "去骨切块", ["qingjiao", "xianggu", "xianjiao", "yangcong"]],
  ["zhuroumo", "肉末", "备用", ["qiezi", "doujiao", "xianjiao", "jiangdou"]],
  ["peigen", "培根", "切段", ["helandou", "xingbaogu", "yangcong", "jinzhengu"]],
  ["xiangchang", "腊肠", "斜切薄片", ["helandou", "suantai", "xilanhua"]],
  ["huotui", "火腿", "切条", ["yumi", "huanggua"]],
  ["dougan", "香干", "切条", ["jiucai", "suantai", "xianjiao", "bocai"]],
]
for (const [mid, noun, cut, vegs] of CHAO) {
  for (const vid of vegs) {
    push({ name: `${nameOf(vid)}炒${noun}`, cui: "jiachang", iconT: "wok", time: 15, serves: 2,
      kcal: (kc(mid, 200) + kcD(vid, 200) + 130) / 2,
      tags: ["下饭", "快手"],
      ing: [{ id: vid, q: "250克" }, { id: mid, q: "200克" }],
      sea: ["dasuan", "jiang", "shengchou", "yan", "shiyongyou"],
      steps: [`${noun}${cut};${nameOf(vid)}${prepOf(vid)}`, `热油先滑炒${noun}至变色盛出`, `下${nameOf(vid)}大火炒断生`, `回${noun}合炒,生抽和盐调味出锅`] });
  }
}

// ———— 3. 烧 / 炖 / 汤 ————————————————————————————————————————
const SHAO = [
  ["niunan", "牛腩", "切块焯水", ["tudou", "bailuobo"]],
  ["zhupaigu", "排骨", "焯净浮沫", ["tudou", "lianou", "doujiao"]],
  ["jitui", "鸡腿", "剁块焯水", ["tudou", "xianggu"]],
  ["jichi", "鸡翅", "划刀焯水", ["tudou"]],
  ["yatui", "鸭腿", "剁块焯水", ["tudou", "xianggu"]],
  ["wuhuarou", "五花肉", "切块焯水", ["dongdoufu", "dabaicai", "fentiao"]],
];
for (const [mid, noun, prep, vegs] of SHAO) {
  for (const vid of vegs) {
    push({ name: `${noun}烧${nameOf(vid)}`, cui: "jiachang", iconT: "wok", time: 40, serves: 2,
      kcal: (kc(mid, 350) + kcD(vid, 300) + 120) / 2,
      tags: ["下饭", "硬菜"],
      ing: [{ id: mid, q: "400克" }, { id: vid, q: "300克" }],
      sea: ["jiang", "dacong", "shengchou", "laochou", "baitang", "liaojiu", "shiyongyou"],
      steps: [`${noun}${prep}`, "热油煸香葱姜,下肉炒上色,烹料酒", "生抽老抽糖调味,加开水没过,中火烧20分钟", `下${nameOf(vid)}再烧10-15分钟,收浓汤汁`] });
  }
}
const DUN = [
  ["zhupaigu", "排骨", "冷水下锅焯净浮沫", ["yumi", "lianou", "shanyao", "haidai", "bailuobo", "donggua", "huluobo"]],
  ["niunan", "牛腩", "切块焯水", ["bailuobo", "tudou"]],
  ["yangpai", "羊排", "焯水去膻", ["bailuobo", "huluobo"]],
  ["jitui", "鸡腿", "剁块焯水", ["xianggu", "shanyao", "tudou"]],
  ["sanhuangji", "老母鸡", "剁块焯水", ["shanyao", "xianggu", "yiner"]],
  ["yatui", "鸭腿", "剁块焯水", ["donggua", "shanyao"]],
];
for (const [mid, noun, prep, vegs] of DUN) {
  for (const vid of vegs) {
    push({ name: `${nameOf(vid)}炖${noun}`, cui: "jiachang", iconT: "pot", time: 70, serves: 3,
      kcal: (kc(mid, 450) + kcD(vid, 350) + 90) / 3,
      tags: ["炖菜", "汤", "滋补"],
      ing: [{ id: mid, q: "450克" }, { id: vid, q: "350克" }],
      sea: ["jiang", "dacong", "liaojiu", "yan", "baihujiao"],
      steps: [`${noun}${prep}`, "砂锅加足量开水和姜葱,小火炖40分钟", `下${nameOf(vid)}再炖20分钟`, "盐和白胡椒调味"] });
  }
}
const SOUPS = [
  ["fanqie", "jidan", "番茄鸡蛋汤", ["番茄去皮切块炒出沙", "加开水煮2分钟", "淋入蛋液成蛋花", "盐和香油调味,撒葱花"]],
  ["sigua", "jidan", "丝瓜蛋汤", ["丝瓜去皮切块", "少油微煸,加开水煮3分钟", "淋蛋液成花", "盐调味,滴香油"]],
  ["dabaicai", "nendoufu", "白菜豆腐汤", ["白菜切段,豆腐切块", "汤锅加水烧开,先下豆腐煮5分钟", "下白菜煮软", "盐白胡椒调味"]],
  ["jinzhengu", "nendoufu", "菌菇豆腐汤", ["金针菇去根撕开,豆腐切块", "水开下锅同煮5分钟", "调味后勾一点薄芡", "撒葱花"]],
  ["haidai", "nendoufu", "海带豆腐汤", ["海带结洗净,豆腐切块", "加姜片和开水煮10分钟", "下豆腐再煮5分钟", "盐调味"]],
  ["bailuobo", "yuwan", "萝卜鱼丸汤", ["白萝卜切丝", "水开下萝卜丝煮软", "下鱼丸煮到浮起", "盐白胡椒调味,撒葱花"]],
];
for (const [a, b, name, steps] of SOUPS) {
  push({ name, cui: "jiachang", iconT: "soup", time: 15, serves: 2,
    kcal: (kcD(a, 250) + kc(b, 150) + 40) / 2,
    tags: ["汤", "快手", "清淡"],
    ing: [{ id: a, q: "250克" }, { id: b, q: "150克" }],
    sea: ["yan", "xiangyou", "baihujiao", "xiaocong"], steps });
}

// ———— 4. 海鲜小炒 + 特色 ————————————————————————————————————————
const SEAFOOD = [
  ["xiaren", "虾仁", ["xilanhua", "huanggua", "qincai", "helandou", "yumi", "jiucai"]],
  ["jiweixia", "大虾", ["xilanhua", "qincai"]],
  ["youyu", "鱿鱼", ["jiucai", "yangcong", "qingjiao", "xianjiao"]],
];
for (const [sid, noun, vegs] of SEAFOOD) {
  for (const vid of vegs) {
    push({ name: `${nameOf(vid)}炒${noun}`, cui: "jiachang", iconT: "wok", time: 14, serves: 2,
      kcal: (kc(sid, 250) + kcD(vid, 200) + 110) / 2,
      tags: ["快手", "鲜"],
      ing: [{ id: sid, q: "250克" }, { id: vid, q: "200克" }],
      sea: ["jiang", "dasuan", "liaojiu", "yan", "shiyongyou"],
      steps: [`${noun}处理干净,料酒姜丝腌5分钟`, `${nameOf(vid)}${prepOf(vid)}`, `热油先下${noun}大火快炒至变色盛出`, `下${nameOf(vid)}炒断生,回锅合炒,盐调味`] });
  }
}
push({ name: "辣炒花蛤", cui: "xiang", iconT: "wok", time: 15, serves: 2, kcal: 220,
  tags: ["下酒", "鲜辣"], ing: [{ id: "hage", q: "500克" }],
  sea: ["xiaomila", "dasuan", "jiang", "doubanjiang", "liaojiu", "shiyongyou", "xiaocong"],
  steps: ["花蛤吐沙洗净,焯水至开口捞出", "爆香蒜姜小米辣和一勺豆瓣酱", "倒入花蛤大火翻炒", "烹料酒,撒葱段出锅"] });
push({ name: "蒜蓉粉丝蒸扇贝", cui: "yue", iconT: "steam", time: 20, serves: 2, kcal: 240,
  tags: ["宴客", "鲜"], ing: [{ id: "shanbei", q: "8只" }, { id: "fentiao", q: "1小把" }],
  sea: ["dasuan", "shengchou", "shiyongyou", "xiaocong"],
  steps: ["扇贝刷净开壳,粉丝泡软垫底", "金银蒜(一半生一半炸)铺在贝肉上", "水开大火蒸6分钟", "淋生抽热油,撒葱花"] });
push({ name: "葱姜炒蟹", cui: "yue", iconT: "wok", time: 20, serves: 2, kcal: 260,
  tags: ["硬菜", "宴客"], ing: [{ id: "pangxie", q: "2只" }],
  sea: ["dacong", "jiang", "liaojiu", "shengchou", "dianfen", "shiyongyou", "baitang"],
  steps: ["蟹处理干净斩块,切口拍淀粉", "热油把蟹块煎到定壳", "下大量葱段姜片爆香", "烹料酒生抽少许糖,加盖焖2分钟"] });

// ———— 5. 蛋与豆腐 ————————————————————————————————————————————
for (const vid of ["jiucai", "huanggua", "kugua", "yangcong", "sigua", "qingjiao", "xihulu", "muer", "douya", "suantai", "xiaocong", "xiangchang"]) {
  push({ name: `${nameOf(vid)}炒蛋`, cui: "jiachang", iconT: "wok", time: 10, serves: 2,
    kcal: (kc("jidan", 150) + kcD(vid, 180) + 110) / 2,
    tags: ["快手", "家常"],
    ing: [{ id: vid, q: "200克" }, { id: "jidan", q: "3个" }],
    sea: ["yan", "shiyongyou"],
    steps: ["鸡蛋加盐打散,热油炒成大块盛出", `${nameOf(vid)}${prepOf(vid)},下锅炒断生`, "回鸡蛋合炒", "盐调味出锅"] });
}
const TOFU = [
  ["zhuroumo", "肉末", "laodoufu", "肉末烧豆腐", false],
  ["xianggu", "香菇", "laodoufu", "香菇烧豆腐", false],
  ["xiaren", "虾仁", "nendoufu", "虾仁豆腐", false],
  ["pidan", "皮蛋", "nendoufu", "皮蛋拌豆腐", true],
  ["xianyadan", "咸蛋黄", "nendoufu", "咸蛋黄豆腐", false],
  ["jinzhengu", "金针菇", "nendoufu", "金针菇烧豆腐", false],
];
for (const [mid, mn, tid, name, cold] of TOFU) {
  push({ name, cui: "jiachang", iconT: cold ? "cold" : "wok", time: cold ? 10 : 18, serves: 2,
    kcal: (kc(tid, 300) + kc(mid, 100) + 110) / 2,
    tags: cold ? ["凉菜", "快手"] : ["下饭", "豆香"],
    ing: [{ id: tid, q: "1盒" }, { id: mid, q: "100克" }],
    sea: cold ? ["shengchou", "xiangcu", "xiangyou", "xiaocong", "lajiangjiang"] : ["dasuan", "shengchou", "haoyou", "dianfen", "shiyongyou", "xiaocong"],
    steps: cold
      ? ["豆腐切块摆盘,皮蛋切瓣", "生抽香醋香油调汁", "浇汁,嗜辣加辣酱", "撒葱花开吃"]
      : [`豆腐切块,盐水焯1分钟`, `${mn}煸炒出香`, "加生抽蚝油和小半碗水,下豆腐轻推焖2分钟", "淀粉水勾芡,撒葱花"] });
}

// ———— 6. 面 / 饭 / 粥(逐条核对的真实菜单)————————————————————————
const NOODLE_MENU = [
  ["番茄鸡蛋面", ["fanqie", "jidan", "xianmian"], ["yan", "shiyongyou", "xiaocong"], "汤", ["番茄炒出沙加开水", "下面条煮熟", "淋蛋液成花", "盐调味撒葱花"]],
  ["青椒肉丝面", ["qingjiao", "zhuliji", "xianmian"], ["shengchou", "dianfen", "shiyongyou", "yan"], "拌", ["肉丝上浆滑炒,下青椒丝合炒", "生抽调味成浇头", "面条煮熟捞出", "浇头盖面拌匀"]],
  ["红烧牛肉面", ["niunan", "xiaobaicai", "xianmian"], ["doubanjiang", "jiang", "bajiao", "shengchou", "laochou", "bingtang"], "汤", ["牛腩焯水,炒糖色加豆瓣酱炒香", "加开水炖60分钟成红汤", "面条煮熟,烫两棵青菜", "浇牛肉和汤"]],
  ["香菇鸡丝面", ["xianggu", "jixiongrou", "guamian"], ["jiang", "yan", "baihujiao", "xiangyou"], "汤", ["鸡胸煮熟撕丝,香菇切片", "姜片香菇煮出鲜汤", "下挂面煮熟", "码鸡丝,盐白胡椒调味"]],
  ["炸酱面", ["zhuroumo", "huanggua", "xianmian"], ["tianmianjiang", "dacong", "jiang", "baitang", "shiyongyou"], "拌", ["肉末煸出油", "下甜面酱小火熬出酱香", "面条煮熟过凉", "浇炸酱,码黄瓜丝拌匀"]],
  ["麻酱拌面", ["xianmian", "huanggua"], ["zhimajiang", "shengchou", "xiangcu", "dasuan", "xiangyou"], "拌", ["麻酱用温水澥开,加生抽醋蒜末", "面条煮熟过凉", "浇麻酱汁", "码黄瓜丝拌匀"]],
  ["酸汤肥牛面", ["feiniujuan", "jinzhengu", "guamian"], ["xiaomila", "dasuan", "jiang", "baicu", "yan"], "汤", ["蒜姜小米辣炒香,加开水和白醋成酸汤", "下金针菇煮软", "下面与肥牛卷烫熟", "连汤上桌"]],
  ["肉丝炒面", ["zhuliji", "yuanbaicai", "xianmian"], ["shengchou", "laochou", "dasuan", "shiyongyou"], "炒", ["面条煮八成熟过凉拌油", "肉丝滑炒,下包菜丝", "下面条大火颠炒", "生抽老抽调味上色"]],
  ["鸡蛋炒面", ["jidan", "douya", "xianmian"], ["shengchou", "yan", "xiaocong", "shiyongyou"], "炒", ["面条煮八成熟过凉", "鸡蛋炒散盛出", "豆芽快炒,下面条和鸡蛋", "调味颠匀"]],
  ["牛肉炒米粉", ["niuliji", "douya", "mifen"], ["shengchou", "laochou", "dasuan", "shiyongyou"], "炒", ["米粉泡软", "牛肉上浆滑炒", "下豆芽和米粉大火快炒", "生抽老抽调味"]],
  ["肉丝汤米粉", ["zhuliji", "xiaobaicai", "mifen"], ["jiang", "yan", "baihujiao", "xiangyou"], "汤", ["清水加姜烧开", "下米粉煮软", "滑炒肉丝码面上", "烫青菜,调味"]],
  ["蚂蚁上树", ["zhuroumo", "fentiao"], ["doubanjiang", "jiang", "dasuan", "shengchou", "xiaocong", "shiyongyou"], "炒", ["粉条温水泡软", "肉末煸香,下豆瓣酱炒出红油", "下粉条和小半碗水焖干", "撒葱花"]],
  ["番茄肉酱意面", ["fanqie", "zhuroumo", "yidalimian"], ["fanqiejiang", "yangcong", "dasuan", "heihujiao", "yan", "ganlanyou"], "拌", ["意面煮8分钟留面水", "洋葱蒜末炒香,下肉末炒散", "下番茄丁和番茄酱熬浓", "拌入意面,黑胡椒调味"]],
  ["蒜香虾仁意面", ["xiaren", "yidalimian"], ["dasuan", "ganlanyou", "yan", "heihujiao", "xianjiao"], "拌", ["意面煮熟", "橄榄油煸香蒜片和辣椒", "下虾仁炒变色", "拌面,盐黑胡椒调味"]],
];
for (const [name, ings, sea, style, steps] of NOODLE_MENU) {
  push({ name, cui: "jiachang", iconT: "noodle", time: style === "汤" ? 25 : 16, serves: 1,
    kcal: ings.reduce((s, id) => s + kcD(id, ["xianmian", "guamian", "mifen", "fentiao", "yidalimian"].includes(id) ? 110 : 90), 0) + 120,
    tags: ["主食", style === "炒" ? "锅气" : "快手"],
    ing: ings.map((id) => ({ id, q: ["xianmian", "guamian", "mifen", "fentiao", "yidalimian"].includes(id) ? "1人份" : "适量" })),
    sea, steps });
}
const RICE_MENU = [
  ["黄焖鸡米饭", ["jitui", "xianggu", "qingjiao", "dami"], ["jiang", "dasuan", "shengchou", "laochou", "haoyou", "bingtang"], ["鸡腿剁块焯水", "爆香姜蒜,下鸡块与香菇炒上色", "生抽老抽蚝油加水焖20分钟,下青椒", "连汁配米饭"]],
  ["卤肉饭", ["wuhuarou", "jidan", "dami"], ["jiang", "dacong", "shengchou", "laochou", "bingtang", "wuxiangfen"], ["五花肉切小丁煸出油", "炒糖色,下五香粉生抽老抽", "加水和卤蛋小火卤40分钟", "浇在热米饭上"]],
  ["咖喱鸡肉饭", ["jitui", "tudou", "huluobo", "yangcong", "dami"], ["galikuai", "shiyongyou"], ["鸡腿切块煎香", "下土豆胡萝卜洋葱翻炒", "加水煮10分钟,放咖喱块化开熬浓", "浇饭"]],
  ["咖喱牛腩饭", ["niunan", "tudou", "yangcong", "dami"], ["galikuai", "jiang", "shiyongyou"], ["牛腩焯水炖40分钟", "下土豆洋葱再煮10分钟", "放咖喱块化开熬浓", "浇饭"]],
  ["扬州炒饭", ["dami", "jidan", "xiaren", "huotui"], ["xiaocong", "yan", "shiyongyou"], ["虾仁火腿切丁备好", "蛋液裹匀隔夜饭", "大火把饭炒散,下配料", "盐调味,撒葱花"]],
  ["酱油炒饭", ["dami", "jidan"], ["shengchou", "laochou", "xiaocong", "shiyongyou", "baitang"], ["隔夜饭打散", "鸡蛋炒散,下饭合炒", "沿锅边淋生抽老抽", "撒葱花,镬气十足"]],
  ["腊肠炒饭", ["xiangchang", "jidan", "dami"], ["xiaocong", "shengchou", "shiyongyou"], ["腊肠切丁小火煸出油", "下蛋液和隔夜饭炒散", "生抽调味", "撒葱花"]],
  ["虾仁蛋炒饭", ["xiaren", "jidan", "dami"], ["xiaocong", "yan", "shiyongyou"], ["虾仁腌5分钟滑油", "鸡蛋炒散下饭", "回虾仁合炒", "盐调味撒葱"]],
  ["南瓜粥", ["nangua", "dami"], ["bingtang"], ["南瓜去皮切块", "与米同煮30分钟", "搅到南瓜融化", "按口味加冰糖"]],
  ["小米粥", ["xiaomi"], ["bingtang"], ["小米淘净", "水开下锅", "小火熬25分钟出米油", "可加冰糖"]],
  ["红薯粥", ["hongshu", "dami"], ["bingtang"], ["红薯去皮切块", "与米同煮", "熬30分钟软糯", "原味即甜"]],
  ["绿豆粥", ["lvdou", "dami"], ["bingtang"], ["绿豆提前泡2小时", "与米同煮40分钟", "豆开花即可", "放凉更好喝"]],
  ["山药粥", ["shanyao", "dami"], ["bingtang"], ["山药去皮切丁", "与米同煮30分钟", "熬到绵软", "养胃早餐"]],
  ["玉米烙", ["yumi", "dianfen_x"], ["baitang", "shiyongyou", "dianfen"], ["玉米粒焯水沥干", "拌淀粉裹匀", "平底锅摊平小火煎定型", "撒糖出锅"]],
];
for (const [name, ings, sea, steps] of RICE_MENU) {
  const realIngs = ings.filter((id) => byId[id]);
  if (realIngs.length < 1) continue;
  const isChaofan = name.includes("炒饭");
  push({ name, cui: "jiachang", iconT: "rice", time: name.includes("粥") ? 40 : 30, serves: isChaofan ? 1 : 2,
    kcal: realIngs.reduce((s, id) => s + kcD(id, 120), 0) / (isChaofan ? 1 : 2) + 110,
    tags: ["主食", name.includes("粥") ? "早餐" : "一碗端"],
    ing: realIngs.map((id) => ({ id, q: "适量" })),
    sea: sea.filter((s) => byId[s]), steps });
}
const GAIFAN = [
  ["qingjiao", "zhuliji", "青椒肉丝盖饭"],
  ["fanqie", "jidan", "番茄鸡蛋盖饭"],
  ["tudou", "jitui", "土豆鸡块盖饭"],
  ["qiezi", "zhuroumo", "肉末茄子盖饭"],
  ["xianggu", "jixiongrou", "香菇滑鸡盖饭"],
  ["yangcong", "niuliji", "洋葱牛肉盖饭"],
  ["jinzhengu", "feiniujuan", "金针菇肥牛盖饭"],
];
for (const [a, b, name] of GAIFAN) {
  push({ name, cui: "jiachang", iconT: "rice", time: 18, serves: 1,
    kcal: kc(a, 120) + kc(b, 120) + kc("dami", 120) + 110,
    tags: ["主食", "一碗端"],
    ing: [{ id: a, q: "120克" }, { id: b, q: "120克" }, { id: "dami", q: "1碗" }],
    sea: ["shengchou", "haoyou", "dianfen", "dasuan", "shiyongyou"],
    steps: [`${nameOf(b)}处理好滑炒`, `下${nameOf(a)}合炒`, "生抽蚝油调味,淀粉水收成有汁浇头", "连汁浇在热米饭上"] });
}

// ———— 7. 凉菜双拼 / 老醋 / 卤 / 烤 / 蒸蛋 / 经典小菜 ——————————————————
const COLD_MIX = [
  ["huanggua", "dougan", "黄瓜拌豆干"],
  ["bocai", "huashengmi", "菠菜拌花生"],
  ["muer", "yangcong", "木耳拌洋葱"],
  ["huanggua", "fentiao", "黄瓜拌粉条"],
  ["doupi", "huanggua", "豆皮拌黄瓜"],
  ["qincai", "huashengmi", "芹菜拌花生米"],
  ["jinzhengu", "huanggua", "金针菇拌黄瓜"],
];
for (const [a, b, name] of COLD_MIX) {
  push({ name, cui: "jiachang", iconT: "cold", time: 14, serves: 2,
    kcal: (kcD(a, 200) + kc(b, 100) + 90) / 2,
    tags: ["凉菜", "开胃"],
    ing: [{ id: a, q: "200克" }, { id: b, q: "100克" }],
    sea: ["dasuan", "xiangcu", "shengchou", "baitang", "xiangyou", "lajiangjiang"],
    steps: [`${nameOf(a)}${prepOf(a)},焯熟过凉攥干`, `${nameOf(b)}处理好`, "蒜末+醋+生抽+糖+香油调汁", "全部拌匀,冷藏10分钟更爽口"] });
}
for (const vid of ["huashengmi", "muer", "haidai", "bocai", "lianou"]) {
  push({ name: `老醋${nameOf(vid)}`, cui: "lu", iconT: "cold", time: 12, serves: 2,
    kcal: (kcD(vid, 220) + 100) / 2,
    tags: ["凉菜", "下酒"],
    ing: [{ id: vid, q: "220克" }],
    sea: ["xiangcu", "shengchou", "baitang", "dasuan", "xiangyou", "xiangcai"],
    steps: [`${nameOf(vid)}${prepOf(vid)},需要焯水的焯熟过凉`, "三勺陈醋一勺生抽半勺糖,蒜末香菜调成老醋汁", "食材入汁抓匀", "腌5分钟,酸香开胃"] });
}
for (const lid of ["jidan", "dougan", "jizhua", "yatui", "niunan", "haidai", "doupi", "anchundan"]) {
  push({ name: `卤${nameOf(lid)}`, cui: "lu", iconT: "pot", time: 60, serves: 3,
    kcal: kc(lid, 250) / 1.5 + 60,
    tags: ["卤味", "下酒"],
    ing: [{ id: lid, q: "400克" }],
    sea: ["bajiao", "jiang", "dacong", "shengchou", "laochou", "bingtang", "liaojiu", "yan"],
    steps: [`${nameOf(lid)}处理干净,需要焯水的先焯水`, "糖色炒到琥珀,加开水、八角葱姜和生抽老抽成卤水", "下主料小火卤30-40分钟", "关火再浸泡1小时更入味"] });
}
for (const rid of ["jichi", "jitui", "yangpai", "jiweixia", "tudou", "yumi", "qiezi", "jinzhengu", "xingbaogu"]) {
  push({ name: `烤${nameOf(rid)}`, cui: "xibei", iconT: "wok", time: 35, serves: 2,
    kcal: (kc(rid, 300) + 90) / 2,
    tags: ["烤箱", "解馋"],
    ing: [{ id: rid, q: "300克" }],
    sea: ["ziranfen", "ganlajiao", "yan", "shiyongyou", "dasuan"],
    steps: [`${nameOf(rid)}${prepOf(rid)},用油盐蒜末抓匀腌20分钟`, "烤箱200度预热", "平铺烤盘烤15-20分钟,中途翻面", "出炉趁热撒孜然和辣椒面"] });
}
push({ name: "蜜汁烤鸡翅", cui: "yue", iconT: "wok", time: 40, serves: 2, kcal: 330,
  tags: ["烤箱", "甜口"], ing: [{ id: "jichi", q: "500克" }],
  sea: ["fengmi", "shengchou", "liaojiu", "jiang", "dasuan"],
  steps: ["鸡翅两面划刀,生抽料酒姜蒜腌30分钟", "烤箱190度预热,烤15分钟", "刷一层蜂蜜再烤5分钟上色", "出炉再刷一次蜜"] });
for (const sid of ["xiaren", "hage", "zhuroumo", "xianggu"]) {
  push({ name: `${nameOf(sid)}蒸蛋`, cui: "jiachang", iconT: "steam", time: 18, serves: 2,
    kcal: (kc("jidan", 150) + kc(sid, 80) + 40) / 2,
    tags: ["清淡", "嫩滑"],
    ing: [{ id: "jidan", q: "3个" }, { id: sid, q: "80克" }],
    sea: ["yan", "xiangyou", "shengchou", "xiaocong"],
    steps: ["鸡蛋加1.5倍温水和盐打匀过筛", "盖保鲜膜扎孔,水开中火蒸8分钟", `铺${nameOf(sid)}再蒸3-4分钟`, "淋生抽香油,撒葱花"] });
}
push({ name: "虎皮尖椒", cui: "jiachang", iconT: "wok", time: 15, serves: 2, kcal: 180,
  tags: ["素菜", "下饭"], ing: [{ id: "xianjiao", q: "8根" }],
  sea: ["dasuan", "shengchou", "xiangcu", "baitang", "shiyongyou"],
  steps: ["尖椒去蒂,干锅压烙出虎皮", "下油爆香蒜末", "调入生抽香醋糖", "焖1分钟收汁"] });
push({ name: "荷塘小炒", cui: "jiachang", iconT: "wok", time: 15, serves: 2, kcal: 160,
  tags: ["素菜", "清爽"], ing: [{ id: "lianou", q: "1节" }, { id: "helandou", q: "100克" }, { id: "muer", q: "1小把" }, { id: "huluobo", q: "半根" }],
  sea: ["dasuan", "yan", "shiyongyou", "dianfen"],
  steps: ["藕片胡萝卜片焯水,木耳泡发", "蒜片爆香", "全部食材大火快炒", "盐调味,薄芡收亮"] });
push({ name: "凉拌三丝", cui: "jiachang", iconT: "cold", time: 15, serves: 2, kcal: 140,
  tags: ["凉菜", "爽口"], ing: [{ id: "fentiao", q: "1把" }, { id: "huanggua", q: "1根" }, { id: "huluobo", q: "半根" }],
  sea: ["dasuan", "xiangcu", "shengchou", "baitang", "xiangyou", "lajiangjiang"],
  steps: ["粉条煮软过凉,黄瓜胡萝卜切丝", "蒜末调入醋生抽糖香油", "三丝入盆浇汁", "抓拌均匀"] });

// ———— 校验 & 落盘 ————————————————————————————————————————————
const BLOCKED = new Set(MAP.blocked);
const kept = out.filter((r) => !BLOCKED.has(r.name));
const ids = new Set();
for (const r of kept) {
  if (ids.has(r.id)) throw new Error("dup id " + r.id);
  ids.add(r.id);
  for (const i of r.ing) if (!byId[i.id]) throw new Error(`${r.name} 主料不存在 ${i.id}`);
  for (const s of r.sea) if (!byId[s]) throw new Error(`${r.name} 调料不存在 ${s}`);
  if (r.steps.length < 3) throw new Error(`${r.name} 步骤过少`);
  if (/[川湘粤鲁]味|^粤式|^东北.|^本帮|^葱香|^麻辣..炖/.test(r.name)) throw new Error(`伪菜系前缀: ${r.name}`);
}
const total = kept.length + hand.recipes.length;
console.log(`generated: ${out.length}, 取证淘汰: ${out.length - kept.length}, 保留: ${kept.length}, handcrafted: ${hand.recipes.length}, total: ${total}`);
const dist = {};
for (const r of kept) dist[r.cui] = (dist[r.cui] ?? 0) + 1;
console.log(dist);
fs.writeFileSync(path.join(root, "Chaimi/Resources/recipes_gen.json"), JSON.stringify({ recipes: kept }));
console.log("wrote recipes_gen.json", (fs.statSync(path.join(root, "Chaimi/Resources/recipes_gen.json")).size / 1024).toFixed(0) + "KB");
