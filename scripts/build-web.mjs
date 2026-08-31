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

// Android APK must launch directly into the EchoCity short-video app shell.
// Keep the public website's index.html unchanged, but use app.html as the
// packaged Capacitor entry point.
await cp("app.html", "www/index.html");

console.log("EchoCity Android web bundle prepared in www/ with video app shell as index.html.");
