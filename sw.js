const CACHE_NAME = "echocity-v72-network-first";
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
  "./assets/video-feed-v4.html",
  "./assets/video-auth.html",
  "./assets/discover.html",
  "./assets/creator-profile.html",
  "./assets/live-center.html",
  "./assets/live-room.html",
  "./assets/report-content.html",
  "./assets/me.html",
  "./assets/admin-content-business.html",
  "./assets/admin-demand-supply.html",
  "./assets/customer-dashboard.html",
  "./assets/customer-role-home.html",
  "./assets/customer-my-requests.html",
  "./assets/customer-order-progress.html",
  "./assets/service-request.html",
  "./assets/service-request-confirmation.html",
  "./assets/service-quote-confirmation.html",
  "./assets/task-link.html",
  "./assets/worker-dashboard.html",
  "./assets/worker-role-home.html",
  "./assets/worker-onboarding.html",
  "./assets/worker-tasks.html",
  "./assets/worker-milestone-submission.html",
  "./assets/worker-settlement.html",
  "./assets/admin-dashboard.html",
  "./assets/admin-operations-overview.html",
  "./assets/admin-worker-management.html",
  "./assets/admin-settlement-ledger.html",
  "./assets/admin-incident-center.html",
  "./assets/admin-dispatch-center.html",
  "./assets/admin-plan-center.html",
  "./assets/implementation-plan-workflow.html",
  "./assets/admin-prestart-center.html",
  "./assets/admin-quality-center.html",
  "./assets/admin-warranty-center.html",
  "./assets/customer-warranty.html",
  "./assets/worker-after-sales.html",
  "./assets/admin-service-quote.html",
  "./assets/admin-order-archive.html",
  "./assets/admin-order-360.html",
  "./assets/admin-cross-module-center.html",
  "./assets/admin-service-assignment.html",
  "./assets/admin-service-milestones.html",
  "./assets/customer-milestone-evaluation.html",
  "./assets/customer-milestone-paper.html",
  "./assets/customer-final-acceptance.html"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      await Promise.allSettled(APP_FILES.map((url) => cache.add(url)));
    })
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => Promise.all(
      cacheNames.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name))
    ))
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  const request = event.request;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith((async () => {
    try {
      const networkResponse = await fetch(request, { cache: "no-store" });
      if (networkResponse && networkResponse.ok) {
        const cache = await caches.open(CACHE_NAME);
        cache.put(request, networkResponse.clone()).catch(() => {});
      }
      return networkResponse;
    } catch (error) {
      const cached = await caches.match(request);
      if (cached) return cached;
      if (request.mode === "navigate") {
        const appShell = await caches.match("./app.html") || await caches.match("./index.html");
        if (appShell) return appShell;
      }
      throw error;
    }
  })());
});