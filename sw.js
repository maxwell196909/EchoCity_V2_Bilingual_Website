const CACHE_NAME = "echocity-v27-unified-workbenches";
const APP_FILES = [
  "./",
  "./index.html",
  "./app.html",
  "./manifest.json",
  "./images/echocity-home-bg.png",
  "./images/echocity-app-icon-192.png",
  "./images/echocity-app-icon-512.png",
  "./js/echocity-supabase.js",
  "./js/echocity-store.js",
  "./js/echocity-services.js",
  "./assets/customer-dashboard.html",
  "./assets/customer-my-requests.html",
  "./assets/service-request.html",
  "./assets/service-request-confirmation.html",
  "./assets/service-quote-confirmation.html",
  "./assets/task-link.html",
  "./assets/admin-milestone-review.html",
  "./assets/worker-dashboard.html",
  "./assets/worker-tasks.html",
  "./assets/worker-milestone-submission.html",
  "./assets/admin-dashboard.html",
  "./assets/admin-service-quote.html",
  "./assets/admin-service-assignment.html",
  "./assets/admin-service-milestones.html",
  "./assets/customer-milestone-evaluation.html",
  "./assets/customer-milestone-paper.html",
  "./assets/customer-final-acceptance.html"
  ,"./assets/admin-settlement.html"
  ,"./assets/worker-settlement.html"
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

  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request).catch(() => caches.match("./index.html"))
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      return cachedResponse || fetch(event.request);
    })
  );
});
