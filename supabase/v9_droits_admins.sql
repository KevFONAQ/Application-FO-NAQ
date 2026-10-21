-- V9 : les administrateurs gèrent les rôles des membres et toutes les actualités
-- Le compte de l'administrateur principal reste intouchable, et personne ne peut le devenir.

-- Rôles des membres : principal + administrateurs (jamais sur le compte principal, jamais vers « principal »)
drop policy if exists "profiles: update admin" on public.profiles;
create policy "profiles: update admin" on public.profiles
  for update to authenticated
  using (public.is_owner() or (public.is_staff() and role::text <> 'admin'))
  with check (
    (public.is_owner() and (role::text <> 'admin' or id = auth.uid()))
    or (public.is_staff() and role::text <> 'admin')
  );

-- Actualités : tout administrateur peut épingler ou supprimer n'importe quelle actualité
drop policy if exists "news: modif auteur ou principal" on public.news;
create policy "news: modif auteur ou principal" on public.news for update to authenticated
  using (public.is_staff()) with check (public.is_staff());
drop policy if exists "news: suppression auteur ou principal" on public.news;
create policy "news: suppression auteur ou principal" on public.news for delete to authenticated
  using (public.is_staff());
