-- V9 : droits des administrateurs
-- Administrateurs : passent les membres d'invité à adhérent (ou l'inverse), gèrent toutes les actualités.
-- Principal (toi) : seul à nommer ou retirer un administrateur ; ton compte est intouchable.

drop policy if exists "profiles: update admin" on public.profiles;
create policy "profiles: update admin" on public.profiles
  for update to authenticated
  using (public.is_owner() or (public.is_staff() and role::text in ('invite', 'adherent')))
  with check (
    (public.is_owner() and (role::text <> 'admin' or id = auth.uid()))
    or (public.is_staff() and role::text in ('invite', 'adherent'))
  );

drop policy if exists "news: modif auteur ou principal" on public.news;
create policy "news: modif auteur ou principal" on public.news for update to authenticated
  using (public.is_staff()) with check (public.is_staff());
drop policy if exists "news: suppression auteur ou principal" on public.news;
create policy "news: suppression auteur ou principal" on public.news for delete to authenticated
  using (public.is_staff());
