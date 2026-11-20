# Pli Scellé

Messagerie privée : chaque personne a une identité (un pseudo et un code secret), les contacts se font face à face ou à distance, et les messages se lisent une fois, sauf si l'expéditeur choisit « Relisible ».

## Utiliser l'appli

Ouvrez https://irrever.github.io/pli-scelle/ sur votre téléphone.

Sur iPhone, pour recevoir les notifications quand l'appli est fermée : Safari → Partager → Sur l'écran d'accueil, puis ouvrez l'appli depuis cette icône (iOS 16.4 ou plus récent).

## Ajouter une personne

Tout se passe dans un seul écran, « Ajouter une personne » :

- **Scanner un QR code** : photographiez le QR code de la personne, ou choisissez son image. L’appli reconnaît seule une invitation ou une personne présente. Touchez « Envoyer ma demande » : la demande part sans code. Le code viendra ensuite, dans l’appli.
- **Mon QR code** : montrez-le à la personne, face à face, ou touchez « Envoyer le lien » pour le lui envoyer à distance. Le code se donne à part, ou se dit de vive voix.
- Les six mots affichés des deux côtés doivent être identiques avant d’ajouter le contact.

## Le relais

Les invitations et les messages passent par un relais Supabase. Les scripts se lancent dans l'éditeur SQL du projet, dans cet ordre, une fois chacun :

1. `relais.sql` : les tables et les fonctions du relais.
2. `securite-relais.sql` : réserve la lecture et la suppression des messages à l'identité qui possède le secret de sa boîte.
3. `securite-envois.sql` : coupures et reprises de lien vérifiées par le serveur. L'appli l'appelle : ne publiez pas cette version avant ce script.
4. `fichiers-prives.sql` : photos et documents (voir « Photos et documents » ci-dessous). L'appli les envoie par ce script : ne publiez pas cette version avant lui. Déjà installé avant la v136 ? Relancez-le : il passe la purge à 48 heures, sans toucher aux données.
5. `notifications.sql` : seulement si vous voulez les notifications quand l'appli est fermée (voir ci-dessous).
6. `sauvegardes-usage-unique.sql` : une sauvegarde ne s'installe qu'une fois. À lancer avant de publier une version qui installe des sauvegardes.

Ne relancez jamais `relais.sql` après `securite-relais.sql` : il remettrait l'ancienne lecture sans secret.

Les messages sont chiffrés de bout en bout. Le relais voit les identifiants de boîte, les pseudos et les dates, mais jamais les noms donnés aux contacts ni le contenu des messages.

La clé publiable dans `index.html` est publique par conception : la protection vient des règles du relais.

## Photos et documents

