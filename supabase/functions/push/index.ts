// Notifications « Pli Scellé » quand l’appli est fermée.
//
// Appelée après chaque message déposé dans le relais (voir notifications.sql).
// Elle envoie une notification vide : aucun texte, aucun nom, aucun contenu ne quitte le serveur.
// Le téléphone affiche seulement « Une nouvelle activité vous attend. ».
//
// Secrets du projet : VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY.
// SUPABASE_URL et la clé de service (SUPABASE_SECRET_KEY, ou SUPABASE_SERVICE_ROLE_KEY) sont fournies par Supabase.
// Déployée sans vérification de jeton (verify_jwt = false) : le relais l’appelle sans authentification.
//
// Journal : chaque étape écrit une ligne dans les journaux de la fonction (Supabase → Edge Functions → push → Logs).
// Aucune adresse de boîte ni d’appareil n’y figure.

const RATE_LIMIT_MS = 15000;                              // au plus une notification toutes les 15 s par boîte
const SUBJECT = 'https://irrever.github.io/pli-scelle/';  // contact VAPID : l’adresse publique de l’appli
const enc = new TextEncoder();

// Journal : seulement l’étape et son résultat. Jamais d’adresse de boîte, ni d’adresse d’appareil, ni contenu.
const journal = (...morceaux: unknown[]) => { if (typeof Deno !== 'undefined') console.log('[push]', ...morceaux); };
const sansAdresse = (texte: string): string => texte.replace(/https?:\/\/\S+/g, '[adresse]');
// Début de la réponse du service de notification, pour comprendre un refus.
async function debutReponse(r: Response): Promise<string> {
  try { return sansAdresse((await r.text()).slice(0, 120)); } catch (e) { return '(illisible)'; }
}

type Env = {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  VAPID_PUBLIC_KEY: string;
  VAPID_PRIVATE_KEY: string;
};
type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;

function b64u(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function unb64u(text: string): Uint8Array {
  const s = atob(text.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(text.length / 4) * 4, '='));
  return Uint8Array.from(s, (c) => c.charCodeAt(0));
}

// En-tête « Authorization: vapid » (RFC 8292) : jeton ES256 signé avec la clé privée du serveur.
export async function vapidAuthorization(endpoint: string, publicKey: string, privateKey: string, now: number): Promise<string> {
  const pub = unb64u(publicKey);                          // 0x04 || x || y (65 octets)
  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: 'EC', crv: 'P-256', x: b64u(pub.slice(1, 33)), y: b64u(pub.slice(33, 65)), d: privateKey, ext: true },
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  const head = b64u(enc.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const body = b64u(enc.encode(JSON.stringify({
    aud: new URL(endpoint).origin,
    exp: Math.floor(now / 1000) + 12 * 3600,
    sub: SUBJECT,
  })));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(head + '.' + body));
  return 'vapid t=' + head + '.' + body + '.' + b64u(new Uint8Array(sig)) + ', k=' + publicKey;
}

const json = (status: number, body: unknown): Response =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

