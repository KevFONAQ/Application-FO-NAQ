/* Service worker : met en cache l'interface (pas les données, pas les PDF). */
const VERSION = "fo-docs-v7";
const SHELL = ["/", "/manifest.json", "/logo-fo.png", "/icons/icon-192.png", "/icons/icon-512.png", "/icons/apple-touch-icon.png"];
const CDN = ["cdn.tailwindcss.com", "cdn.jsdelivr.net", "cdnjs.cloudflare.com", "fonts.googleapis.com", "fonts.gstatic.com"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  // Supabase (comptes, données, PDF signés) : jamais mis en cache
  if (url.hostname.endsWith("supabase.co")) return;

  // Page de l'application : réseau d'abord, cache si hors ligne
  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then((res) => { const copy = res.clone(); caches.open(VERSION).then((c) => c.put("/", copy)); return res; })
        .catch(() => caches.match("/"))
    );
    return;
  }

  // Fichiers de l'app et bibliothèques : cache d'abord, mise à jour en arrière-plan
  if (url.origin === location.origin || CDN.includes(url.hostname)) {
    e.respondWith(
      caches.match(req).then((cached) => {
        const net = fetch(req).then((res) => {
          if (res.ok || res.type === "opaque") { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(req, copy)); }
          return res;
        }).catch(() => cached);
        return cached || net;
      })
    );
  }
});

/* Notifications : affichage et ouverture de l'application au toucher */
self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { body: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(d.title || "FO France Travail NAQ", {
    body: d.body || "Nouvelle actualité sur le fil",
    icon: "/icons/icon-192.png",
    data: { url: d.url || "/" },
    tag: "fo-actu",
    renotify: true,
  }));
});

self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = new URL(e.notification.data?.url || "/", self.location.origin).href;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((wins) => {
    for (const w of wins) if (w.url.startsWith(self.location.origin) && "focus" in w) return w.focus();
    return self.clients.openWindow(url);
  }));
});
