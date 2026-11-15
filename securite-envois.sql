-- Pli Scellé : coupures et reprises vérifiées par le serveur.
-- À lancer une fois, dans l’éditeur SQL du projet, après securite-relais.sql.
-- Ne publier la nouvelle version de l’appli qu’après ce script : elle appelle pli_send_auth.

-- 1) pli_send garde sa signature, pour que les anciennes versions continuent d’envoyer leurs messages.
--    Mais le champ « auth » envoyé par l’appli est supprimé : seul le serveur peut poser ce champ.
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
  insert into public.messages (mailbox, payload) values (p_mailbox, p_payload - 'auth')
  returning id into v_id;
  return v_id;
end;
$$;

-- 2) pli_send_auth : envoi signé. L’expéditeur (champ « from ») doit posséder le secret de sa boîte.
--    Le serveur ajoute alors auth = true. C’est la seule façon d’obtenir ce champ.
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
  insert into public.messages (mailbox, payload)
  values (p_mailbox, (p_payload - 'auth') || jsonb_build_object('auth', true))
  returning id into v_id;
  return v_id;
end;
$$;

-- Droits : l’appli peut appeler ces deux fonctions, rien d’autre n’est ouvert
revoke execute on function public.pli_send(text, jsonb) from public;
revoke execute on function public.pli_send_auth(text, jsonb, text) from public;
grant execute on function public.pli_send(text, jsonb) to anon, authenticated;
grant execute on function public.pli_send_auth(text, jsonb, text) to anon, authenticated;
