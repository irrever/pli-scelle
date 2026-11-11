// Service worker de Pli Scellé : il affiche les notifications et ouvre l’appli au toucher.
// Il ne met rien en cache et ne lit aucun message.
self.addEventListener('install', () => { self.skipWaiting(); });
self.addEventListener('activate', (event) => { event.waitUntil(self.clients.claim()); });
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const fenetres = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (fenetres.length) return fenetres[0].focus();
    return self.clients.openWindow(self.registration.scope);
  })());
});
