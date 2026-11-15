# Pli Scellé

Messagerie privée : chaque personne a une identité (un pseudo et un code secret), les contacts se font face à face ou à distance, et les messages se lisent une fois, sauf si l'expéditeur choisit « Relisible ».

## Utiliser l'appli

Ouvrez https://irrever.github.io/pli-scelle/ sur votre téléphone.

Sur iPhone, pour recevoir les notifications quand l'appli est fermée : Safari → Partager → Sur l'écran d'accueil, puis ouvrez l'appli depuis cette icône (iOS 16.4 ou plus récent).

## Ajouter une personne

Tout se passe dans un seul écran, « Ajouter une personne » :

- **Scanner un QR code** : photographiez le QR code de la personne, ou choisissez son image. L’appli reconnaît seule une invitation ou une identité. Entrez le code, puis « Envoyer ma demande ».
- **Mon QR code** : montrez-le à la personne, face à face, ou touchez « Envoyer le lien » pour le lui envoyer à distance. Le code se donne à part, ou se dit de vive voix.
- Les six mots affichés des deux côtés doivent être identiques avant d’ajouter le contact.

## Le relais

Les invitations et les messages passent par un relais Supabase. Les scripts se lancent dans l'éditeur SQL du projet, dans cet ordre, une fois chacun :

1. `relais.sql` : les tables et les fonctions du relais.
2. `securite-relais.sql` : réserve la lecture et la suppression des messages à l'identité qui possède le secret de sa boîte.
3. `notifications.sql` : seulement si vous voulez les notifications quand l'appli est fermée (voir ci-dessous).

Ne relancez jamais `relais.sql` après `securite-relais.sql` : il remettrait l'ancienne lecture sans secret.

Les messages sont chiffrés de bout en bout. Le relais voit les identifiants de boîte, les pseudos et les dates, mais jamais les noms donnés aux contacts ni le contenu des messages.

La clé publiable dans `index.html` est publique par conception : la protection vient des règles du relais.

## Notifications quand l'appli est fermée

Elles passent par les notifications web, et ne fonctionnent qu'après ces étapes :

1. Lancer `notifications.sql` dans l'éditeur SQL, après les deux scripts précédents. Il accorde à la clé de service les droits de lecture nécessaires : sur les projets récents, Supabase ne les accorde pas automatiquement.
2. Créer une fonction Edge nommée `push` (Edge Functions → New function), avec le contenu de `supabase/functions/push/index.ts`. Désactiver la vérification du jeton (« Verify JWT ») : le relais appelle cette fonction sans jeton.
3. Ajouter deux secrets à la fonction :
   - `VAPID_PUBLIC_KEY` : la clé publique VAPID, la même que `PUSH_KEY` dans `index.html`.
   - `VAPID_PRIVATE_KEY` : la clé privée correspondante. Elle ne doit jamais être publiée dans le dépôt.
   `SUPABASE_URL` et `SUPABASE_SECRET_KEYS` sont fournies par Supabase : rien à ajouter.

Pour créer la paire de clés (Node.js 18 ou plus récent), lance dans un terminal :

```bash
node -e "const c=require('crypto');const {privateKey:k}=c.generateKeyPairSync('ec',{namedCurve:'prime256v1'});const j=k.export({format:'jwk'});console.log('publique : '+Buffer.concat([Buffer.from([4]),Buffer.from(j.x,'base64url'),Buffer.from(j.y,'base64url')]).toString('base64url'));console.log('privée : '+Buffer.from(j.d,'base64url').toString('base64url'));"
```

Chaque valeur tient sur une seule ligne, sans espace ni retour à la ligne. Mets la clé publique dans `PUSH_KEY` de `index.html`, puis désactive et réactive les notifications sur chaque téléphone.

La notification affiche seulement « Une nouvelle activité vous attend. ». Le serveur sait qu'une boîte reçoit un message, mais jamais son contenu ni le nom du contact. Une seule notification au plus toutes les 15 secondes par boîte. Le son de la notification est celui du téléphone : le choix de sonnerie ne s'applique qu'à l'intérieur de l'appli.

Pour changer de clés, il faut refaire l'inscription de chaque appareil : désactiver puis réactiver les notifications dans « Mon identité ».

## Garder ses contacts

- **Sauvegarder** : Mon identité → « Sauvegarder mes contacts ». Le fichier, chiffré par votre code secret, contient vos contacts et de quoi reprendre le lien avec chacun. Gardez-le comme un mot de passe.
- **Supprimer son identité en gardant ses contacts** : Mon identité → Supprimer mon identité → « Garder mes contacts et supprimer ». Chaque contact passe en pause pendant 7 jours, sans être coupé. Il apparaît grisé dans « Liens en attente » et ne peut plus être ouvert.
- **Reprendre** : après « Créer mon identité », l’appli propose « Installer ma sauvegarde ». Puis « Réactiver les liens » envoie la demande à chaque contact. Le lien repart sans nouveau QR code, tant que la personne n’a pas supprimé son identité de son côté.
- **Limites** : si les deux personnes suppriment leur identité, il faut refaire un QR code. Après 7 jours de pause, le lien est retiré. Une sauvegarde faite avec une version antérieure de l’appli ne peut plus être installée.

## Fichiers

- `index.html` : l'appli, un seul fichier.
- `relais.sql` : les tables et les fonctions du relais.
- `securite-relais.sql` : la protection des boîtes, à lancer après `relais.sql`.
- `notifications.sql` : les abonnements et l'appel au serveur d'envoi, à lancer après `securite-relais.sql`.
- `sw.js` : le service worker, qui affiche la notification.
- `supabase/functions/push/index.ts` : la fonction d'envoi des notifications.

## Options

- Déverrouillage par empreinte ou Face ID, si le téléphone le propose. Il s'active dans « Mon identité », avec le code secret. Le code reste toujours possible.
- Sonnerie à la réception, facultative, avec quatre sons au choix. Elle joue à chaque message ou demande reçus, tant que l'appli est ouverte.
- Notifications quand l'appli est fermée, facultatives, réglées dans « Mon identité » → Alertes (voir plus haut).
