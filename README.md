# Pli Scellé

Messagerie privée : chaque personne a une identité (un pseudo et un code secret), les contacts se font face à face ou à distance, et les messages se lisent une fois, sauf si l'expéditeur choisit « Relisible ».

## Utiliser l'appli

Ouvrez https://irrever.github.io/pli-scelle/ sur votre téléphone.

## Le relais

Les invitations et les messages passent par un relais Supabase. Son script est dans `relais.sql` : il se lance une fois, dans l'éditeur SQL du projet.

Les messages sont chiffrés de bout en bout. Le relais voit les identifiants de boîte, les pseudos et les dates, mais jamais les noms donnés aux contacts ni le contenu des messages.

La clé publiable dans `index.html` est publique par conception : la protection vient des règles du relais.

## Fichiers

- `index.html` : l'appli, un seul fichier.
- `relais.sql` : les tables et les fonctions du relais.
- `sw.js` : le service worker, pour les notifications. Il ne met rien en cache et ne lit aucun message.

## Options

- Déverrouillage par empreinte ou Face ID, si le téléphone le propose. Il s'active dans « Mon identité », avec le code secret. Le code reste toujours possible.
- Sonnerie et notifications, facultatives. Elles ne fonctionnent que si l'appli reste ouverte sur le téléphone : rien ne part quand l'appli est fermée.
