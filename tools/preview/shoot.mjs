// Renders preview screenshots.  node shoot.mjs <outDir> view1 view2 ...   (views: see main.js)
import { createRequire } from "module";
import http from "http";
import fs from "fs";
import path from "path";
const require = createRequire(import.meta.url);
// Use the local playwright (npm install), or a globally installed one.
let playwright;
try {
  playwright = require("playwright");
} catch {
  playwright = require("/opt/node22/lib/node_modules/playwright");
}
const { chromium } = playwright;

const root = path.dirname(new URL(import.meta.url).pathname);
const outDir = process.argv[2] || "shots";
const views = process.argv.slice(3);
fs.mkdirSync(outDir, { recursive: true });

const types = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".png": "image/png" };
const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(new URL(req.url, "http://x").pathname));
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" });
    res.end(data);
  });
}).listen(0);
const port = server.address().port;

const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
page.on("console", (m) => { if (m.type() === "error") console.error("page:", m.text()); });
page.on("pageerror", (e) => console.error("pageerror:", e.message));
for (const v of views) {
  const [name, query] = v.split("?");
  // "ui/<scenario>" draws a UI preview (ui.html); anything else is a 3D view (index.html).
  const url = name.startsWith("ui/")
    ? `ui.html?scenario=${name.slice(3)}${query ? "&" + query : ""}`
    : `index.html?view=${name}${query ? "&" + query : ""}`;
  await page.goto(`http://localhost:${port}/${url}`);
  await page.waitForFunction(() => window.__ready === true, null, { timeout: 120000 });
  const file = path.join(outDir, `${name.replace("/", "-")}${query ? "-" + query.replace(/[^a-z0-9]+/gi, "_") : ""}.png`);
  await page.screenshot({ path: file });
  console.log("saved", file);
}
await browser.close();
server.close();
