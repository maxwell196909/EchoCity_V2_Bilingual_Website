import { cp, mkdir, rm, readFile, writeFile } from "node:fs/promises";

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

// Force the packaged app to open the video home screen first and bust old
// in-app page caches from previous APK versions.
let packagedIndex = await readFile("www/index.html", "utf8");
packagedIndex = packagedIndex.replace("target.searchParams.set('app_v','53')", "target.searchParams.set('app_v','71')");
packagedIndex = packagedIndex.replace("const saved=localStorage.getItem('echocity-client-page')||'home';", "const saved='home';localStorage.setItem('echocity-client-page','home');");
await writeFile("www/index.html", packagedIndex, "utf8");

console.log("EchoCity Android video app v71 prepared in www/ and forced to video home on launch.");
