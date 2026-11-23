-- Pli Scellé : la boîte d’une identité supprimée ne reçoit plus rien.
-- À lancer une fois, dans l’éditeur SQL du projet, après securite-envois.sql.
-- Ensuite, ne relancez ni relais.sql ni securite-envois.sql : ils remettraient les envois sans ce contrôle.
-- Sans ce script, l’appli marche comme avant, mais le relais ne refuse pas les envois vers une identité supprimée.

-- 1) Les boîtes fermées. Une identité supprimée n’a plus ses clés : sa boîte ne peut plus servir.
--    La fermeture est donc définitive. Le délai de 7 jours ne concerne que le lien, côté contacts.
create table if not exists public.boites_fermees (
  mailbox text primary key check (mailbox ~ '^[0-9a-f]{64}$'),
  ferme_le timestamptz not null default now()
);
alter table public.boites_fermees enable row level security;
revoke all on public.boites_fermees from public, anon, authenticated;

-- 2) Fermer sa propre boîte, avant d’effacer l’identité. Seul le secret de la boîte le permet.
--    Les notifications vers cette boîte s’arrêtent aussi. La table push_subscriptions n’existe que si notifications.sql a été lancé.
create or replace function public.pli_box_fermer(p_mailbox text, p_secret text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  if not public.box_check(p_mailbox, p_secret) then raise exception 'accès refusé'; end if;
  insert into public.boites_fermees (mailbox) values (p_mailbox)
  on conflict (mailbox) do nothing;
  if to_regclass('public.push_subscriptions') is not null then
    execute 'delete from public.push_subscriptions where mailbox = $1' using p_mailbox;
  end if;
end;
$$;

-- 3) Envois : une boîte fermée refuse tout, l’envoi non signé (pli_send) comme l’envoi signé (pli_send_auth).
--    L’appli reconnaît le message « boite fermee » et le montre à l’expéditeur. Les corps des fonctions reprennent ceux de securite-envois.sql.
create or replace function public.pli_send(p_mailbox text, p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  if octet_length(p_payload::text) > 30000 then raise exception 'message trop long'; end if;
  if exists (select 1 from public.boites_fermees f where f.mailbox = p_mailbox) then raise exception 'boite fermee'; end if;
  insert into public.messages (mailbox, payload) values (p_mailbox, p_payload - 'auth')
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.pli_send_auth(p_mailbox text, p_payload jsonb, p_secret text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_from text; v_b64 text; v_box text; v_id uuid;
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  v_from := p_payload->>'from';
  if v_from is null or v_from !~ '^[A-Za-z0-9_-]{40,200}$' then raise exception 'expéditeur invalide'; end if;
  -- La boîte d’un expéditeur est l’empreinte SHA-256 de son identité (même calcul que dans l’appli)
  v_b64 := translate(v_from, '-_', '+/');
  v_b64 := rpad(v_b64, length(v_b64) + ((4 - length(v_b64) % 4) % 4), '=');
  v_box := encode(sha256(decode(v_b64, 'base64')), 'hex');
  if not public.box_check(v_box, p_secret) then raise exception 'accès refusé'; end if;
  if octet_length(p_payload::text) > 30000 then raise exception 'message trop long'; end if;
  if exists (select 1 from public.boites_fermees f where f.mailbox = p_mailbox) then raise exception 'boite fermee'; end if;
  insert into public.messages (mailbox, payload)
  values (p_mailbox, (p_payload - 'auth') || jsonb_build_object('auth', true))
  returning id into v_id;
  return v_id;
end;
$$;

-- Droits : l’appli peut fermer sa propre boîte. Les envois gardent leurs droits (create or replace les conserve).
revoke execute on function public.pli_box_fermer(text, text) from public;
grant execute on function public.pli_box_fermer(text, text) to anon, authenticated;
