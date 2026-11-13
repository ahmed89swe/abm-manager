// Dedicated Notification Service Worker (scoped to ./notifications/)
// Works alongside Flutter's root PWA service worker without scope conflicts.
self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl =
    (event.notification.data && event.notification.data.url) ||
    new URL('../', self.registration.scope).href;

  event.waitUntil(
    self.clients
        .matchAll({ type: 'window', includeUncontrolled: true })
        .then((clientList) => {
          for (const client of clientList) {
            if ('focus' in client) {
              return client.focus();
            }
          }
          if (self.clients.openWindow) {
            return self.clients.openWindow(targetUrl);
          }
          return undefined;
        })
  );
});

self.addEventListener('push', (event) => {
  if (!event.data) return;
  let payload = {};
  try {
    payload = event.data.json();
  } catch (_) {
    payload = { title: 'ABM Manager', body: event.data.text() };
  }
  const title = payload.title || (payload.notification && payload.notification.title) || 'ABM Manager';
  const body = payload.body || (payload.notification && payload.notification.body) || '';
  const tag = payload.tag || 'abm-push';

  event.waitUntil(
    self.registration.showNotification(title, {
      body: body,
      icon: '../icons/Icon-192.png',
      badge: '../icons/Icon-192.png',
      tag: tag,
      renotify: true,
      data: { url: new URL('../', self.registration.scope).href },
    })
  );
});
