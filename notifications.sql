-- Pli Scellé : notifications quand l’appli est fermée (iPhone : appli ajoutée à l’écran d’accueil, iOS 16.4 ou plus récent).
-- À lancer une fois, dans l’éditeur SQL du projet, APRÈS relais.sql puis securite-relais.sql.
-- Après chaque message déposé, le relais demande à la fonction « push » d’envoyer une notification vide
-- (voir supabase/functions/push/index.ts). Le texte affiché ne dit que : « Une nouvelle activité vous attend. »

-- Les inscriptions : fermées à tout le monde, lues seulement par la fonction « push » (clé de service).
create table if not exists public.push_subscriptions (
  mailbox text primary key check (mailbox ~ '^[0-9a-f]{64}$'),
  subscription jsonb not null,
  last_push_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from public, anon, authenticated;

-- Une version précédente, sans secret, ne doit plus être ouverte
drop function if exists public.pli_push_put(text, jsonb);
drop function if exists public.pli_push_delete(text);

-- Enregistrer (ou remplacer) l’abonnement d’une boîte : le secret de la boîte est obligatoire
create or replace function public.pli_push_put(p_mailbox text, p_secret text, p_sub jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  if not public.box_check(p_mailbox, p_secret) then raise exception 'accès refusé'; end if;
  if jsonb_typeof(p_sub) <> 'object' or p_sub->>'endpoint' is null or p_sub->>'endpoint' !~ '^https://'
     or octet_length(p_sub::text) > 2000 then
    raise exception 'abonnement invalide';
  end if;
  insert into public.push_subscriptions (mailbox, subscription, updated_at)
  values (p_mailbox, p_sub, now())
  on conflict (mailbox) do update set subscription = excluded.subscription, updated_at = now();
end;
$$;

-- Oublier l’abonnement d’une boîte : le secret de la boîte est obligatoire
create or replace function public.pli_push_delete(p_mailbox text, p_secret text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_mailbox !~ '^[0-9a-f]{64}$' then raise exception 'boîte invalide'; end if;
  if not public.box_check(p_mailbox, p_secret) then raise exception 'accès refusé'; end if;
  delete from public.push_subscriptions where mailbox = p_mailbox;
end;
$$;

-- Après chaque message : demander l’envoi. pg_net envoie la requête sans bloquer le dépôt du message.
create extension if not exists pg_net with schema extensions;

create or replace function public.pli_push_on_message()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  perform net.http_post(
    url := 'https://lvdkwatbqesxvsllnthz.supabase.co/functions/v1/push',
    body := jsonb_build_object('mailbox', new.mailbox),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;

drop trigger if exists pli_messages_push on public.messages;
create trigger pli_messages_push
  after insert on public.messages
  for each row execute function public.pli_push_on_message();

-- Droits : seules ces deux fonctions sont ouvertes à l’appli ; le déclencheur n’est appelé que par la base
revoke execute on function public.pli_push_put(text, text, jsonb) from public;
revoke execute on function public.pli_push_delete(text, text) from public;
revoke execute on function public.pli_push_on_message() from public, anon, authenticated;

grant execute on function public.pli_push_put(text, text, jsonb) to anon, authenticated;
grant execute on function public.pli_push_delete(text, text) to anon, authenticated;
