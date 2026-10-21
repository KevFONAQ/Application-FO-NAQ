-- V7 : fil d'actualité, administrateurs secondaires, documents Word/Excel
-- À exécuter une fois dans Supabase > SQL Editor > Run

-- 1. Nouveau rôle : administrateur secondaire (« gestionnaire »)
alter type public.app_role add value if not exists 'gestionnaire';

-- Fonctions d'aide (comparaison en texte : utilisable dans la même exécution)
create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role::text = 'admin' from public.profiles where id = auth.uid()), false)
$$;
create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role::text in ('admin', 'gestionnaire') from public.profiles where id = auth.uid()), false)
$$;
grant execute on function public.is_owner(), public.is_staff() to authenticated;

-- 2. Profils : les administrateurs secondaires voient les membres ; seul le principal modifie les rôles
drop policy if exists "profiles: lecture propre ou admin" on public.profiles;
create policy "profiles: lecture propre ou admin" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_staff());

drop policy if exists "profiles: update admin" on public.profiles;
create policy "profiles: update admin" on public.profiles
  for update to authenticated
  using (public.is_owner())
  with check (public.is_owner() and (role::text <> 'admin' or id = auth.uid()));

-- Validation / refus des demandes d'adhésion (principal et secondaires)
create or replace function public.decide_members(ids uuid[], approve boolean)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_staff() then raise exception 'Action réservée aux administrateurs'; end if;
  update public.profiles
     set role = case when approve then 'adherent'::public.app_role else role end,
         requested_adherent = false
   where id = any(ids) and role::text = 'invite';
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.decide_members(uuid[], boolean) from public, anon;
grant execute on function public.decide_members(uuid[], boolean) to authenticated;

-- 3. Documents : ajout et modification pour tous les administrateurs, suppression pour le principal
drop policy if exists "documents: écriture admin" on public.documents;
drop policy if exists "documents: ajout admins" on public.documents;
drop policy if exists "documents: modif admins" on public.documents;
drop policy if exists "documents: suppression principal" on public.documents;
create policy "documents: ajout admins" on public.documents for insert to authenticated with check (public.is_staff());
create policy "documents: modif admins" on public.documents for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "documents: suppression principal" on public.documents for delete to authenticated using (public.is_owner());

drop policy if exists "pages: écriture admin" on public.document_pages;
create policy "pages: écriture admin" on public.document_pages
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Stockage des documents
drop policy if exists "storage: upload admin" on storage.objects;
create policy "storage: upload admin" on storage.objects
  for insert to authenticated with check (bucket_id = 'documents' and public.is_staff());
drop policy if exists "storage: lecture admin" on storage.objects;
create policy "storage: lecture admin" on storage.objects
  for select to authenticated using (bucket_id = 'documents' and public.is_staff());
drop policy if exists "storage: suppression admin" on storage.objects;
create policy "storage: suppression admin" on storage.objects
  for delete to authenticated using (bucket_id = 'documents' and public.is_owner());

-- 4. Fil d'actualité
create table if not exists public.news (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  author_id   uuid default auth.uid() references public.profiles(id) on delete set null,
  author_name text,
  body        text,
  link_url    text,
  media_path  text,
  media_type  text check (media_type in ('image', 'video')),
  pinned      boolean not null default false
);
create index if not exists news_order_idx on public.news (pinned desc, created_at desc);
alter table public.news enable row level security;

grant select, insert, update, delete on public.news to authenticated;
grant select, insert, update, delete on public.news to service_role;
revoke all on public.news from anon;

drop policy if exists "news: lecture membres" on public.news;
create policy "news: lecture membres" on public.news for select to authenticated using (true);
drop policy if exists "news: publication admins" on public.news;
create policy "news: publication admins" on public.news for insert to authenticated
  with check (public.is_staff() and author_id = auth.uid());
drop policy if exists "news: modif auteur ou principal" on public.news;
create policy "news: modif auteur ou principal" on public.news for update to authenticated
  using (public.is_owner() or (public.is_staff() and author_id = auth.uid()))
  with check (public.is_owner() or (public.is_staff() and author_id = auth.uid()));
drop policy if exists "news: suppression auteur ou principal" on public.news;
create policy "news: suppression auteur ou principal" on public.news for delete to authenticated
  using (public.is_owner() or (public.is_staff() and author_id = auth.uid()));

-- Photos et vidéos du fil (stockage privé, lecture par les membres connectés)
insert into storage.buckets (id, name, public) values ('actus', 'actus', false) on conflict (id) do nothing;
drop policy if exists "actus: lecture membres" on storage.objects;
create policy "actus: lecture membres" on storage.objects for select to authenticated using (bucket_id = 'actus');
drop policy if exists "actus: ajout admins" on storage.objects;
create policy "actus: ajout admins" on storage.objects for insert to authenticated with check (bucket_id = 'actus' and public.is_staff());
drop policy if exists "actus: suppression admins" on storage.objects;
create policy "actus: suppression admins" on storage.objects for delete to authenticated using (bucket_id = 'actus' and public.is_staff());

-- 5. Lecture des documents : les administrateurs secondaires voient tout, comme les adhérents
drop policy if exists "documents: lecture selon rôle" on public.documents;
create policy "documents: lecture selon rôle" on public.documents
  for select to authenticated
  using (is_public or public.current_role_app()::text in ('adherent', 'admin', 'gestionnaire'));

drop policy if exists "storage: lecture selon rôle" on storage.objects;
create policy "storage: lecture selon rôle" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documents' and exists (
      select 1 from public.documents d
       where d.storage_path = storage.objects.name
         and (d.is_public or public.current_role_app()::text in ('adherent', 'admin', 'gestionnaire'))
    )
  );
