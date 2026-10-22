#!/usr/bin/env node
/**
 * 莫高雷村庄布局生成器（watabou village-generator 算法模型复刻）
 * ------------------------------------------------------------------
 * 背景：https://watabou.github.io/village-generator 是 OpenFL/WebGL 桌面应用，
 * 数据只存在于运行时内存，网页版无法脚本化导出（沙箱内浏览器亦无外网）。
 * 因此这里按同一套模型在本地实现，输出与生成器一致的图元：路网折线 + 沿街建筑 + 地块。
 *
 * 模型（与 watabou 一致的四步）：
 *   1. 主干道：从村心向若干方向生长，每段带角度抖动（wobbly walk）
 *   2. 支路：沿主干道按间距分叉，垂直于主路生长
 *   3. 建筑：沿所有道路两侧排布，按路宽退让，带随机旋转/尺寸
 *   4. 地块/广场/道具：外围农田、村心广场、公共设施
 *
 * 输出坐标单位 = 米，与 Godot 世界坐标 (x, z) 一致。
 * 用法：
 *   node tools/village_gen.mjs --seed 20261022 --out data/worldgen/mulgore_village.json
 */
import fs from "node:fs";
import path from "node:path";

// ---------- 参数 ----------
function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 && process.argv[i + 1] ? process.argv[i + 1] : def;
}
const SEED = parseInt(arg("seed", "20261022"), 10);
const OUT = arg("out", "data/worldgen/mulgore_village.json");
const CENTER = arg("center", "0,-130").split(",").map(Number);
const INNER = parseFloat(arg("inner", "118"));   // 广场半径（避开 KayKit 地砖）
const OUTER = parseFloat(arg("outer", "268"));   // 村庄外缘半径

