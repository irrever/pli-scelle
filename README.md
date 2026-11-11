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
- `notifications.sql` : les inscriptions aux notifications et le déclencheur d'envoi. Se lance après `relais.sql`.
- `supabase/functions/push/index.ts` : la fonction qui envoie les notifications quand l'appli est fermée.

## Options

- Déverrouillage par empreinte ou Face ID, si le téléphone le propose. Il s'active dans « Mon identité », avec le code secret. Le code reste toujours possible.
- Sonnerie et notifications, facultatives. La sonnerie ne joue que si l'appli est ouverte. Les notifications arrivent aussi quand l'appli est fermée, une fois le serveur d'envoi en place (ci-dessous). Elles ne montrent jamais le contenu du message.

## Notifications quand l'appli est fermée

Le serveur d'envoi se met en place une fois, dans le projet Supabase :

1. Lancer `notifications.sql` dans l'éditeur SQL, après `relais.sql`.
2. Créer deux secrets du projet : `VAPID_PUBLIC_KEY` (la clé publique, identique à `PUSH_KEY` dans `index.html`) et `VAPID_PRIVATE_KEY` (la clé privée, qui ne doit jamais entrer dans le dépôt).
3. Déployer la fonction `push` (dossier `supabase/functions/push`), sans vérification de jeton.

Les notifications ne contiennent aucun texte : elles disent seulement qu'une activité attend.
