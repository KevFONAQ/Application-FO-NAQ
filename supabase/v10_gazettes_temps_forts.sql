-- V10 : rubrique Gazettes, encart « Temps forts du mois », inscription toujours en Invité
-- À exécuter une fois dans Supabase > SQL Editor > Run

-- 1. Gazettes : un document appartient à une rubrique (textes juridiques ou gazettes)
alter table public.documents add column if not exists section text not null default 'textes';
alter table public.documents drop constraint if exists documents_section_check;
alter table public.documents add constraint documents_section_check check (section in ('textes', 'gazette'));

-- 2. Inscription : toujours « invité », quoi qu'envoie le navigateur
create or replace function public.force_invite_on_signup()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.role := 'invite';
  new.requested_adherent := false;
  return new;
end $$;
drop trigger if exists profiles_force_invite on public.profiles;
create trigger profiles_force_invite before insert on public.profiles
  for each row execute function public.force_invite_on_signup();

-- 3. Temps forts du mois (prochain CSE, visites d'agences, autres rendez-vous)
create table if not exists public.highlights (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('cse', 'visite', 'autre')),
  event_date  date not null,
  label       text not null,
  label_norm  text not null,
  details     text,
  source      text not null default 'manuel' check (source in ('manuel', 'import')),
  created_by  uuid default auth.uid() references public.profiles(id) on delete set null,
  created_by_name text,
  created_at  timestamptz not null default now()
);
-- Anti-doublon : un même rendez-vous (type + date + intitulé) ne peut exister qu'une fois
create unique index if not exists highlights_unique on public.highlights (kind, event_date, label_norm);
create index if not exists highlights_date_idx on public.highlights (event_date);
alter table public.highlights enable row level security;

grant select, insert, update, delete on public.highlights to authenticated;
grant select, insert, update, delete on public.highlights to service_role;
revoke all on public.highlights from anon;

drop policy if exists "temps forts: lecture membres" on public.highlights;
create policy "temps forts: lecture membres" on public.highlights for select to authenticated using (true);
drop policy if exists "temps forts: ajout admins" on public.highlights;
create policy "temps forts: ajout admins" on public.highlights for insert to authenticated with check (public.is_staff());
drop policy if exists "temps forts: modif admins" on public.highlights;
create policy "temps forts: modif admins" on public.highlights for update to authenticated using (public.is_staff()) with check (public.is_staff());
drop policy if exists "temps forts: suppression admins" on public.highlights;
create policy "temps forts: suppression admins" on public.highlights for delete to authenticated using (public.is_staff());
