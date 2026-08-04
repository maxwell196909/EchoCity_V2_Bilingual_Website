import { cp, mkdir, rm } from "node:fs/promises";

const files = [
  "index.html",
  "app.html",
  "city-map.html",
  "manifest.json",
  "sw.js",
  "assets",
  "images",
  "js"
];

await rm("www", { recursive: true, force: true });
await mkdir("www", { recursive: true });

for (const file of files) {
  await cp(file, `www/${file}`, { recursive: true });
}

console.log("EchoCity web files prepared in www/.");
