#!/usr/bin/env node
// Replay a walkthrough in a real browser and record it.
//
//   node video/record-web.mjs <steps.json> <workdir>
//
// Writes <workdir>/raw.mp4 and <workdir>/beats.tsv (seconds since recording start, beat name).
// The page is laid out at "viewport" (1280x720) and captured at "scale" times that (1.5 gives a true
// 1920x1080 picture, with text rendered at that size, not enlarged afterwards).
// Needs ffmpeg, and Playwright with Chromium: npm i -D playwright && npx playwright install chromium
//
// steps.json: { "baseURL", "viewport", "scale", "slowMo", "clipboardOrigins": [...], "setup": [...], "steps": [...] }
// "setup" runs off camera (log in); its cookies carry into the recording. Values written "$env:NAME"
// are read from the environment and never stored. Any step may carry "beat": "<name>", recorded
// just before the step runs. A beat whose name starts with "cut" marks frames the edit leaves out.
//
// Steps:
//   {"do":"goto","url":"/apis"}                  {"do":"click","target":"<selector>"}
//   {"do":"type","target":"<sel>","text":"...","delay":45}    visible typing
//   {"do":"press","key":"End"}                   {"do":"hover","target":"<sel>"}
//   {"do":"paste","file":"x.json","field":"data"} or {"do":"paste","text":"..."}   real clipboard paste
//   {"do":"scroll","target":"<sel>"}             smooth scroll that centres the element
//   {"do":"waitFor","target":"<sel>"}            {"do":"expect","text":"..."}   fails the take if absent
//   {"do":"highlight","target":"<sel>","seconds":3}   fading outline around the element
//   {"do":"pause","seconds":2}
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

let chromium;
for (const base of [path.join(process.cwd(), 'x.js'), import.meta.url]) {
  try { ({ chromium } = createRequire(base)('playwright')); break; } catch { /* try the next place */ }
}
if (!chromium) { console.error('Playwright is missing: npm i -D playwright && npx playwright install chromium'); process.exit(2); }

const [stepsPath, workdir] = process.argv.slice(2);
if (!stepsPath || !workdir) { console.error('usage: node record-web.mjs <steps.json> <workdir>'); process.exit(2); }
const plan = JSON.parse(fs.readFileSync(stepsPath, 'utf8'));
const here = path.dirname(path.resolve(stepsPath));
fs.mkdirSync(workdir, { recursive: true });
const viewport = plan.viewport || { width: 1280, height: 720 };
const env = (v) => (typeof v === 'string' && v.startsWith('$env:'))
  ? (process.env[v.slice(5)] ?? (() => { throw new Error(`environment variable ${v.slice(5)} is not set`); })()) : v;

// Headless video has no pointer, so draw one.
const CURSOR = () => {
  if (window.__cursor) return; window.__cursor = true;
  const add = () => {
    const c = document.createElement('div');
    c.style.cssText = 'position:fixed;z-index:2147483647;pointer-events:none;width:20px;height:20px;margin:-10px 0 0 -10px;' +
      'border-radius:50%;background:rgba(255,255,255,.75);border:2px solid #8438FA;box-shadow:0 1px 6px rgba(0,0,0,.35);' +
      'left:-100px;top:-100px;transition:transform .12s';
    document.documentElement.appendChild(c);
    addEventListener('mousemove', (e) => { c.style.left = e.clientX + 'px'; c.style.top = e.clientY + 'px'; }, true);
    addEventListener('mousedown', () => { c.style.transform = 'scale(1.7)'; }, true);
    addEventListener('mouseup', () => { c.style.transform = 'scale(1)'; }, true);
  };
  if (document.documentElement) add(); else addEventListener('DOMContentLoaded', add);
};

async function moveTo(page, loc) {
  await loc.scrollIntoViewIfNeeded();
  const b = await loc.boundingBox();
  if (b) await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2, { steps: 20 });
}

async function run(page, s, mark) {
  if (s.beat) mark(s.beat);
  const T = s.timeout ?? 20000;
  const L = () => page.locator(s.target).first();
  switch (s.do) {
    case 'goto':
      await page.goto(new URL(s.url, plan.baseURL).toString(), { waitUntil: 'load' });
      if (page.__startCapture) await page.__startCapture();   // a new site can mean a new renderer
      break;
    case 'click': await L().waitFor({ state: 'visible', timeout: T }); await moveTo(page, L()); await L().click(); break;
    case 'fill': await L().fill(String(env(s.value))); break;
    case 'type': await moveTo(page, L()); await L().click(); await L().pressSequentially(String(env(s.text)), { delay: s.delay ?? 45 }); break;
    case 'press': if (s.target) await L().press(s.key); else await page.keyboard.press(s.key); break;
    case 'hover': await L().waitFor({ state: 'visible', timeout: T }); await moveTo(page, L()); break;
    case 'paste': {
      let text = s.text;
      if (s.file) {
        const raw = fs.readFileSync(path.resolve(here, s.file), 'utf8');
        text = s.field ? JSON.stringify(JSON.parse(raw)[s.field], null, 2) : raw;
      }
      await page.evaluate((t) => navigator.clipboard.writeText(t), text);
      await page.keyboard.press('ControlOrMeta+V');
      break;
    }
    case 'scroll':
      await L().waitFor({ state: 'visible', timeout: T });
      await L().evaluate((el) => el.scrollIntoView({ block: 'center', behavior: 'smooth' }));
      await page.waitForTimeout(800);
      break;
    case 'waitFor': await L().waitFor({ state: 'visible', timeout: T }); break;
    case 'expect': await page.getByText(s.text, { exact: false }).first().waitFor({ state: 'visible', timeout: T }); break;
    case 'highlight': {
      const ms = Math.round((s.seconds ?? 2.5) * 1000);
      await L().waitFor({ state: 'visible', timeout: T });
      await moveTo(page, L());
      await L().evaluate((el, ms) => {
        const r = el.getBoundingClientRect(), h = document.createElement('div');
        h.style.cssText = 'position:fixed;z-index:2147483646;pointer-events:none;border:3px solid #23E2C2;border-radius:10px;' +
          'box-shadow:0 0 0 9999px rgba(3,3,28,.18),0 0 22px rgba(35,226,194,.55);opacity:0;transition:opacity .4s ease;' +
          `left:${r.left - 7}px;top:${r.top - 7}px;width:${r.width + 14}px;height:${r.height + 14}px`;
        document.body.appendChild(h);
        requestAnimationFrame(() => { h.style.opacity = 1; });
        setTimeout(() => { h.style.opacity = 0; }, ms - 450);
        setTimeout(() => h.remove(), ms);
      }, ms);
      await page.waitForTimeout(ms);
      break;
    }
    case 'pause': await page.waitForTimeout(Math.round((s.seconds ?? 1) * 1000)); break;
    default: throw new Error(`unknown step "do": ${s.do}`);
  }
}

