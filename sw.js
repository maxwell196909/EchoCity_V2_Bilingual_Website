const CACHE_NAME = "echocity-v4";

const APP_FILES = [
  "./",
  "./index.html",
  "./manifest.json",
  "./assets/service-request.html",
  "./assets/worker-tasks.html",
  "./assets/worker-milestone-submission.html",
  "./assets/customer-milestone-evaluation.html",
  "./assets/customer-milestone-paper.html",
  "./assets/customer-final-acceptance.html"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(APP_FILES);
    })
  );

  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      );
    })
  );

  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") {
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      return (
        cachedResponse ||
        fetch(event.request).catch(() => {
          return caches.match("./index.html");
        })
      );
    })
  );
});