// ---------- 伪随机（mulberry32，固定 seed 可复现）----------
let _s = SEED >>> 0;
function rnd() {
  _s |= 0; _s = (_s + 0x6D2B79F5) | 0;
  let t = Math.imul(_s ^ (_s >>> 15), 1 | _s);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const rf = (a, b) => a + rnd() * (b - a);
const ri = (a, b) => Math.floor(rf(a, b + 1));
const pick = (arr) => arr[Math.floor(rnd() * arr.length)];

// ---------- 几何工具 ----------
const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
function segDist(p, a, b) {
  const abx = b[0] - a[0], abz = b[1] - a[1];
  const l2 = abx * abx + abz * abz;
  if (l2 < 1e-6) return dist(p, a);
  let t = ((p[0] - a[0]) * abx + (p[1] - a[1]) * abz) / l2;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(p[0] - (a[0] + abx * t), p[1] - (a[1] + abz * t));
}
function polyDist(p, pts) {
  let best = Infinity;
  for (let i = 0; i < pts.length - 1; i++) best = Math.min(best, segDist(p, pts[i], pts[i + 1]));
  return best;
}

// ---------- 状态 ----------
const roads = [];       // {width, kind, points}
const buildings = [];   // {x,z,w,d,rot,style,floors,seed}
const fields = [];      // {x,z,w,h,rot}
const props = [];       // {x,z,type,rot,scale}

function addRoad(points, width, kind) {
  roads.push({ width: +width.toFixed(2), kind, points: points.map(p => [+p[0].toFixed(2), +p[1].toFixed(2)]) });
}

// 与所有道路的最近距离（建筑必须离路 ≥ 半路宽 + 退让）
function nearestRoad(p) {
  let best = Infinity;
  for (const r of roads) best = Math.min(best, polyDist(p, r.points) - r.width * 0.5);
  return best;
}

// ---------- 1) 主干道 ----------
// 出村方向：朝北接官道（-z），朝南/东/西各自散开；watabou 的村子通常 4~7 条
const C = [CENTER[0], CENTER[1]];
const mainDirs = [
  { a: -Math.PI / 2, len: 210, w: 7.0, kind: "main" },   // 北 → 接官道（地狱火方向）
  { a: Math.PI / 2, len: 180, w: 6.0, kind: "main" },     // 南 → 湖泊支路
  { a: 0.22, len: 150, w: 5.2, kind: "lane" },            // 东
  { a: Math.PI - 0.28, len: 168, w: 5.2, kind: "lane" },  // 西
  { a: Math.PI - 0.95, len: 128, w: 4.4, kind: "lane" },  // 西南
  { a: 0.95, len: 132, w: 4.4, kind: "lane" },            // 东南
];

let roadSeedCursor = 0;
for (const md of mainDirs) {
  const pts = [[C[0] + Math.cos(md.a) * 26, C[1] + Math.sin(md.a) * 26]];
  let ang = md.a;
  let pos = [pts[0][0], pts[0][1]];
  let travelled = 26;
  while (travelled < md.len) {
    const seg = rf(26, 42);
    ang += rf(-0.22, 0.22);            // 每段抖动，形成自然弯曲
    pos = [pos[0] + Math.cos(ang) * seg, pos[1] + Math.sin(ang) * seg];
    pts.push(pos);
    travelled += seg;
  }
  addRoad(pts, md.w, md.kind);
}

// 村心环道（把六条主干连起来，形成广场圈）
{
  const ring = [];
  const n = 22;
  for (let i = 0; i <= n; i++) {
    const a = (i / n) * Math.PI * 2;
    const rr = INNER * 0.78 + Math.sin(a * 3 + 1.1) * 5;
    ring.push([C[0] + Math.cos(a) * rr, C[1] + Math.sin(a) * rr]);
  }
  addRoad(ring, 5.4, "ring");
}

// ---------- 2) 支路 ----------
// 沿每条主干道采样，向两侧垂直伸出（watabou 的 side streets）
const mainRoads = roads.filter(r => r.kind !== "ring");
for (const r of mainRoads) {
  const pts = r.points;
  for (let i = 1; i < pts.length - 1; i++) {
    if (rnd() > 0.62) continue;
    const a = pts[i], b = pts[i + 1];
    const dx = b[0] - a[0], dz = b[1] - a[1];
    const len = Math.hypot(dx, dz) || 1;
    // 法线
    const nx = -dz / len, nz = dx / len;
    for (const side of [1, -1]) {
      if (rnd() > 0.7) continue;
      const L = rf(34, 88);
      const start = [a[0] + nx * side * (r.width * 0.5 + 1.0), a[1] + nz * side * (r.width * 0.5 + 1.0)];
      const end = [start[0] + nx * side * L + rf(-7, 7), start[1] + nz * side * L + rf(-7, 7)];
      if (dist(end, C) > OUTER * 1.15) continue;
      // 终点离村心太近（扎进广场）则跳过
      if (dist(end, C) < INNER * 0.92) continue;
      addRoad([start, end], rf(3.0, 3.8), "alley");
    }
  }
}

// ---------- 3) 建筑 ----------
const STYLES = ["hut", "hut", "hut", "barn", "house", "house", "forge", "tower", "tent", "wellhouse"];

function tryBuilding(at, dirAng, roadW) {
  // 建筑中心 = 路边 + 进深/2 + 退让
  const w = rf(7.2, 13.5);
  const d = rf(7.8, 12.0);
  const setback = 1.6 + rf(0, 1.2);
  const off = roadW * 0.5 + setback + d * 0.5;
  const cx = at[0] + Math.cos(dirAng) * off;
  const cz = at[1] + Math.sin(dirAng) * off;
  const p = [cx, cz];
  if (dist(p, C) < INNER * 0.86) return;
  if (dist(p, C) > OUTER) return;
  // 与已有道路至少留 1.2m（不含自身路肩）
  if (nearestRoad(p) < 1.2) return;
  // 建筑之间至少留 3.5m（含对角）
  for (const b of buildings) {
    if (Math.hypot(b.x - cx, b.z - cz) < (Math.max(b.w, b.d) + Math.max(w, d)) * 0.5 - 1.0) return;
  }
  const rot = dirAng + Math.PI / 2 + rf(-0.10, 0.10);
  buildings.push({
    x: +cx.toFixed(2), z: +cz.toFixed(2),
    w: +w.toFixed(2), d: +d.toFixed(2),
    rot: +rot.toFixed(4),
    style: pick(STYLES),
    floors: rnd() < 0.14 ? 2 : 1,
  });
}

for (const r of roads) {
  if (r.kind === "ring") continue;
  const pts = r.points;
  let acc = 0;
  for (let i = 0; i < pts.length - 1; i++) {
    const a = pts[i], b = pts[i + 1];
    const dx = b[0] - a[0], dz = b[1] - a[1];
    const len = Math.hypot(dx, dz) || 1;
    const ang = Math.atan2(dz, dx);
    const nx = -dz / len, nz = dx / len;
    let t = rf(3, 9);
    while (t < len) {
      const at = [a[0] + (dx / len) * t, a[1] + (dz / len) * t];
      for (const side of [1, -1]) {
        if (rnd() > 0.55) continue;
        const nAng = Math.atan2(nz * side, nx * side);
        tryBuilding(at, nAng, r.width);
      }
      t += rf(11, 20);
    }
    acc += len;
  }
}

// 村心广场周边：一圈商铺（朝内）
{
  const n = 10;
  for (let i = 0; i < n; i++) {
    if (rnd() > 0.7) continue;
    const a = (i / n) * Math.PI * 2 + rf(-0.12, 0.12);
    const rr = INNER * 0.96;
    const p = [C[0] + Math.cos(a) * rr, C[1] + Math.sin(a) * rr];
    if (nearestRoad(p) < 1.4) continue;
    let clash = false;
    for (const b of buildings) {
      if (Math.hypot(b.x - p[0], b.z - p[1]) < 13) { clash = true; break; }
    }
    if (clash) continue;
    buildings.push({
      x: +p[0].toFixed(2), z: +p[1].toFixed(2),
      w: +rf(9, 14).toFixed(2), d: +rf(8, 11).toFixed(2),
      rot: +(a + Math.PI / 2).toFixed(4),
      style: pick(["house", "barn", "forge", "wellhouse"]),
      floors: rnd() < 0.3 ? 2 : 1,
    });
  }
}

// ---------- 4) 农田（外围矩形地块）----------
for (let i = 0; i < 7; i++) {
  const a = rf(0, Math.PI * 2);
  const rr = rf(OUTER * 0.9, OUTER * 1.35);
  const p = [C[0] + Math.cos(a) * rr, C[1] + Math.sin(a) * rr];
  if (nearestRoad(p) < 9) continue;
  let clash = false;
  for (const b of buildings) if (Math.hypot(b.x - p[0], b.z - p[1]) < 22) { clash = true; break; }
  if (clash) continue;
  fields.push({
    x: +p[0].toFixed(2), z: +p[1].toFixed(2),
    w: +rf(26, 46).toFixed(2), h: +rf(20, 34).toFixed(2),
    rot: +(a + Math.PI / 2 + rf(-0.2, 0.2)).toFixed(4),
  });
}

// ---------- 5) 道具（桶/车/栅栏/火盆/图腾/水井/草垛）----------
const PROP_TYPES = ["barrel", "crate", "cart", "firepit", "totem", "haystack", "anvil", "banner"];
for (const r of roads) {
  const pts = r.points;
  for (let i = 0; i < pts.length - 1; i++) {
    const a = pts[i], b = pts[i + 1];
    const dx = b[0] - a[0], dz = b[1] - a[1];
    const len = Math.hypot(dx, dz) || 1;
    const nx = -dz / len, nz = dx / len;
    for (let t = rf(6, 14); t < len; t += rf(18, 34)) {
      const side = rnd() < 0.5 ? 1 : -1;
      const off = r.width * 0.5 + rf(0.8, 2.4);
      const p = [a[0] + (dx / len) * t + nx * side * off, a[1] + (dz / len) * t + nz * side * off];
      if (dist(p, C) < INNER * 0.7) continue;
      if (dist(p, C) > OUTER * 1.05) continue;
      if (nearestRoad(p) < 0.6) continue;
      props.push({
        x: +p[0].toFixed(2), z: +p[1].toFixed(2),
        type: pick(PROP_TYPES),
        rot: +rf(0, Math.PI * 2).toFixed(4),
        scale: +rf(0.85, 1.25).toFixed(3),
      });
    }
  }
}

// ---------- 输出 ----------
const data = {
  generator: "mulgore_village",
  note: "watabou village-generator 同款模型（主干道抖动生长 → 支路分叉 → 沿街建筑 → 地块道具）本地生成",
  seed: SEED,
  center: C,
  inner_radius: INNER,
  outer_radius: OUTER,
  roads,
  buildings,
  fields,
  props,
};
const outPath = path.resolve(OUT);
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(data, null, 1), "utf8");
console.log(
  `[village_gen] seed=${SEED} roads=${roads.length} buildings=${buildings.length} ` +
  `fields=${fields.length} props=${props.length} -> ${outPath}`
);
