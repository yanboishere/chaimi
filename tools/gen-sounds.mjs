// gen-sounds.mjs — 程序化合成老虎机音效(16-bit 44.1kHz mono WAV),无版权素材。
// 运行:node tools/gen-sounds.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.join(here, "..", "Chaimi", "Resources");
const SR = 44100;

function writeWav(file, samples) {
  const n = samples.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write("RIFF", 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write("WAVE", 8);
  buf.write("fmt ", 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22); buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 2, 28);
  buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write("data", 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    buf.writeInt16LE((v * 32760) | 0, 44 + i * 2);
  }
  fs.writeFileSync(path.join(outDir, file), buf);
  console.log(file, (buf.length / 1024).toFixed(1) + "KB");
}

const sec = (s) => Math.floor(s * SR);
function mix(target, src, at, gain = 1) {
  const o = sec(at);
  for (let i = 0; i < src.length && o + i < target.length; i++) target[o + i] += src[i] * gain;
}
// 简短"嗒":高频正弦 + 噪声,指数衰减
function tick(freq = 1900, dur = 0.03, noise = 0.35) {
  const n = sec(dur), out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR, env = Math.exp(-t * 90);
    out[i] = env * (Math.sin(2 * Math.PI * freq * t) * (1 - noise) + (Math.random() * 2 - 1) * noise);
  }
  return out;
}
// 低沉"咔哒"(停轮/机械落位)
function clack() {
  const n = sec(0.09), out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR, env = Math.exp(-t * 45);
    out[i] = env * (Math.sin(2 * Math.PI * 420 * t) * 0.7 + Math.sin(2 * Math.PI * 180 * t) * 0.5 + (Math.random() * 2 - 1) * 0.25);
  }
  return out;
}
// 铃"叮"
function bell(freqs = [1318, 1760], dur = 0.7) {
  const n = sec(dur), out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR, env = Math.exp(-t * 6);
    let v = 0;
    for (const f of freqs) v += Math.sin(2 * Math.PI * f * t) / freqs.length;
    out[i] = env * v;
  }
  return out;
}

// 1) 拉杆:两声棘轮咔 + 弹簧回弹闷响
{
  const out = new Float64Array(sec(0.42));
  mix(out, tick(1500, 0.025, 0.5), 0.0, 0.9);
  mix(out, tick(1300, 0.025, 0.5), 0.07, 0.9);
  mix(out, clack(), 0.16, 1.0);
  const n = sec(0.18), spring = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR, env = Math.exp(-t * 20);
    spring[i] = env * Math.sin(2 * Math.PI * (130 + 60 * Math.exp(-t * 18)) * t) * 0.8;
  }
  mix(out, spring, 0.2, 0.8);
  writeWav("slot_lever.wav", out);
}

// 2) 转轮:嗒嗒声由密到疏(与动画 easeOut 对齐),三声重音在 1.1 / 1.65 / 2.2s
{
  const total = 2.5;
  const out = new Float64Array(sec(total));
  const stops = [1.1, 1.65, 2.2];
  let t = 0, interval = 0.034;
  while (t < 2.2) {
    const gain = 0.55 - 0.25 * (t / 2.2);
    mix(out, tick(1700 + Math.random() * 500, 0.022, 0.45), t, gain);
    const progress = t / 2.2;
    interval = 0.034 + 0.12 * progress * progress;
    t += interval;
  }
  for (const s of stops) mix(out, clack(), s, 1.0);
  mix(out, bell([1046, 1568], 0.28), 2.21, 0.35);
  writeWav("slot_spin.wav", out);
}

// 3) 出票:打印机滋滋(门控噪声)+ 完成"叮-叮"
{
  const out = new Float64Array(sec(1.6));
  const dur = sec(0.85);
  for (let i = 0; i < dur; i++) {
    const t = i / SR;
    const gate = (Math.sin(2 * Math.PI * 26 * t) > -0.25) ? 1 : 0.12; // 步进马达
    out[i] += (Math.random() * 2 - 1) * 0.22 * gate * (0.8 + 0.2 * Math.sin(2 * Math.PI * 3 * t));
  }
  mix(out, bell([1318, 1976], 0.6), 0.92, 0.85);
  mix(out, bell([1046], 0.5), 1.05, 0.5);
  writeWav("slot_print.wav", out);
}

// 4) 印章"咚"
{
  const n = sec(0.3), out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR, env = Math.exp(-t * 30);
    out[i] = env * (Math.sin(2 * Math.PI * 110 * t) * 0.9 + (Math.random() * 2 - 1) * 0.12);
  }
  writeWav("slot_stamp.wav", out);
}