- Une photo part jusqu'à 15 Mo, un document jusqu'à 25 Mo. Rien n'est recompressé : le fichier reçu est identique à l'original.
- Le fichier est chiffré avec la clé du lien, puis envoyé par morceaux de 96 Ko dans la table `pli_pieces`. Le relais ne voit ni le nom du fichier ni son contenu : seulement des morceaux chiffrés, donc une taille approximative.
- Le destinataire touche la tuile « Photo reçue » ou « Document reçu » : le fichier est reconstitué sur son téléphone, enregistré, puis effacé du relais. Il ne peut pas être téléchargé une seconde fois. Pour une photo, l’envoyeur peut choisir « Aperçu seul » : le destinataire la voit dans l’appli, sans bouton de téléchargement, et elle est effacée du relais à la fermeture. Ce n’est pas une protection absolue : une capture d’écran reste possible. Les documents restent téléchargeables.
- Sans téléchargement, il est effacé au bout de 48 heures : côté relais (à chaque envoi et chaque lecture, et par `pli_pieces_purge()` si vous l'appelez à la main ou par `pg_cron`), côté appli (la tuile devient « Photo expirée »).
- La table grossit avec les fichiers en attente, jusqu'à 48 heures. Surveillez la taille de la base du projet Supabase.

## Notifications quand l'appli est fermée

Elles passent par les notifications web, et ne fonctionnent qu'après ces étapes :

1. Lancer `notifications.sql` dans l'éditeur SQL, après `securite-envois.sql`. Il accorde à la clé de service les droits de lecture nécessaires : sur les projets récents, Supabase ne les accorde pas automatiquement.
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

- **Sauvegarder** : Mon identité → « Sauvegarder mes contacts ». Le fichier, chiffré par votre code secret, contient vos contacts et de quoi reprendre le lien avec chacun. Gardez-le comme un mot de passe. L'option coûte 200 sceaux à l'achat ou à l'activation, une fois par identité (voir Boutique).
- **Supprimer son identité en gardant ses contacts** : Mon identité → Supprimer mon identité → « Garder mes contacts et supprimer ». Chaque contact passe en pause pendant 7 jours, sans être coupé. Il apparaît grisé dans « Liens en attente » et ne peut plus être ouvert.
- **Reprendre** : après « Créer mon identité », l’appli propose « Installer ma sauvegarde ». Une sauvegarde ne s’installe qu’une fois : ensuite, les autres sauvegardes de la même identité sont refusées. Puis « Réactiver les liens » envoie la demande à chaque contact. Le lien repart sans nouveau QR code, tant que la personne n’a pas supprimé son identité de son côté.
- **Limites** : si les deux personnes suppriment leur identité, il faut refaire un QR code. Après 7 jours de pause, le lien est retiré. Une sauvegarde faite avec une version antérieure de l’appli ne peut plus être installée.

## Boutique

Mon identité → « Voir les options et recharger ». Le solde, en sceaux, reste sur l'appareil : un sceau vaut 0,01 €. Le nom « sceaux » est provisoire.

- Recharges : 200 sceaux (2 €), 500 sceaux (5 €), 1 000 sceaux (10 €), 2 000 sceaux (20 €), 5 000 sceaux (50 €).
- Agent double : 500 sceaux à chaque création.
- Code d'urgence : 300 sceaux, une fois par identité.
- Sauvegarde des contacts : 200 sceaux, une fois par identité.
- Pack complet : 900 sceaux (agent double, code d'urgence, sauvegarde). Pack sécurité : 450 sceaux (code d'urgence, sauvegarde). Un pack s'achète toujours, même si l'une de ses options est déjà là : chaque option du pack ajoute un crédit au compte.
- Options : chaque achat ajoute un crédit au compte, même si l'option est déjà activée sur une identité. Activer une option sur une identité consomme un crédit du compte, sans rien débiter ; sans crédit, elle se paie à ce moment-là.

Installer une sauvegarde ne coûte rien. Les achats ne sont pas encore branchés (`PAIEMENT_ACTIF` vaut `false` dans `index.html`) : les boutons affichent « Bientôt », et rien n'est débité.

## Fichiers

- `index.html` : l'appli, un seul fichier.
- `relais.sql` : les tables et les fonctions du relais.
- `securite-relais.sql` : la protection des boîtes, à lancer après `relais.sql`.
- `securite-envois.sql` : coupures et reprises vérifiées par le serveur, à lancer après `securite-relais.sql`.
- `fichiers-prives.sql` : la table et les fonctions des photos et documents, à lancer après `securite-envois.sql`.
- `notifications.sql` : les abonnements et l'appel au serveur d'envoi, à lancer après `securite-envois.sql`.
- `sauvegardes-usage-unique.sql` : la table et la fonction qui refusent une seconde installation de la même sauvegarde, à lancer une fois dans Supabase.
- `sw.js` : le service worker, qui affiche la notification.
- `supabase/functions/push/index.ts` : la fonction d'envoi des notifications.

## Options

- Déverrouillage par empreinte ou Face ID, si le téléphone le propose. Il s'active dans « Mon identité », avec le code secret. Le code reste toujours possible.
- Sonnerie à la réception, facultative, avec quatre sons au choix. Elle joue à chaque message ou demande reçus, tant que l'appli est ouverte.
- Notifications quand l'appli est fermée, facultatives, réglées dans « Mon identité » → Alertes (voir plus haut).