const scale = plan.scale ?? 1.5;
const out = { width: Math.round(viewport.width * scale), height: Math.round(viewport.height * scale) };
const browser = await chromium.launch({ headless: true, slowMo: plan.slowMo ?? 150, args: [`--force-device-scale-factor=${scale}`] });
let storageState;
if (plan.setup?.length) {                                  // off camera
  const ctx = await browser.newContext({ viewport });
  const p = await ctx.newPage();
  for (const s of plan.setup) await run(p, { ...s, beat: undefined }, () => {});
  storageState = await ctx.storageState();
  await ctx.close();
}
const ctx = await browser.newContext({ viewport, deviceScaleFactor: scale, storageState });
for (const origin of plan.clipboardOrigins || []) await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin });
await ctx.addInitScript(CURSOR);
const page = await ctx.newPage();

// Capture: the browser hands over a frame whenever the picture changes. Each is saved with its time,
// and ffmpeg later holds every frame until the next one, giving a constant 30 frames per second.
const frameDir = path.join(workdir, 'frames');
fs.rmSync(frameDir, { recursive: true, force: true });
fs.mkdirSync(frameDir);
const frames = [];                                         // [seconds on the wall clock, file]
const cdp = await ctx.newCDPSession(page);
cdp.on('Page.screencastFrame', (f) => {
  const file = path.join(frameDir, String(frames.length).padStart(6, '0') + '.jpg');
  fs.writeFileSync(file, Buffer.from(f.data, 'base64'));
  frames.push([f.metadata.timestamp, file]);
  cdp.send('Page.screencastFrameAck', { sessionId: f.sessionId }).catch(() => {});
});
page.__startCapture = () => cdp.send('Page.startScreencast',
  { format: 'jpeg', quality: 90, maxWidth: out.width, maxHeight: out.height, everyNthFrame: 1 }).catch(() => {});
await page.__startCapture();

const beats = [];                                          // [seconds on the wall clock, name]
const mark = (name) => { beats.push([Date.now() / 1000, name]); if (!name.startsWith('cut')) console.log('beat', name); };
let failed = null;
try {
  for (const [i, s] of plan.steps.entries()) {
    try { await run(page, s, mark); } catch (e) { e.message = `step ${i + 1} (${s.do} ${s.target ?? s.text ?? s.url ?? ''}): ${e.message}`; throw e; }
  }
  mark('done');
  await page.waitForTimeout(500);
} catch (e) {
  failed = e;
  mark('failed');
  await page.screenshot({ path: path.join(workdir, 'failed.png') }).catch(() => {});
}
const end = Date.now() / 1000;
await cdp.send('Page.stopScreencast').catch(() => {});
await browser.close();

if (!frames.length) { console.error('TAKE FAILED: the browser produced no frames'); process.exit(1); }
const t0 = frames[0][0];
const list = frames.map(([t, file], i) => {
  const next = i + 1 < frames.length ? frames[i + 1][0] : end;
  return `file '${file}'\nduration ${Math.max(0.001, next - t).toFixed(4)}`;
}).join('\n') + `\nfile '${frames[frames.length - 1][1]}'\n`;
fs.writeFileSync(path.join(workdir, 'frames.txt'), list);
execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', path.join(workdir, 'frames.txt'),
  '-vf', `fps=30,scale=${out.width}:${out.height}:flags=lanczos,format=yuv420p`, '-c:v', 'libx264', '-crf', '14', '-preset', 'fast',
  path.join(workdir, 'raw.mp4')], { stdio: 'inherit' });
fs.rmSync(frameDir, { recursive: true, force: true });
fs.writeFileSync(path.join(workdir, 'beats.tsv'), '# seconds\tbeat\n' + beats.map(([t, n]) => `${Math.max(0, t - t0).toFixed(3)}\t${n}`).join('\n') + '\n');
if (failed) {
  console.error(`TAKE FAILED: ${failed.message.split('\n')[0]}\nScreenshot: ${path.join(workdir, 'failed.png')}`);
  process.exit(1);
}
console.log(`recorded ${path.join(workdir, 'raw.mp4')}: ${frames.length} frames at ${out.width}x${out.height}`);
