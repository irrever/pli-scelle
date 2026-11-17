-- Sauvegardes à usage unique (Pli Scellé).
-- Chaque sauvegarde porte un identifiant secret, chiffré dans le fichier. L’appli n’envoie au relais que son empreinte
-- (sha256 de « pli-sauvegarde|identifiant », en hexadécimal). La première installation la réserve ; toute autre tentative est refusée.
-- À exécuter une fois dans l’éditeur SQL du projet Supabase, avant de publier une version qui installe les sauvegardes.

create table if not exists public.pli_sauvegardes_utilisees (
  h text primary key check (length(h) = 64),
  utilisee_le timestamptz not null default now()
);

-- Personne n’a d’accès direct à la table : seule la fonction ci-dessous y touche.
alter table public.pli_sauvegardes_utilisees enable row level security;

create or replace function public.pli_claim_backup(p_h text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_h is null or length(p_h) <> 64 then
    raise exception 'empreinte invalide';
  end if;
  insert into public.pli_sauvegardes_utilisees (h) values (p_h) on conflict (h) do nothing;
  return found;   -- vrai seulement si l’empreinte vient d’être enregistrée
end;
$$;

revoke execute on function public.pli_claim_backup(text) from public;
grant execute on function public.pli_claim_backup(text) to anon, authenticated;
