-- Pli Scellé : photos et documents, chiffrés, envoyés par morceaux et supprimés après téléchargement.
-- À lancer une fois, dans l’éditeur SQL du projet, après securite-envois.sql.
-- Mise à jour v136 : relancer ce script entier passe la purge à 48 heures, sans toucher aux données déjà là.
-- Le serveur ne lit jamais le contenu : il garde des morceaux déjà chiffrés par l’appli.
-- Un fichier disparaît au téléchargement, ou au plus tard 48 heures après l’envoi.

create table if not exists public.pli_pieces (
  id text not null check (length(id) between 16 and 64),
  idx integer not null check (idx >= 0),
  total integer not null check (total between 1 and 400),
  destinataire text not null check (destinataire ~ '^[0-9a-f]{64}$'),
  expediteur text not null check (expediteur ~ '^[0-9a-f]{64}$'),
  data text not null,
  cree_le timestamptz not null default now(),
  primary key (id, idx)
);
create index if not exists pli_pieces_cree_le_idx on public.pli_pieces (cree_le);
alter table public.pli_pieces enable row level security;
revoke all on public.pli_pieces from public, anon, authenticated;

-- Supprime les morceaux de plus de 48 heures. Appelée à chaque envoi et chaque lecture.
create or replace function public.pli_pieces_purge()
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.pli_pieces where cree_le < now() - interval '48 hours';
$$;

-- Envoi d’un morceau : l’expéditeur doit posséder le secret de son identité (même vérification que pli_send_auth).
create or replace function public.pli_piece_put(p_from text, p_secret text, p_destinataire text, p_id text, p_idx integer, p_total integer, p_data text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_b64 text; v_box text;
begin
  if p_from is null or p_from !~ '^[A-Za-z0-9_-]{40,200}$' then raise exception 'expéditeur invalide'; end if;
  v_b64 := translate(p_from, '-_', '+/');
  v_b64 := rpad(v_b64, length(v_b64) + ((4 - length(v_b64) % 4) % 4), '=');
  v_box := encode(sha256(decode(v_b64, 'base64')), 'hex');
  if not public.box_check(v_box, p_secret) then raise exception 'accès refusé'; end if;
  if p_destinataire !~ '^[0-9a-f]{64}$' then raise exception 'destinataire invalide'; end if;
  if p_total < 1 or p_total > 400 or p_idx < 0 or p_idx >= p_total then raise exception 'morceau invalide'; end if;
  if length(p_data) > 400000 then raise exception 'morceau trop gros'; end if;
  perform public.pli_pieces_purge();
  -- Un identifiant appartient à un seul envoi : même expéditeur, même destinataire, même nombre de morceaux.
  if exists (select 1 from public.pli_pieces p where p.id = p_id and (p.expediteur <> v_box or p.destinataire <> p_destinataire or p.total <> p_total)) then
    raise exception 'identifiant déjà utilisé';
  end if;
  insert into public.pli_pieces (id, idx, total, destinataire, expediteur, data)
  values (p_id, p_idx, p_total, p_destinataire, v_box, p_data)
  on conflict (id, idx) do update set data = excluded.data;
end;
$$;

-- Lecture d’un morceau : le destinataire doit posséder le secret de sa boîte.
create or replace function public.pli_piece_get(p_mailbox text, p_secret text, p_id text, p_idx integer)
returns table (out_total integer, out_data text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  if not public.box_check(p_mailbox, p_secret) then raise exception 'accès refusé'; end if;
  perform public.pli_pieces_purge();
  return query
    select p.total, p.data from public.pli_pieces p
    where p.id = p_id and p.idx = p_idx and p.destinataire = p_mailbox;
end;
$$;

-- Suppression : le destinataire supprime le fichier après téléchargement, ou quand le message disparaît.
create or replace function public.pli_piece_delete(p_mailbox text, p_secret text, p_id text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  if not public.box_check(p_mailbox, p_secret) then raise exception 'accès refusé'; end if;
  delete from public.pli_pieces where id = p_id and destinataire = p_mailbox;
end;
$$;

-- Droits : seules ces trois fonctions sont ouvertes à l’appli.
revoke execute on function public.pli_pieces_purge() from public, anon, authenticated;
revoke execute on function public.pli_piece_put(text, text, text, text, integer, integer, text) from public;
revoke execute on function public.pli_piece_get(text, text, text, integer) from public;
revoke execute on function public.pli_piece_delete(text, text, text) from public;
grant execute on function public.pli_piece_put(text, text, text, text, integer, integer, text) to anon, authenticated;
grant execute on function public.pli_piece_get(text, text, text, integer) to anon, authenticated;
grant execute on function public.pli_piece_delete(text, text, text) to anon, authenticated;

-- Facultatif, sur Supabase : purger même si personne n’appelle l’appli (extension pg_cron, une fois par jour).
-- select cron.schedule('purge-pieces', '0 3 * * *', $$ select public.pli_pieces_purge(); $$);
