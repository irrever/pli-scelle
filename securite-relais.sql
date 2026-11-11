-- Pli Scellé : seule l’identité qui possède le secret de sa boîte peut lire et vider cette boîte.
-- À lancer une fois, dans l’éditeur SQL du projet, après relais.sql.
-- Ne publier la nouvelle version de l’appli qu’après ce script : les anciennes fonctions sont supprimées.

-- Pour chaque boîte : l’empreinte du secret (jamais le secret lui-même)
create table if not exists public.box_auth (
  mailbox text primary key check (mailbox ~ '^[0-9a-f]{64}$'),
  auth text not null check (auth ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);
alter table public.box_auth enable row level security;
revoke all on public.box_auth from public, anon, authenticated;

-- Inscrire une boîte. Refaire l’inscription avec le même secret ne fait rien ; un autre secret est refusé.
create or replace function public.pli_box_register(p_mailbox text, p_auth text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare n integer;
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' or p_auth !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  insert into public.box_auth (mailbox, auth) values (p_mailbox, p_auth)
  on conflict (mailbox) do nothing;
  get diagnostics n = row_count;
  if n = 0 and not exists (select 1 from public.box_auth where mailbox = p_mailbox and auth = p_auth) then
    raise exception 'boîte déjà enregistrée';
  end if;
end;
$$;

-- Vérifier le secret d’une boîte (fonction interne, réservée aux autres fonctions du relais)
create or replace function public.box_check(p_mailbox text, p_secret text)
returns boolean
language sql
security definer
set search_path = public, pg_temp
as $$
  select p_secret ~ '^[0-9a-f]{64}$' and exists (
    select 1 from public.box_auth b
    where b.mailbox = p_mailbox
      and b.auth = encode(sha256(decode(p_secret, 'hex')), 'hex')
  );
$$;

-- Lire sa boîte : le secret est obligatoire
create or replace function public.pli_fetch(p_mailbox text, p_secret text)
returns table (msg_id uuid, msg_payload jsonb)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  if not public.box_check(p_mailbox, p_secret) then raise exception 'accès refusé'; end if;
  return query
    select m.id, m.payload
    from public.messages m
    where m.mailbox = p_mailbox
    order by m.created_at
    limit 200;
end;
$$;

-- Supprimer un message de sa boîte : le secret est obligatoire
create or replace function public.pli_ack(p_id uuid, p_mailbox text, p_secret text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  if not public.box_check(p_mailbox, p_secret) then raise exception 'accès refusé'; end if;
  delete from public.messages where id = p_id and mailbox = p_mailbox;
end;
$$;

-- Les anciennes versions, sans secret, ne doivent plus être ouvertes
drop function if exists public.pli_fetch(text);
drop function if exists public.pli_ack(uuid);

-- Droits : l’appli peut inscrire une boîte, lire et vider la sienne ; la vérification reste interne
revoke execute on function public.box_check(text, text) from public, anon, authenticated;
revoke execute on function public.pli_box_register(text, text) from public;
revoke execute on function public.pli_fetch(text, text) from public;
revoke execute on function public.pli_ack(uuid, text, text) from public;

grant execute on function public.pli_box_register(text, text) to anon, authenticated;
grant execute on function public.pli_fetch(text, text) to anon, authenticated;
grant execute on function public.pli_ack(uuid, text, text) to anon, authenticated;