// Une réponse identique dans tous les cas valides : le relais ne révèle rien sur la boîte.
export async function handle(req: Request, env: Env, fetchFn: Fetcher, now: number): Promise<Response> {
  if (req.method !== 'POST') return json(405, { ok: false });
  let mailbox = '';
  try {
    mailbox = String((await req.json()).mailbox || '');
  } catch (e) {
    return json(400, { ok: false });
  }
  if (!/^[0-9a-f]{64}$/.test(mailbox)) return json(400, { ok: false });

  // Comme l’appli : la clé va dans l’en-tête apikey. Seule une clé au format JWT (ancienne génération) va aussi dans
  // Authorization ; une clé « sb_secret_ » n’y va pas, le serveur la refuserait comme jeton.
  const db = (path: string, init: RequestInit = {}) => {
    const entetes: Record<string, string> = { apikey: env.SUPABASE_SERVICE_ROLE_KEY, 'Content-Type': 'application/json' };
    if (env.SUPABASE_SERVICE_ROLE_KEY.startsWith('eyJ')) entetes.Authorization = 'Bearer ' + env.SUPABASE_SERVICE_ROLE_KEY;
    return fetchFn(env.SUPABASE_URL + '/rest/v1/' + path, {
      ...init,
      headers: { ...entetes, ...((init.headers as Record<string, string>) || {}) },
    });
  };

  // 1. Il faut un message en attente dans la boîte.
  const rMessages = await db('messages?select=id&mailbox=eq.' + mailbox + '&limit=1');
  const pending = await rMessages.json();
  if (!Array.isArray(pending)) { journal('lecture des messages : réponse inattendue, statut', rMessages.status); return json(200, { ok: true }); }
  if (pending.length === 0) { journal('aucun message en attente : déjà lu, ou rien à notifier'); return json(200, { ok: true }); }

  // 2. Il faut un abonnement, et pas une notification trop rapprochée de la précédente.
  const rSubs = await db('push_subscriptions?select=subscription,last_push_at&mailbox=eq.' + mailbox);
  const rows = await rSubs.json();
  if (!Array.isArray(rows)) { journal('lecture des abonnements : réponse inattendue, statut', rSubs.status); return json(200, { ok: true }); }
  if (rows.length === 0) { journal('aucun abonnement pour cette boîte : l’appareil ne s’est pas inscrit'); return json(200, { ok: true }); }
  const last = rows[0].last_push_at ? Date.parse(rows[0].last_push_at) : 0;
  if (now - last < RATE_LIMIT_MS) { journal('une notification a été envoyée il y a moins de 15 s : pas de nouvel envoi'); return json(200, { ok: true }); }

  // 3. Envoi : notification vide, en-tête signé.
  const endpoint: string = rows[0].subscription.endpoint;
  journal('envoi au service de notification :', new URL(endpoint).host);
  const auth = await vapidAuthorization(endpoint, env.VAPID_PUBLIC_KEY, env.VAPID_PRIVATE_KEY, now);
  const res = await fetchFn(endpoint, { method: 'POST', headers: { TTL: '3600', Urgency: 'normal', Authorization: auth } });
  if (res.status === 404 || res.status === 410) {
    // Abonnement périmé (appareil désinstallé, notifications retirées) : on l’oublie.
    journal('service de notification : abonnement périmé (' + res.status + '), oublié');
    await db('push_subscriptions?mailbox=eq.' + mailbox, { method: 'DELETE' });
    return json(200, { ok: true });
  }
  if (res.status >= 200 && res.status < 300) journal('service de notification : accepté (' + res.status + ')');
  else journal('service de notification : refusé (' + res.status + ')', await debutReponse(res));
  await db('push_subscriptions?mailbox=eq.' + mailbox, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ last_push_at: new Date(now).toISOString() }),
  });
  return json(200, { ok: true });
}

// Point d’entrée sur Supabase (Deno). Absent quand le fichier est chargé ailleurs (tests).
if (typeof Deno !== 'undefined') {
  Deno.serve(async (req: Request) => {
    try {
      // Clé de service : le nom de la nouvelle génération (SUPABASE_SECRET_KEY) d’abord, puis l’ancien (SUPABASE_SERVICE_ROLE_KEY).
      const cleNouvelle = Deno.env.get('SUPABASE_SECRET_KEY') ?? '';
      const cleAncienne = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
      const env: Env = {
        SUPABASE_URL: Deno.env.get('SUPABASE_URL') ?? '',
        SUPABASE_SERVICE_ROLE_KEY: cleNouvelle || cleAncienne,
        VAPID_PUBLIC_KEY: Deno.env.get('VAPID_PUBLIC_KEY') ?? '',
        VAPID_PRIVATE_KEY: Deno.env.get('VAPID_PRIVATE_KEY') ?? '',
      };
      journal('secrets : publique', env.VAPID_PUBLIC_KEY ? 'présente' : 'MANQUANTE', '| privée', env.VAPID_PRIVATE_KEY ? 'présente' : 'MANQUANTE', '| clé de service', cleNouvelle ? 'SUPABASE_SECRET_KEY' : cleAncienne ? 'SUPABASE_SERVICE_ROLE_KEY' : 'MANQUANTE');
      return await handle(req, env, fetch, Date.now());
    } catch (e) {
      journal('erreur :', sansAdresse(e instanceof Error ? e.message : String(e)));
      return json(500, { ok: false });
    }
  });
}
