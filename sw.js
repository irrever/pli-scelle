// Service worker de Pli Scellé : il affiche les notifications et ouvre l’appli au toucher.
// Il ne met rien en cache et ne lit aucun message.
self.addEventListener('install', () => { self.skipWaiting(); });
self.addEventListener('activate', (event) => { event.waitUntil(self.clients.claim()); });
// Notification envoyée par le serveur quand l’appli est fermée. Le texte est générique : rien ne fuit sur l’écran verrouillé.
self.addEventListener('push', (event) => {
  event.waitUntil(self.registration.showNotification('Pli Scellé', {
    body: 'Une nouvelle activité vous attend.',
    tag: 'pli-msg',
    renotify: false,
  }));
});
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const fenetres = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (fenetres.length) return fenetres[0].focus();
    return self.clients.openWindow(self.registration.scope);
  })());
});
