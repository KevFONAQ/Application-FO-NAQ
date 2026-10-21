-- V8 : abonnements aux notifications (un enregistrement par téléphone / navigateur)
-- À exécuter une fois dans Supabase > SQL Editor > Run
create table if not exists public.push_subscriptions (
  endpoint   text primary key,
  user_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  p256dh     text not null,
  auth       text not null,
  user_agent text,
  created_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;

grant select, insert, update, delete on public.push_subscriptions to authenticated;
grant select, insert, update, delete on public.push_subscriptions to service_role;
revoke all on public.push_subscriptions from anon;

drop policy if exists "push: mes appareils" on public.push_subscriptions;
create policy "push: mes appareils" on public.push_subscriptions
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
