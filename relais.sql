-- Pli Scellé : relais de messages et d'invitations (Supabase).
-- Les tables sont fermées à tout le monde. On passe uniquement par les fonctions ci-dessous.

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  mailbox text not null check (mailbox ~ '^[0-9a-f]{64}$'),
  payload jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists messages_mailbox_idx on public.messages (mailbox, created_at);

create table if not exists public.invitations (
  id text primary key check (id ~ '^[a-z0-9]{8,24}$'),
  data jsonb not null
);

alter table public.messages enable row level security;
alter table public.invitations enable row level security;
revoke all on public.messages from public, anon, authenticated;
revoke all on public.invitations from public, anon, authenticated;

-- Envoyer un message chiffré à une boîte
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
  insert into public.messages (mailbox, payload) values (p_mailbox, p_payload)
  returning id into v_id;
  return v_id;
end;
$$;

-- Lire les messages d'une boîte
create or replace function public.pli_fetch(p_mailbox text)
returns table (msg_id uuid, msg_payload jsonb)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  return query
    select m.id, m.payload
    from public.messages m
    where m.mailbox = p_mailbox
    order by m.created_at
    limit 200;
end;
$$;

-- Supprimer un message une fois traité
create or replace function public.pli_ack(p_id uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.messages where id = p_id;
$$;

-- Écrire une invitation
create or replace function public.pli_inv_put(p_id text, p_data jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_id !~ '^[a-z0-9]{8,24}$' then raise exception 'invitation invalide'; end if;
  if octet_length(p_data::text) > 4000 then raise exception 'invitation trop longue'; end if;
  insert into public.invitations (id, data) values (p_id, p_data)
  on conflict (id) do update set data = excluded.data;
end;
$$;

-- Lire une invitation (null si elle n'existe pas)
create or replace function public.pli_inv_get(p_id text)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select i.data from public.invitations i
  where i.id = p_id and p_id ~ '^[a-z0-9]{8,24}$';
$$;

-- Supprimer une invitation
create or replace function public.pli_inv_delete(p_id text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.invitations where id = p_id;
$$;

-- Droits : seules ces six fonctions sont ouvertes à l'appli
revoke execute on function public.pli_send(text, jsonb) from public;
revoke execute on function public.pli_fetch(text) from public;
revoke execute on function public.pli_ack(uuid) from public;
revoke execute on function public.pli_inv_put(text, jsonb) from public;
revoke execute on function public.pli_inv_get(text) from public;
revoke execute on function public.pli_inv_delete(text) from public;

grant execute on function public.pli_send(text, jsonb) to anon, authenticated;
grant execute on function public.pli_fetch(text) to anon, authenticated;
grant execute on function public.pli_ack(uuid) to anon, authenticated;
grant execute on function public.pli_inv_put(text, jsonb) to anon, authenticated;
grant execute on function public.pli_inv_get(text) to anon, authenticated;
grant execute on function public.pli_inv_delete(text) to anon, authenticated;
